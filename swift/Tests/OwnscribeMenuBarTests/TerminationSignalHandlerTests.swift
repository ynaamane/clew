import XCTest
@testable import OwnscribeMenuBar

@MainActor
private final class FakeTerminationSignalSource: TerminationSignalSource {
    private let signalNumber: Int32
    private let recorder: SignalWiringRecorder

    init(signalNumber: Int32, recorder: SignalWiringRecorder) {
        self.signalNumber = signalNumber
        self.recorder = recorder
    }

    func setHandler(_ handler: @escaping () -> Void) {
        recorder.handlerInstalled(for: signalNumber, handler: handler)
    }

    func begin() {
        recorder.sourceBegan(signalNumber)
    }
}

private final class WeakSourceBox {
    weak var source: FakeTerminationSignalSource?

    init(_ source: FakeTerminationSignalSource) {
        self.source = source
    }
}

@MainActor
private final class SignalWiringRecorder {
    enum WiringStep: Equatable {
        case ignoredDefaultDisposition(Int32)
        case madeSource(Int32)
        case handlerInstalled(Int32)
        case sourceBegan(Int32)
    }

    enum HandlerAction: Equatable {
        case restoredUnmute
        case terminated
    }

    private(set) var wiring: [WiringStep] = []
    private(set) var handlerActions: [HandlerAction] = []
    private var handlers: [Int32: () -> Void] = [:]
    private var sourceBoxes: [WeakSourceBox] = []

    func ignoreDefaultDisposition(_ signalNumber: Int32) {
        wiring.append(.ignoredDefaultDisposition(signalNumber))
    }

    func makeSource(_ signalNumber: Int32) -> TerminationSignalSource {
        wiring.append(.madeSource(signalNumber))
        let source = FakeTerminationSignalSource(signalNumber: signalNumber, recorder: self)
        sourceBoxes.append(WeakSourceBox(source))
        return source
    }

    func handlerInstalled(for signalNumber: Int32, handler: @escaping () -> Void) {
        wiring.append(.handlerInstalled(signalNumber))
        handlers[signalNumber] = handler
    }

    func sourceBegan(_ signalNumber: Int32) {
        wiring.append(.sourceBegan(signalNumber))
    }

    func recordRestoredUnmute() {
        handlerActions.append(.restoredUnmute)
    }

    func recordTerminated() {
        handlerActions.append(.terminated)
    }

    var registeredSignals: [Int32] {
        wiring.compactMap { step in
            guard case .madeSource(let signalNumber) = step else { return nil }
            return signalNumber
        }
    }

    var liveSourceCount: Int {
        sourceBoxes.filter { $0.source != nil }.count
    }

    func fireHandler(for signalNumber: Int32) -> Bool {
        guard let handler = handlers[signalNumber] else { return false }
        handler()
        return true
    }

    func indexOfStep(_ step: WiringStep) -> Int? {
        wiring.firstIndex(of: step)
    }
}

private final class SpyMuteDevice: AudioMuteDevice {
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
final class TerminationSignalHandlerTests: XCTestCase {
    private func makeRecordedHandlers(
        _ recorder: SignalWiringRecorder
    ) -> TerminationSignalHandlers {
        TerminationSignalHandlers(
            makeSource: { recorder.makeSource($0) },
            ignoreDefaultDisposition: { recorder.ignoreDefaultDisposition($0) },
            onTerminate: { recorder.recordTerminated() })
    }

    func testBothSigtermAndSigintAreRegistered() {
        let recorder = SignalWiringRecorder()
        let handlers = makeRecordedHandlers(recorder)

        handlers.register(restoreUnmuted: { recorder.recordRestoredUnmute() })

        XCTAssertEqual(
            recorder.registeredSignals.count, 2,
            "Exactly two termination signals must be wired; anything else means the list drifted")
        XCTAssertEqual(
            Set(recorder.registeredSignals), Set([SIGTERM, SIGINT]),
            "killall sends SIGTERM and ⌃C sends SIGINT. Missing either one means that exit path skips restoreUnmutedOnQuit and leaves the user's microphone muted system-wide after the app is gone.")
    }

    func testTheDefaultDispositionIsIgnoredBeforeEachSourceBegins() {
        let recorder = SignalWiringRecorder()
        let handlers = makeRecordedHandlers(recorder)

        handlers.register(restoreUnmuted: { recorder.recordRestoredUnmute() })

        for signalNumber in [SIGTERM, SIGINT] {
            guard let ignoredAt = recorder.indexOfStep(.ignoredDefaultDisposition(signalNumber)),
                  let beganAt = recorder.indexOfStep(.sourceBegan(signalNumber)) else {
                XCTFail("signal \(signalNumber) was neither set to ignore nor begun")
                continue
            }
            XCTAssertLessThan(
                ignoredAt, beganAt,
                "signal \(signalNumber): the default disposition must be set to ignore BEFORE the source is resumed. The default disposition terminates the process immediately, so a signal arriving in that window kills the app before the unmute handler ever runs.")
        }
    }

    func testEverySourceIsBegun() {
        let recorder = SignalWiringRecorder()
        let handlers = makeRecordedHandlers(recorder)

        handlers.register(restoreUnmuted: { recorder.recordRestoredUnmute() })

        for signalNumber in [SIGTERM, SIGINT] {
            XCTAssertNotNil(
                recorder.indexOfStep(.sourceBegan(signalNumber)),
                "signal \(signalNumber): a DispatchSourceSignal that is never resumed delivers nothing. Creating the source is not registering it.")
        }
    }

    func testFiringAHandlerRestoresTheUnmuteBeforeTerminating() {
        let recorder = SignalWiringRecorder()
        let handlers = makeRecordedHandlers(recorder)
        handlers.register(restoreUnmuted: { recorder.recordRestoredUnmute() })

        XCTAssertTrue(recorder.fireHandler(for: SIGTERM), "no handler was installed for SIGTERM")

        XCTAssertEqual(
            recorder.handlerActions, [.restoredUnmute, .terminated],
            "The unmute must run BEFORE the terminate. NSApplication.terminate tears the process down, so anything sequenced after it may never run — and what would be skipped here is the system-wide unmute.")
    }

    func testEverySignalGetsAHandlerThatRestoresTheUnmute() {
        for signalNumber in [SIGTERM, SIGINT] {
            let recorder = SignalWiringRecorder()
            let handlers = makeRecordedHandlers(recorder)
            handlers.register(restoreUnmuted: { recorder.recordRestoredUnmute() })

            XCTAssertTrue(
                recorder.fireHandler(for: signalNumber),
                "signal \(signalNumber) has no handler, so that exit path cannot restore the mic")
            XCTAssertEqual(
                recorder.handlerActions, [.restoredUnmute, .terminated],
                "signal \(signalNumber) must restore the unmute then terminate")
        }
    }

    func testTheSignalSourcesAreRetainedAfterRegistration() {
        let recorder = SignalWiringRecorder()
        let handlers = makeRecordedHandlers(recorder)

        handlers.register(restoreUnmuted: { recorder.recordRestoredUnmute() })

        XCTAssertEqual(
            recorder.liveSourceCount, 2,
            "A deallocated DispatchSourceSignal stops delivering — measured: an unretained source's handler never ran while a retained one's did. If a refactor drops the sources array the app silently stops restoring the mic on SIGTERM, with every other test still green.")
        _ = handlers
    }

    func testAFiredTerminationSignalUnmutesTheDeviceTheAppMuted() {
        let recorder = SignalWiringRecorder()
        let device = SpyMuteDevice()
        let appState = AppState(
            homeDir: temporaryHome(),
            muteDevice: device,
            terminationSignals: makeRecordedHandlers(recorder))
        appState.toggleMasterMute()
        XCTAssertTrue(appState.isMuted, "precondition: the app owns a verified mute")
        device.setInputMuteCalls = []

        XCTAssertTrue(recorder.fireHandler(for: SIGTERM), "AppState never installed a SIGTERM handler")

        XCTAssertEqual(
            device.setInputMuteCalls, [false],
            "A SIGTERM must reach the hardware unmute. This is the killall path in APP_TEST.md: without it the mic stays muted for Zoom and every other app after the process dies.")
    }

    func testAFiredTerminationSignalLeavesAMuteTheAppDoesNotOwnAlone() {
        let recorder = SignalWiringRecorder()
        let device = SpyMuteDevice()
        _ = device.setInputMute(true)
        let appState = AppState(
            homeDir: temporaryHome(),
            muteDevice: device,
            terminationSignals: makeRecordedHandlers(recorder))
        XCTAssertTrue(appState.isMuted, "precondition: launched into a pre-existing mute")
        device.setInputMuteCalls = []

        XCTAssertTrue(recorder.fireHandler(for: SIGTERM), "AppState never installed a SIGTERM handler")

        XCTAssertTrue(
            device.setInputMuteCalls.isEmpty,
            "The signal handler must go through restoreUnmutedOnQuit, which owns the appOwnsMute guard. Unmuting a mute the user set in System Settings is worse than the problem it fixes.")
    }

    func testAppStateRetainsItsTerminationSignalHandlers() {
        let recorder = SignalWiringRecorder()
        let device = SpyMuteDevice()
        var handlers: TerminationSignalHandlers? = makeRecordedHandlers(recorder)
        let appState = AppState(
            homeDir: temporaryHome(),
            muteDevice: device,
            terminationSignals: handlers)
        appState.toggleMasterMute()
        device.setInputMuteCalls = []
        handlers = nil

        XCTAssertEqual(
            recorder.liveSourceCount, 2,
            "AppState must own the handlers for the app's lifetime. Registering into a local that dies at the end of init releases the sources and the SIGTERM path goes silently dead.")
        XCTAssertTrue(recorder.fireHandler(for: SIGTERM), "no SIGTERM handler survived")
        XCTAssertEqual(device.setInputMuteCalls, [false], "the surviving handler must still unmute")
    }

    func testTheProductionDefaultsAreTheRealSignalWiring() {
        let handlers = TerminationSignalHandlers()

        XCTAssertEqual(
            Set(TerminationSignalHandlers.terminationSignals), Set([SIGTERM, SIGINT]),
            "the shipped signal list is what every injected test above stands in for")
        XCTAssertNotNil(handlers, "the production initializer must build without any injection")
    }

    private func temporaryHome() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("termsignal-\(UUID().uuidString)")
    }
}
