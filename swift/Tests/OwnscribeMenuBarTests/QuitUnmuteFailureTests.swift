import XCTest
@testable import OwnscribeMenuBar

private final class UnmuteFailingDevice: AudioMuteDevice {
    private var muteState = false
    var failUnmute = false
    var setInputMuteCalls: [Bool] = []

    func isBluetooth() -> Bool { true }

    func setInputMute(_ muted: Bool) -> Bool {
        setInputMuteCalls.append(muted)
        if !muted && failUnmute { return false }
        muteState = muted
        return true
    }

    func readInputMute() -> Bool? { muteState }

    func nominalSampleRate() -> Double? { nil }
}

@MainActor
final class QuitUnmuteFailureTests: XCTestCase {
    private var recordPath: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("quit-unmute-\(UUID().uuidString)")
    }

    func testFailedUnmuteOnQuitIsRetriedBeforeGivingUp() {
        let device = UnmuteFailingDevice()
        let state = AppState(homeDir: recordPath, muteDevice: device)
        state.toggleMasterMute()
        XCTAssertTrue(state.isMuted)
        device.failUnmute = true
        device.setInputMuteCalls = []

        state.restoreUnmutedOnQuit()

        XCTAssertGreaterThan(
            device.setInputMuteCalls.count, 1,
            "A failed unmute on quit must be retried — one silent attempt leaves the user's microphone muted system-wide for every other app after the recorder is gone")
    }

    func testFailedUnmuteOnQuitDoesNotClaimTheMicIsLive() {
        let device = UnmuteFailingDevice()
        let state = AppState(homeDir: recordPath, muteDevice: device)
        state.toggleMasterMute()
        device.failUnmute = true

        state.restoreUnmutedOnQuit()

        XCTAssertTrue(
            state.isMuted,
            "When the hardware unmute fails the app must not report itself unmuted; it is still muted and the user needs to know")
        XCTAssertNotNil(
            state.muteWarning,
            "A failed unmute on quit must raise a warning — silently leaving the mic muted is the failure this guard exists to prevent")
    }

    func testSuccessfulUnmuteOnQuitStaysSilentAndTouchesHardwareOnce() {
        let device = UnmuteFailingDevice()
        let state = AppState(homeDir: recordPath, muteDevice: device)
        state.toggleMasterMute()
        device.setInputMuteCalls = []

        state.restoreUnmutedOnQuit()

        XCTAssertEqual(device.setInputMuteCalls, [false])
        XCTAssertFalse(state.isMuted)
        XCTAssertNil(state.muteWarning)
    }
}
