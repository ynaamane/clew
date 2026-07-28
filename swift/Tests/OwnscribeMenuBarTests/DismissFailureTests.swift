import XCTest
@testable import OwnscribeMenuBar
@testable import OwnscribeCapture

@MainActor
final class DismissFailureTests: XCTestCase {
    func testDismissFailureTransitionsFromFailedToIdle() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())
        state.systemCaptureFactory = { _ in ThrowingSystemCapture() }
        state.isMicCaptureEnabled = false
        state.micCaptureFactory = { nil }

        XCTAssertEqual(state.phase, .idle)
        await state.toggleRecording()
        guard case .failed = state.phase else {
            XCTFail("Expected .failed phase, got \(state.phase)")
            return
        }

        state.dismissFailure()

        XCTAssertEqual(state.phase, .idle, "dismissFailure must transition from .failed to .idle")
    }

    func testDismissFailureIsNoOpFromRecording() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())
        state.systemCaptureFactory = { _ in StubSystemCapture() }
        state.isMicCaptureEnabled = false
        state.micCaptureFactory = { nil }

        await state.toggleRecording()
        guard case .recording = state.phase else {
            XCTFail("Failed to reach recording state")
            return
        }
        let recordingPhase = state.phase

        state.dismissFailure()

        XCTAssertEqual(state.phase, recordingPhase, "dismissFailure must NOT abort a live recording")
    }

    func testDismissFailureIsNoOpWhenAlreadyIdle() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())
        XCTAssertEqual(state.phase, .idle)

        state.dismissFailure()

        XCTAssertEqual(state.phase, .idle, "dismissFailure must be idempotent when already idle")
    }
}

private final class StubMuteDevice: AudioMuteDevice {
    private var muted = false

    func isBluetooth() -> Bool { false }

    func setInputMute(_ muted: Bool) -> Bool {
        self.muted = muted
        return true
    }

    func readInputMute() -> Bool? { muted }

    func nominalSampleRate() -> Double? { nil }
}

private final class StubSystemCapture: SystemAudioCapturing {
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var micCapture: MicCapture?
    var startHostTime: UInt64 = 0

    func start() async throws { startHostTime = mach_absolute_time() }
    func stop() {}
}

private final class ThrowingSystemCapture: SystemAudioCapturing {
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var micCapture: MicCapture?
    var startHostTime: UInt64 = 0

    func start() async throws {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Capture failed"])
    }
    func stop() {}
}
