import ScreenCaptureKit
import CoreMedia
import AVFAudio
import AVFoundation
import CoreGraphics
import Foundation
import AppKit
import CoreAudio
import AudioToolbox
import IOKit.pwr_mgt
import OwnscribeCapture

// MARK: - System Audio Capture via ScreenCaptureKit

class SystemAudioCapture: NSObject, SystemAudioCapturing, SCStreamOutput, SCStreamDelegate, SCContentSharingPickerObserver {
    private var stream: SCStream?
    private var audioFile: AVAudioFile?
    private var audioConverter: AVAudioConverter?
    private let captureQueue = DispatchQueue(label: "com.ownscribe.audioCapture", qos: .userInitiated)

    private let outputPath: String

    // Timestamp for sync alignment
    private(set) var startHostTime: UInt64 = 0

    // Silence detection
    private var peakLevel: Float = 0.0
    private var totalFrames: Int64 = 0
    private var silenceChecked: Bool = false
    private var silenceWarned: Bool = false

    // Silence timeout auto-stop
    var silenceTimeout: TimeInterval = 0  // seconds; 0 = disabled
    var onSilenceTimeout: (() -> Void)?
    var micCapture: MicCapture?  // checked by silence timer
    private var lastLoudTime: UInt64 = DispatchTime.now().uptimeNanoseconds
    private var lastLoudTimeLock = os_unfair_lock_s()
    private var silenceTimer: DispatchSourceTimer?

    // Power assertion to prevent display sleep during capture
    private var powerAssertionID: IOPMAssertionID = IOPMAssertionID(kIOPMNullAssertionID)

    // Picker continuation
    private var startContinuation: CheckedContinuation<Void, Error>?

    init(outputPath: String) {
        self.outputPath = outputPath
        super.init()
    }

    var captureModeAll: Bool = false

    func start() async throws {
        if captureModeAll {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let display = content.displays.first else {
                throw CaptureError.noDisplay
            }
            let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            try await self.beginCapture(with: filter)
        } else {
            let picker = SCContentSharingPicker.shared
            var pickerConfig = SCContentSharingPickerConfiguration()
            pickerConfig.allowedPickerModes = [.singleWindow, .singleDisplay, .singleApplication]
            picker.defaultConfiguration = pickerConfig
            picker.add(self)
            picker.isActive = true
            picker.present()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.startContinuation = continuation
            }
        }
    }

    // MARK: - SCContentSharingPickerObserver

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task {
            do {
                try await self.beginCapture(with: filter)
                self.startContinuation?.resume()
                self.startContinuation = nil
            } catch {
                self.startContinuation?.resume(throwing: error)
                self.startContinuation = nil
            }
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        fputs("Content picker cancelled.\n", stderr)
        exit(0)
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        self.startContinuation?.resume(throwing: error)
        self.startContinuation = nil
    }

    // MARK: - Begin Capture

    private func beginCapture(with filter: SCContentFilter) async throws {
        // Configure stream (audio only, minimal video)
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(kSystemAudioSampleRate)
        config.channelCount = 1
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        // Create AVAudioFile for WAV output (interleaved to avoid CoreAudio warning)
        let fileFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: kSystemAudioSampleRate, channels: 1, interleaved: true)!
        let audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: outputPath),
                                         settings: fileFormat.settings,
                                         commonFormat: .pcmFormatFloat32,
                                         interleaved: true)
        self.audioFile = audioFile

        // Create and start stream
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)

        // Initialize last-loud time before starting capture (no lock needed — callbacks haven't started)
        if silenceTimeout > 0 {
            lastLoudTime = DispatchTime.now().uptimeNanoseconds
        }

        try await stream.startCapture()
        self.stream = stream

        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "ownscribe is recording audio" as CFString,
            &powerAssertionID)

        fputs("Recording system audio to \(outputPath)... Press Ctrl+C to stop.\n", stderr)

        // Start silence timeout timer if configured.
        // Checks every 1s whether both system audio and mic (if active) have been
        // quiet longer than silenceTimeout. Uses the most recent "loud" timestamp
        // from either source so that activity on either channel prevents auto-stop.
        if silenceTimeout > 0 {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 1, repeating: 1.0)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let now = DispatchTime.now().uptimeNanoseconds
                os_unfair_lock_lock(&self.lastLoudTimeLock)
                var effectiveLastLoud = self.lastLoudTime
                os_unfair_lock_unlock(&self.lastLoudTimeLock)
                // If mic is active, use the more recent of the two
                if let mic = self.micCapture {
                    let micLastLoud = mic.lastLoudTime
                    if micLastLoud > effectiveLastLoud {
                        effectiveLastLoud = micLastLoud
                    }
                }
                guard now >= effectiveLastLoud else { return }
                let elapsed = Double(now - effectiveLastLoud) / 1_000_000_000.0
                if elapsed > self.silenceTimeout {
                    fputs("[SILENCE_TIMEOUT]\n", stderr)
                    self.silenceTimer?.cancel()
                    self.silenceTimer = nil
                    self.onSilenceTimeout?()
                }
            }
            timer.resume()
            silenceTimer = timer
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let audioFile else { return }
        guard CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return }

        // Capture start host time from first audio buffer
        if startHostTime == 0 {
            startHostTime = mach_absolute_time()
        }

        // Get format from sample buffer
        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }
        guard let sampleFormat = AVAudioFormat(streamDescription: asbd) else { return }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: sampleFormat, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        // Copy audio data into PCM buffer
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frameCount),
            into: pcmBuffer.mutableAudioBufferList
        )
        guard status == noErr else { return }

        // Convert non-interleaved → interleaved if needed, then write
        do {
            if sampleFormat.isInterleaved {
                try audioFile.write(from: pcmBuffer)
            } else {
                if audioConverter?.inputFormat != sampleFormat {
                    let interleavedFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                       sampleRate: sampleFormat.sampleRate,
                                                       channels: sampleFormat.channelCount,
                                                       interleaved: true)!
                    audioConverter = AVAudioConverter(from: sampleFormat, to: interleavedFmt)
                }
                if let converter = audioConverter {
                    let outFmt = converter.outputFormat
                    guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFmt, frameCapacity: frameCount) else { return }
                    try converter.convert(to: outBuffer, from: pcmBuffer)
                    try audioFile.write(from: outBuffer)
                }
            }
        } catch {
            fputs("Write error: \(error)\n", stderr)
        }

        totalFrames += Int64(frameCount)

        // Peak detection on the pre-conversion buffer — floatChannelData returns nil
        // for interleaved buffers, so we must use the original SCK buffer
        let bufferPeak: Float = pcmBuffer.floatChannelData.map {
            computePeakLevel(in: $0, channels: Int(pcmBuffer.format.channelCount), frames: Int(pcmBuffer.frameLength))
        } ?? 0.0
        if bufferPeak > self.peakLevel { self.peakLevel = bufferPeak }

        // Update last loud time for silence timeout
        if bufferPeak > kSystemLoudThreshold {
            os_unfair_lock_lock(&lastLoudTimeLock)
            lastLoudTime = DispatchTime.now().uptimeNanoseconds
            os_unfair_lock_unlock(&lastLoudTimeLock)
        }

        // Check for silence after ~3 seconds of data
        if !silenceChecked && Double(totalFrames) > kSystemAudioSampleRate * 3 {
            silenceChecked = true
            if peakLevel < 1e-6 {
                silenceWarned = true
                if micCapture != nil {
                    fputs("[SILENCE_WARNING] System audio is silent (mic is still recording). No system audio sources detected.\n", stderr)
                } else {
                    fputs("[SILENCE_WARNING] Audio data received but peak level is near zero (\(peakLevel)). Audio may be silent.\n", stderr)
                    fputs("Check: System Settings > Privacy & Security > Screen Recording — enable your terminal app.\n", stderr)
                }
            }
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        fputs("Stream error: \(error)\n", stderr)
    }

    // MARK: - Stop

    func stop() {
        silenceTimer?.cancel()
        silenceTimer = nil

        if powerAssertionID != IOPMAssertionID(kIOPMNullAssertionID) {
            IOPMAssertionRelease(powerAssertionID)
            powerAssertionID = IOPMAssertionID(kIOPMNullAssertionID)
        }

        let sem = DispatchSemaphore(value: 0)
        Task.detached { [stream] in
            try? await stream?.stopCapture()
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 2)

        // AVAudioFile finalizes on close
        audioFile = nil

        let seconds = Double(totalFrames) / kSystemAudioSampleRate
        fputs("Saved \(outputPath) (\(String(format: "%.1f", seconds)) seconds, peak=\(String(format: "%.6f", peakLevel)))\n", stderr)
        if totalFrames > 0 && peakLevel < 1e-6 {
            fputs("[SILENCE_WARNING] Recording appears silent. Check Screen Recording permission.\n", stderr)
        }
    }

    enum CaptureError: Error, CustomStringConvertible {
        case cannotOpenFile(String)
        case noDisplay

        var description: String {
            switch self {
            case .cannotOpenFile(let p): return "Cannot open file: \(p)"
            case .noDisplay: return "No display found"
            }
        }
    }
}

// MARK: - List apps

func listAudioApps() {
    print("Running apps:")
    for app in NSWorkspace.shared.runningApplications {
        if app.activationPolicy == .regular, let name = app.localizedName {
            print("  PID \(app.processIdentifier): \(name)")
        }
    }
}

// MARK: - List input devices

func listInputDevices() {
    // Get default input device
    var defaultAddr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var defaultDevice: AudioDeviceID = 0
    var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                &defaultAddr, 0, nil, &defaultSize, &defaultDevice)

    // Enumerate all devices
    var propAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    var dataSize: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                    &propAddress, 0, nil, &dataSize)
    let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    var devices = [AudioDeviceID](repeating: 0, count: deviceCount)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                &propAddress, 0, nil, &dataSize, &devices)

    print("Input devices:")
    for deviceID in devices {
        // Get device name
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfNameRef: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, &cfNameRef)
        let name = cfNameRef?.takeRetainedValue() as String? ?? "(unknown)"

        // Check input channel count
        var inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var bufSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &inputAddr, 0, nil, &bufSize)
        guard bufSize > 0 else { continue }

        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferList.deallocate() }
        AudioObjectGetPropertyData(deviceID, &inputAddr, 0, nil, &bufSize, bufferList)
        let inputChannels = UnsafeMutableAudioBufferListPointer(bufferList)
            .reduce(0) { $0 + Int($1.mNumberChannels) }

        if inputChannels > 0 {
            let suffix = (deviceID == defaultDevice) ? " (default)" : ""
            print("  \(name)\(suffix)")
        }
    }
}

// MARK: - Audio activity detection

func defaultInputDeviceID() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
    return status == noErr ? deviceID : nil
}

func isAudioDeviceRunningSomewhere(_ deviceID: AudioDeviceID) -> Bool? {
    var isRunning: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &isRunning)
    return status == noErr ? (isRunning != 0) : nil
}

func watchAudioActivity(sustainedSeconds: Double, pollInterval: Double = 1.0) {
    guard let outputID = defaultOutputDeviceID() else {
        fputs("Error: could not resolve default output device\n", stderr)
        exit(1)
    }
    guard let inputID = defaultInputDeviceID() else {
        fputs("Error: could not resolve default input device\n", stderr)
        exit(1)
    }

    let detector = SustainedActivityDetector(sustainedSeconds: sustainedSeconds)

    fputs("Watching for sustained mic+output activity (a call, not just playback or dictation) (>\(sustainedSeconds)s)...\n", stderr)

    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    signal(SIGINT, SIG_IGN)
    sigintSource.setEventHandler { exit(0) }
    sigintSource.resume()

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: pollInterval)
    timer.setEventHandler {
        let micRunning = isAudioDeviceRunningSomewhere(inputID)
        let outputRunning = isAudioDeviceRunningSomewhere(outputID)
        guard let combined = combinedCallSignal(mic: micRunning, output: outputRunning) else { return }
        if detector.observe(running: combined, now: Date()) {
            print("[MEETING_DETECTED]")
            fflush(stdout)
            exit(0)
        }
    }
    timer.resume()

    RunLoop.main.run()
}

// MARK: - Main

func printUsage() {
    fputs("""
    ownscribe-audio — system audio capture helper

    USAGE:
        ownscribe-audio capture --output FILE [--mic] [--mic-device NAME] [--silence-timeout N]
        ownscribe-audio list-apps
        ownscribe-audio list-devices
        ownscribe-audio watch-activity [--sustained-seconds N]

    OPTIONS:
        --output, -o FILE      Output WAV file path (required for capture)
        --mic                  Also capture microphone input
        --mic-device NAME      Use specific mic input device (implies --mic)
        --capture-backend NAME "coreaudio" (default, macOS 14.2+) or "screencapturekit"
        --capture-mode-all     ScreenCaptureKit only: capture all system audio without a picker
        --silence-timeout N    Auto-stop after N seconds of silence (0 = disabled)
        --sustained-seconds N  Seconds of continuous mic+output activity before watch-activity
                               reports a detected meeting (default 3)
        --help, -h             Show this help

    SUBCOMMANDS:
        capture          Record audio to a WAV file
        list-apps         Show running applications
        list-devices      Show available audio input devices
        watch-activity    Poll for sustained mic AND output activity together (mic alone is
                          dictation, output alone is media playback; both together is a call)
                          and print [MEETING_DETECTED] once it holds for --sustained-seconds

    """, stderr)
}

func main() {
    let args = CommandLine.arguments
    guard args.count >= 2 else {
        printUsage()
        exit(1)
    }

    let command = args[1]

    switch command {
    case "list-apps":
        listAudioApps()

    case "list-devices":
        listInputDevices()

    case "watch-activity":
        var sustainedSeconds = 3.0
        var i = 2
        while i < args.count {
            switch args[i] {
            case "--sustained-seconds":
                i += 1
                guard i < args.count, let val = Double(args[i]) else {
                    fputs("Error: --sustained-seconds requires a number of seconds\n", stderr)
                    exit(1)
                }
                sustainedSeconds = val
            default:
                fputs("Unknown option: \(args[i])\n", stderr)
                printUsage()
                exit(1)
            }
            i += 1
        }
        watchAudioActivity(sustainedSeconds: sustainedSeconds)

    case "capture":
        // Initialize NSApplication so the picker GUI can render
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var outputPath: String?
        var enableMic = false
        var micDeviceName: String?
        var captureModeAll = false
        var silenceTimeout: TimeInterval = 0
        var captureBackend = "coreaudio"
        var echoCancellation = "off"

        var i = 2
        while i < args.count {
            switch args[i] {
            case "--output", "-o":
                i += 1
                guard i < args.count else {
                    fputs("Error: --output requires a file path\n", stderr)
                    exit(1)
                }
                outputPath = args[i]
            case "--capture-mode-all":
                captureModeAll = true
            case "--capture-backend":
                i += 1
                guard i < args.count else {
                    fputs("Error: --capture-backend requires a value (coreaudio or screencapturekit)\n", stderr)
                    exit(1)
                }
                captureBackend = args[i]
            case "--mic":
                enableMic = true
            case "--mic-device":
                i += 1
                guard i < args.count else {
                    fputs("Error: --mic-device requires a device name\n", stderr)
                    exit(1)
                }
                micDeviceName = args[i]
                enableMic = true  // --mic-device implies --mic
            case "--echo-cancellation":
                i += 1
                guard i < args.count, ["off", "on", "auto"].contains(args[i]) else {
                    fputs("Error: --echo-cancellation requires off, on, or auto\n", stderr)
                    exit(1)
                }
                echoCancellation = args[i]
            case "--silence-timeout":
                i += 1
                guard i < args.count, let val = TimeInterval(args[i]) else {
                    fputs("Error: --silence-timeout requires a number of seconds\n", stderr)
                    exit(1)
                }
                if val < 0 {
                    fputs("Error: --silence-timeout must be zero (disabled) or a positive number of seconds\n", stderr)
                    exit(1)
                }
                silenceTimeout = val
            default:
                fputs("Unknown option: \(args[i])\n", stderr)
                printUsage()
                exit(1)
            }
            i += 1
        }

        guard let output = outputPath else {
            fputs("Error: --output is required\n", stderr)
            printUsage()
            exit(1)
        }

        let useCoreAudioTap: Bool
        if #available(macOS 14.2, *) {
            useCoreAudioTap = captureBackend != "screencapturekit"
        } else {
            useCoreAudioTap = false
        }

        if !useCoreAudioTap {
            if !runCapturePermissionPreflight(needsMic: enableMic) {
                exit(1)
            }
        } else {
            if !preflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess()
            }
            if !runCoreAudioTapPermissionPreflight(needsMic: enableMic) {
                exit(1)
            }
        }

        // Determine paths: if mic enabled, use temp files then merge
        let systemPath = enableMic ? output + ".sys.tmp.wav" : output
        let micPath = output + ".mic.tmp.wav"

        let capture: SystemAudioCapturing
        if useCoreAudioTap, #available(macOS 14.2, *) {
            CoreAudioTapCapture.cleanupStaleAggregateDevices()
            capture = CoreAudioTapCapture(outputPath: systemPath)
        } else {
            let sckCapture = SystemAudioCapture(outputPath: systemPath)
            sckCapture.captureModeAll = captureModeAll
            capture = sckCapture
        }
        capture.silenceTimeout = silenceTimeout
        var micCapture: MicCapture?

        if enableMic {
            let mic = MicCapture()
            do {
                try mic.start(
                    outputPath: micPath,
                    deviceName: micDeviceName,
                    echoCancellation: echoCancellation)
            } catch {
                fputs("Error starting mic capture: \(error)\n", stderr)
                exit(1)
            }
            micCapture = mic
            capture.micCapture = mic
        }

        // Shared shutdown logic for SIGINT, SIGTERM, and silence timeout
        let shutdown: () -> Void = {
            capture.stop()
            if let mic = micCapture {
                mic.stop()
                do {
                    try mergeAudioFiles(
                        systemPath: systemPath,
                        micPath: micPath,
                        systemStartHostTime: capture.startHostTime,
                        micStartHostTime: mic.startHostTime,
                        outputPath: output)
                } catch {
                    fputs("Error merging audio: \(error)\n", stderr)
                }
            }
            exit(0)
        }

        capture.onSilenceTimeout = shutdown

        // Toggle mic mute on SIGUSR1 (sent by Python wrapper)
        var _sigusr1Source: DispatchSourceSignal?  // retained to keep source alive
        if let mic = micCapture {
            signal(SIGUSR1, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            src.setEventHandler { mic.toggleMute() }
            src.resume()
            _sigusr1Source = src
        }
        _ = _sigusr1Source

        // Handle Ctrl+C gracefully
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        signal(SIGINT, SIG_IGN)
        sigintSource.setEventHandler { shutdown() }
        sigintSource.resume()

        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN)
        sigtermSource.setEventHandler { shutdown() }
        sigtermSource.resume()

        Task {
            do {
                try await capture.start()
            } catch {
                fputs("Error: \(error)\n", stderr)
                exit(1)
            }
        }

        app.run()

    case "--help", "-h":
        printUsage()

    default:
        fputs("Unknown command: \(command)\n", stderr)
        printUsage()
        exit(1)
    }
}

main()
