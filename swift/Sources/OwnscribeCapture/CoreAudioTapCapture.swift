import AVFAudio
import AudioToolbox
import CoreAudio
import Foundation

@available(macOS 14.2, *)
public class CoreAudioTapCapture: SystemAudioCapturing {
    private var tapID: AudioObjectID = kAudioObjectUnknown
    private var aggregateDeviceID: AudioObjectID = kAudioObjectUnknown
    private var deviceProcID: AudioDeviceIOProcID?
    private let processingQueue = DispatchQueue(label: "com.ownscribe.coreAudioTap", qos: .userInitiated)

    private let outputPath: String
    private var audioFile: AVAudioFile?
    private var capturedSampleRate: Double?

    public private(set) var startHostTime: UInt64 = 0

    private var peakLevel: Float = 0.0
    private var totalFrames: Int64 = 0
    private var silenceChecked: Bool = false

    public var silenceTimeout: TimeInterval = 0
    public var onSilenceTimeout: (() -> Void)?
    public var micCapture: MicCapture?
    private var lastLoudTime: UInt64 = DispatchTime.now().uptimeNanoseconds
    private var lastLoudTimeLock = os_unfair_lock_s()
    private var silenceTimer: DispatchSourceTimer?

    private static let noAudioYetWarningDelay: TimeInterval = 6.0
    private var anyAudioReceived = false
    private var noAudioYetWarningTimer: DispatchWorkItem?

    public init(outputPath: String) {
        self.outputPath = outputPath
    }

    public func start() async throws {
        try createTapAndAggregateDevice()

        var format = try readAudioTapStreamBasicDescription(tapID: tapID)
        guard let avFormat = AVAudioFormat(streamDescription: &format) else {
            throw CaptureError.unsupportedTapFormat
        }

        let audioFile = try AVAudioFile(
            forWriting: URL(fileURLWithPath: outputPath),
            settings: avFormat.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: avFormat.isInterleaved
        )
        self.audioFile = audioFile
        self.capturedSampleRate = avFormat.sampleRate

        if silenceTimeout > 0 {
            lastLoudTime = DispatchTime.now().uptimeNanoseconds
        }

        try startIOProc(format: avFormat)
        armNoAudioYetWarning()

        fputs("Recording system audio to \(outputPath) via CoreAudio process tap... Press Ctrl+C to stop.\n", stderr)

        if silenceTimeout > 0 {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + 1, repeating: 1.0)
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                let now = DispatchTime.now().uptimeNanoseconds
                os_unfair_lock_lock(&self.lastLoudTimeLock)
                var effectiveLastLoud = self.lastLoudTime
                os_unfair_lock_unlock(&self.lastLoudTimeLock)
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

    private func createTapAndAggregateDevice() throws {
        let excludeList: [AudioObjectID] = AudioObjectID.currentProcessAudioObjectID().map { [$0] } ?? []
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: excludeList)
        tapDescription.name = "ownscribe System Audio Tap"
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = .unmuted
        tapDescription.isPrivate = true

        var newTapID: AudioObjectID = kAudioObjectUnknown
        var status = AudioHardwareCreateProcessTap(tapDescription, &newTapID)
        guard status == noErr, newTapID != kAudioObjectUnknown else {
            throw CaptureError.tapCreationFailed(status)
        }
        tapID = newTapID

        let aggregateUID = "com.ownscribe.system-audio-tap-\(UUID().uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ownscribe System Audio",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: tapDescription.uuid.uuidString]
            ],
        ]

        var newAggregateDeviceID: AudioObjectID = kAudioObjectUnknown
        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newAggregateDeviceID)
        guard status == noErr, newAggregateDeviceID != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
            throw CaptureError.aggregateDeviceCreationFailed(status)
        }
        aggregateDeviceID = newAggregateDeviceID
    }

    private func startIOProc(format: AVAudioFormat) throws {
        var newProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&newProcID, aggregateDeviceID, processingQueue) {
            [weak self] _, inputData, inputTime, _, _ in
            self?.handleAudio(inputData: inputData, inputTime: inputTime, format: format)
        }
        guard status == noErr, let procID = newProcID else {
            throw CaptureError.ioProcCreationFailed(status)
        }
        deviceProcID = procID

        let startStatus = AudioDeviceStart(aggregateDeviceID, procID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            deviceProcID = nil
            throw CaptureError.deviceStartFailed(startStatus)
        }
    }

    private func armNoAudioYetWarning() {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.anyAudioReceived else { return }
            fputs("""
            [SILENCE_WARNING] No system audio has been received at all in the first \(Int(Self.noAudioYetWarningDelay))s.
            This can mean nothing has played through the speakers yet (normal), or that System
            Audio Recording permission was never granted (macOS may not have been able to show
            the permission prompt for this binary). If a call is active and you expect audio,
            check: open x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture
            """, stderr)
            fputs("\n", stderr)
            self.noAudioYetWarningTimer = nil
        }
        noAudioYetWarningTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.noAudioYetWarningDelay, execute: workItem)
    }

    private func handleAudio(inputData: UnsafePointer<AudioBufferList>, inputTime: UnsafePointer<AudioTimeStamp>, format: AVAudioFormat) {
        if startHostTime == 0 {
            startHostTime = inputTime.pointee.mHostTime
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil) else {
            return
        }
        guard buffer.frameLength > 0 else { return }

        if !anyAudioReceived {
            anyAudioReceived = true
            noAudioYetWarningTimer?.cancel()
            noAudioYetWarningTimer = nil
        }

        do {
            try audioFile?.write(from: buffer)
        } catch {
            fputs("Write error: \(error)\n", stderr)
            return
        }

        totalFrames += Int64(buffer.frameLength)

        let bufferPeak: Float = buffer.floatChannelData.map {
            computePeakLevel(in: $0, channels: Int(buffer.format.channelCount), frames: Int(buffer.frameLength))
        } ?? 0.0
        if bufferPeak > peakLevel { peakLevel = bufferPeak }

        if bufferPeak > kSystemLoudThreshold {
            os_unfair_lock_lock(&lastLoudTimeLock)
            lastLoudTime = DispatchTime.now().uptimeNanoseconds
            os_unfair_lock_unlock(&lastLoudTimeLock)
        }

        if !silenceChecked && Double(totalFrames) > format.sampleRate * 3 {
            silenceChecked = true
            if peakLevel < 1e-6 {
                if micCapture != nil {
                    fputs("[SILENCE_WARNING] System audio is silent (mic is still recording). No system audio sources detected.\n", stderr)
                } else {
                    fputs("[SILENCE_WARNING] Audio data received but peak level is near zero (\(peakLevel)). Audio may be silent.\n", stderr)
                    fputs("Check: System Settings > Privacy & Security > Screen & System Audio Recording — enable your terminal app.\n", stderr)
                }
            }
        }
    }

    public func stop() {
        silenceTimer?.cancel()
        silenceTimer = nil
        noAudioYetWarningTimer?.cancel()
        noAudioYetWarningTimer = nil

        if let procID = deviceProcID {
            AudioDeviceStop(aggregateDeviceID, procID)
            AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)
            deviceProcID = nil
        }

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }

        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }

        audioFile = nil

        let summary = stopSummary(totalFrames: totalFrames, rate: capturedSampleRate, peak: peakLevel)
        fputs("Saved \(outputPath) \(summary)\n", stderr)

        if totalFrames > 0 && peakLevel < 1e-6 {
            fputs("[SILENCE_WARNING] Recording appears silent. Check System Audio Recording permission.\n", stderr)
        }
    }

    func stopSummary(totalFrames: Int64, rate: Double?, peak: Float) -> String {
        if let rate = rate {
            let seconds = Double(totalFrames) / rate
            return "(\(String(format: "%.1f", seconds)) seconds, peak=\(String(format: "%.6f", peak)))"
        } else {
            return "(\(totalFrames) frames, rate unknown)"
        }
    }

    public enum CaptureError: Error, CustomStringConvertible {
        case tapCreationFailed(OSStatus)
        case aggregateDeviceCreationFailed(OSStatus)
        case ioProcCreationFailed(OSStatus)
        case deviceStartFailed(OSStatus)
        case unsupportedTapFormat

        public var description: String {
            switch self {
            case .tapCreationFailed(let status) where status == kAudioDevicePermissionsError:
                return """
                [PERMISSION_MISSING] System Audio Recording permission is not granted.
                Fix: open x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture
                Enable your terminal app under "System Audio Recording Only", then restart it.
                """
            case .tapCreationFailed(let status): return "Process tap creation failed (status: \(status))"
            case .aggregateDeviceCreationFailed(let status): return "Aggregate device creation failed (status: \(status))"
            case .ioProcCreationFailed(let status): return "IO proc creation failed (status: \(status))"
            case .deviceStartFailed(let status): return "Device start failed (status: \(status))"
            case .unsupportedTapFormat: return "Could not construct AVAudioFormat from the tap's stream description"
            }
        }
    }

    public static func cleanupStaleAggregateDevices() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return }

        var devices = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &devices) == noErr else {
            return
        }

        for deviceID in devices {
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfNameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(deviceID, &nameAddress, 0, nil, &nameSize, &cfNameRef) == noErr else { continue }
            let deviceName = cfNameRef?.takeRetainedValue() as String? ?? ""
            if deviceName == "ownscribe System Audio" {
                fputs("Cleaning up stale aggregate device \(deviceID)\n", stderr)
                AudioHardwareDestroyAggregateDevice(deviceID)
            }
        }
    }
}

extension AudioObjectID {
    static func currentProcessAudioObjectID() -> AudioObjectID? {
        let myPID = ProcessInfo.processInfo.processIdentifier

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr else {
            return nil
        }
        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return nil }

        var objects = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &objects) == noErr else {
            return nil
        }

        var pidAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        for object in objects {
            var objectPID: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            if AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &objectPID) == noErr, objectPID == myPID {
                return object
            }
        }
        return nil
    }

}

@available(macOS 14.2, *)
func readAudioTapStreamBasicDescription(tapID: AudioObjectID) throws -> AudioStreamBasicDescription {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioTapPropertyFormat,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    var format = AudioStreamBasicDescription()
    var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
    guard status == noErr else {
        throw CoreAudioTapCapture.CaptureError.unsupportedTapFormat
    }
    return format
}
