import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class MeetingInspectorAbsentAnchorsTests: XCTestCase {
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

    func testAbsentAnchorsShowsNotYetVerified() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")
        let configToml = """
        [output]
        format = "markdown"
        """
        try! configToml.write(to: configURL, atomically: true, encoding: .utf8)

        let summaryMd = """
        # Meeting Summary

        ## Summary
        Technical review of project

        ## Key Points
        - Gary discussed a bug that needs checking
        - JWT authentication setup was reviewed
        - Lambda deployment architecture was explained

        ## Action Items
        None mentioned.
        """
        try! summaryMd.write(to: tempDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        let result = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertNotNil(result, "Should load key points")
        XCTAssertEqual(result?.count, 3, "Three key points")

        for keyPoint in result ?? [] {
            XCTAssertNil(keyPoint.anchors, "All points should have nil anchors when file is absent")
        }
    }

    func testPresentAnchorsShowsEvidenceOrDash() {
        let configURL = tempConfigDir.appendingPathComponent("config.toml")
        let configToml = """
        [output]
        format = "markdown"
        """
        try! configToml.write(to: configURL, atomically: true, encoding: .utf8)

        let summaryMd = """
        # Meeting Summary

        ## Summary
        Technical review

        ## Key Points
        - Gary discussed a bug that needs checking
        - JWT authentication setup was reviewed
        - The possibility of using a fictitious user for testing was considered

        ## Action Items
        None.
        """
        try! summaryMd.write(to: tempDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [{"timestamp": "08:30", "context": "Gary discussed the bug"}],
            "JWT": [{"timestamp": "05:28", "context": "JWT authentication"}]
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
        XCTAssertEqual(result?.count, 3)

        let first = result?[0]
        XCTAssertNotNil(first?.anchors, "First point has anchors dict")
        XCTAssertEqual(first?.anchors?.count, 1, "Gary is matched")

        let second = result?[1]
        XCTAssertNotNil(second?.anchors, "Second point has anchors dict")
        XCTAssertEqual(second?.anchors?.count, 1, "JWT is matched")

        let third = result?[2]
        XCTAssertNotNil(third?.anchors, "Third point has anchors dict")
        XCTAssertTrue(third?.anchors?.isEmpty == true, "Fictitious has no match - this is the dash")
    }

    func testAbsentVsPresentAnchorsRenderDifferently() {
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
        None.
        """
        try! summaryMd.write(to: tempDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        let withoutAnchors = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertEqual(withoutAnchors?.count, 2)
        XCTAssertNil(withoutAnchors?[0].anchors, "Without file: nil")
        XCTAssertNil(withoutAnchors?[1].anchors, "Without file: nil")

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [{"timestamp": "08:30", "context": "Gary"}]
          }
        }
        """
        try! anchorsJson.write(to: tempDir.appendingPathComponent("anchors.json"), atomically: true, encoding: .utf8)

        let withAnchors = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            configURL: configURL,
            fileManager: fileManager
        )

        XCTAssertEqual(withAnchors?.count, 2)
        XCTAssertNotNil(withAnchors?[0].anchors, "With file: non-nil dict")
        XCTAssertEqual(withAnchors?[0].anchors?.count, 1, "Gary matched")
        XCTAssertNotNil(withAnchors?[1].anchors, "With file: non-nil dict")
        XCTAssertTrue(withAnchors?[1].anchors?.isEmpty == true, "Unanchored has empty dict (dash)")

        XCTAssertNotEqual(
            withoutAnchors?[0].anchors == nil,
            withAnchors?[0].anchors == nil,
            "Absent vs present must render differently"
        )
    }
}
