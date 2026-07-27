import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class RecordingMicEnabledTests: XCTestCase {
    func testMicCaptureIsEnabledByDefaultSoTheOwnerVoiceIsRecorded() {
        let controller = RecordingController()

        XCTAssertTrue(
            controller.enableMic,
            "Mic capture must default to on: the owner's own voice is the only track that can carry it, and a call recorded without it loses half the conversation.")
    }

    func testAppStateStartsRecordingWithMicEnabled() {
        let state = AppState(homeDir: FileManager.default.temporaryDirectory, muteDevice: StubMuteDevice())

        XCTAssertTrue(
            state.isMicCaptureEnabled,
            "AppState must drive the controller with mic capture on, otherwise the menu-bar app can never record the owner.")
    }

    func testDisablingMicIsPossibleForSystemOnlyCapture() {
        let controller = RecordingController()

        controller.enableMic = false

        XCTAssertFalse(controller.enableMic)
    }

    func testTempPathsSplitTracksOnlyWhenMicIsEnabled() {
        let withMic = RecordingTempPaths(outputPath: "/tmp/x/recording.wav", micEnabled: true)
        let withoutMic = RecordingTempPaths(outputPath: "/tmp/x/recording.wav", micEnabled: false)

        XCTAssertNotEqual(
            withMic.systemPath, "/tmp/x/recording.wav",
            "With mic on, the system track must land on a temp path so the merge can write the final file.")
        XCTAssertEqual(
            withoutMic.systemPath, "/tmp/x/recording.wav",
            "With mic off there is no merge step, so the system track must be written straight to the final path.")
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
