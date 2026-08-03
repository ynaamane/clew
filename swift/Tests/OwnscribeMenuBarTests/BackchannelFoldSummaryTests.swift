import Foundation
import XCTest
@testable import OwnscribeMenuBar

final class BackchannelFoldSummaryTests: XCTestCase {
    private func utterance(_ speaker: String, _ start: TimeInterval, _ text: String) -> Utterance {
        Utterance(speaker: speaker, start: start, text: text)
    }

    func testNoBackchannelUtterancesProducesNoLabel() {
        let long = utterance("SPEAKER_00", 0, "Une réplique assez longue pour ne jamais être un backchannel")
        XCTAssertNil(BackchannelFoldSummary.label(for: [long]))
    }

    func testEmptyTranscriptProducesNoLabel() {
        XCTAssertNil(BackchannelFoldSummary.label(for: []))
    }

    func testSingleBackchannelUtteranceIsCountedAndQuoted() {
        let ok = utterance("SPEAKER_00", 0, "Ok")
        let label = BackchannelFoldSummary.label(for: [ok])

        XCTAssertEqual(label, BackchannelFoldLabel(count: 1, examples: ["Ok"]))
        XCTAssertEqual(BackchannelFoldSummary.text(for: label!), "1 intervention courte masquée — « Ok »")
    }

    func testMultipleDistinctExamplesArePluralized() {
        let ok = utterance("SPEAKER_00", 0, "Ok")
        let merci = utterance("SPEAKER_01", 2, "Merci")
        let mmhmm = utterance("SPEAKER_00", 4, "Mm-hmm")
        let long = utterance("SPEAKER_00", 6, "Une réplique assez longue pour ne jamais être un backchannel")

        let label = BackchannelFoldSummary.label(for: [ok, merci, mmhmm, long])

        XCTAssertEqual(label?.count, 3, "Only backchannel lines are counted; the long line is excluded")
        XCTAssertEqual(label?.examples, ["Ok", "Merci", "Mm-hmm"])
        XCTAssertEqual(
            BackchannelFoldSummary.text(for: label!),
            "3 interventions courtes masquées — « Ok », « Merci », « Mm-hmm »")
    }

    func testExamplesAreCappedAtThreeDistinctTextsEvenWithMoreHiddenLines() {
        let utterances = ["Ok", "Merci", "Mm-hmm", "Oui", "Ah"].enumerated().map {
            utterance("SPEAKER_00", TimeInterval($0.offset), $0.element)
        }

        let label = BackchannelFoldSummary.label(for: utterances)

        XCTAssertEqual(label?.count, 5, "Every hidden line counts, even past the third distinct example")
        XCTAssertEqual(label?.examples, ["Ok", "Merci", "Mm-hmm"], "Capped at three distinct examples")
        XCTAssertEqual(
            BackchannelFoldSummary.text(for: label!),
            "5 interventions courtes masquées — « Ok », « Merci », « Mm-hmm »")
    }

    func testDuplicateTextsCountEveryOccurrenceButOnlyExampleOnce() {
        let a = utterance("SPEAKER_00", 0, "Ok")
        let b = utterance("SPEAKER_01", 2, "Ok")
        let c = utterance("SPEAKER_00", 4, "Ok")

        let label = BackchannelFoldSummary.label(for: [a, b, c])

        XCTAssertEqual(label?.count, 3, "Three hidden lines, even though they repeat the same word")
        XCTAssertEqual(label?.examples, ["Ok"], "The example list de-duplicates identical text")
        XCTAssertEqual(BackchannelFoldSummary.text(for: label!), "3 interventions courtes masquées — « Ok »")
    }
}
