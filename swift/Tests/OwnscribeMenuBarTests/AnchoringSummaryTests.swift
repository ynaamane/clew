import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class AnchoringSummaryTests: XCTestCase {
    private func keyPoint(_ text: String, anchors: [String: [TokenAnchor]]?) -> KeyPointWithAnchors {
        KeyPointWithAnchors(text: text, anchors: anchors)
    }

    // MARK: - AnchoringSummaryCalculator

    func testNoKeyPointsProducesNoSummary() {
        XCTAssertNil(AnchoringSummaryCalculator.summary(for: []))
    }

    func testAllNilAnchorsMeansAnchorsJsonIsAbsentSoNoSummary() {
        let points = [
            keyPoint("Gary discussed a bug", anchors: nil),
            keyPoint("JWT authentication setup", anchors: nil),
        ]

        XCTAssertNil(
            AnchoringSummaryCalculator.summary(for: points),
            "Nobody has checked anchoring yet — that must never render as a ratio, not even 0/2")
    }

    func testAnchorsPresentButAllEmptyIsARealZeroNotAnAbsence() {
        let points = [
            keyPoint("Gary discussed a bug", anchors: [:]),
            keyPoint("JWT authentication setup", anchors: [:]),
        ]

        let summary = AnchoringSummaryCalculator.summary(for: points)

        XCTAssertEqual(
            summary, AnchoringSummary(anchored: 0, total: 2),
            "anchors.json exists and found nothing for either claim — 0/2 is information, not an absent check")
    }

    func testSomeAnchoredSomeNot() {
        let points = [
            keyPoint("Gary discussed a bug", anchors: ["Gary": [TokenAnchor(timestamp: "08:30", context: "Gary")]]),
            keyPoint("Unrelated fictitious claim", anchors: [:]),
            keyPoint("JWT authentication setup", anchors: ["JWT": [TokenAnchor(timestamp: "05:28", context: "JWT")]]),
        ]

        let summary = AnchoringSummaryCalculator.summary(for: points)

        XCTAssertEqual(summary, AnchoringSummary(anchored: 2, total: 3))
    }

    func testEveryPointAnchored() {
        let points = [
            keyPoint("Gary discussed a bug", anchors: ["Gary": [TokenAnchor(timestamp: "08:30", context: "Gary")]]),
            keyPoint("JWT authentication setup", anchors: ["JWT": [TokenAnchor(timestamp: "05:28", context: "JWT")]]),
        ]

        let summary = AnchoringSummaryCalculator.summary(for: points)

        XCTAssertEqual(summary, AnchoringSummary(anchored: 2, total: 2))
    }

    // MARK: - PointsClesCaption

    func testCaptionWithNoAnchorsDataHasNoRatio() {
        XCTAssertEqual(PointsClesCaption.text(for: nil), "Points clés")
    }

    func testCaptionWithSummaryAppendsRatio() {
        let summary = AnchoringSummary(anchored: 6, total: 7)
        XCTAssertEqual(PointsClesCaption.text(for: summary), "Points clés · 6/7 ancrés")
    }

    func testCaptionWithZeroAnchoredStillShowsTheRealZero() {
        let summary = AnchoringSummary(anchored: 0, total: 2)
        XCTAssertEqual(PointsClesCaption.text(for: summary), "Points clés · 0/2 ancrés")
    }

    // MARK: - AnchoringCalloutText

    func testCalloutTextMatchesTheMockupPhrasing() {
        let summary = AnchoringSummary(anchored: 6, total: 7)
        XCTAssertEqual(
            AnchoringCalloutText.text(for: summary),
            "6 des 7 points clés sont ancrés dans le transcript. Clique un point clé pour sauter à sa preuve.")
    }

    func testCalloutTextUsesSingularWhenOnlyOneKeyPoint() {
        let summary = AnchoringSummary(anchored: 1, total: 1)
        XCTAssertEqual(
            AnchoringCalloutText.text(for: summary),
            "1 des 1 points clés sont ancrés dans le transcript. Clique un point clé pour sauter à sa preuve.",
            "Kept literal per the mockup's own copy — no singular/plural agreement rule was specified")
    }
}
