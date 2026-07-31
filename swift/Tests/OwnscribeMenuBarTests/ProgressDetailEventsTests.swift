import XCTest
@testable import OwnscribeMenuBar
@testable import OwnscribeCapture

@MainActor
final class ProgressDetailEventsTests: XCTestCase {
    private func phaseAfterStreaming(_ events: [ProgressEvent]) async -> AppState.Phase? {
        let state = AppState(homeDir: FileManager.default.temporaryDirectory)
        var observed: AppState.Phase?

        let runner = EventEmittingRunner(events: events) {
            observed = state.phase
        }
        state.pipelineRunnerFactory = { runner }
        state.systemCaptureFactory = { _ in StubProgressSystemCapture() }
        state.isMicCaptureEnabled = false
        state.micCaptureFactory = { nil }

        await state.toggleRecording()
        await state.toggleRecording()
        return observed
    }

    func testADetailEventKeepsTheStepAndFractionItArrivesUnder() async {
        let phase = await phaseAfterStreaming([
            ProgressEvent(event: .update, step: "transcription", fraction: 0.5),
            ProgressEvent(event: .detail, step: "transcription", detail: "Loading alignment model (fr)"),
        ])

        guard case .processing(let step, let fraction, let detail) = phase else {
            return XCTFail("Expected .processing, got \(String(describing: phase))")
        }
        XCTAssertEqual(step, "transcription")
        XCTAssertEqual(
            fraction, 0.5,
            "a detail event carries no fraction of its own; discarding the current one would reset the bar to indeterminate")
        XCTAssertEqual(
            detail, "Loading alignment model (fr)",
            "the CLI's sub-step text is the only thing that distinguishes a model download from a hang")
    }

    func testTheNextRealStepClearsTheDetailOfThePreviousOne() async {
        let phase = await phaseAfterStreaming([
            ProgressEvent(event: .update, step: "transcription", fraction: 0.5),
            ProgressEvent(event: .detail, step: "transcription", detail: "Loading alignment model (fr)"),
            ProgressEvent(event: .update, step: "diarization", fraction: 0.7),
        ])

        guard case .processing(let step, _, let detail) = phase else {
            return XCTFail("Expected .processing, got \(String(describing: phase))")
        }
        XCTAssertEqual(step, "diarization")
        XCTAssertNil(
            detail,
            "a stale detail under a new step would describe work that already finished")
    }

    func testAPerStepCompleteDoesNotEndTheRun() async {
        let phase = await phaseAfterStreaming([
            ProgressEvent(event: .update, step: "diarization", fraction: 0.8),
            ProgressEvent(event: .complete, step: "diarization"),
        ])

        guard case .processing(let step, let fraction, _) = phase else {
            return XCTFail("a per-step .complete must not end the run; only the process exit decides")
        }
        XCTAssertEqual(step, "diarization")
        XCTAssertEqual(fraction, 0.8)
    }

    func testADetailArrivingBeforeAnyStepIsNotShownUnderAnEmptyStep() async {
        let phase = await phaseAfterStreaming([
            ProgressEvent(event: .detail, step: "", detail: "Loading alignment model (fr)"),
        ])

        guard case .processing(let step, _, _) = phase else {
            return XCTFail("Expected .processing, got \(String(describing: phase))")
        }
        XCTAssertFalse(
            step.isEmpty,
            "runPipeline seeds the step to 'starting'; a detail must not blank it out")
    }
}

private final class EventEmittingRunner: PipelineRunning {
    private let events: [ProgressEvent]
    private let afterStreaming: @MainActor () -> Void

    init(events: [ProgressEvent], afterStreaming: @escaping @MainActor () -> Void) {
        self.events = events
        self.afterStreaming = afterStreaming
    }

    func run(arguments: [String], onEvent: @escaping @Sendable (ProgressEvent) -> Void) async throws {
        for event in events {
            onEvent(event)
            await Task.yield()
        }
        afterStreaming()
    }

    func cancel() {}
}

private final class StubProgressSystemCapture: SystemAudioCapturing {
    var micCapture: MicCapture?
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var startHostTime: UInt64 = 0

    func start() async throws {}
    func stop() {}
}
