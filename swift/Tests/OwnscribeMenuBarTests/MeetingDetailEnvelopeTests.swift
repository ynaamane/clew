import XCTest
@testable import OwnscribeMenuBar

final class MeetingDetailEnvelopeTests: XCTestCase {
    func testProductionLoaderReturnsEnvelopeWhenFileExists() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let json = """
        {"envelope": [0.2, 0.5, 0.8, 0.3]}
        """
        try json.write(to: tempDir.appendingPathComponent("envelope.json"), atomically: true, encoding: .utf8)

        let envelope = EnvelopeDocument.load(from: tempDir)

        XCTAssertNotNil(envelope, "Production seam must load envelope when file exists")
        XCTAssertEqual(envelope?.buckets.count, 4)
        XCTAssertEqual(envelope?.buckets[2] ?? 0, 0.8, accuracy: 0.001)
    }

    func testProductionLoaderReturnsNilWhenFileAbsent() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let envelope = EnvelopeDocument.load(from: tempDir)

        XCTAssertNil(envelope, "Production seam must return nil when envelope.json absent")
    }
}

