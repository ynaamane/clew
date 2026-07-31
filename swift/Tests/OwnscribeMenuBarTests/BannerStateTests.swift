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
            "The banner appears in the sidebar (216pt width minus 12pt padding on each side = 192pt available). At .callout size, approximately 5pt per character, 40 characters ≈ 200pt, leaving a small margin for the icon and spacing. The headline must fit without wrapping to avoid overlapping sidebar items beneath it. LibraryWindow.swift:49 sets the column width; InlineBanner renders the headline at .callout."
        )
    }

    func testCliMissingRecoveryInstructionIsReachable() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: nil,
            muteIndicator: .notMuted,
            isCliAvailable: false
        )

        guard let banner = result else {
            XCTFail("CLI missing should produce a banner")
            return
        }

        XCTAssertTrue(
            banner.message.contains("./rec.sh redo"),
            "The recovery instruction './rec.sh redo <répertoire>' must be present in the message field AND InlineBanner.swift:13-32 must render BOTH headline AND message when headline != nil. This test verifies the data exists; the rendering contract is documented here but cannot be tested without instantiating a View (deadlock risk per swift-suite-hygiene.md). Manual verification: when headline is set, InlineBanner shows headline in .callout semibold, then message in .caption secondary below it. Mutation: changing InlineBanner to render only 'headline ?? message' orphans the recovery instruction."
        )

        XCTAssertNotNil(
            banner.headline,
            "This test guards the specific case where a headline is set. If headline is nil, the rendering path changes and this guard is meaningless."
        )
    }

    func testTheBannerViewRendersTheMessageAndNotOnlyTheHeadline() throws {
        let banner = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OwnscribeMenuBar/InlineBanner.swift"),
            encoding: .utf8)

        XCTAssertFalse(
            banner.contains("state.headline ?? state.message"),
            "`Text(state.headline ?? state.message)` renders the headline INSTEAD of the message, so for the CLI banner — the only state that sets a headline — the recovery instruction becomes unreachable data. It shipped exactly that way: the user saw \"CLI absent\" and nothing told them ./rec.sh redo exists. A `??` here silently drops the half of the message that says how to recover.")
        XCTAssertTrue(
            banner.contains("Text(state.message)"),
            "InlineBanner must render state.message on every path. The headline is an addition to it, never a replacement — a user who clicks nothing must still learn how to recover.")
    }
}
