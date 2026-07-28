import XCTest
@testable import OwnscribeMenuBar

final class EnvelopeDocumentTests: XCTestCase {
    func testLoadRealProductionEnvelope() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let fixtureSource = URL(fileURLWithPath: "/tmp/ms-fixture/envelope.json")
        let fixtureTarget = tempDir.appendingPathComponent("envelope.json")
        try FileManager.default.copyItem(at: fixtureSource, to: fixtureTarget)

        let doc = try EnvelopeDocument(contentsOf: fixtureTarget)

        XCTAssertEqual(doc.buckets.count, 500, "Fixture is 500 buckets from real 17.5-min recording")
        XCTAssertEqual(doc.buckets.max() ?? 0, 1.0, accuracy: 0.0001, "Normalized envelope peaks at 1.0")

        let exactlyZero = doc.buckets.filter { $0 == 0.0 }.count
        XCTAssertEqual(exactlyZero, 7, "Fixture has exactly 7 buckets == 0.0 (indices 23-29)")
    }

    func testAbsentFileReturnsNil() throws {
        let nonexistent = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).json")

        let doc = try? EnvelopeDocument(contentsOf: nonexistent)

        XCTAssertNil(doc, "Absent envelope.json MUST throw, yielding nil via try?")
    }

    func testAllZeroEnvelopeIsDistinctFromAbsent() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let envelopePath = tempDir.appendingPathComponent("envelope.json")
        let json = """
        {"envelope": [0.0, 0.0, 0.0]}
        """
        try json.write(to: envelopePath, atomically: true, encoding: .utf8)

        let doc = try EnvelopeDocument(contentsOf: envelopePath)

        XCTAssertEqual(doc.buckets.count, 3, "All-zero envelope on disk is different from file absent")
        XCTAssertEqual(doc.buckets, [0.0, 0.0, 0.0])
    }
}
