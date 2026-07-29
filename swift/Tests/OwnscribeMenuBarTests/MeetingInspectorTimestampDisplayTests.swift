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

        let display = AnchorEvidenceDisplayModel.display(for: keyPoint)

        XCTAssertEqual(
            display,
            .evidence([AnchorEvidenceChip(token: "Gary", timestamp: "08:30")]),
            "A key point with one anchored token renders one evidence chip")
        XCTAssertNil(display.placeholderText, "Evidence must not render a placeholder")
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

        let display = AnchorEvidenceDisplayModel.display(for: keyPoint)

        XCTAssertEqual(
            display.chips,
            [
                AnchorEvidenceChip(token: "JWT", timestamp: "05:28"),
                AnchorEvidenceChip(token: "Lambda", timestamp: "05:09")
            ],
            "Every anchored token gets its own chip")
    }

    func testKeyPointWithoutAnchorsShowsDash() {
        let keyPoint = KeyPointWithAnchors(
            text: "The possibility of using a fictitious user for testing was considered",
            anchors: [:]
        )

        let display = AnchorEvidenceDisplayModel.display(for: keyPoint)

        XCTAssertEqual(
            display, .noEvidenceFound,
            "Anchoring ran and found nothing for this claim — that is a dash, not an absence of checking")
        XCTAssertEqual(display.placeholderText, "—")
        XCTAssertTrue(display.chips.isEmpty)
    }

    func testChipLabelJoinsTokenAndTimestamp() {
        let keyPoint = KeyPointWithAnchors(
            text: "Gary discussed the bug",
            anchors: ["Gary": [TokenAnchor(timestamp: "08:30", context: "Gary discussed the bug")]]
        )

        let display = AnchorEvidenceDisplayModel.display(for: keyPoint)

        XCTAssertEqual(display.chips.first?.label, "Gary→08:30", "The rendered label is token→timestamp")
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

        let display = AnchorEvidenceDisplayModel.display(for: keyPoint)

        XCTAssertEqual(display.chips.count, 1, "One chip per token, not one per occurrence")
        XCTAssertEqual(
            display.chips.first?.timestamp, "05:28",
            "The earliest recorded occurrence is the one offered as evidence")
    }

    func testSortedTokenKeysProduceConsistentDisplay() {
        let tokens = ["Zoom", "Gary", "JWT", "Lambda", "Confluence", "PPTX", "Aurora", "Redshift"]
        var anchors: [String: [TokenAnchor]] = [:]
        for token in tokens {
            anchors[token] = [TokenAnchor(timestamp: "01:10", context: token)]
        }
        let keyPoint = KeyPointWithAnchors(text: "Discussion with multiple tokens", anchors: anchors)

        let display = AnchorEvidenceDisplayModel.display(for: keyPoint)

        XCTAssertEqual(
            display.chips.map(\.token), tokens.sorted(),
            "Dictionary order is seeded per process, so an unsorted display reshuffles between launches. Eight tokens are used deliberately: with three, a random order is already sorted one run in six, and a mutation that drops the sort survived 1 of 8 runs at that size.")
    }

    func testKeyPointWithNilAnchorsShowsNotYetVerified() {
        let keyPoint = KeyPointWithAnchors(text: "Some claim without anchoring", anchors: nil)

        let display = AnchorEvidenceDisplayModel.display(for: keyPoint)

        XCTAssertEqual(
            display, .notYetVerified,
            "No anchors.json means nobody checked — that must never look like checked-and-found-nothing")
        XCTAssertEqual(display.placeholderText, "(pas encore vérifié)")
    }

    func testTokenWhoseOccurrencesAllFailedToParseIsNotSilentlyEmpty() {
        let keyPoint = KeyPointWithAnchors(text: "Gary discussed a bug", anchors: ["Gary": []])

        let display = AnchorEvidenceDisplayModel.display(for: keyPoint)

        XCTAssertEqual(
            display, .noEvidenceFound,
            "A token with zero usable occurrences has no chip to show; rendering nothing at all would leave the claim unlabelled")
        XCTAssertEqual(display.placeholderText, "—")
    }

    func testDisplayConsumesWhatTheDiskLoaderProduces() throws {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let configDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: configDir) }

        let configURL = configDir.appendingPathComponent("config.toml")
        try "[output]\nformat = \"markdown\"\n".write(to: configURL, atomically: true, encoding: .utf8)

        let summaryMd = """
        # Meeting Summary

        ## Key Points
        - Gary discussed a bug that needs checking
        - The possibility of using a fictitious user was considered

        ## Action Items
        None.
        """
        try summaryMd.write(to: tempDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        let withoutAnchorsFile = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir, configURL: configURL, fileManager: fileManager)
        XCTAssertEqual(withoutAnchorsFile?.count, 2)
        XCTAssertEqual(
            withoutAnchorsFile.map { $0.map(AnchorEvidenceDisplayModel.display(for:)) },
            [.notYetVerified, .notYetVerified],
            "With no anchors.json on disk every claim reads as unchecked")

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [{"timestamp": "08:30", "context": "Gary discussed the bug"}]
          }
        }
        """
        try anchorsJson.write(to: tempDir.appendingPathComponent("anchors.json"), atomically: true, encoding: .utf8)

        let withAnchorsFile = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir, configURL: configURL, fileManager: fileManager)
        XCTAssertEqual(
            withAnchorsFile.map { $0.map(AnchorEvidenceDisplayModel.display(for:)) },
            [.evidence([AnchorEvidenceChip(token: "Gary", timestamp: "08:30")]), .noEvidenceFound],
            "The same loader output now separates anchored evidence from a checked-but-unanchored claim")
    }
}
