import Testing
import SwiftUI
@testable import OwnscribeMenuBar

@Suite("MeetingStatusBadge")
struct MeetingStatusBadgeTests {
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
