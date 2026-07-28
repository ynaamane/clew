import XCTest
@testable import OwnscribeMenuBar
@testable import OwnscribeCapture

@MainActor
final class RecordingControllerSilenceTimeoutTests: XCTestCase {
    func testSilenceTimeoutReachesAppStateAndStopsRecording() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())
        let fakeCapture = FakeSystemAudioCapture()
        state.systemCaptureFactory = { _ in fakeCapture }
        state.isMicCaptureEnabled = false

        await state.toggleRecording()

        guard case .recording = state.phase else {
            XCTFail("AppState must be recording before silence timeout fires")
            return
        }

        fakeCapture.onSilenceTimeout?()
        try await Task.sleep(for: .milliseconds(100))

        if case .recording = state.phase {
            XCTFail("After silence timeout fires through the capture, AppState must leave .recording and move to .processing or .done so the app actually auto-stops")
        }
    }

    func testSilenceTimeoutDuringProcessingIsNoOp() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())
        let fakeCapture = FakeSystemAudioCapture()
        state.systemCaptureFactory = { _ in fakeCapture }
        state.isMicCaptureEnabled = false

        await state.toggleRecording()

        guard case .recording = state.phase else {
            XCTFail("AppState must be recording before we stop it")
            return
        }

        await state.toggleRecording()

        if case .recording = state.phase {
            XCTFail("AppState must have left .recording before the late timeout fires")
            return
        }
        let phaseAfterStop = state.phase

        fakeCapture.onSilenceTimeout?()
        try await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(
            state.phase, phaseAfterStop,
            "A silence timeout landing after the recording already stopped must be a no-op, not flip the user to .failed with notRecording after a recording that finished fine")
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

private final class FakeSystemAudioCapture: SystemAudioCapturing {
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var micCapture: MicCapture?
    var startHostTime: UInt64 = 0

    func start() async throws {
        startHostTime = mach_absolute_time()
    }

    func stop() {
    }
}
