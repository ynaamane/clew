import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class UtteranceScrollIdentityTests: XCTestCase {
    private let markdown = """
    # Transcript

    **Language:** en

    [05:28] The JWT authentication setup was reviewed.
    [06:40] Oui exactement.
    [08:30] Gary said he would check the bug before the release.
    """

    func testScrollIdSurvivesTheBackchannelFilterAndAnArrayCopy() throws {
        let doc = try TranscriptDocument(markdown: markdown)
        XCTAssertEqual(doc.utterances.count, 3)

        let hidden = doc.utterances.filter { !$0.isBackchannel }
        let shown = doc.utterances

        XCTAssertEqual(hidden.count, 2, "The middle line is three words, so the toggle filters it")
        XCTAssertEqual(
            hidden[0].id, shown[0].id,
            "visibleUtterances rebuilds the array on every toggle flip; if filtering minted new ids, the ScrollViewReader target resolved before the flip would silently point at nothing")
        XCTAssertEqual(hidden.last?.id, shown.last?.id)
    }

    func testAScrollTargetIsInvalidatedByReparsingTheSameMarkdown() throws {
        let first = try TranscriptDocument(markdown: markdown)
        let second = try TranscriptDocument(markdown: markdown)

        XCTAssertNotEqual(
            first.utterances[0].id, second.utterances[0].id,
            "Utterance.id is `let id = UUID()`, minted per instance, so identical markdown yields different ids. A target must be resolved at click time against the array being rendered, never cached across the .task that reassigns the transcript.")
    }

    func testTargetingAgainstTheRenderedArrayResolvesInsideThatArray() throws {
        let doc = try TranscriptDocument(markdown: markdown)

        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "08:30", in: doc.utterances, backchannelVisible: true)

        XCTAssertNotNil(target)
        XCTAssertTrue(
            doc.utterances.contains(where: { $0.id == target?.utteranceID }),
            "The returned id must belong to the array that was passed in, which is the array the ForEach renders")
    }
}
