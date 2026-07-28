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
}
