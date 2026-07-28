import XCTest
import OSLog
@testable import OwnscribeMenuBar

final class AppLoggerTests: XCTestCase {
    func testSubsystemIsCorrect() {
        XCTAssertEqual(AppLogger.subsystem, "com.ownscribe.menubar")
    }

    func testCategoryNamesMatch() {
        XCTAssertEqual(AppLogCategory.recording.category, "recording")
        XCTAssertEqual(AppLogCategory.mute.category, "mute")
        XCTAssertEqual(AppLogCategory.pipeline.category, "pipeline")
        XCTAssertEqual(AppLogCategory.library.category, "library")
    }
    func testPhaseLogDescriptionIdle() {
        let phase = AppState.Phase.idle
        XCTAssertEqual(phase.logDescription(), "idle")
    }

    func testPhaseLogDescriptionRecording() {
        let date = Date(timeIntervalSince1970: 1700000000)
        let phase = AppState.Phase.recording(startedAt: date)
        XCTAssertEqual(phase.logDescription(), "recording(startedAt: 1700000000)")
    }

    func testPhaseLogDescriptionProcessingWithFraction() {
        let phase = AppState.Phase.processing(step: "transcribing", fraction: 0.65)
        XCTAssertEqual(phase.logDescription(), "processing(step: transcribing, fraction: 0.65)")
    }

    func testPhaseLogDescriptionProcessingWithoutFraction() {
        let phase = AppState.Phase.processing(step: "starting", fraction: nil)
        XCTAssertEqual(phase.logDescription(), "processing(step: starting)")
    }

    func testPhaseLogDescriptionDone() {
        let url = URL(fileURLWithPath: "/Users/user/ownscribe/2026-07-28_1430_meeting")
        let phase = AppState.Phase.done(directory: url)
        XCTAssertEqual(phase.logDescription(), "done(directory: 2026-07-28_1430_meeting)")
    }

    func testPhaseLogDescriptionFailed() {
        let phase = AppState.Phase.failed("Permission denied")
        XCTAssertEqual(phase.logDescription(), "failed")
    }

    func testTimestampPrefixExtractsOnlyTimestamp() {
        let input = "2026-07-27_1536_project-technical-review-key-points"
        let result = AppLogger.timestampPrefix(from: input)
        XCTAssertEqual(result, "2026-07-27_1536")
    }

    func testTimestampPrefixWithoutSlugReturnsTimestamp() {
        let input = "2026-07-28_1430"
        let result = AppLogger.timestampPrefix(from: input)
        XCTAssertEqual(result, "2026-07-28_1430")
    }

    func testTimestampPrefixWithMalformedInputReturnsOriginal() {
        let input = "malformed"
        let result = AppLogger.timestampPrefix(from: input)
        XCTAssertEqual(result, "malformed")
    }

    func testTimestampPrefixStripsContentSlug() {
        let input = "2026-07-24_1756_emerging-internet-force-impact"
        let result = AppLogger.timestampPrefix(from: input)
        XCTAssertEqual(result, "2026-07-24_1756")
        XCTAssertFalse(result.contains("emerging"))
        XCTAssertFalse(result.contains("internet"))
    }
}
