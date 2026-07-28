import XCTest
@testable import OwnscribeCapture
@testable import OwnscribeMenuBar

@MainActor
final class RealHardwareMuteTests: XCTestCase {
    private var device: DefaultInputAudioMuteDevice!
    private var stateAtStart: Bool!

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OWNSCRIBE_TEST_REAL_MUTE"] == "1",
            "Mutes the machine's real input device. Run with OWNSCRIBE_TEST_REAL_MUTE=1, on the built-in mic only — the documented macOS Bluetooth mute bug makes AirPods the case this suite cannot assert against.")

        device = DefaultInputAudioMuteDevice()
        try XCTSkipIf(
            device.isBluetooth(),
            "Default input is Bluetooth. setInputMute is unreliable there by documented macOS bug, so a failure would not distinguish our logic from the platform's.")

        stateAtStart = try XCTUnwrap(
            device.readInputMute(),
            "Cannot read the input device's mute state, so the test cannot restore what it changes.")
    }

    override func tearDown() {
        guard let device, let stateAtStart else { return }
        _ = device.setInputMute(stateAtStart)
        XCTAssertEqual(
            device.readInputMute(), stateAtStart,
            "FAILED TO RESTORE the machine's mute state — the mic may be left muted. Check System Settings > Sound > Input.")
    }

    func testAPreExistingMuteSurvivesQuit() throws {
        XCTAssertTrue(device.setInputMute(true), "precondition: the device accepted a mute")
        XCTAssertEqual(device.readInputMute(), true, "precondition: hardware reports muted")

        let state = AppState(homeDir: temporaryHome(), muteDevice: device)

        XCTAssertTrue(
            state.isMuted,
            "Launching with the mic already muted must show muted — reporting live is how a user joins a call believing they are heard")
        XCTAssertEqual(state.muteIndicator, .mutedVerified, "a read-back-confirmed mute IS verified")

        state.restoreUnmutedOnQuit()

        XCTAssertEqual(
            device.readInputMute(), true,
            "THE CRITICAL ASSERTION: quitting must NOT unmute a mute this app never made. Undoing the user's own System Settings mute silently is worse than the stale display it fixes.")
    }

    func testAnAppOwnedMuteIsUndoneOnQuit() throws {
        XCTAssertTrue(device.setInputMute(false), "precondition: start unmuted")

        let state = AppState(homeDir: temporaryHome(), muteDevice: device)
        XCTAssertFalse(state.isMuted, "precondition: seeded unmuted")

        state.toggleMasterMute()

        XCTAssertEqual(device.readInputMute(), true, "the app's own mute must reach the hardware")
        XCTAssertEqual(state.muteIndicator, .mutedVerified)

        state.restoreUnmutedOnQuit()

        XCTAssertEqual(
            device.readInputMute(), false,
            "A mute this app made MUST be undone on quit, or the mic is left muted system-wide for every other app with no warning")
        XCTAssertFalse(state.isMuted)
    }

    func testTogglingThroughTheAppTakesOwnershipOfAPreExistingMute() throws {
        XCTAssertTrue(device.setInputMute(true), "precondition: a mute the app did not make")

        let state = AppState(homeDir: temporaryHome(), muteDevice: device)
        state.toggleMasterMute()
        XCTAssertEqual(device.readInputMute(), false, "the first toggle unmutes")

        state.toggleMasterMute()
        XCTAssertEqual(device.readInputMute(), true, "the second toggle re-mutes, and the app now owns it")

        state.restoreUnmutedOnQuit()

        XCTAssertEqual(
            device.readInputMute(), false,
            "Once the user has toggled through this app the app owns the state, so quit must restore it even though the mute began as pre-existing")
    }

    private func temporaryHome() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("realmute-\(UUID().uuidString)")
    }
}
