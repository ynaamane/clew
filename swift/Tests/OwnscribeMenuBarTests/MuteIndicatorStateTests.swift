import XCTest
@testable import OwnscribeMenuBar

private final class ConfigurableMuteDevice: AudioMuteDevice {
    var bluetooth = false
    var refuseSet = false
    var hardwareMuted = false

    func isBluetooth() -> Bool { bluetooth }

    func setInputMute(_ muted: Bool) -> Bool {
        if refuseSet { return false }
        hardwareMuted = muted
        return true
    }

    func readInputMute() -> Bool? { hardwareMuted }

    func nominalSampleRate() -> Double? { nil }
}

@MainActor
final class MuteIndicatorStateTests: XCTestCase {
    private var tempHome: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mute-\(UUID().uuidString)")
    }

    func testUnverifiedMuteIsNotReportedAsMuted() {
        let device = ConfigurableMuteDevice()
        device.bluetooth = true
        device.refuseSet = true
        let state = AppState(homeDir: tempHome, muteDevice: device)

        state.toggleMasterMute()

        XCTAssertEqual(
            state.muteIndicator, .mutedUnverified,
            "When the hardware refuses the mute, the app must report it as UNVERIFIED — reporting plain muted tells the user Zoom cannot hear them when it still can")
    }

    func testVerifiedMuteIsReportedAsVerified() {
        let device = ConfigurableMuteDevice()
        let state = AppState(homeDir: tempHome, muteDevice: device)

        state.toggleMasterMute()

        XCTAssertEqual(state.muteIndicator, .mutedVerified)
    }

    func testUnmutedIsTheDefaultWhenHardwareIsLive() {
        let device = ConfigurableMuteDevice()
        let state = AppState(homeDir: tempHome, muteDevice: device)

        XCTAssertEqual(state.muteIndicator, .notMuted)
    }

    func testEachIndicatorStateHasItsOwnSymbol() {
        let symbols = Set([
            MuteIndicator.notMuted.symbolName,
            MuteIndicator.mutedVerified.symbolName,
            MuteIndicator.mutedUnverified.symbolName,
        ])

        XCTAssertEqual(
            symbols.count, 3,
            "The three mute states must be visually distinct in the menu bar; sharing a symbol is what let an unverified mute look like a verified one")
    }

    func testUnverifiedMuteStillRaisesTheWarning() {
        let device = ConfigurableMuteDevice()
        device.refuseSet = true
        let state = AppState(homeDir: tempHome, muteDevice: device)

        state.toggleMasterMute()

        XCTAssertNotNil(state.muteWarning)
    }
}
