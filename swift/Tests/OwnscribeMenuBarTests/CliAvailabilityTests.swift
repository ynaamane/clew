import XCTest
@testable import OwnscribeMenuBar
@testable import OwnscribeCapture

@MainActor
final class CliAvailabilityTests: XCTestCase {
    func testBannerStateShowsWarningWhenCliUnavailable() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: false
        )

        XCTAssertNotNil(result, "Must show banner when CLI unavailable")
        XCTAssertEqual(result?.severity, .warning)
        XCTAssertFalse(result!.isDismissible, "CLI warning must not be dismissible - user must fix the venv")
        XCTAssertTrue(
            result!.message.contains("transcribe") || result!.message.contains("CLI"),
            "Message must mention transcription or CLI being unavailable"
        )
    }

    func testBannerStateOmitsCliWarningWhenCliAvailable() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: true
        )

        XCTAssertNil(result, "Must not show banner when CLI is available and no other issues")
    }

    func testFailedPhaseTakesPrecedenceOverCliWarning() {
        let result = BannerState.bannerState(
            phase: .failed("Recording failed"),
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: false
        )

        XCTAssertEqual(result?.severity, .error)
        XCTAssertEqual(result?.message, "Recording failed")
    }

    func testMuteWarningTakesPrecedenceOverCliWarning() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: "The call may still hear you",
            muteIndicator: .mutedUnverified,
            isCliAvailable: false
        )

        XCTAssertEqual(result?.severity, .warning)
        XCTAssertEqual(result?.message, "The call may still hear you")
    }

    func testRefreshCliAvailabilityFindsNewBinary() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())
        XCTAssertFalse(state.isCliAvailable, "No venv exists yet")

        let venvDir = tempDir.appendingPathComponent("meeting-scribe/.venv/bin")
        try FileManager.default.createDirectory(at: venvDir, withIntermediateDirectories: true)
        let binaryPath = venvDir.appendingPathComponent("ownscribe")
        try "#!/bin/sh\necho test".write(to: binaryPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)

        state.refreshCliAvailability()

        XCTAssertTrue(state.isCliAvailable, "Must detect newly created binary")
    }

    func testRefreshCliAvailabilityDetectsMissingBinary() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let venvDir = tempDir.appendingPathComponent("meeting-scribe/.venv/bin")
        try FileManager.default.createDirectory(at: venvDir, withIntermediateDirectories: true)
        let binaryPath = venvDir.appendingPathComponent("ownscribe")
        try "#!/bin/sh\necho test".write(to: binaryPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())
        XCTAssertTrue(state.isCliAvailable, "Binary exists at init")

        try FileManager.default.removeItem(at: binaryPath)

        state.refreshCliAvailability()

        XCTAssertFalse(state.isCliAvailable, "Must detect binary removal")
    }

    func testToggleRecordingRefreshesCliAvailabilityBeforeStarting() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())
        state.systemCaptureFactory = { _ in StubSystemCapture() }
        state.micCaptureFactory = { nil }
        XCTAssertFalse(state.isCliAvailable, "No binary at init")

        let venvDir = tempDir.appendingPathComponent("meeting-scribe/.venv/bin")
        try FileManager.default.createDirectory(at: venvDir, withIntermediateDirectories: true)
        let binaryPath = venvDir.appendingPathComponent("ownscribe")
        try "#!/bin/sh\necho test".write(to: binaryPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)

        await state.toggleRecording()

        XCTAssertTrue(state.isCliAvailable, "toggleRecording must call refreshCliAvailability before starting")
    }

    func testRefreshCliAvailabilityRespectsInjectedFactory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var factoryCallCount = 0
        let fakePipelineRunner = FakePipelineRunner()

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())
        state.pipelineRunnerFactory = {
            factoryCallCount += 1
            return fakePipelineRunner
        }
        state.systemCaptureFactory = { _ in StubSystemCapture() }
        state.micCaptureFactory = { nil }

        let initialCount = factoryCallCount
        await state.toggleRecording()

        XCTAssertEqual(
            factoryCallCount,
            initialCount + 1,
            "refreshCliAvailability must call the injected factory, not makeDefault, so the seam stays honest"
        )
        XCTAssertTrue(state.isCliAvailable, "Fake runner means CLI is available")
    }
}

private final class FakePipelineRunner: PipelineRunning {
    func run(arguments: [String], onEvent: @escaping @Sendable (ProgressEvent) -> Void) async throws {}
    func cancel() {}
}

private final class StubSystemCapture: SystemAudioCapturing {
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var micCapture: MicCapture?
    var startHostTime: UInt64 = 0

    func start() async throws { startHostTime = mach_absolute_time() }
    func stop() {}
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
