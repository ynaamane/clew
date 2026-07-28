import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class MeetingInspectorKeyPointAnchorsTests: XCTestCase {
    var tempDir: URL!
    var fileManager: FileManager!

    override func setUp() {
        super.setUp()
        fileManager = FileManager.default
        tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? fileManager.removeItem(at: dir)
        }
        super.tearDown()
    }

    func testLoadKeyPointsWithAnchors() {
        let summaryURL = tempDir.appendingPathComponent("summary.md")
        let anchorsURL = tempDir.appendingPathComponent("anchors.json")

        let summaryMd = """
        # Meeting Summary

        ## Summary
        Technical review of the project.

        ## Key Points
        - Gary discussed a bug that needs checking
        - JWT authentication setup was reviewed
        - Lambda deployment on architecture was explained
        - The possibility of using a fictitious user for testing was considered

        ## Action Items
        None mentioned.
        """
        try! summaryMd.write(to: summaryURL, atomically: true, encoding: .utf8)

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [
              {"timestamp": "08:30", "context": "Gary discussed the bug"}
            ],
            "JWT": [
              {"timestamp": "05:28", "context": "JWT auth setup"},
              {"timestamp": "13:32", "context": "JWT token testing"}
            ],
            "Lambda": [
              {"timestamp": "05:09", "context": "Lambda deployment"}
            ]
          }
        }
        """
        try! anchorsJson.write(to: anchorsURL, atomically: true, encoding: .utf8)

        let result = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            fileManager: fileManager
        )

        XCTAssertNotNil(result, "Should load key points and anchors")
        XCTAssertEqual(result?.count, 4, "Four key points")

        let firstPoint = result?[0]
        XCTAssertEqual(firstPoint?.text, "Gary discussed a bug that needs checking")
        XCTAssertEqual(firstPoint?.anchors.count, 1, "First point has one anchor")
        XCTAssertEqual(firstPoint?.anchors["Gary"]?.first?.timestamp, "08:30")

        let secondPoint = result?[1]
        XCTAssertEqual(secondPoint?.text, "JWT authentication setup was reviewed")
        XCTAssertEqual(secondPoint?.anchors.count, 1, "Second point has JWT")
        XCTAssertEqual(secondPoint?.anchors["JWT"]?.count, 2, "JWT has two timestamps")

        let fourthPoint = result?[3]
        XCTAssertEqual(fourthPoint?.text, "The possibility of using a fictitious user for testing was considered")
        XCTAssertTrue(fourthPoint?.anchors.isEmpty == true, "Fourth point has no anchors")
    }

    func testLoadKeyPointsWithNoAnchorsFile() {
        let summaryURL = tempDir.appendingPathComponent("summary.md")

        let summaryMd = """
        # Meeting Summary

        ## Key Points
        - First point
        - Second point

        ## Action Items
        None mentioned.
        """
        try! summaryMd.write(to: summaryURL, atomically: true, encoding: .utf8)

        let result = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            fileManager: fileManager
        )

        XCTAssertNotNil(result, "Should still load key points without anchors file")
        XCTAssertEqual(result?.count, 2, "Two key points")
        XCTAssertTrue(result?[0].anchors.isEmpty == true, "No anchors")
        XCTAssertTrue(result?[1].anchors.isEmpty == true, "No anchors")
    }

    func testLoadKeyPointsWithNoSummaryFile() {
        let result = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            fileManager: fileManager
        )

        XCTAssertNil(result, "Missing summary returns nil")
    }

    func testKeyPointsAnchorsCaseInsensitive() {
        let summaryURL = tempDir.appendingPathComponent("summary.md")
        let anchorsURL = tempDir.appendingPathComponent("anchors.json")

        let summaryMd = """
        # Meeting Summary

        ## Key Points
        - The jwt token and GARY's review

        ## Action Items
        None.
        """
        try! summaryMd.write(to: summaryURL, atomically: true, encoding: .utf8)

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [{"timestamp": "08:30", "context": "Gary"}],
            "JWT": [{"timestamp": "05:28", "context": "JWT"}]
          }
        }
        """
        try! anchorsJson.write(to: anchorsURL, atomically: true, encoding: .utf8)

        let result = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: tempDir,
            fileManager: fileManager
        )

        XCTAssertEqual(result?.count, 1)
        let point = result?[0]
        XCTAssertEqual(point?.anchors.count, 2, "Case-insensitive match finds both tokens")
        XCTAssertNotNil(point?.anchors["Gary"])
        XCTAssertNotNil(point?.anchors["JWT"])
    }
}
