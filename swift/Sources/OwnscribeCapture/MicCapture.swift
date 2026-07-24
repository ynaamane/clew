import AVFAudio
import AudioToolbox
import CoreAudio
import Foundation

public func collapseDuplicatedVoiceProcessingChannels(of format: AVAudioFormat) -> AVAudioFormat {
    guard format.channelCount > 2 else { return format }
    return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                          channels: 1, interleaved: true) ?? format
}

public class MicCapture {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    public private(set) var startHostTime: UInt64 = 0

    // Fixed processing format of the output file. Every tap buffer is normalised to
    // this before writing, so a mid-stream format change cannot break the writes the
    // way a fixed AVAudioFile did before (Meet flipping the shared input into
    // 3-channel voice-processing mode made every write fail with -50, killing the mic).
    private var fileFormat: AVAudioFormat?
    private var audioConverter: AVAudioConverter?

    // Set when a write/convert failure has been logged; reset on the next successful write
    // so a persistent failure logs once instead of once per tap buffer (~10+/sec). Touched
    // only from writeBuffer on the tap (render) thread, so it needs no locking.
    private var loggedWriteError = false

    // Remembered so an explicitly named device can be re-applied after a route change.
    private var micDeviceName: String?

    // Re-bind the input + reinstall the tap when the audio route changes. The token is
    // kept so stop() can deregister it. isStopping guards a notification already queued
    // on .main behind stop(): the observer is delivered on .main and stop() runs on
    // .main (the SIGINT/SIGTERM sources), so they serialise and the flag alone is enough.
    private var configObserver: NSObjectProtocol?
    private var isStopping = false

    // Mute support — guarded by os_unfair_lock (tap callback is on AVAudioEngine thread)
    private var _isMuted = false
    private var _muteLock = os_unfair_lock_s()

    // Level tracking for silence timeout (mirrors SystemAudioCapture pattern)
    private var _lastLoudTime: UInt64 = DispatchTime.now().uptimeNanoseconds
    private var _lastLoudTimeLock = os_unfair_lock_s()

    public init() {}

    public var lastLoudTime: UInt64 {
        os_unfair_lock_lock(&_lastLoudTimeLock)
        defer { os_unfair_lock_unlock(&_lastLoudTimeLock) }
        return _lastLoudTime
    }

    public var isMuted: Bool {
        os_unfair_lock_lock(&_muteLock)
        defer { os_unfair_lock_unlock(&_muteLock) }
        return _isMuted
    }

    public func toggleMute() {
        os_unfair_lock_lock(&_muteLock)
        _isMuted.toggle()
        let muted = _isMuted
        os_unfair_lock_unlock(&_muteLock)
        fputs(muted ? "[MIC_MUTED]\n" : "[MIC_UNMUTED]\n", stderr)
    }

    public func start(outputPath: String, deviceName: String?, echoCancellation: String = "off") throws {
        micDeviceName = deviceName
        try applyInputDevice()
        applyEchoCancellation(mode: echoCancellation)

        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            throw MicError.noInputAvailable
        }

        let fileWriteFormat = collapseDuplicatedVoiceProcessingChannels(of: format)

        let url = URL(fileURLWithPath: outputPath)
        let file = try AVAudioFile(forWriting: url,
                                   settings: fileWriteFormat.settings,
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: true)
        audioFile = file
        fileFormat = file.processingFormat

        guard installMicTap() else {
            throw MicError.noInputAvailable
        }

        // Earbuds plugged in mid-recording, or a conferencing app reconfiguring the
        // shared input format, posts this notification (the engine stops itself first).
        // Rebind + restart so the mic keeps recording instead of silently dying.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in self?.handleConfigChange() }

        try engine.start()
        fputs("Recording microphone audio to \(outputPath)...\n", stderr)
    }

    /// Re-apply the explicitly named input device, if one was requested. When no device
    /// was named the engine follows the system default input — which is exactly what
    /// makes "switch to earbuds mid-recording" work, so we deliberately do nothing.
    private func applyInputDevice() throws {
        guard let name = micDeviceName else { return }
        // audioUnit can be nil while the node is in flux during a route change; treat
        // that as "cannot set device" rather than force-unwrapping into a crash.
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw MicError.cannotSetDevice(name)
        }
        let deviceID = try findInputDevice(named: name)
        var id = deviceID
        let err = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global, 0,
            &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        if err != noErr {
            throw MicError.cannotSetDevice(name)
        }
    }

    private func applyEchoCancellation(mode: String) {
        let shouldEnableForBuiltInSpeakerEcho = mode == "auto" && defaultOutputDeviceIsBuiltIn()
        let shouldEnableExplicitly = mode == "on"
        guard shouldEnableExplicitly || shouldEnableForBuiltInSpeakerEcho else { return }
        do {
            try engine.inputNode.setVoiceProcessingEnabled(true)
        } catch {
            fputs("Warning: could not enable echo cancellation: \(error)\n", stderr)
        }
    }

    /// Install the capture tap using the input node's current format. Returns false if
    /// no input is available yet (sample rate 0), e.g. mid-route-change.
    @discardableResult
    private func installMicTap() -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return false }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self else { return }
            if self.startHostTime == 0 {
                self.startHostTime = time.hostTime
            }
            let muted = self.isMuted
            if muted, let channelData = buffer.floatChannelData {
                let channels = Int(buffer.format.channelCount)
                let frames = Int(buffer.frameLength)
                for ch in 0..<channels {
                    memset(channelData[ch], 0, frames * MemoryLayout<Float>.size)
                }
            }
            // Track peak level for silence timeout (muted mic = silence)
            if !muted, let channelData = buffer.floatChannelData {
                let peak = computePeakLevel(in: channelData,
                                     channels: Int(buffer.format.channelCount),
                                     frames: Int(buffer.frameLength))
                if peak > kMicLoudThreshold {
                    os_unfair_lock_lock(&self._lastLoudTimeLock)
                    self._lastLoudTime = DispatchTime.now().uptimeNanoseconds
                    os_unfair_lock_unlock(&self._lastLoudTimeLock)
                }
            }
            self.writeBuffer(buffer)
        }
        return true
    }

    /// Write a tap buffer to the file, converting to the file's fixed format whenever
    /// the incoming format differs (Meet voice-processing mode, or a new device with a
    /// different sample rate or channel count). The fast path — unchanged format —
    /// writes directly, exactly as the original code did. On a sample-rate change the
    /// converter is rebuilt; any sub-buffer of tail samples left inside the old
    /// converter is dropped (sub-10ms, inaudible for transcription).
    private func writeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let audioFile, let fileFormat else { return }
        do {
            if buffer.format == fileFormat {
                try audioFile.write(from: buffer)
                loggedWriteError = false
                return
            }
            if audioConverter?.inputFormat != buffer.format {
                audioConverter = AVAudioConverter(from: buffer.format, to: fileFormat)
            }
            guard let converter = audioConverter else {
                logWriteErrorOnce("Mic convert error: converter unavailable for format \(buffer.format)")
                return
            }
            let ratio = fileFormat.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: fileFormat,
                                                   frameCapacity: capacity) else { return }
            var fed = false
            var convError: NSError?
            let status = converter.convert(to: outBuffer, error: &convError) { _, outStatus in
                if fed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                fed = true
                outStatus.pointee = .haveData
                return buffer
            }
            if status == .error || convError != nil {
                logWriteErrorOnce("Mic convert error: \(convError?.description ?? "unknown")")
                return
            }
            if outBuffer.frameLength > 0 {
                try audioFile.write(from: outBuffer)
                loggedWriteError = false
            }
        } catch {
            logWriteErrorOnce("Mic write error: \(error)")
        }
    }

    /// Log a recurring write/convert failure only once until the next successful write, so a
    /// persistent bad state (e.g. an unconvertible format) doesn't flood stderr at the tap
    /// rate. Reset by writeBuffer on every successful write. Render-thread only — no locking.
    private func logWriteErrorOnce(_ message: String) {
        guard !loggedWriteError else { return }
        loggedWriteError = true
        fputs(message + "\n", stderr)
    }

    /// Rebind the input and reinstall the tap after an audio route change. Runs on
    /// .main, so it never overlaps stop(); removeTap quiesces the render thread before
    /// we touch the tap, and the file/converter stay valid across the swap.
    ///
    /// Known limitation: the mic file is written continuously with no silence padding,
    /// so if the input drops out for a moment during a device switch (e.g. plugging in
    /// earbuds), the post-switch mic audio is appended immediately and the mic track
    /// drifts slightly earlier relative to the system track. Acceptable for
    /// transcription/diarization, and far better than the previous behaviour (losing
    /// all post-switch mic audio). The common conferencing-app case reconfigures only
    /// the *format*, not the device, so the converter absorbs it with no gap at all.
    private func handleConfigChange() {
        guard !isStopping else { return }
        fputs("Mic reconfigure: audio route changed; rebinding microphone input.\n", stderr)
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try applyInputDevice()  // re-pin a named device; no-op when following default
        } catch {
            fputs("Mic reconfigure: \(error) — falling back to default input.\n", stderr)
        }
        reinstallAndStart()
    }

    /// Reinstall the tap and restart the engine. If the input is not ready yet
    /// (sampleRate 0 while a route is still settling), retry on .main a bounded number
    /// of times rather than relying on another notification arriving — a single
    /// transient zero-rate change must not kill the mic for the rest of the session.
    private func reinstallAndStart(attempt: Int = 0) {
        guard !isStopping else { return }
        guard installMicTap() else {
            let maxAttempts = 20  // ~5s at 0.25s spacing
            if attempt < maxAttempts {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.reinstallAndStart(attempt: attempt + 1)
                }
            } else {
                fputs("Mic reconfigure: input did not return after \(maxAttempts) retries; mic stopped.\n", stderr)
            }
            return
        }
        do {
            try engine.start()
        } catch {
            fputs("Mic reconfigure: failed to restart engine: \(error)\n", stderr)
        }
    }

    public func stop() {
        isStopping = true
        if let token = configObserver {
            NotificationCenter.default.removeObserver(token)
            configObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
    }

    public enum MicError: Error, CustomStringConvertible {
        case deviceNotFound(String)
        case cannotSetDevice(String)
        case noInputAvailable

        public var description: String {
            switch self {
            case .deviceNotFound(let n): return "Input device not found: \(n)"
            case .cannotSetDevice(let n): return "Cannot set input device: \(n)"
            case .noInputAvailable: return "No audio input available (sample rate is 0)"
            }
        }
    }
}

/// Find an input audio device by name, returning its AudioDeviceID.
public func findInputDevice(named name: String) throws -> AudioDeviceID {
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

    for deviceID in devices {
        // Get device name
        var nameAddr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfNameRef: Unmanaged<CFString>?
        var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        AudioObjectGetPropertyData(deviceID, &nameAddr, 0, nil, &nameSize, &cfNameRef)
        let deviceName = cfNameRef?.takeRetainedValue() as String? ?? "(unknown)"

        // Check input channel count
        var inputAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var bufSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(deviceID, &inputAddr, 0, nil, &bufSize)
        if bufSize > 0 {
            let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
            defer { bufferList.deallocate() }
            AudioObjectGetPropertyData(deviceID, &inputAddr, 0, nil, &bufSize, bufferList)
            let inputChannels = UnsafeMutableAudioBufferListPointer(bufferList)
                .reduce(0) { $0 + Int($1.mNumberChannels) }
            if inputChannels > 0 && deviceName.lowercased().contains(name.lowercased()) {
                return deviceID
            }
        }
    }
    throw MicCapture.MicError.deviceNotFound(name)
}
