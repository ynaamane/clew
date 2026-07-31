import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class BannerStateTests: XCTestCase {
    func testFailedPhaseProducesErrorBanner() {
        let result = BannerState.bannerState(
            phase: .failed("Capture permission denied"),
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: true
        )

        XCTAssertEqual(result?.message, "Capture permission denied")
        XCTAssertEqual(result?.severity, .error)
        XCTAssertEqual(result?.isDismissible, true)
    }

    func testMutedUnverifiedWithWarningProducesWarningBanner() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: "The call may still hear you",
            muteIndicator: .mutedUnverified,
            isCliAvailable: true
        )

        XCTAssertEqual(result?.message, "The call may still hear you")
        XCTAssertEqual(result?.severity, .warning)
        XCTAssertEqual(result?.isDismissible, false)
    }

    func testIdlePhaseWithNoMuteWarningProducesNoBanner() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: true
        )

        XCTAssertNil(result)
    }

    func testRecordingPhaseWithNoMuteWarningProducesNoBanner() {
        let result = BannerState.bannerState(
            phase: .recording(startedAt: Date()),
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: true
        )

        XCTAssertNil(result)
    }

    func testProcessingPhaseWithNoMuteWarningProducesNoBanner() {
        let result = BannerState.bannerState(
            phase: .processing(step: "transcribing", fraction: 0.5),
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: true
        )

        XCTAssertNil(result)
    }

    func testDonePhaseWithNoMuteWarningProducesNoBanner() {
        let directory = FileManager.default.temporaryDirectory
        let result = BannerState.bannerState(
            phase: .done(directory: directory),
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: true
        )

        XCTAssertNil(result)
    }

    func testMutedVerifiedDoesNotProduceBanner() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: "Some warning",
            muteIndicator: .mutedVerified,
            isCliAvailable: true
        )

        XCTAssertNil(result, "Verified mute should not produce a banner even if warning text exists")
    }

    func testMutedUnverifiedWithoutWarningTextProducesNoBanner() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: nil,
            muteIndicator: .mutedUnverified,
            isCliAvailable: true
        )

        XCTAssertNil(result, "Unverified mute without warning text should not produce a banner")
    }

    func testFailedPhaseTakesPrecedenceOverMuteWarning() {
        let result = BannerState.bannerState(
            phase: .failed("Recording failed"),
            muteWarning: "The call may still hear you",
            muteIndicator: .mutedUnverified,
            isCliAvailable: true
        )

        XCTAssertEqual(result?.message, "Recording failed")
        XCTAssertEqual(result?.severity, .error)
        XCTAssertEqual(result?.isDismissible, true, "Error takes precedence and is dismissible")
    }

    func testCliMissingBannerIsProduced() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: false
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
        XCTAssertEqual(result?.isDismissible, false)
    }

    func testCliMissingHeadlineFitsTheSidebarWidth() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: false
        )

        guard let headline = result?.headline else {
            XCTFail("CLI missing banner should have a headline")
            return
        }

        XCTAssertLessThanOrEqual(
            headline.count, 40,
            "The banner appears in the sidebar (216pt width minus 12pt padding on each side = 192pt available). At .callout size, approximately 5pt per character, 40 characters ≈ 200pt, leaving a small margin for the icon and spacing. The headline must fit without wrapping to avoid overlapping sidebar items beneath it. LibraryWindow.swift:49 sets the column width; InlineBanner.swift:14 renders the headline at .callout."
        )
    }
}
