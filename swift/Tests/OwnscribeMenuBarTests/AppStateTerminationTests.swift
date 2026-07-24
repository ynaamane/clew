import XCTest
@testable import OwnscribeMenuBar

private final class SpyAudioMuteDevice: AudioMuteDevice {
    var setInputMuteCalls: [Bool] = []

    func isBluetooth() -> Bool { false }

    func setInputMute(_ muted: Bool) -> Bool {
        setInputMuteCalls.append(muted)
        return true
    }

    func readInputMute() -> Bool? {
        setInputMuteCalls.last
    }

    func nominalSampleRate() -> Double? { nil }
}

@MainActor
final class AppStateTerminationTests: XCTestCase {
    func testWillTerminateNotificationRestoresUnmuteWithoutTheQuitButton() {
        let device = SpyAudioMuteDevice()
        let appState = AppState(homeDir: FileManager.default.temporaryDirectory, muteDevice: device)
        appState.toggleMasterMute()
        XCTAssertTrue(appState.isMuted)
        device.setInputMuteCalls = []

        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApplication.shared)

        XCTAssertEqual(device.setInputMuteCalls, [false])
    }

    func testWillTerminateNotificationWhenAlreadyUnmutedDoesNothing() {
        let device = SpyAudioMuteDevice()
        let appState = AppState(homeDir: FileManager.default.temporaryDirectory, muteDevice: device)
        XCTAssertFalse(appState.isMuted)
        device.setInputMuteCalls = []

        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: NSApplication.shared)

        XCTAssertTrue(device.setInputMuteCalls.isEmpty)
    }
}
