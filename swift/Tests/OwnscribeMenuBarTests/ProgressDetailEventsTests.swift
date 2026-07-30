import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class ProgressDetailEventsTests: XCTestCase {

    func testDetailEventPreservesStepAndFraction() {
        let state = AppState(homeDir: FileManager.default.temporaryDirectory)
        state.setPhaseForTesting(.processing(step: "transcription", fraction: 0.5, detail: nil))

        let detailEvent = ProgressEvent(
            event: .detail,
            step: "transcription",
            fraction: nil,
            detail: "Loading alignment model (fr)"
        )

        state.handle(detailEvent)

        guard case .processing(let step, let fraction, let detail) = state.phase else {
            return XCTFail("Expected .processing phase with detail, got \(state.phase)")
        }

        XCTAssertEqual(step, "transcription")
        XCTAssertEqual(fraction, 0.5)
        XCTAssertEqual(detail, "Loading alignment model (fr)")
    }

    func testDetailEventWithNilClearsDetail() {
        let state = AppState(homeDir: FileManager.default.temporaryDirectory)
        state.setPhaseForTesting(.processing(step: "transcription", fraction: 0.5, detail: "old detail"))

        let clearEvent = ProgressEvent(
            event: .detail,
            step: "transcription",
            fraction: nil,
            detail: nil
        )

        state.handle(clearEvent)

        guard case .processing(let step, let fraction, let detail) = state.phase else {
            return XCTFail("Expected .processing phase, got \(state.phase)")
        }

        XCTAssertEqual(step, "transcription")
        XCTAssertEqual(fraction, 0.5)
        XCTAssertNil(detail)
    }

    func testCompleteAndFailEventsRemainNoOp() {
        let state = AppState(homeDir: FileManager.default.temporaryDirectory)
        let initialPhase = AppState.Phase.processing(step: "diarization", fraction: 0.8, detail: nil)
        state.setPhaseForTesting(initialPhase)

        let completeEvent = ProgressEvent(event: .complete, step: "diarization")
        state.handle(completeEvent)
        XCTAssertEqual(state.phase, initialPhase)

        let failEvent = ProgressEvent(event: .fail, step: "diarization", detail: "error message")
        state.handle(failEvent)
        XCTAssertEqual(state.phase, initialPhase)
    }
}
