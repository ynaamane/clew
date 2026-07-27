import XCTest
@testable import OwnscribeMenuBar

final class EnrolledSpeakerStoreTests: XCTestCase {
    private func makeHome(_ json: String?) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("voices-\(UUID().uuidString)")
        let dir = home.appendingPathComponent(".config/meeting-scribe/voiceprints")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let json {
            try json.write(to: dir.appendingPathComponent("voiceprints.json"), atomically: true, encoding: .utf8)
        }
        return home
    }

    func testReadsNamesFromThePythonVoiceprintFile() throws {
        let home = try makeHome("""
        {
          "voiceprints": [
            {"name": "Sam", "embedding": [0.1, 0.2]},
            {"name": "Idris", "embedding": [0.3]}
          ]
        }
        """)
        defer { try? FileManager.default.removeItem(at: home) }

        XCTAssertEqual(EnrolledSpeakerStore.names(in: home), ["Sam", "Idris"])
    }

    func testMissingFileMeansNoVoicesRatherThanAnError() throws {
        let home = try makeHome(nil)
        defer { try? FileManager.default.removeItem(at: home) }

        XCTAssertEqual(EnrolledSpeakerStore.names(in: home), [])
    }

    func testMalformedFileDoesNotBrickTheSidebar() throws {
        let home = try makeHome("{ this is not json")
        defer { try? FileManager.default.removeItem(at: home) }

        XCTAssertEqual(
            EnrolledSpeakerStore.names(in: home), [],
            "A corrupt voiceprint file must degrade to an empty list; the window is built at launch and must not fail to open")
    }

    func testEmbeddingsAreNotLoadedIntoTheUI() throws {
        let home = try makeHome("""
        {"voiceprints": [{"name": "Sam", "embedding": [0.1, 0.2, 0.3]}]}
        """)
        defer { try? FileManager.default.removeItem(at: home) }

        let names = EnrolledSpeakerStore.names(in: home)

        XCTAssertEqual(names, ["Sam"])
    }
}
