import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class AnchorEvidenceRealMeetingTests: XCTestCase {
    private var fixtureDir: URL!

    override func setUpWithError() throws {
        fixtureDir = URL(fileURLWithPath: "/tmp/ms-fixture")
        for name in ["summary.md", "anchors.json", "transcript.md"] {
            guard FileManager.default.fileExists(atPath: fixtureDir.appendingPathComponent(name).path) else {
                throw XCTSkip("Real meeting fixture not available. Run: python3 scripts/regenerate_fixtures.py")
            }
        }
    }

    private func loadRealKeyPoints() throws -> [KeyPointWithAnchors] {
        let configDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: configDir) }
        let configURL = configDir.appendingPathComponent("config.toml")
        try "[output]\nformat = \"markdown\"\n".write(to: configURL, atomically: true, encoding: .utf8)

        let keyPoints = MeetingInspectorState.loadKeyPointsWithAnchors(
            from: fixtureDir,
            configURL: configURL,
            fileManager: FileManager.default)
        return try XCTUnwrap(keyPoints, "The production loader must read the real meeting on disk")
    }

    func testEveryChipOfferedAsEvidenceOnTheRealMeetingReachesAnUtterance() throws {
        let keyPoints = try loadRealKeyPoints()
        let transcript = try TranscriptDocument(
            contentsOf: fixtureDir.appendingPathComponent("transcript.md"))

        var chipsChecked = 0
        var unreachable: [String] = []

        for keyPoint in keyPoints {
            for chip in AnchorEvidenceDisplayModel.display(for: keyPoint).chips {
                chipsChecked += 1
                let target = AnchorScrollTargeting.target(
                    forAnchorTimestamp: chip.timestamp,
                    provingToken: chip.token,
                    in: transcript.utterances,
                    backchannelVisible: false)
                if target == nil {
                    unreachable.append(chip.label)
                }
            }
        }

        XCTAssertGreaterThan(
            chipsChecked, 0,
            "The real meeting must produce at least one evidence chip, or this test proves nothing")
        XCTAssertEqual(
            unreachable, [],
            "A chip the user can click must resolve to an utterance; these did not: \(unreachable)")
    }

    func testAClickableChipLandsOnAnUtteranceThatContainsItsToken() throws {
        let keyPoints = try loadRealKeyPoints()
        let transcript = try TranscriptDocument(
            contentsOf: fixtureDir.appendingPathComponent("transcript.md"))

        var verified = 0
        var wrongEvidence: [String] = []

        for keyPoint in keyPoints {
            for chip in AnchorEvidenceDisplayModel.display(for: keyPoint).chips {
                guard let target = AnchorScrollTargeting.target(
                    forAnchorTimestamp: chip.timestamp,
                    provingToken: chip.token,
                    in: transcript.utterances,
                    backchannelVisible: false),
                    let landed = transcript.utterances.first(where: { $0.id == target.utteranceID })
                else { continue }

                verified += 1
                if !landed.text.lowercased().contains(chip.token.lowercased()) {
                    wrongEvidence.append("\(chip.label) landed on \(landed.timecode)")
                }
            }
        }

        XCTAssertGreaterThan(verified, 0, "No chip resolved, so nothing was verified")
        XCTAssertEqual(
            wrongEvidence, [],
            "The utterance shown as proof must contain the token it proves: \(wrongEvidence)")
    }

    func testTheRealMeetingHasBothAnchoredAndUnanchoredClaims() throws {
        let displays = try loadRealKeyPoints().map(AnchorEvidenceDisplayModel.display(for:))

        XCTAssertFalse(
            displays.contains(.notYetVerified),
            "anchors.json exists for this meeting, so no claim may read as never-checked")
        XCTAssertTrue(
            displays.contains(.noEvidenceFound),
            "The FR/EN mismatch leaves at least one key point unanchored on this meeting; "
                + "if this fails, absent evidence is being rendered as evidence")
        XCTAssertTrue(
            displays.contains(where: { !$0.chips.isEmpty }),
            "At least one key point must carry real evidence")
    }
}
