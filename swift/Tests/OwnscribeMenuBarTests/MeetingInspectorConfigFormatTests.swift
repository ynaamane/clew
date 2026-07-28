import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class MeetingInspectorConfigFormatTests: XCTestCase {
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

    func testLoadSummaryWithMarkdownFormat() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")
        let configToml = """
        [output]
        format = "markdown"
        """
        try! configToml.write(to: configURL, atomically: true, encoding: .utf8)

        let summaryMd = """
        # Meeting Summary

        ## Summary
        Test summary

        ## Key Points
        - Point one

        ## Action Items
        None.
        """
        try! summaryMd.write(to: tempDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        let result = MeetingInspectorState.loadSummary(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertNotNil(result, "Should load markdown summary")
        XCTAssertEqual(result?.prose, "Test summary")
    }

    func testLoadSummaryWithJsonFormat() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")
        let configToml = """
        [output]
        format = "json"
        """
        try! configToml.write(to: configURL, atomically: true, encoding: .utf8)

        let summaryJson = """
        {
          "summary": "Test JSON summary",
          "key_points": ["Point one", "Point two"],
          "action_items": []
        }
        """
        try! summaryJson.write(to: tempDir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)

        let result = MeetingInspectorState.loadSummary(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertNotNil(result, "Should load JSON summary")
        XCTAssertEqual(result?.prose, "Test JSON summary")
        XCTAssertEqual(result?.keyPoints.count, 2)
    }

    func testLoadSummaryWithMissingConfig() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")

        let summaryMd = """
        # Meeting Summary

        ## Summary
        Default format

        ## Action Items
        None.
        """
        try! summaryMd.write(to: tempDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        let result = MeetingInspectorState.loadSummary(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertNotNil(result, "Missing config should default to markdown")
        XCTAssertEqual(result?.prose, "Default format")
    }

    func testLoadSummaryWithNoOutputFormatSection() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")
        let configToml = """
        [audio]
        mic = true
        """
        try! configToml.write(to: configURL, atomically: true, encoding: .utf8)

        let summaryMd = """
        # Meeting Summary

        ## Summary
        No format specified

        ## Action Items
        None.
        """
        try! summaryMd.write(to: tempDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        let result = MeetingInspectorState.loadSummary(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertNotNil(result, "No format section should default to markdown")
        XCTAssertEqual(result?.prose, "No format specified")
    }

    func testLoadKeyPointsWithJsonFormat() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")
        let configToml = """
        [output]
        format = "json"
        """
        try! configToml.write(to: configURL, atomically: true, encoding: .utf8)

        let summaryJson = """
        {
          "summary": "Test",
          "key_points": ["Gary discussed a bug", "JWT authentication"],
          "action_items": []
        }
        """
        try! summaryJson.write(to: tempDir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [{"timestamp": "08:30", "context": "Gary"}],
            "JWT": [{"timestamp": "05:28", "context": "JWT"}]
          }
        }
        """
        try! anchorsJson.write(to: tempDir.appendingPathComponent("anchors.json"), atomically: true, encoding: .utf8)

        let result = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.count, 2)
        XCTAssertEqual(result?[0].text, "Gary discussed a bug")
        XCTAssertEqual(result?[0].anchors?.count, 1)
    }
}
