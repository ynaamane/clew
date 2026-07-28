import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class PhaseTransitionTests: XCTestCase {
    private let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("test-meeting")

    func testTerminalPhaseAllowsTransitionFromProcessing() {
        let result = AppState.terminalPhase(after: .processing(step: "transcribing", fraction: 0.5), completedWith: testDirectory)

        XCTAssertNotNil(result, "Terminal phase must allow transition from .processing")
        if case .done(let directory) = result {
            XCTAssertEqual(directory, testDirectory)
        } else {
            XCTFail("Expected .done phase")
        }
    }

    func testTerminalPhasePreventsTransitionFromRecording() {
        let result = AppState.terminalPhase(after: .recording(startedAt: Date()), completedWith: testDirectory)

        XCTAssertNil(
            result,
            "Terminal phase must NOT allow transition from .recording — this prevents the first pipeline from clobbering a live second recording")
    }

    func testTerminalPhasePreventsTransitionFromIdle() {
        let result = AppState.terminalPhase(after: .idle, completedWith: testDirectory)

        XCTAssertNil(result, "Terminal phase must NOT allow transition from .idle")
    }

    func testTerminalPhasePreventsTransitionFromDone() {
        let anotherDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("other-meeting")
        let result = AppState.terminalPhase(after: .done(directory: anotherDirectory), completedWith: testDirectory)

        XCTAssertNil(result, "Terminal phase must NOT allow transition from .done")
    }

    func testTerminalPhasePreventsTransitionFromFailed() {
        let result = AppState.terminalPhase(after: .failed("some error"), completedWith: testDirectory)

        XCTAssertNil(result, "Terminal phase must NOT allow transition from .failed")
    }

    func testFailureTransitionAllowsTransitionFromProcessing() {
        let result = AppState.terminalPhase(after: .processing(step: "transcribing", fraction: 0.5), failedWith: "test error")

        XCTAssertNotNil(result, "Failure transition must allow transition from .processing")
        if case .failed(let message) = result {
            XCTAssertEqual(message, "test error")
        } else {
            XCTFail("Expected .failed phase")
        }
    }

    func testFailureTransitionPreventsTransitionFromRecording() {
        let result = AppState.terminalPhase(after: .recording(startedAt: Date()), failedWith: "test error")

        XCTAssertNil(
            result,
            "Failure transition must NOT allow transition from .recording — this prevents the first pipeline's error from clobbering a live second recording")
    }
}
