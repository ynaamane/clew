import XCTest
@testable import OwnscribeCapture

@available(macOS 14.2, *)
final class CoreAudioTapCaptureStopTests: XCTestCase {
    func testStopSummaryWithKnownRateReportsDuration() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).wav").path

        let capture = CoreAudioTapCapture(outputPath: tempPath)
        let summary = capture.stopSummary(totalFrames: 48000, rate: 48000.0, peak: 0.5)

        XCTAssertTrue(summary.contains("1.0 seconds"), "With known rate, summary must report duration in seconds")
        XCTAssertFalse(summary.contains("rate unknown"), "With known rate, summary must not say rate unknown")
    }

    func testStopSummaryWithUnknownRateReportsFramesOnly() {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).wav").path

        let capture = CoreAudioTapCapture(outputPath: tempPath)
        let summary = capture.stopSummary(totalFrames: 48000, rate: nil, peak: 0.5)

        XCTAssertTrue(summary.contains("48000 frames"), "With unknown rate, summary must report frame count")
        XCTAssertTrue(summary.contains("rate unknown"), "With unknown rate, summary must say rate unknown")
        XCTAssertFalse(summary.contains("seconds"), "With unknown rate, summary must not fabricate a duration")
    }
}
