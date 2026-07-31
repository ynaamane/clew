import XCTest
@testable import OwnscribeMenuBar

final class TestRunnerSignalHygieneTests: XCTestCase {
    private func disposition(_ signalNumber: Int32) -> Int {
        var current = sigaction()
        sigaction(signalNumber, nil, &current)
        return unsafeBitCast(current.__sigaction_u.__sa_handler, to: Int.self)
    }

    @MainActor
    func testConstructingAppStateDoesNotLeaveTheTestRunnerUnkillable() {
        let ignore = 1
        let before = TerminationSignalHandlers.terminationSignals.map(disposition)

        _ = AppState(
            homeDir: FileManager.default.temporaryDirectory
                .appendingPathComponent("signal-hygiene-\(UUID().uuidString)"),
            muteDevice: NeverMutesDevice(),
            terminationSignals: TerminationSignalHandlers(
                makeSource: { _ in UnusedSignalSource() },
                ignoreDefaultDisposition: { _ in },
                onTerminate: {}))

        let after = TerminationSignalHandlers.terminationSignals.map(disposition)

        XCTAssertEqual(
            before, after,
            "An AppState built with an injected termination seam must not touch the PROCESS's signal dispositions. This matters because 39 AppState constructions happen across this suite: every one that does NOT inject the seam runs the shipped signal(SIGTERM, SIG_IGN), which leaves the xctest runner ignoring SIGTERM — unkillable by `kill` for the rest of the run, so it needs SIGKILL. The blast radius stops there and is measured: the parent shell reads [0, 0] both before and after a full suite run, so this does NOT escape to the machine. The production default is correct FOR THE APP and wrong for a test process, which is exactly why the seam exists.")
        XCTAssertFalse(
            after.contains(ignore) && !before.contains(ignore),
            "the suite must not be the thing that ignores SIGTERM")
    }

    func testTheUninjectedPathIsKnownToAlterTheRunnerAndIsNotSilentlyForgotten() throws {
        let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let files = try FileManager.default.contentsOfDirectory(at: testsDir, includingPropertiesForKeys: nil)

        let uninjected = try files
            .filter { $0.pathExtension == "swift" }
            .filter { file in
                let text = try String(contentsOf: file, encoding: .utf8)
                return text.contains("AppState(homeDir:") && !text.contains("terminationSignals:")
            }
            .map(\.lastPathComponent)
            .sorted()

        XCTAssertEqual(
            uninjected.count, 13,
            "Measured: an AppState built WITHOUT the seam moves this process's dispositions from [0, 0] to [1, 1] — SIGTERM and SIGINT both ignored — so the xctest runner becomes unkillable by `kill` and needs SIGKILL. \(uninjected.count) files do that today: \(uninjected.joined(separator: ", ")). They are not broken and their assertions are sound, so this is a NAMED gap rather than a pretended pass: the count is pinned so the number cannot grow unnoticed, and it should fall as suites adopt the seam. If you add a suite that constructs AppState, inject terminationSignals and lower this number.")
    }
}

private struct NeverMutesDevice: AudioMuteDevice {
    func readInputMute() -> Bool? { nil }
    func setInputMute(_ muted: Bool) -> Bool { false }
    func isBluetooth() -> Bool { false }
    func nominalSampleRate() -> Double? { nil }
}

@MainActor
private final class UnusedSignalSource: TerminationSignalSource {
    func setHandler(_ handler: @escaping () -> Void) {}
    func begin() {}
}
