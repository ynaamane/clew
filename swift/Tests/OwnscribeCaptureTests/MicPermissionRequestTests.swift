import AVFoundation
import XCTest
@testable import OwnscribeCapture

final class MicPermissionRequestTests: XCTestCase {
    func testNotDeterminedIsNotTreatedAsAuthorized() {
        XCTAssertFalse(
            microphoneAccessIsAuthorized(status: .notDetermined),
            "a status nobody has answered yet is not a grant")
        XCTAssertFalse(microphoneAccessIsAuthorized(status: .denied))
        XCTAssertFalse(microphoneAccessIsAuthorized(status: .restricted))
        XCTAssertTrue(microphoneAccessIsAuthorized(status: .authorized))
    }

    func testAnUnansweredMicStatusMustBeREQUESTEDRatherThanFailed() {
        XCTAssertTrue(
            microphoneAccessNeedsPrompting(status: .notDetermined),
            "the very first launch has no answer yet; failing here means the record button can NEVER "
                + "work, because nothing else in the app ever asks for the microphone")
    }

    func testADeniedMicIsNotPromptedAgain() {
        XCTAssertFalse(
            microphoneAccessNeedsPrompting(status: .denied),
            "macOS shows the system prompt once; re-requesting a denied status returns immediately "
                + "and the user must be sent to System Settings instead")
        XCTAssertFalse(microphoneAccessNeedsPrompting(status: .restricted))
        XCTAssertFalse(microphoneAccessNeedsPrompting(status: .authorized))
    }

    func testPreflightPassesWhenTheMicIsAuthorizedAndSystemAudioIsGranted() {
        XCTAssertTrue(
            runCapturePermissionPreflight(
                needsMic: true, hasScreenCaptureAccess: true, hasMicrophoneAccess: true))
    }

    func testPreflightStillFailsClosedOnAGenuineDenial() {
        XCTAssertFalse(
            runCapturePermissionPreflight(
                needsMic: true, hasScreenCaptureAccess: true, hasMicrophoneAccess: false),
            "a real denial must still block: the fix is to ASK when unanswered, not to assume yes")
        XCTAssertFalse(
            runCapturePermissionPreflight(
                needsMic: false, hasScreenCaptureAccess: false, hasMicrophoneAccess: true),
            "system audio is required even when the mic is off")
    }
}
