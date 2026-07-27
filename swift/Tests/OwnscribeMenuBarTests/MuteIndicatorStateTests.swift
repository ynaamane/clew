import XCTest
@testable import OwnscribeCapture
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

@MainActor
final class RecordingStateSurfaceTests: XCTestCase {
    private var tempHome: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("recstate-\(UUID().uuidString)")
    }

    func testIsRecordingReflectsTheRecordingPhase() async throws {
        let state = AppState(homeDir: tempHome, muteDevice: ConfigurableMuteDevice())
        let fake = RecordingStateFakeCapture()
        state.systemCaptureFactory = { _ in fake }
        state.isMicCaptureEnabled = false

        XCTAssertFalse(state.isRecording)

        await state.toggleRecording()

        XCTAssertTrue(
            state.isRecording,
            "The window's record button reads this; a constant false makes it say \"Enregistrer\" while a recording is live")
    }

    func testIsRecordingIsFalseOnceProcessingStarts() async throws {
        let state = AppState(homeDir: tempHome, muteDevice: ConfigurableMuteDevice())
        let fake = RecordingStateFakeCapture()
        state.systemCaptureFactory = { _ in fake }
        state.isMicCaptureEnabled = false

        await state.toggleRecording()
        await state.toggleRecording()

        XCTAssertFalse(state.isRecording, "Processing is not recording; the button must not offer to stop a finished capture")
    }
}

private final class RecordingStateFakeCapture: SystemAudioCapturing {
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var micCapture: MicCapture?
    var startHostTime: UInt64 = 0

    func start() async throws { startHostTime = mach_absolute_time() }
    func stop() {}
}
