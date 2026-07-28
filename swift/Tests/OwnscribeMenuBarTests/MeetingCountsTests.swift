import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class MeetingCountsTests: XCTestCase {
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

    func testNoSummaryReturnsNilForBoth() {
        let result = MeetingCounts.compute(
            summaryDirectory: tempDir,
            fileManager: fileManager
        )

        XCTAssertNil(result.actionItemCount, "Missing summary → nil action count")
        XCTAssertNil(result.unanchoredClaimCount, "Missing summary → nil unanchored count")
    }

    func testNoAnchorsReturnsNilForUnanchored() {
        let summaryURL = tempDir.appendingPathComponent("summary.md")

        let summaryMd = """
        # Meeting Summary

        ## Key Points
        - First point
        - Second point

        ## Action Items
        - Do the thing
        - Check the code
        """
        try! summaryMd.write(to: summaryURL, atomically: true, encoding: .utf8)

        let result = MeetingCounts.compute(
            summaryDirectory: tempDir,
            fileManager: fileManager
        )

        XCTAssertEqual(result.actionItemCount, 2, "Two action items")
        XCTAssertNil(result.unanchoredClaimCount, "Missing anchors.json → nil unanchored count")
    }

    func testAllKeyPointsAnchoredReturnsZero() {
        let summaryURL = tempDir.appendingPathComponent("summary.md")
        let anchorsURL = tempDir.appendingPathComponent("anchors.json")

        let summaryMd = """
        # Meeting Summary

        ## Key Points
        - Gary discussed architecture
        - Lambda security was reviewed

        ## Action Items
        None mentioned.
        """
        try! summaryMd.write(to: summaryURL, atomically: true, encoding: .utf8)

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [{"timestamp": "08:30", "context": "Gary joined"}],
            "architecture": [{"timestamp": "10:00", "context": "architecture slide"}],
            "Lambda": [{"timestamp": "12:00", "context": "lambda function"}],
            "security": [{"timestamp": "14:00", "context": "security concerns"}]
          }
        }
        """
        try! anchorsJson.write(to: anchorsURL, atomically: true, encoding: .utf8)

        let result = MeetingCounts.compute(
            summaryDirectory: tempDir,
            fileManager: fileManager
        )

        XCTAssertEqual(result.actionItemCount, 0, "No action items")
        XCTAssertEqual(result.unanchoredClaimCount, 0, "All key points have anchored tokens")
    }

    func testPartiallyAnchoredWithProductionCapitalization() {
        let summaryURL = tempDir.appendingPathComponent("summary.md")
        let anchorsURL = tempDir.appendingPathComponent("anchors.json")

        let summaryMd = """
        # Meeting Summary

        ## Key Points
        - Gary discussed architecture
        - Lambda security with JWT was reviewed
        - The possibility of using a fictitious user for testing was considered

        ## Action Items
        - Follow up on security
        """
        try! summaryMd.write(to: summaryURL, atomically: true, encoding: .utf8)

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [{"timestamp": "08:30", "context": "Gary joined"}],
            "architecture": [{"timestamp": "10:00", "context": "architecture slide"}],
            "Lambda": [{"timestamp": "12:00", "context": "lambda function"}],
            "JWT": [{"timestamp": "14:00", "context": "JWT tokens"}],
            "security": [{"timestamp": "14:00", "context": "security concerns"}]
          }
        }
        """
        try! anchorsJson.write(to: anchorsURL, atomically: true, encoding: .utf8)

        let result = MeetingCounts.compute(
            summaryDirectory: tempDir,
            fileManager: fileManager
        )

        XCTAssertEqual(result.actionItemCount, 1, "One action item")
        XCTAssertEqual(result.unanchoredClaimCount, 1, "Third key point has no anchored tokens")
    }

    func testCaseSensitiveMatchingFixVerification() {
        let summaryURL = tempDir.appendingPathComponent("summary.md")
        let anchorsURL = tempDir.appendingPathComponent("anchors.json")

        let summaryMd = """
        # Meeting Summary

        ## Key Points
        - PPTX Tool integration discussed
        - Confluence setup reviewed
        - Zoom meeting scheduled

        ## Action Items
        None mentioned.
        """
        try! summaryMd.write(to: summaryURL, atomically: true, encoding: .utf8)

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "PPTX": [{"timestamp": "01:00", "context": "PPTX Tool"}],
            "Tool": [{"timestamp": "01:00", "context": "PPTX Tool"}],
            "Confluence": [{"timestamp": "02:00", "context": "Confluence setup"}],
            "Zoom": [{"timestamp": "03:00", "context": "Zoom meeting"}]
          }
        }
        """
        try! anchorsJson.write(to: anchorsURL, atomically: true, encoding: .utf8)

        let result = MeetingCounts.compute(
            summaryDirectory: tempDir,
            fileManager: fileManager
        )

        XCTAssertEqual(result.unanchoredClaimCount, 0, "All key points match despite mixed case")
    }
}
