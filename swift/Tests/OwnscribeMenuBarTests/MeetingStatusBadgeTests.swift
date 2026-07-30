import Testing
import SwiftUI
@testable import OwnscribeMenuBar

@Suite("MeetingStatusBadge")
struct MeetingStatusBadgeTests {
    @Test("The pill is driven by the three-state anchor model, not by a bare count")
    func testEveryAnchorStateMapsToTheRightPill() {
        func variant(unanchored: Int?) -> MeetingStatusBadge.Variant? {
            let meeting = MeetingSummary(
                directory: URL(fileURLWithPath: "/tmp/2026-07-30_1200_m"),
                hasTranscript: true,
                hasSummary: true,
                actionItemCount: 0,
                unanchoredClaimCount: unanchored
            )
            return MeetingStatusBadge.Variant(
                anchorState: UnanchoredClaimBadge.state(unanchoredClaimCount: meeting.unanchoredClaimCount))
        }

        #expect(
            variant(unanchored: nil) == .neverChecked,
            "every meeting on the real disk is unchecked; dropping this pill makes the whole library look verified")
        #expect(
            variant(unanchored: 0) == nil,
            "a meeting whose claims all have evidence is the quiet case and carries no pill")
        #expect(variant(unanchored: 2) == .unanchored(count: 2))
    }

    @Test("An unchecked meeting is grey, not amber")
    func testNeverCheckedIsNotAlarming() {
        #expect(MeetingStatusBadge.Variant.neverChecked.text == "non vérifiée")
        #expect(
            MeetingStatusBadge.Variant.neverChecked.foregroundColor == Color.secondary,
            "unknown is not the same as bad; amber here would cry wolf on every meeting")
    }

    @Test("Amber pill for unanchored claims")
    func testUnanchoredBadge() {
        let badge = MeetingStatusBadge.Variant.unanchored(count: 3)

        #expect(badge.text == "3 non ancrés")
        #expect(badge.foregroundColor == Color.orange)
    }

    @Test("Green pill for action items")
    func testActionItemsBadge() {
        let badge = MeetingStatusBadge.Variant.actionItems(count: 5)

        #expect(badge.text == "5 actions")
        #expect(badge.foregroundColor == Color.green)
    }

    @Test("Grey pill for muted track")
    func testMutedTrackBadge() {
        let badge = MeetingStatusBadge.Variant.mutedTrack

        #expect(badge.text == "piste système muette")
        #expect(badge.foregroundColor == Color.secondary)
    }

    @Test("Plural inflection for unanchored")
    func testUnanchoredSingularPlural() {
        let singular = MeetingStatusBadge.Variant.unanchored(count: 1)
        let plural = MeetingStatusBadge.Variant.unanchored(count: 2)

        #expect(singular.text == "1 non ancré")
        #expect(plural.text == "2 non ancrés")
    }

    @Test("Plural inflection for action items")
    func testActionItemsSingularPlural() {
        let singular = MeetingStatusBadge.Variant.actionItems(count: 1)
        let plural = MeetingStatusBadge.Variant.actionItems(count: 2)

        #expect(singular.text == "1 action")
        #expect(plural.text == "2 actions")
    }
}
