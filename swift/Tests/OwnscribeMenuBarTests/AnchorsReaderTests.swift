import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class AnchorsReaderTests: XCTestCase {
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

    func testLoadAnchorsFromMissingFile() {
        let anchorsURL = tempDir.appendingPathComponent("anchors.json")
        let result = AnchorsReader.loadAnchors(from: anchorsURL, fileManager: fileManager)

        XCTAssertNil(result, "Missing file returns nil")
    }

    func testLoadAnchorsFromValidJSON() {
        let anchorsURL = tempDir.appendingPathComponent("anchors.json")

        let anchorsJson = """
        {
          "version": "1.0",
          "anchors": {
            "Gary": [
              {"timestamp": "08:30", "context": "Gary discussed the bug"}
            ],
            "JWT": [
              {"timestamp": "05:28", "context": "JWT authentication"},
              {"timestamp": "13:32", "context": "JWT token testing"}
            ]
          }
        }
        """
        try! anchorsJson.write(to: anchorsURL, atomically: true, encoding: .utf8)

        let result = AnchorsReader.loadAnchors(from: anchorsURL, fileManager: fileManager)

        XCTAssertNotNil(result, "Valid JSON returns result")
        XCTAssertEqual(result?.count, 2, "Two anchored tokens")

        let gary = result?["Gary"]
        XCTAssertEqual(gary?.count, 1, "Gary has one anchor")
        XCTAssertEqual(gary?.first?.timestamp, "08:30")
        XCTAssertTrue(gary?.first?.context.contains("discussed") == true)

        let jwt = result?["JWT"]
        XCTAssertEqual(jwt?.count, 2, "JWT has two anchors")
        XCTAssertEqual(jwt?.first?.timestamp, "05:28")
    }

    func testFindAnchorsForTextWithOneMatch() {
        let keyPoint = "Discussion about Gary and his bug fix"
        let anchors = [
            "Gary": [TokenAnchor(timestamp: "08:30", context: "Gary joined")],
            "JWT": [TokenAnchor(timestamp: "05:28", context: "JWT auth")]
        ]

        let result = AnchorsReader.findAnchorsForText(keyPoint, in: anchors)

        XCTAssertEqual(result.count, 1, "Found one matching token")
        XCTAssertEqual(result["Gary"]?.count, 1)
        XCTAssertEqual(result["Gary"]?.first?.timestamp, "08:30")
    }

    func testFindAnchorsForTextWithMultipleMatches() {
        let keyPoint = "Gary discussed JWT authentication with Lambda security"
        let anchors = [
            "Gary": [TokenAnchor(timestamp: "08:30", context: "Gary joined")],
            "JWT": [
                TokenAnchor(timestamp: "05:28", context: "JWT auth"),
                TokenAnchor(timestamp: "13:32", context: "JWT test")
            ],
            "Lambda": [TokenAnchor(timestamp: "05:09", context: "Lambda deploy")]
        ]

        let result = AnchorsReader.findAnchorsForText(keyPoint, in: anchors)

        XCTAssertEqual(result.count, 3, "Found three matching tokens")
        XCTAssertNotNil(result["Gary"])
        XCTAssertEqual(result["JWT"]?.count, 2, "JWT has both anchors")
        XCTAssertNotNil(result["Lambda"])
    }

    func testFindAnchorsForTextWithNoMatches() {
        let keyPoint = "Discussion about architecture design patterns"
        let anchors = [
            "Gary": [TokenAnchor(timestamp: "08:30", context: "Gary joined")],
            "JWT": [TokenAnchor(timestamp: "05:28", context: "JWT auth")]
        ]

        let result = AnchorsReader.findAnchorsForText(keyPoint, in: anchors)

        XCTAssertTrue(result.isEmpty, "No matching tokens returns empty dict")
    }

    func testFindAnchorsCaseInsensitive() {
        let keyPoint = "The jwt token and GARY's review"
        let anchors = [
            "Gary": [TokenAnchor(timestamp: "08:30", context: "Gary joined")],
            "JWT": [TokenAnchor(timestamp: "05:28", context: "JWT auth")]
        ]

        let result = AnchorsReader.findAnchorsForText(keyPoint, in: anchors)

        XCTAssertEqual(result.count, 2, "Case-insensitive matching finds both")
        XCTAssertNotNil(result["Gary"])
        XCTAssertNotNil(result["JWT"])
    }

    func testFindAnchorsWordBoundary() {
        let keyPoint = "GWT token processing"
        let anchors = [
            "GW": [TokenAnchor(timestamp: "01:00", context: "GW prefix")],
            "GWT": [TokenAnchor(timestamp: "05:37", context: "GWT token")]
        ]

        let result = AnchorsReader.findAnchorsForText(keyPoint, in: anchors)

        XCTAssertEqual(result.count, 1, "Only exact word boundary match")
        XCTAssertNotNil(result["GWT"], "GWT matches")
        XCTAssertNil(result["GW"], "GW does not match (not a word boundary)")
    }

    func testHasAnchoredToken() {
        let anchors = [
            "Gary": [TokenAnchor(timestamp: "08:30", context: "Gary joined")],
            "JWT": [TokenAnchor(timestamp: "05:28", context: "JWT auth")]
        ]

        XCTAssertTrue(AnchorsReader.hasAnchoredToken(in: "Gary reviewed the code", anchors: anchors))
        XCTAssertTrue(AnchorsReader.hasAnchoredToken(in: "JWT authentication setup", anchors: anchors))
        XCTAssertFalse(AnchorsReader.hasAnchoredToken(in: "Architecture discussion", anchors: anchors))
    }
}
