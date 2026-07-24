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

        public var description: String {
            switch self {
            case .permissionDenied: return "System Audio Recording or Microphone permission is not granted."
            case .unsupportedOSVersion: return "CoreAudio process-tap capture requires macOS 14.2 or later."
            case .notRecording: return "No recording is in progress."
            }
        }
    }

    public private(set) var state: State = .idle

    public var enableMic: Bool = false
    public var micDeviceName: String?
    public var silenceTimeout: TimeInterval = 0

    private var systemCapture: SystemAudioCapturing?
    private var micCapture: MicCapture?
    private var currentOutputPath: String?
    private var currentTempPaths: RecordingTempPaths?

    public init() {}

    public var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    public func start(outputPath: String) async throws {
        guard state == .idle else { return }

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

        CoreAudioTapCapture.cleanupStaleAggregateDevices()
        let capture = CoreAudioTapCapture(outputPath: tempPaths.systemPath)
        capture.silenceTimeout = silenceTimeout

        if enableMic {
            let mic = MicCapture()
            try mic.start(outputPath: tempPaths.micPath, deviceName: micDeviceName, echoCancellation: "off")
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

        systemCapture?.stop()
        micCapture?.stop()

        if enableMic, let tempPaths = currentTempPaths,
           let capture = systemCapture, let mic = micCapture {
            try mergeAudioFiles(
                systemPath: tempPaths.systemPath,
                micPath: tempPaths.micPath,
                systemStartHostTime: capture.startHostTime,
                micStartHostTime: mic.startHostTime,
                outputPath: outputPath)
        }

        systemCapture = nil
        micCapture = nil
        currentOutputPath = nil
        currentTempPaths = nil
        state = .idle
        return URL(fileURLWithPath: outputPath)
    }
}
