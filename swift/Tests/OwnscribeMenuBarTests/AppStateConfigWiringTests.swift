import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class AppStateConfigWiringTests: XCTestCase {
    func testAppStateAppliesConfigMicSettingToRecordingController() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configDir = tempDir.appendingPathComponent(".config/ownscribe")
        try! FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let configPath = configDir.appendingPathComponent("config.toml")
        let configContent = """
        [audio]
        mic = false
        """
        try! configContent.write(to: configPath, atomically: true, encoding: .utf8)

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())

        XCTAssertFalse(
            state.isMicCaptureEnabled,
            "AppState must read [audio] mic from config and apply it to RecordingController so the setting is honored")
    }

    func testAppStateAppliesConfigSilenceTimeoutToRecordingController() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let configDir = tempDir.appendingPathComponent(".config/ownscribe")
        try! FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let configPath = configDir.appendingPathComponent("config.toml")
        let configContent = """
        [audio]
        silence_timeout = 120
        """
        try! configContent.write(to: configPath, atomically: true, encoding: .utf8)

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())

        let timeout = state.recordingControllerSilenceTimeout

        XCTAssertEqual(
            timeout,
            120,
            "AppState must read [audio] silence_timeout from config and apply it to RecordingController so auto-stop works as configured")
    }

    func testAppStateDefaultsToMicTrueWhenConfigAbsent() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())

        XCTAssertTrue(state.isMicCaptureEnabled, "Must default to mic = true matching CLI effective behavior (rec.sh always passes --mic) when config is absent, preserving BUG4 fix where owner's voice must be recorded")
    }

    func testAppStateDefaultsToSilenceTimeout300WhenConfigAbsent() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let state = AppState(homeDir: tempDir, muteDevice: StubMuteDevice())

        XCTAssertEqual(state.recordingControllerSilenceTimeout, 300, "Must default to 300 seconds matching CLI when config is absent")
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
