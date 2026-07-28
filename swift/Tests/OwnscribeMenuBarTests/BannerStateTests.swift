import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class BannerStateTests: XCTestCase {
    func testFailedPhaseProducesErrorBanner() {
        let result = BannerState.bannerState(
            phase: .failed("Capture permission denied"),
            muteWarning: nil,
            muteIndicator: .notMuted
        )

        XCTAssertEqual(result?.message, "Capture permission denied")
        XCTAssertEqual(result?.severity, .error)
        XCTAssertEqual(result?.isDismissible, true)
    }

    func testMutedUnverifiedWithWarningProducesWarningBanner() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: "The call may still hear you",
            muteIndicator: .mutedUnverified
        )

        XCTAssertEqual(result?.message, "The call may still hear you")
        XCTAssertEqual(result?.severity, .warning)
        XCTAssertEqual(result?.isDismissible, false)
    }

    func testIdlePhaseWithNoMuteWarningProducesNoBanner() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: nil,
            muteIndicator: .notMuted
        )

        XCTAssertNil(result)
    }

    func testRecordingPhaseWithNoMuteWarningProducesNoBanner() {
        let result = BannerState.bannerState(
            phase: .recording(startedAt: Date()),
            muteWarning: nil,
            muteIndicator: .notMuted
        )

        XCTAssertNil(result)
    }

    func testProcessingPhaseWithNoMuteWarningProducesNoBanner() {
        let result = BannerState.bannerState(
            phase: .processing(step: "transcribing", fraction: 0.5),
            muteWarning: nil,
            muteIndicator: .notMuted
        )

        XCTAssertNil(result)
    }

    func testDonePhaseWithNoMuteWarningProducesNoBanner() {
        let directory = FileManager.default.temporaryDirectory
        let result = BannerState.bannerState(
            phase: .done(directory: directory),
            muteWarning: nil,
            muteIndicator: .notMuted
        )

        XCTAssertNil(result)
    }

    func testMutedVerifiedDoesNotProduceBanner() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: "Some warning",
            muteIndicator: .mutedVerified
        )

        XCTAssertNil(result, "Verified mute should not produce a banner even if warning text exists")
    }

    func testMutedUnverifiedWithoutWarningTextProducesNoBanner() {
        let result = BannerState.bannerState(
            phase: .idle,
            muteWarning: nil,
            muteIndicator: .mutedUnverified
        )

        XCTAssertNil(result, "Unverified mute without warning text should not produce a banner")
    }

    func testFailedPhaseTakesPrecedenceOverMuteWarning() {
        let result = BannerState.bannerState(
            phase: .failed("Recording failed"),
            muteWarning: "The call may still hear you",
            muteIndicator: .mutedUnverified
        )

        XCTAssertEqual(result?.message, "Recording failed")
        XCTAssertEqual(result?.severity, .error)
        XCTAssertEqual(result?.isDismissible, true, "Error takes precedence and is dismissible")
    }
}
