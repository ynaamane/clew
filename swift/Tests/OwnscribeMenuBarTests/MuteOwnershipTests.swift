import XCTest
@testable import OwnscribeMenuBar

private final class PresetMuteDevice: AudioMuteDevice {
    var hardwareMuted: Bool
    var refuseRead = false
    var setInputMuteCalls: [Bool] = []

    init(hardwareMuted: Bool) {
        self.hardwareMuted = hardwareMuted
    }

    func isBluetooth() -> Bool { false }

    func setInputMute(_ muted: Bool) -> Bool {
        setInputMuteCalls.append(muted)
        hardwareMuted = muted
        return true
    }

    func readInputMute() -> Bool? {
        refuseRead ? nil : hardwareMuted
    }

    func nominalSampleRate() -> Double? { nil }
}

@MainActor
final class MuteOwnershipTests: XCTestCase {
    private var tempHome: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mute-ownership-\(UUID().uuidString)")
    }

    func testLaunchWithHardwareMutedSeedsIsMutedTrue() {
        let device = PresetMuteDevice(hardwareMuted: true)

        let state = AppState(homeDir: tempHome, muteDevice: device)

        XCTAssertTrue(
            state.isMuted,
            "When the mic is left muted by a crash or another app, the menu must show Unmute not Mute — seeding false produces a false sense of being live")
    }

    func testLaunchWithHardwareUnmutedSeedsIsMutedFalse() {
        let device = PresetMuteDevice(hardwareMuted: false)

        let state = AppState(homeDir: tempHome, muteDevice: device)

        XCTAssertFalse(state.isMuted)
    }

    func testLaunchWithUnreadableHardwareDefaultsToNotMuted() {
        let device = PresetMuteDevice(hardwareMuted: true)
        device.refuseRead = true

        let state = AppState(homeDir: tempHome, muteDevice: device)

        XCTAssertFalse(
            state.isMuted,
            "When the hardware cannot be read at all (nil return), default to NOT muted — the safer failure mode")
    }

    func testPreExistingMuteIsNotRestoredOnQuit() {
        let device = PresetMuteDevice(hardwareMuted: true)
        let state = AppState(homeDir: tempHome, muteDevice: device)
        XCTAssertTrue(state.isMuted, "precondition: observed the pre-existing mute")
        device.setInputMuteCalls = []

        state.restoreUnmutedOnQuit()

        XCTAssertTrue(
            device.setInputMuteCalls.isEmpty,
            "A pre-existing mute (the user muted in System Settings) must NOT be unmuted by this app on quit — that would silently unmute the user's own mute, which is the worse failure")
        XCTAssertTrue(
            state.isMuted,
            "isMuted should still be true for a pre-existing mute, since we didn't create it")
    }

    func testAppCreatedMuteIsRestoredOnQuit() {
        let device = PresetMuteDevice(hardwareMuted: false)
        let state = AppState(homeDir: tempHome, muteDevice: device)
        state.toggleMasterMute()
        XCTAssertTrue(state.isMuted, "precondition: the app successfully muted")
        device.setInputMuteCalls = []

        state.restoreUnmutedOnQuit()

        XCTAssertFalse(
            device.setInputMuteCalls.isEmpty,
            "An app-owned mute (toggled by this app) MUST be unmuted on quit — leaving it muted silently breaks every other app")
        XCTAssertFalse(device.hardwareMuted, "The hardware should now be unmuted")
        XCTAssertFalse(state.isMuted)
    }

    func testTogglingOffPreExistingMuteCreatesAppOwnership() {
        let device = PresetMuteDevice(hardwareMuted: true)
        let state = AppState(homeDir: tempHome, muteDevice: device)
        XCTAssertTrue(state.isMuted, "precondition: observed the pre-existing mute")

        state.toggleMasterMute()

        XCTAssertFalse(state.isMuted, "The toggle should unmute")

        state.toggleMasterMute()

        XCTAssertTrue(state.isMuted, "The second toggle should re-mute")
        device.setInputMuteCalls = []

        state.restoreUnmutedOnQuit()

        XCTAssertFalse(
            device.setInputMuteCalls.isEmpty,
            "Once the user toggles through this app (even starting from a pre-existing mute), the app now OWNS the mute state and must restore it on quit")
    }

    func testPreExistingMuteUsesVerifiedIndicatorWhenReadbackConfirms() {
        let device = PresetMuteDevice(hardwareMuted: true)

        let state = AppState(homeDir: tempHome, muteDevice: device)

        XCTAssertEqual(
            state.muteIndicator, .mutedVerified,
            "A pre-existing mute that is confirmed by readback IS verified — the readback proves the mic is actually muted")
    }
}
