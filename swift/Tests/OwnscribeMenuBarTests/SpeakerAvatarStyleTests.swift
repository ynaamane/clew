import Testing
import SwiftUI
@testable import OwnscribeMenuBar

@Suite struct SpeakerAvatarStyleTests {
    @Test func ownerGetsGreen() {
        #expect(SpeakerAvatarStyle.color(for: "Owner") == .green)
    }

    @Test func unknownGetsSecondary() {
        #expect(SpeakerAvatarStyle.color(for: "Unknown") == .secondary)
    }

    @Test func speaker00GetsBlue() {
        #expect(SpeakerAvatarStyle.color(for: "SPEAKER_00") == .blue)
    }

    @Test func speaker01GetsPurple() {
        #expect(SpeakerAvatarStyle.color(for: "SPEAKER_01") == .purple)
    }

    @Test func speakerEndingIn0GetsBlue() {
        #expect(SpeakerAvatarStyle.color(for: "SPEAKER_10") == .blue)
    }

    @Test func displayLabelExtractsSuffix() {
        #expect(SpeakerAvatarStyle.displayLabel(for: "SPEAKER_01") == "01")
        #expect(SpeakerAvatarStyle.displayLabel(for: "SPEAKER_00") == "00")
        #expect(SpeakerAvatarStyle.displayLabel(for: "SPEAKER_10") == "10")
    }

    @Test func displayLabelPreservesSpecialNames() {
        #expect(SpeakerAvatarStyle.displayLabel(for: "Owner") == "Owner")
        #expect(SpeakerAvatarStyle.displayLabel(for: "Unknown") == "Unknown")
    }

    @Test func displayLabelPreservesEnrolledNames() {
        #expect(SpeakerAvatarStyle.displayLabel(for: "Léa_B") == "Léa_B")
        #expect(SpeakerAvatarStyle.displayLabel(for: "Marc_B") == "Marc_B")
        #expect(SpeakerAvatarStyle.displayLabel(for: "Marie_Claire") == "Marie_Claire")
        #expect(SpeakerAvatarStyle.displayLabel(for: "Sam") == "Sam")
    }

    @Test func colorDistinguishesSPEAKERPattern() {
        let s00 = SpeakerAvatarStyle.color(for: "SPEAKER_00")
        let s01 = SpeakerAvatarStyle.color(for: "SPEAKER_01")
        #expect(s00 != s01, "SPEAKER_00 and SPEAKER_01 must have different colors")
    }

    @Test func enrolledNamesGetConsistentColors() {
        let nicolas1 = SpeakerAvatarStyle.color(for: "Sam")
        let nicolas2 = SpeakerAvatarStyle.color(for: "Sam")
        #expect(nicolas1 == nicolas2, "Same name must get same color")

        let Idris = SpeakerAvatarStyle.color(for: "Idris")
        #expect(Idris == SpeakerAvatarStyle.color(for: "Idris"), "Same name must get same color")

        let lea = SpeakerAvatarStyle.color(for: "Léa_B")
        #expect(lea == SpeakerAvatarStyle.color(for: "Léa_B"), "Same name must get same color")
    }

    @Test func enrolledNamesDoNotCollapseToOnePurple() {
        let Sam = SpeakerAvatarStyle.color(for: "Sam")
        let Idris = SpeakerAvatarStyle.color(for: "Idris")
        let marc = SpeakerAvatarStyle.color(for: "Marc_B")

        let speaker01Purple = Color.purple

        let allPurple = (Sam == speaker01Purple && Idris == speaker01Purple && marc == speaker01Purple)
        #expect(!allPurple, "F9: Enrolled names must not all collapse to purple (the old behavior)")
    }

    @Test func deterministicColorMapping() {
        #expect(SpeakerAvatarStyle.color(for: "Sam") == .purple)
        #expect(SpeakerAvatarStyle.color(for: "Idris") == .pink)
        #expect(SpeakerAvatarStyle.color(for: "Léa_B") == .indigo)
        #expect(SpeakerAvatarStyle.color(for: "Marc_B") == .cyan)
    }

    @Test func enrolledNamesGetDistinctColors() {
        let Sam = SpeakerAvatarStyle.color(for: "Sam")
        let Idris = SpeakerAvatarStyle.color(for: "Idris")
        let lea = SpeakerAvatarStyle.color(for: "Léa_B")

        #expect(Sam != Idris, "Sam and Idris must have different colors")
        #expect(Sam != lea, "Sam and Léa_B must have different colors")
        #expect(Idris != lea, "Idris and Léa_B must have different colors")
    }
}
