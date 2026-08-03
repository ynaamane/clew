import XCTest
@testable import OwnscribeMenuBar

final class LibraryNavigationSubtitleTests: XCTestCase {
    func testComposesCountAndAggregateDurationLikeTheMockup() {
        // mockup.html:244 — "42 réunions · 18 h 12 min". 18h12min = 65520s = 36000 + 29520.
        let text = LibraryNavigationSubtitle.text(meetingCount: 8, knownDurations: [36000, 29520])

        XCTAssertEqual(text, "8 réunions · 18 h 12 min")
    }

    func testSingularMeetingCountDropsThePluralS() {
        let text = LibraryNavigationSubtitle.text(meetingCount: 1, knownDurations: [])

        XCTAssertEqual(text, "1 réunion")
    }

    func testCountAloneWhenNoDurationIsKnown() {
        let text = LibraryNavigationSubtitle.text(meetingCount: 5, knownDurations: [])

        XCTAssertEqual(text, "5 réunions", "an empty library, or one where nothing has been transcribed yet, must not claim a duration it doesn't know")
    }

    func testUnderAnHourOmitsTheHoursComponent() {
        let text = LibraryNavigationSubtitle.text(meetingCount: 2, knownDurations: [90, 30])

        XCTAssertEqual(text, "2 réunions · 2 min")
    }

    func testCountIsIndependentOfHowManyDurationsAreKnown() {
        // meetingCount always reflects the whole library; only the duration figure narrows to
        // what's known. A 10-meeting library with just one dated recording still says "10
        // réunions", not "1 réunion".
        let text = LibraryNavigationSubtitle.text(meetingCount: 10, knownDurations: [600])

        XCTAssertTrue(text.hasPrefix("10 réunions"), "expected the full library count, got: \(text)")
        XCTAssertTrue(text.hasSuffix("10 min"), "expected only the one known duration to be summed, got: \(text)")
    }
}
