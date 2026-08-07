import XCTest
@testable import OwnscribeMenuBar

final class TrackStatusWiringTests: XCTestCase {
    func testSilentAndSpeechTracksRenderDifferently() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let silentDir = home.appendingPathComponent("clew/2026-07-27_1352")
        let speechDir = home.appendingPathComponent("clew/2026-07-27_1536_project-technical-review-key-points")

        let silent = AudioTracksPresence.checkTracks(in: silentDir)
            .first { $0.filename == "recording.wav" }
        let speech = AudioTracksPresence.checkTracks(in: speechDir)
            .first { $0.filename == "recording.wav" }

        let silentStatus = try XCTUnwrap(silent).displayStatus
        let speechStatus = try XCTUnwrap(speech).displayStatus

        XCTAssertNotEqual(silentStatus, speechStatus, "a silent capture must not render like one with speech")
        XCTAssertFalse(silentStatus.contains("✓"), "33s of pure silence must not carry a checkmark")
        XCTAssertTrue(speechStatus.contains("✓"), "a real meeting must carry a checkmark")
    }

    func testAbsentTrackRendersDash() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("wire-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: tmp) }

        let track = try XCTUnwrap(AudioTracksPresence.checkTracks(in: tmp).first)

        XCTAssertEqual(track.displayStatus, "—", "an absent track must render as a dash, never a checkmark")
    }
}
