import XCTest
@testable import OwnscribeMenuBar

final class MeetingDetailViewWiringTests: XCTestCase {
    private func source() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OwnscribeMenuBar/MeetingDetailView.swift"),
            encoding: .utf8)
    }

    func testTranscriptIsRenderedThroughTurnGroupingNotOnePerUtteranceRow() throws {
        let text = try source()

        XCTAssertTrue(
            text.contains("TranscriptTurnGrouping.turns(from:"),
            "The view must consume the pure grouping function rather than iterating utterances directly — "
                + "otherwise TranscriptTurnGroupingTests proves nothing about what actually renders")
        XCTAssertFalse(
            text.contains("private struct UtteranceRow"),
            "UtteranceRow rendered the 18pt avatar + speaker name on every line; it must be gone, not just unused")
    }

    func testAnchoringCalloutIsGatedOnTheSummaryExistingWithAtLeastOneKeyPoint() throws {
        let text = try source()

        XCTAssertTrue(
            text.contains("AnchoringSummaryCalculator.summary(for:"),
            "The callout's N/M must come from the same calculator the inspector's ratio caption uses, "
                + "so the two can never disagree")
        XCTAssertTrue(
            text.contains("AnchoringCalloutText.text(for:"),
            "The callout copy must come from the shared pure formatter, not be hand-written inline")
        XCTAssertTrue(
            text.contains("if let anchoringSummary"),
            "AnchoringSummaryCalculator.summary(for:) already returns nil when anchors data is absent or "
                + "there are zero key points; the view must gate rendering on that nil rather than showing an empty box")
    }

    func testScrollToAnchorSetsTheHighlightBeforeScrolling() throws {
        let text = try source()

        guard let range = text.range(of: "private func scrollToAnchor") else {
            XCTFail("scrollToAnchor was renamed or removed; this guard needs updating")
            return
        }
        let body = String(text[range.lowerBound...])

        XCTAssertTrue(
            body.contains("highlightedUtteranceID = target.utteranceID"),
            "The scroll-target line must be tinted by driving state from scrollToAnchor, not by a one-off view hack")
        XCTAssertTrue(
            text.contains("LineHighlightDecision.isHighlighted("),
            "The line highlight must be decided by the pure, unit-tested function, not an inline == comparison "
                + "that no test can reach")
    }

    func testBackchannelToggleWasReplacedByTheCountCarryingPill() throws {
        let text = try source()

        XCTAssertFalse(
            text.contains("Toggle(") && text.contains(".toggleStyle(.switch)"),
            "The stock switch must be gone; the mockup's fold pill replaces it entirely, not sits beside it")
        XCTAssertTrue(
            text.contains("BackchannelFoldSummary.label(for:"),
            "The pill's count and examples must come from the pure, unit-tested summariser")
        XCTAssertTrue(
            text.contains("BackchannelFoldSummary.text(for:"),
            "The pill's text must come from the pure, unit-tested formatter, not be assembled inline in the view")
        XCTAssertTrue(
            text.contains(".accessibilityIdentifier(\"meeting.backchannelToggle\")"),
            "The identifier must survive the swap from Toggle to pill so AccessibilityIdentifierTests and any "
                + "review script that addresses this control by name keep working")
    }
}
