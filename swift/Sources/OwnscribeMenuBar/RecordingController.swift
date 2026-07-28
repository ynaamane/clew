import CoreGraphics
import Foundation
import OwnscribeCapture

@MainActor
@Observable
public final class RecordingController {
    public enum State: Equatable {
        case idle
        case recording(startedAt: Date)
        case stopping
    }

    public enum RecordingError: Error, CustomStringConvertible {
        case permissionDenied
        case unsupportedOSVersion
        case notRecording
        case alreadyRecording

        public var description: String {
            switch self {
            case .permissionDenied: return "System Audio Recording or Microphone permission is not granted."
            case .unsupportedOSVersion: return "CoreAudio process-tap capture requires macOS 14.2 or later."
            case .notRecording: return "No recording is in progress."
            case .alreadyRecording: return "A recording is already in progress."
            }
        }
    }

    public private(set) var state: State = .idle

    public var enableMic: Bool = true
    public var micDeviceName: String?
    public var silenceTimeout: TimeInterval = 0
    public var onSilenceTimeout: (() -> Void)?

    private var systemCapture: SystemAudioCapturing?
    private var micCapture: MicCapture?
    private var currentOutputPath: String?
    private var currentTempPaths: RecordingTempPaths?

    var mergeAudioFilesImpl: (String, String, UInt64, UInt64, String) throws -> Void = mergeAudioFiles

    var makeSystemCapture: ((String) -> SystemAudioCapturing)?

    var makeMicCapture: (() -> MicCapture?) = { MicCapture() }

    var startMicCapture: ((MicCapture, String, String?) throws -> Void) = { mic, path, deviceName in
        try mic.start(outputPath: path, deviceName: deviceName, echoCancellation: "off")
    }

    public init() {}

    public var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    public var isLocalMicMuted: Bool {
        micCapture?.isMuted ?? false
    }

    @discardableResult
    public func setLocalMicMute(_ muted: Bool) -> Bool {
        guard let mic = micCapture else { return false }
        if mic.isMuted != muted {
            mic.toggleMute()
        }
        return mic.isMuted
    }

    private func makeCapture(outputPath: String) throws -> SystemAudioCapturing {
        if let makeSystemCapture {
            return makeSystemCapture(outputPath)
        }
        guard #available(macOS 14.2, *) else {
            throw RecordingError.unsupportedOSVersion
        }
        CoreAudioTapCapture.cleanupStaleAggregateDevices()
        return CoreAudioTapCapture(outputPath: outputPath)
    }

    public func start(outputPath: String) async throws {
        guard state == .idle else { throw RecordingError.alreadyRecording }

        if !preflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
        }
        guard runCoreAudioTapPermissionPreflight(needsMic: enableMic) else {
            throw RecordingError.permissionDenied
        }

        guard #available(macOS 14.2, *) else {
            throw RecordingError.unsupportedOSVersion
        }

        let tempPaths = RecordingTempPaths(outputPath: outputPath, micEnabled: enableMic)
        currentOutputPath = outputPath
        currentTempPaths = tempPaths

        var capture = try makeCapture(outputPath: tempPaths.systemPath)
        capture.silenceTimeout = silenceTimeout
        capture.onSilenceTimeout = { [weak self] in
            Task { @MainActor [weak self] in
                self?.onSilenceTimeout?()
            }
        }

        if enableMic, let mic = makeMicCapture() {
            try startMicCapture(mic, tempPaths.micPath, micDeviceName)
            micCapture = mic
            capture.micCapture = mic
        }

        try await capture.start()
        systemCapture = capture
        state = .recording(startedAt: Date())
    }

    public func stop() throws -> URL {
        guard case .recording = state, let outputPath = currentOutputPath else {
            throw RecordingError.notRecording
        }
        state = .stopping

        defer {
            systemCapture = nil
            micCapture = nil
            currentOutputPath = nil
            currentTempPaths = nil
            state = .idle
        }

        systemCapture?.stop()
        micCapture?.stop()

        if enableMic, let tempPaths = currentTempPaths,
           let capture = systemCapture, let mic = micCapture {
            try mergeAudioFilesImpl(
                tempPaths.systemPath,
                tempPaths.micPath,
                capture.startHostTime,
                mic.startHostTime,
                outputPath)
        }

        return URL(fileURLWithPath: outputPath)
    }
}
