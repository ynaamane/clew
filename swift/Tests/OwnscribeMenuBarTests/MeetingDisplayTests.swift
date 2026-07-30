import XCTest
@testable import OwnscribeMenuBar

final class MeetingDisplayTests: XCTestCase {
    private func meeting(_ folder: String) -> MeetingSummary {
        MeetingSummary(
            directory: URL(fileURLWithPath: "/tmp/\(folder)"),
            hasTranscript: true,
            hasSummary: true
        )
    }

    func testTitleComesFromTheSlugNotTheTimestamp() {
        let shown = meeting("2026-07-27_1536_project-technical-review-key-points").displayTitle

        XCTAssertEqual(shown, "Project technical review key points")
    }

    func testTitleShowsTimeWhenThereIsNoSlugAndNoTranscript() {
        let shown = meeting("2026-07-29_1537").displayTitle

        XCTAssertTrue(shown.contains("15:37"), "Should show time when no slug and no transcript, got \(shown)")
        XCTAssertFalse(shown.contains("Sans titre"), "Must not fabricate 'Sans titre', got \(shown)")
    }

    func testTitleGuardsAgainstLLMRefusalAsSlug() {
        let refusal = meeting("2026-07-30_1141_sure-please-provide-the-transcript-of-the-meeting")

        XCTAssertFalse(refusal.displayTitle.lowercased().contains("please"), "LLM refusal must not become title")
        XCTAssertFalse(refusal.displayTitle.lowercased().contains("sorry"), "LLM apology must not become title")
        XCTAssertTrue(refusal.displayTitle.contains("11:41"), "Should fall back to time when slug is refusal")
    }

    func testTitleKeepsLegitimateUsesOfCommonWords() {
        let legitimate = [
            "transcript-pipeline-review",
            "we-need-to-ship-friday",
            "provide-api-access-to-vendor",
            "sorry-state-of-the-build",
            "cannot-reproduce-bug-triage",
            "please-review-my-pr-process",
            "transcription-quality-sprint",
            "i-o-latency-investigation",
            "i-18n-rollout-plan",
        ]

        for dir in legitimate {
            let shown = meeting("2026-07-29_1537_\(dir)").displayTitle
            XCTAssertFalse(shown.contains(":"), "Legitimate title '\(dir)' must not fall back to time, got '\(shown)'")
            XCTAssertTrue(shown.lowercased().contains(dir.split(separator: "-").first!), "Title should contain slug content for '\(dir)', got '\(shown)'")
        }
    }

    func testTitleErasesShortRefusals() {
        let refusals = [
            "please-provide-the-transcript",
            "could-you-send-the-notes",
            "i-need-more-context",
        ]

        for dir in refusals {
            let shown = meeting("2026-07-29_1537_\(dir)").displayTitle
            XCTAssertTrue(shown.contains(":"), "Short refusal '\(dir)' must fall back to time, got '\(shown)'")
        }
    }

    func testDateIsReadableRatherThanAFolderName() {
        let shown = meeting("2026-07-27_1536_project-technical-review").displayDate

        XCTAssertTrue(shown.contains("15:36"), "The recording time matters when several meetings share a day; got \(shown)")
        XCTAssertFalse(shown.contains("_"), "A folder name is not a date; got \(shown)")
    }

    func testMalformedFolderNameDoesNotCrashOrLie() {
        let odd = meeting("not-a-meeting")

        XCTAssertEqual(odd.displayTitle, "Not a meeting")
        XCTAssertEqual(odd.displayDate, "")
    }
}
