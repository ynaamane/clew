import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class MeetingCountsFormatAgreementTests: XCTestCase {
    var tempDir: URL!
    var fileManager: FileManager!
    var tempConfigDir: URL!

    override func setUp() {
        super.setUp()
        fileManager = FileManager.default
        tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        tempConfigDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! fileManager.createDirectory(at: tempConfigDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? fileManager.removeItem(at: dir)
        }
        if let configDir = tempConfigDir {
            try? fileManager.removeItem(at: configDir)
        }
        super.tearDown()
    }

    func testBadgeAndInspectorAgreeOnMarkdownDoubleQuotes() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")
        let configToml = """
        [output]
        format = "markdown"
        """
        try! configToml.write(to: configURL, atomically: true, encoding: .utf8)

        let summaryMd = """
        # Meeting Summary

        ## Key Points
        - Gary discussed a bug
        - Unanchored claim

        ## Action Items
        - Follow up
        """
        try! summaryMd.write(to: tempDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [{"timestamp": "08:30", "context": "Gary"}]
          }
        }
        """
        try! anchorsJson.write(to: tempDir.appendingPathComponent("anchors.json"), atomically: true, encoding: .utf8)

        let counts = MeetingCounts.compute(summaryDirectory: tempDir, configURL: configURL, fileManager: fileManager)
        let keyPoints = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertEqual(counts.actionItemCount, 1, "Badge: 1 action")
        XCTAssertEqual(counts.unanchoredClaimCount, 1, "Badge: 1 unanchored")
        XCTAssertEqual(keyPoints?.count, 2, "Inspector: 2 key points")
        XCTAssertNotNil(keyPoints?[0].anchors, "Inspector: first has anchors dict")
        XCTAssertEqual(keyPoints?[0].anchors?.count, 1, "Inspector: Gary matched")
        XCTAssertTrue(keyPoints?[1].anchors?.isEmpty == true, "Inspector: second is unanchored")
    }

    func testBadgeAndInspectorAgreeOnMarkdownSingleQuotes() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")
        let configToml = """
        [output]
        format = 'markdown'
        """
        try! configToml.write(to: configURL, atomically: true, encoding: .utf8)

        let summaryMd = """
        # Meeting Summary

        ## Key Points
        - Point one

        ## Action Items
        None.
        """
        try! summaryMd.write(to: tempDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        let counts = MeetingCounts.compute(summaryDirectory: tempDir, configURL: configURL, fileManager: fileManager)
        let keyPoints = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertEqual(
            OwnscribeConfigReader.parseOutputSettings(fromTOML: configToml).format,
            "markdown",
            "the single quotes must be stripped: this is the only assertion here that can SEE the parse, "
                + "because summary.md is the fallback branch of `format == \"json\" ? ... : \"summary.md\"` "
                + "and so is reached even when the parse returns the literal \"'markdown'\""
        )
        XCTAssertEqual(counts.actionItemCount, 0, "Badge: 0 actions")
        XCTAssertNil(counts.unanchoredClaimCount, "Badge: nil (no anchors file)")
        XCTAssertEqual(keyPoints?.count, 1, "Inspector: 1 key point")
        XCTAssertNil(keyPoints?[0].anchors, "Inspector: nil (no anchors file)")
    }

    func testBadgeAndInspectorAgreeOnJsonDoubleQuotes() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")
        let configToml = """
        [output]
        format = "json"
        """
        try! configToml.write(to: configURL, atomically: true, encoding: .utf8)

        let summaryJson = """
        {
          "summary": "Test",
          "key_points": ["Gary discussed a bug"],
          "action_items": []
        }
        """
        try! summaryJson.write(to: tempDir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [{"timestamp": "08:30", "context": "Gary"}]
          }
        }
        """
        try! anchorsJson.write(to: tempDir.appendingPathComponent("anchors.json"), atomically: true, encoding: .utf8)

        let counts = MeetingCounts.compute(summaryDirectory: tempDir, configURL: configURL, fileManager: fileManager)
        let keyPoints = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertEqual(counts.actionItemCount, 0, "Badge: 0 actions")
        XCTAssertEqual(counts.unanchoredClaimCount, 0, "Badge: 0 unanchored (Gary matched)")
        XCTAssertEqual(keyPoints?.count, 1, "Inspector: 1 key point")
        XCTAssertEqual(keyPoints?[0].anchors?.count, 1, "Inspector: Gary matched")
    }

    func testBadgeAndInspectorAgreeOnJsonSingleQuotes() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")
        let configToml = """
        [output]
        format = 'json'
        """
        try! configToml.write(to: configURL, atomically: true, encoding: .utf8)

        let summaryJson = """
        {
          "summary": "Test",
          "key_points": ["Point one", "Point two"],
          "action_items": ["Do thing"]
        }
        """
        try! summaryJson.write(to: tempDir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)

        let counts = MeetingCounts.compute(summaryDirectory: tempDir, configURL: configURL, fileManager: fileManager)
        let keyPoints = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertEqual(counts.actionItemCount, 1, "Badge: 1 action")
        XCTAssertNil(counts.unanchoredClaimCount, "Badge: nil (no anchors file)")
        XCTAssertEqual(keyPoints?.count, 2, "Inspector: 2 key points")
        XCTAssertNil(keyPoints?[0].anchors, "Inspector: nil (no anchors file)")
        XCTAssertNil(keyPoints?[1].anchors, "Inspector: nil (no anchors file)")
    }
}
