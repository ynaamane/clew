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

    @Test func speaker10DoesNotShareSpeaker00sColor() {
        let s00 = SpeakerAvatarStyle.color(for: "SPEAKER_00")
        let s10 = SpeakerAvatarStyle.color(for: "SPEAKER_10")
        #expect(s00 != s10, "two speakers sharing an avatar reads as one person")
    }

    @Test func sevenConcurrentSpeakersAllGetDistinctColors() {
        let speakers = (0..<7).map { String(format: "SPEAKER_%02d", $0) }
        let colors = speakers.map { SpeakerAvatarStyle.color(for: $0) }
        #expect(Set(colors).count == 7, "collapsed to \(Set(colors).count) colors for 7 speakers")
    }

    @Test func theEighthSpeakerWrapsOntoTheFirstColor() {
        #expect(SpeakerAvatarStyle.color(for: "SPEAKER_07") == SpeakerAvatarStyle.color(for: "SPEAKER_00"))
    }

    @Test func aNegativeIndexReachesTheHashBranchInsteadOfSubscriptingOutOfRange() {
        #expect(SpeakerAvatarStyle.color(for: "SPEAKER_-1") == .indigo)
    }

    @Test func aMalformedIndexReachesTheHashBranch() {
        #expect(SpeakerAvatarStyle.color(for: "SPEAKER_ab") == .orange)
        #expect(SpeakerAvatarStyle.color(for: "SPEAKER_1_2") == .cyan)
    }

    @Test func displayLabelExtractsSuffix() {
        #expect(SpeakerAvatarStyle.displayLabel(for: "SPEAKER_01") == "01")
        #expect(SpeakerAvatarStyle.displayLabel(for: "SPEAKER_00") == "00")
        #expect(SpeakerAvatarStyle.displayLabel(for: "SPEAKER_10") == "10")
    }

    @Test func displayLabelAbbreviatesSpecialNames() {
        #expect(SpeakerAvatarStyle.displayLabel(for: "Owner") == "O")
        #expect(SpeakerAvatarStyle.displayLabel(for: "Unknown") == "?")
    }

    @Test func displayLabelAbbreviatesEnrolledNames() {
        #expect(SpeakerAvatarStyle.displayLabel(for: "Léa_B") == "LB")
        #expect(SpeakerAvatarStyle.displayLabel(for: "Marc_B") == "MB")
        #expect(SpeakerAvatarStyle.displayLabel(for: "Marie_Claire") == "MC")
        #expect(SpeakerAvatarStyle.displayLabel(for: "Sam") == "S")
    }

    @Test func colorDistinguishesSPEAKERPattern() {
        let s00 = SpeakerAvatarStyle.color(for: "SPEAKER_00")
        let s01 = SpeakerAvatarStyle.color(for: "SPEAKER_01")
        #expect(s00 != s01, "SPEAKER_00 and SPEAKER_01 must have different colors")
    }

    @Test func enrolledNamesGetConsistentColors() {
        let sam1 = SpeakerAvatarStyle.color(for: "Sam")
        let sam2 = SpeakerAvatarStyle.color(for: "Sam")
        #expect(sam1 == sam2, "Same name must get same color")

        let idris = SpeakerAvatarStyle.color(for: "Idris")
        #expect(idris == SpeakerAvatarStyle.color(for: "Idris"), "Same name must get same color")

        let lea = SpeakerAvatarStyle.color(for: "Léa_B")
        #expect(lea == SpeakerAvatarStyle.color(for: "Léa_B"), "Same name must get same color")
    }

    @Test func enrolledNamesDoNotCollapseToOnePurple() {
        let sam = SpeakerAvatarStyle.color(for: "Sam")
        let idris = SpeakerAvatarStyle.color(for: "Idris")
        let marc = SpeakerAvatarStyle.color(for: "Marc_B")

        let speaker01Purple = Color.purple

        let allPurple = (sam == speaker01Purple && idris == speaker01Purple && marc == speaker01Purple)
        #expect(!allPurple, "F9: Enrolled names must not all collapse to purple (the old behavior)")
    }

    @Test func deterministicColorMapping() {
        #expect(SpeakerAvatarStyle.color(for: "Sam") == .teal)
        #expect(SpeakerAvatarStyle.color(for: "Idris") == .teal)
        #expect(SpeakerAvatarStyle.color(for: "Léa_B") == .indigo)
        #expect(SpeakerAvatarStyle.color(for: "Marc_B") == .cyan)
    }

    @Test func enrolledNamesGetDistinctColors() {
        let sam = SpeakerAvatarStyle.color(for: "Sam")
        let lea = SpeakerAvatarStyle.color(for: "Léa_B")
        let marc = SpeakerAvatarStyle.color(for: "Marc_B")

        #expect(sam != lea, "Sam and Léa_B must have different colors")
        #expect(sam != marc, "Sam and Marc_B must have different colors")
        #expect(lea != marc, "Léa_B and Marc_B must have different colors")
    }

    @Test func twoEnrolledNamesCanShareAColourAndTheInitialIsWhatSeparatesThem() {
        // FNV-1a modulo a 7-colour palette cannot promise distinct colours for
        // arbitrary names, and "Sam" and "Idris" are a real collision (both teal,
        // pinned above). The pair is kept here on purpose: the previous version of
        // this suite asserted pairwise distinctness on the two sample names it
        // happened to hold, which read as a guarantee the palette does not make.
        // What actually separates them at a glance is the initial.
        #expect(SpeakerAvatarStyle.color(for: "Sam") == SpeakerAvatarStyle.color(for: "Idris"))
        #expect(SpeakerAvatarStyle.displayLabel(for: "Sam")
                != SpeakerAvatarStyle.displayLabel(for: "Idris"))
    }
}
