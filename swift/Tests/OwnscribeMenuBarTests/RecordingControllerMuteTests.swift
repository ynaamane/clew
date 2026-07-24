import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class RecordingControllerMuteTests: XCTestCase {
    func testSetLocalMuteWhenNotRecordingIsANoOpAndReportsFalse() {
        let controller = RecordingController()

        let result = controller.setLocalMicMute(true)

        XCTAssertFalse(result)
        XCTAssertFalse(controller.isLocalMicMuted)
    }
}
