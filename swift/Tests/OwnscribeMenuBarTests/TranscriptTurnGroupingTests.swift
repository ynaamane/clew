import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class TranscriptTurnGroupingTests: XCTestCase {
    private func utterance(_ speaker: String, _ start: TimeInterval, _ text: String) -> Utterance {
        Utterance(speaker: speaker, start: start, text: text)
    }

    func testEmptyUtterancesProducesNoTurns() {
        XCTAssertEqual(TranscriptTurnGrouping.turns(from: []), [])
    }

    func testSingleUtteranceProducesOneTurnWithOneLine() {
        let one = utterance("SPEAKER_00", 5, "Bonjour tout le monde, comment allez-vous aujourd'hui")
        let turns = TranscriptTurnGrouping.turns(from: [one])

        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].speaker, "SPEAKER_00")
        XCTAssertEqual(turns[0].utterances, [one])
        XCTAssertEqual(turns[0].firstTimecode, one.timecode)
    }

    func testAlternatingSpeakersProduceOneTurnEach() {
        let a1 = utterance("SPEAKER_00", 0, "Première réplique assez longue pour ne pas être un backchannel")
        let b1 = utterance("SPEAKER_01", 5, "Deuxième réplique assez longue pour ne pas être un backchannel")
        let a2 = utterance("SPEAKER_00", 10, "Troisième réplique assez longue pour ne pas être un backchannel")

        let turns = TranscriptTurnGrouping.turns(from: [a1, b1, a2])

        XCTAssertEqual(turns.count, 3, "Alternating speakers never merge, even when the speaker repeats later")
        XCTAssertEqual(turns.map(\.speaker), ["SPEAKER_00", "SPEAKER_01", "SPEAKER_00"])
        XCTAssertEqual(turns.map { $0.utterances.count }, [1, 1, 1])
    }

    func testLongRunOfSameSpeakerProducesOneTurnWithAllLines() {
        let lines = (0..<12).map {
            utterance("SPEAKER_00", TimeInterval($0 * 3), "Réplique numéro \($0) assez longue pour rester visible")
        }

        let turns = TranscriptTurnGrouping.turns(from: lines)

        XCTAssertEqual(turns.count, 1, "Twelve consecutive lines from one speaker form a single turn")
        XCTAssertEqual(turns[0].utterances.count, 12)
        XCTAssertEqual(turns[0].utterances, lines, "Order inside the turn is preserved")
    }

    func testUnknownSpeakerGroupsLikeAnyOtherSpeaker() {
        let u1 = utterance("Unknown", 0, "Une phrase suffisamment longue pour ne pas être filtrée")
        let u2 = utterance("Unknown", 4, "Une autre phrase suffisamment longue pour ne pas être filtrée")

        let turns = TranscriptTurnGrouping.turns(from: [u1, u2])

        XCTAssertEqual(turns.count, 1, "Unknown is a speaker label like any other for grouping purposes")
        XCTAssertEqual(turns[0].speaker, "Unknown")
        XCTAssertEqual(turns[0].utterances.count, 2)
    }

    func testConsecutiveSameSpeakerAfterBackchannelFilterMergeIntoOneTurn() {
        let before = utterance("SPEAKER_00", 0, "Une phrase suffisamment longue pour ne pas être filtrée")
        let backchannel = utterance("SPEAKER_01", 2, "Ok")
        let after = utterance("SPEAKER_00", 4, "Une autre phrase suffisamment longue pour ne pas être filtrée")

        XCTAssertTrue(backchannel.isBackchannel)

        let filtered = [before, backchannel, after].filter { !$0.isBackchannel }
        let turns = TranscriptTurnGrouping.turns(from: filtered)

        XCTAssertEqual(
            turns.count, 1,
            "Once the backchannel line is filtered out upstream, the two SPEAKER_00 lines become adjacent and must merge")
        XCTAssertEqual(turns[0].utterances, [before, after])
    }

    func testTurnPreservesUtteranceOrderAcrossMultipleTurns() {
        let a1 = utterance("SPEAKER_00", 0, "Première réplique assez longue pour ne pas être un backchannel")
        let a2 = utterance("SPEAKER_00", 2, "Deuxième réplique assez longue pour ne pas être un backchannel")
        let b1 = utterance("SPEAKER_01", 5, "Troisième réplique assez longue pour ne pas être un backchannel")
        let b2 = utterance("SPEAKER_01", 7, "Quatrième réplique assez longue pour ne pas être un backchannel")

        let turns = TranscriptTurnGrouping.turns(from: [a1, a2, b1, b2])

        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].utterances, [a1, a2])
        XCTAssertEqual(turns[1].utterances, [b1, b2])
    }

    func testEachTurnKeepsFirstUtterancesTimecodeAsHeaderTimecode() {
        let a1 = utterance("SPEAKER_00", 69, "Première réplique assez longue pour ne pas être un backchannel")
        let a2 = utterance("SPEAKER_00", 130, "Deuxième réplique assez longue pour ne pas être un backchannel")

        let turns = TranscriptTurnGrouping.turns(from: [a1, a2])

        XCTAssertEqual(turns[0].firstTimecode, a1.timecode, "The header timestamp is the first line's, not the last")
        XCTAssertNotEqual(turns[0].firstTimecode, a2.timecode)
    }

    func testTurnIDIsStableAndDerivedFromFirstUtterance() {
        let a1 = utterance("SPEAKER_00", 0, "Première réplique assez longue pour ne pas être un backchannel")
        let a2 = utterance("SPEAKER_00", 2, "Deuxième réplique assez longue pour ne pas être un backchannel")

        let turns = TranscriptTurnGrouping.turns(from: [a1, a2])

        XCTAssertEqual(turns[0].id, a1.id, "A stable, unique id lets ForEach diff turns without a synthetic counter")
    }
}
