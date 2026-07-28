import XCTest
@testable import OwnscribeMenuBar

final class MeetingAssetsTests: XCTestCase {
    func testLoadMeetingAssetsWithBothFilesPresent() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let transcriptMd = """
        # Transcript

        **Language:** fr
        **Duration:** 10:30

        **SPEAKER_01** [00:05]
        [00:05] Test utterance.
        """
        try transcriptMd.write(to: tempDir.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)

        let envelopeJson = """
        {"envelope": [0.2, 0.5, 0.8]}
        """
        try envelopeJson.write(to: tempDir.appendingPathComponent("envelope.json"), atomically: true, encoding: .utf8)

        let meeting = MeetingSummary(directory: tempDir, hasTranscript: true, hasSummary: false)
        let assets = loadMeetingAssets(from: meeting)

        XCTAssertNotNil(assets.transcript, "Transcript must load when file exists")
        XCTAssertEqual(assets.transcript?.language, "fr")
        XCTAssertNotNil(assets.envelope, "Envelope must load when file exists")
        XCTAssertEqual(assets.envelope?.buckets.count, 3)
    }

    func testLoadMeetingAssetsWithTranscriptOnlyReturnsNilEnvelope() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let transcriptMd = """
        # Transcript

        **SPEAKER_01** [00:05]
        [00:05] Test.
        """
        try transcriptMd.write(to: tempDir.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)

        let meeting = MeetingSummary(directory: tempDir, hasTranscript: true, hasSummary: false)
        let assets = loadMeetingAssets(from: meeting)

        XCTAssertNotNil(assets.transcript, "Transcript must load when file exists")
        XCTAssertNil(assets.envelope, "Envelope must be nil when file absent")
    }

    func testLoadMeetingAssetsWithEnvelopeOnlyReturnsNilTranscript() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let envelopeJson = """
        {"envelope": [0.1, 0.2]}
        """
        try envelopeJson.write(to: tempDir.appendingPathComponent("envelope.json"), atomically: true, encoding: .utf8)

        let meeting = MeetingSummary(directory: tempDir, hasTranscript: false, hasSummary: false)
        let assets = loadMeetingAssets(from: meeting)

        XCTAssertNil(assets.transcript, "Transcript must be nil when file absent")
        XCTAssertNotNil(assets.envelope, "Envelope must load when file exists")
    }

    func testLoadMeetingAssetsWithBothAbsentReturnsBothNil() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tempDir) }

        let meeting = MeetingSummary(directory: tempDir, hasTranscript: false, hasSummary: false)
        let assets = loadMeetingAssets(from: meeting)

        XCTAssertNil(assets.transcript, "Transcript must be nil when file absent")
        XCTAssertNil(assets.envelope, "Envelope must be nil when file absent")
    }
}
