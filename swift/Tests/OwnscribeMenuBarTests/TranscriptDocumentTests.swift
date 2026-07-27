import XCTest
@testable import OwnscribeMenuBar

final class TranscriptDocumentTests: XCTestCase {
    func testCurrentFormatKeepsEveryUtterance() throws {
        let markdown = """
        # Transcript

        **Language:** fr\u{0020}\u{0020}
        **Duration:** 17:30\u{0020}\u{0020}

        **SPEAKER_01** [05:09]
        [05:09] Une image de coeur qui se deploie sur la Lambda.
        [05:28] Et devant, c'est toujours le JWT ?

        **SPEAKER_00** [05:54]
        [05:54] Ok.
        """

        let doc = try TranscriptDocument(markdown: markdown)

        XCTAssertEqual(doc.language, "fr")
        XCTAssertEqual(doc.duration, 17 * 60 + 30)
        XCTAssertEqual(doc.utterances.count, 3)
        XCTAssertEqual(doc.utterances[0].speaker, "SPEAKER_01")
        XCTAssertEqual(doc.utterances[0].start, 5 * 60 + 9)
        XCTAssertEqual(doc.utterances[2].speaker, "SPEAKER_00")
    }

    func testLegacyFormatDoesNotLoseTheFirstLineOfEachTurn() throws {
        let legacy = """
        # Transcript

        **Language:** fr\u{0020}\u{0020}

        **SPEAKER_01** [05:09]
        Une image de coeur qui se deploie sur la Lambda.
        [05:28] Et devant, c'est toujours le JWT ?

        **SPEAKER_00** [05:54]
        Ok.
        """

        let doc = try TranscriptDocument(markdown: legacy)

        XCTAssertEqual(
            doc.utterances.count, 3,
            "Meetings written before the timestamp fix put each turn's first line with no [mm:ss]; dropping it loses 28% of the transcript, including the claims most worth verifying")
        XCTAssertEqual(doc.utterances[0].text, "Une image de coeur qui se deploie sur la Lambda.")
        XCTAssertEqual(
            doc.utterances[0].start, 5 * 60 + 9,
            "A turn's first line must inherit the timestamp from its speaker header")
        XCTAssertEqual(doc.utterances[2].speaker, "SPEAKER_00")
        XCTAssertEqual(doc.utterances[2].start, 5 * 60 + 54)
    }

    func testSpeakersAreListedInFirstAppearanceOrder() throws {
        let markdown = """
        **SPEAKER_01** [00:01]
        [00:01] A.

        **Owner** [00:05]
        [00:05] B.

        **SPEAKER_01** [00:09]
        [00:09] C.
        """

        let doc = try TranscriptDocument(markdown: markdown)

        XCTAssertEqual(doc.speakers, ["SPEAKER_01", "Owner"])
    }

    func testBackchannelIsFlaggedSoItCanBeFolded() throws {
        let markdown = """
        **SPEAKER_00** [00:01]
        [00:01] Ok.
        [00:03] Mm-hmm.
        [00:07] Et sur la partie architecture, j'entends une image de coeur.
        """

        let doc = try TranscriptDocument(markdown: markdown)

        XCTAssertTrue(doc.utterances[0].isBackchannel)
        XCTAssertTrue(doc.utterances[1].isBackchannel)
        XCTAssertFalse(doc.utterances[2].isBackchannel)
    }

    func testEmptyTranscriptIsNotAnError() throws {
        let doc = try TranscriptDocument(markdown: "# Transcript\n")

        XCTAssertTrue(doc.utterances.isEmpty)
        XCTAssertTrue(doc.speakers.isEmpty)
    }
}

extension TranscriptDocumentTests {
    func testAStampedLineClearsTheInheritedHeaderTimestamp() throws {
        let mixed = """
        **SPEAKER_01** [00:12]
        [00:30] Stamped line.
        Bare line after a stamped one.
        """

        let doc = try TranscriptDocument(markdown: mixed)

        XCTAssertEqual(
            doc.utterances.count, 1,
            "Once a timestamped line consumes the turn, a following bare line must not resurrect the header timestamp — that invents an utterance AND puts it out of chronological order")
        XCTAssertEqual(doc.utterances[0].text, "Stamped line.")
        XCTAssertEqual(doc.utterances[0].start, 30)
    }
}
