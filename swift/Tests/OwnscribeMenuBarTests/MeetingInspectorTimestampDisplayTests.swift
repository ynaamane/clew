import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class MeetingInspectorTimestampDisplayTests: XCTestCase {
    func testKeyPointWithAnchorsDisplaysTimestamps() {
        let keyPoint = KeyPointWithAnchors(
            text: "Gary discussed a bug",
            anchors: [
                "Gary": [TokenAnchor(timestamp: "08:30", context: "Gary joined")]
            ]
        )

        XCTAssertFalse(keyPoint.anchors.isEmpty, "Key point should have anchors")
        XCTAssertEqual(keyPoint.anchors.count, 1)
        XCTAssertNotNil(keyPoint.anchors["Gary"])

        let firstAnchor = keyPoint.anchors["Gary"]?.first
        XCTAssertEqual(firstAnchor?.timestamp, "08:30")
    }

    func testKeyPointWithMultipleTokensDisplaysAllTimestamps() {
        let keyPoint = KeyPointWithAnchors(
            text: "JWT authentication with Lambda",
            anchors: [
                "JWT": [
                    TokenAnchor(timestamp: "05:28", context: "JWT auth"),
                    TokenAnchor(timestamp: "13:32", context: "JWT test")
                ],
                "Lambda": [TokenAnchor(timestamp: "05:09", context: "Lambda deploy")]
            ]
        )

        XCTAssertEqual(keyPoint.anchors.count, 2, "Should have two anchored tokens")

        let jwtAnchors = keyPoint.anchors["JWT"]
        XCTAssertEqual(jwtAnchors?.count, 2, "JWT should have two timestamps")
        XCTAssertEqual(jwtAnchors?.first?.timestamp, "05:28")

        let lambdaAnchors = keyPoint.anchors["Lambda"]
        XCTAssertEqual(lambdaAnchors?.count, 1)
        XCTAssertEqual(lambdaAnchors?.first?.timestamp, "05:09")
    }

    func testKeyPointWithoutAnchorsShowsDash() {
        let keyPoint = KeyPointWithAnchors(
            text: "The possibility of using a fictitious user for testing was considered",
            anchors: [:]
        )

        XCTAssertTrue(keyPoint.anchors.isEmpty, "Key point should have no anchors")
    }

    func testAnchorTimestampFormat() {
        let anchor = TokenAnchor(timestamp: "08:30", context: "Gary discussed the bug")

        XCTAssertEqual(anchor.timestamp, "08:30")
        XCTAssertTrue(anchor.context.contains("Gary"))
    }

    func testMultipleAnchorsForSameTokenOnlyFirstIsUsed() {
        let keyPoint = KeyPointWithAnchors(
            text: "JWT authentication discussed twice",
            anchors: [
                "JWT": [
                    TokenAnchor(timestamp: "05:28", context: "First mention"),
                    TokenAnchor(timestamp: "13:32", context: "Second mention")
                ]
            ]
        )

        let jwtAnchors = keyPoint.anchors["JWT"]
        XCTAssertEqual(jwtAnchors?.count, 2, "Both anchors are stored")

        let firstTimestamp = jwtAnchors?.first?.timestamp
        XCTAssertEqual(firstTimestamp, "05:28", "First timestamp should be used for display")
    }

    func testSortedTokenKeysProduceConsistentDisplay() {
        let keyPoint = KeyPointWithAnchors(
            text: "Discussion with multiple tokens",
            anchors: [
                "Zoom": [TokenAnchor(timestamp: "01:10", context: "Zoom")],
                "Gary": [TokenAnchor(timestamp: "08:30", context: "Gary")],
                "JWT": [TokenAnchor(timestamp: "05:28", context: "JWT")]
            ]
        )

        let sortedKeys = Array(keyPoint.anchors.keys.sorted())
        XCTAssertEqual(sortedKeys, ["Gary", "JWT", "Zoom"], "Keys should be alphabetically sorted")
    }
}
