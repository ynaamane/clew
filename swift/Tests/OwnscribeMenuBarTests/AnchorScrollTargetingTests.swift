import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class AnchorScrollTargetingTests: XCTestCase {
    private let transcriptMarkdown = """
    # Transcript

    **Language:** en
    **Duration:** 09:00

    **SPEAKER_00** [05:09]
    Une image de coeur qui se deploie sur la Lambda.

    **SPEAKER_01** [05:28]
    The JWT authentication setup was reviewed line by line.

    **SPEAKER_00** [06:40]
    Oui exactement.

    **SPEAKER_01** [08:30]
    Gary said he would check the bug before the release.
    """

    private func utterances() throws -> [Utterance] {
        try TranscriptDocument(markdown: transcriptMarkdown).utterances
    }

    func testExactTimecodeMatchSelectsThatUtterance() throws {
        let all = try utterances()
        XCTAssertEqual(all.count, 4)

        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "05:28", in: all, backchannelVisible: true)

        XCTAssertEqual(
            target?.utteranceID, all[1].id,
            "An anchor timestamp copied from a transcript line must land on that exact line")
    }

    func testTimestampBetweenTwoUtterancesSelectsTheLastOneAtOrBefore() throws {
        let all = try utterances()

        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "05:40", in: all, backchannelVisible: true)

        XCTAssertEqual(
            target?.utteranceID, all[1].id,
            "05:40 falls inside the line that started at 05:28; scrolling forward to 06:40 would land past the evidence")
    }

    func testTimestampBeforeTheFirstUtteranceIsUnreachable() throws {
        let all = try utterances()

        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "00:30", in: all, backchannelVisible: true)

        XCTAssertNil(
            target,
            "A timestamp earlier than every line cannot come from this transcript; snapping to the top would present the opening line as the evidence for the claim")
        XCTAssertFalse(AnchorScrollTargeting.canReach(anchorTimestamp: "00:30", in: all))
    }

    func testHourLongTimestampIsParsed() throws {
        let markdown = """
        # Transcript

        **Language:** en

        [00:10] Opening remarks.
        [01:05:30] The Lambda deployment came up again much later.
        """
        let all = try TranscriptDocument(markdown: markdown).utterances
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[1].start, 3930)

        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "01:05:30", in: all, backchannelVisible: true)

        XCTAssertEqual(
            target?.utteranceID, all[1].id,
            "Past one hour the pipeline writes HH:MM:SS, so the parser must accept three components")
    }

    func testUnparseableTimestampIsUnreachable() throws {
        let all = try utterances()

        for bad in ["", "abc", "530", "05", "05:xx", "::"] {
            XCTAssertNil(
                AnchorScrollTargeting.target(forAnchorTimestamp: bad, in: all, backchannelVisible: true),
                "\(bad) is not a timecode and must not resolve to any utterance")
            XCTAssertFalse(
                AnchorScrollTargeting.canReach(anchorTimestamp: bad, in: all),
                "\(bad) must render as static text, never as a control that does nothing")
        }
    }

    func testEmptyTranscriptIsUnreachable() {
        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "05:28", in: [], backchannelVisible: true)

        XCTAssertNil(target, "No transcript means nothing to scroll to")
        XCTAssertFalse(AnchorScrollTargeting.canReach(anchorTimestamp: "05:28", in: []))
    }

    func testBackchannelTargetAsksForTheToggleWhenHidden() throws {
        let all = try utterances()
        XCTAssertTrue(all[2].isBackchannel, "Oui exactement. is three words, so the toggle hides it")

        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "06:40", in: all, backchannelVisible: false)

        XCTAssertEqual(
            target?.utteranceID, all[2].id,
            "The evidence line is the target even when currently filtered out")
        XCTAssertEqual(
            target?.revealsBackchannel, true,
            "Scrolling to an id that is not rendered does nothing silently; the caller must reveal the row first")
    }

    func testBackchannelTargetNeedsNoToggleWhenAlreadyVisible() throws {
        let all = try utterances()

        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "06:40", in: all, backchannelVisible: true)

        XCTAssertEqual(target?.utteranceID, all[2].id)
        XCTAssertEqual(target?.revealsBackchannel, false, "The row is already on screen; do not touch the user's toggle")
    }

    func testOrdinaryTargetNeverTouchesTheToggle() throws {
        let all = try utterances()
        XCTAssertFalse(all[1].isBackchannel)

        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "05:28", in: all, backchannelVisible: false)

        XCTAssertEqual(target?.utteranceID, all[1].id)
        XCTAssertEqual(
            target?.revealsBackchannel, false,
            "A visible target must not flip the toggle and dump every filler line into the transcript")
    }

    func testNearMissOntoAHiddenLineStillRevealsIt() throws {
        let all = try utterances()

        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "07:00", in: all, backchannelVisible: false)

        XCTAssertEqual(target?.utteranceID, all[2].id, "07:00 falls inside the short line at 06:40")
        XCTAssertEqual(target?.revealsBackchannel, true)
    }

    func testDuplicateTimecodesSelectTheFirstLineAtThatMoment() throws {
        let markdown = """
        # Transcript

        **Language:** en

        [05:28] The JWT authentication setup was reviewed.
        [05:28] And the JWT refresh path too.
        """
        let all = try TranscriptDocument(markdown: markdown).utterances
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].start, all[1].start)

        let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: "05:28", in: all, backchannelVisible: true)

        XCTAssertEqual(
            target?.utteranceID, all[0].id,
            "Two lines share the timestamp; the earliest is the evidence, and it is the one the anchor context was cut from")
    }

    func testAReachableAnchorGetsAButtonAndAnUnreachableOneStaysStaticText() throws {
        let all = try utterances()

        XCTAssertEqual(
            AnchorScrollTargeting.interactivity(forAnchorTimestamp: "05:28", in: all), .scrollButton,
            "A resolvable anchor is the only case that earns a control")

        for unreachable in ["00:30", "abc", ""] {
            XCTAssertEqual(
                AnchorScrollTargeting.interactivity(forAnchorTimestamp: unreachable, in: all), .staticText,
                "\(unreachable) resolves to nothing; a516cc7 removed the button that looked live and did nothing rather than leave it")
        }

        XCTAssertEqual(
            AnchorScrollTargeting.interactivity(forAnchorTimestamp: "05:28", in: []), .staticText,
            "With no transcript loaded every chip must be inert text")
    }

    func testTargetIsResolvedAgainstTheArrayPassedIn() throws {
        let all = try utterances()
        let reparsed = try utterances()

        let fromFirst = AnchorScrollTargeting.target(
            forAnchorTimestamp: "05:28", in: all, backchannelVisible: true)
        let fromSecond = AnchorScrollTargeting.target(
            forAnchorTimestamp: "05:28", in: reparsed, backchannelVisible: true)

        XCTAssertEqual(fromFirst?.utteranceID, all[1].id)
        XCTAssertEqual(fromSecond?.utteranceID, reparsed[1].id)
        XCTAssertNotEqual(
            fromFirst?.utteranceID, fromSecond?.utteranceID,
            "Utterance.id is a fresh UUID per instance, so a target held across a reparse would no longer resolve — the id must be derived at click time from the array being rendered")
    }
}
