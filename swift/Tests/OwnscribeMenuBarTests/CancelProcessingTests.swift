import XCTest
@testable import OwnscribeMenuBar
@testable import OwnscribeCapture

private final class SpyCancellableRunner: PipelineRunning {
    private let duringRun: @MainActor () -> Void
    var cancelCount = 0

    init(duringRun: @escaping @MainActor () -> Void) {
        self.duringRun = duringRun
    }

    func run(arguments: [String], onEvent: @escaping @Sendable (ProgressEvent) -> Void) async throws {
        onEvent(ProgressEvent(event: .update, step: "transcription", fraction: 0.4))
        await Task.yield()
        duringRun()
    }

    func cancel() {
        cancelCount += 1
    }
}

private final class StubCancelSystemCapture: SystemAudioCapturing {
    var micCapture: MicCapture?
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var startHostTime: UInt64 = 0

    func start() async throws {}
    func stop() {}
}

@MainActor
final class CancelProcessingTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-meeting")

    func testCancellingWhileProcessingIsAllowedAndLeavesNoSpinner() {
        let decision = AppState.cancelDecision(for: .processing(step: "transcribing", fraction: 0.4))

        XCTAssertEqual(
            decision, .cancel,
            "A multi-minute transcription must be stoppable. PipelineRunner.cancel() existed with zero callers, so the only way out of .processing was to wait or quit the app.")
    }

    func testCancellingLeavesAPhaseTheUserCanActFrom() {
        guard case .cancel = AppState.cancelDecision(for: .processing(step: "diarizing", fraction: nil)) else {
            return XCTFail("cancelling from .processing must be allowed")
        }

        let resulting = AppState.phaseAfterCancellation()

        XCTAssertEqual(
            resulting, .idle,
            "Cancelling must not strand the UI on .processing, whose only control is a spinner. It must also not be .failed: the user asked for this, and .failed raises an error banner for a deliberate action. Idle is the state a new recording can start from — the audio is retained on disk either way, recoverable with ./rec.sh redo.")
    }

    func testCancellingIsRefusedWhileRecordingSoAMeetingIsNeverLost() {
        let decision = AppState.cancelDecision(for: .recording(startedAt: Date()))

        XCTAssertEqual(
            decision, .refuse,
            "A recording in progress is IRREPLACEABLE — the meeting is happening now. Cancel must never reach it; stopping a recording is stop(), which keeps the audio and runs the pipeline.")
    }

    func testCancellingIsANoOpOnceThePipelineHasAlreadyFinished() {
        for phase in [AppState.Phase.idle, .done(directory: directory), .failed("boom")] {
            XCTAssertEqual(
                AppState.cancelDecision(for: phase), .refuse,
                "Nothing is running in \(phase), so a late cancel must not rewrite a terminal phase. This is the same guard terminalPhase() applies in the other direction: a finishing pipeline must not clobber a phase that has moved on.")
        }
    }

    func testCancellingReachesTheRunnerAndDoesNotOnlyRepaintThePhase() async {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancel-spy-\(UUID().uuidString)")
        let state = AppState(homeDir: home)
        let runner = SpyCancellableRunner { state.cancelProcessing() }

        state.pipelineRunnerFactory = { runner }
        state.systemCaptureFactory = { _ in StubCancelSystemCapture() }
        state.isMicCaptureEnabled = false
        state.micCaptureFactory = { nil }

        state.cancelProcessing()
        XCTAssertEqual(
            runner.cancelCount, 0,
            "cancelProcessing() from .idle must not signal a child process; nothing is running")

        await state.toggleRecording()
        await state.toggleRecording()

        XCTAssertEqual(
            runner.cancelCount, 1,
            "Cancelled from INSIDE the running pipeline, through the real toggleRecording path. Setting phase back to .idle without calling cancel() would leave the ownscribe child transcribing for minutes, burning CPU with nothing to show it — the button would LOOK like it worked. This is the assertion that distinguishes cancelling from hiding.")
        XCTAssertEqual(
            state.phase, .idle,
            "and the pipeline's own completion must not resurrect a terminal phase after the user cancelled")
    }

    func testTheCancelControlIsWiredToTheViewAndNotJustDefined() throws {
        let window = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OwnscribeMenuBar/LibraryWindow.swift"),
            encoding: .utf8)

        XCTAssertTrue(
            window.contains("appState.cancelProcessing()"),
            "A function with tests and no caller is not a fix — UnanchoredClaimBadge shipped that way with 4 green tests and zero callers, and silence_timeout was plumbed through four layers into a callback nobody assigned. The cancel control must exist in the window, next to the progress label that is the only other sign the pipeline is running.")
        XCTAssertTrue(
            window.contains(".accessibilityIdentifier(\"library.cancelButton\")"),
            "Interactive controls carry an identifier so a review can address them; the progress toolbar is exactly where a script would look for this one.")
    }
}
