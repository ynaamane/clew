import XCTest
@testable import OwnscribeMenuBar

final class SpeakerAvatarInitialsTests: XCTestCase {
    private let discBudget = 3

    func testNoLabelOverflowsTheDiscItIsDrawnIn() {
        let speakers = ["Owner", "Unknown", "Sam", "Marie_Claire", "Léa_B", "SPEAKER_00", "SPEAKER_10"]

        for speaker in speakers {
            let label = SpeakerAvatarStyle.displayLabel(for: speaker)
            XCTAssertLessThanOrEqual(
                label.count, discBudget,
                "\(speaker) renders as \"\(label)\" (\(label.count) chars) inside an 18pt circle at 9pt bold — measured in a render, \"Unknown\" spilled OUTSIDE the disc in dark mode and clipped to \"kno\" in light mode. The disc fits about \(discBudget) characters. A label is an initial, not a name; the full name is already displayed next to the avatar.")
        }
    }

    func testOwnerAndUnknownBecomeInitialsRatherThanClippedWords() {
        XCTAssertEqual(
            SpeakerAvatarStyle.displayLabel(for: "Owner"), "O",
            "Owner is you. One letter, and the green colour plus the adjacent name carry the rest.")
        XCTAssertEqual(
            SpeakerAvatarStyle.displayLabel(for: "Unknown"), "?",
            "An unidentified speaker is genuinely unknown, so a question mark says that in one glyph, where a clipped \"kno\" says nothing. This is the state EVERY meeting on disk is in, because none has enrolled voices.")
    }

    func testAnEnrolledNameBecomesItsInitials() {
        XCTAssertEqual(SpeakerAvatarStyle.displayLabel(for: "Sam"), "N")
        XCTAssertEqual(
            SpeakerAvatarStyle.displayLabel(for: "Marie_Claire"), "MC",
            "an underscore separates given and family name in an enrolled label, so both initials survive")
        XCTAssertEqual(SpeakerAvatarStyle.displayLabel(for: "Léa_B"), "LB")
    }

    func testDiarizedLabelsKeepTheirTwoDigitNumber() {
        XCTAssertEqual(
            SpeakerAvatarStyle.displayLabel(for: "SPEAKER_00"), "00",
            "the digits ARE the identity for an un-enrolled diarized speaker and they already fit")
        XCTAssertEqual(SpeakerAvatarStyle.displayLabel(for: "SPEAKER_10"), "10")
    }

    func testTwoDifferentSpeakersDoNotCollapseOntoTheSameInitial() {
        let Sam = SpeakerAvatarStyle.displayLabel(for: "Sam")
        let nathalie = SpeakerAvatarStyle.displayLabel(for: "Nathalie")

        XCTAssertEqual(Sam, nathalie, "two names sharing an initial DO share a glyph — that is expected")
        XCTAssertNotEqual(
            SpeakerAvatarStyle.color(for: "Sam"), SpeakerAvatarStyle.color(for: "Nathalie"),
            "which is why the COLOUR has to separate them. An initial alone is not an identity, and the avatar's whole job is telling two speakers apart at a glance.")
    }

    func testAThreePartNameStillFitsTheDisc() {
        let label = SpeakerAvatarStyle.displayLabel(for: "Marie_Claire_Dupont")

        XCTAssertEqual(
            label, "MC",
            "At most TWO initials, whatever the name's part count. This test exists because a mutation widening .prefix(2) to .prefix(4) SURVIVED the budget test above: every name in it has at most two parts, so nothing could observe the change. A three-part name is the only input that distinguishes them, and enrolled labels are user-supplied, so \"Marie_Claire_Dupont\" is a name a colleague can actually have.")
        XCTAssertLessThanOrEqual(label.count, discBudget)
    }

    func testAnEmptyOrPunctuationOnlySpeakerStillRendersSomething() {
        XCTAssertFalse(
            SpeakerAvatarStyle.displayLabel(for: "").isEmpty,
            "an empty disc reads as a rendering failure; a transcript with a malformed speaker header must still draw a glyph")
        XCTAssertFalse(
            SpeakerAvatarStyle.displayLabel(for: "_").isEmpty,
            "splitting on underscores must not produce an empty label from a degenerate name")
    }
}
