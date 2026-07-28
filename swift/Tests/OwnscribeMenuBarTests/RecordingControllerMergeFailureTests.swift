import XCTest
@testable import OwnscribeCapture
@testable import OwnscribeMenuBar

@MainActor
final class RecordingControllerMergeFailureTests: XCTestCase {
    func testStateReturnsToIdleAfterMergeFailureSoSubsequentStartIsNotBricked() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OWNSCRIBE_TEST_REAL_MIC"] == "1",
            "Opens the real input device: the merge path only runs with a live MicCapture, and AVAudioEngine claims the device at init. On AirPods that forces the HFP profile — 24 kHz mic and degraded playback for every app until it renegotiates. Run with OWNSCRIBE_TEST_REAL_MIC=1 on built-in hardware.")

        let controller = RecordingController()
        controller.mergeAudioFilesImpl = { _, _, _, _, _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated merge failure"])
        }
        controller.enableMic = true
        controller.makeSystemCapture = { _ in SilentFakeCapture() }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputPath = tempDir.appendingPathComponent("recording.wav").path
        try await controller.start(outputPath: outputPath)

        XCTAssertEqual(controller.state, .recording(startedAt: controller.state.startedAt ?? Date()))

        do {
            _ = try controller.stop()
            XCTFail("stop() should have thrown due to merge failure")
        } catch {
        }

        XCTAssertEqual(
            controller.state,
            .idle,
            "After a merge failure, state must return to .idle so the next start() can proceed instead of silently no-op'ing while AppState believes recording started, causing total data loss.")

        let secondOutputPath = tempDir.appendingPathComponent("recording2.wav").path
        do {
            try await controller.start(outputPath: secondOutputPath)
            XCTAssertEqual(controller.state, .recording(startedAt: controller.state.startedAt ?? Date()), "Second start() must succeed after a merge failure, not silently no-op")
        } catch {
            XCTFail("Second start() after merge failure recovery should succeed, got error: \(error)")
        }
    }

    func testSecondStartThrowsInsteadOfSilentNoOp() async throws {
        let controller = RecordingController()
        controller.enableMic = false
        controller.makeSystemCapture = { _ in SilentFakeCapture() }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstPath = tempDir.appendingPathComponent("recording1.wav").path
        try await controller.start(outputPath: firstPath)

        let secondPath = tempDir.appendingPathComponent("recording2.wav").path
        do {
            try await controller.start(outputPath: secondPath)
            XCTFail("Second start() without stop() must throw .alreadyRecording, not silently no-op while AppState sets phase=.recording")
        } catch RecordingController.RecordingError.alreadyRecording {

        } catch {
            XCTFail("Expected .alreadyRecording, got \(error)")
        }
    }
}

extension RecordingControllerMergeFailureTests {
    func testStateReturnsToIdleAfterAnyStopFailureWithoutTouchingTheMic() async throws {
        let controller = RecordingController()
        controller.enableMic = false
        controller.makeSystemCapture = { _ in ThrowingStopFakeCapture() }
        controller.makeMicCapture = { nil }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await controller.start(outputPath: tempDir.appendingPathComponent("recording.wav").path)
        _ = try? controller.stop()

        XCTAssertEqual(
            controller.state, .idle,
            "state must return to .idle after a failing stop, or the record button is bricked until relaunch while AppState believes recording started — total data loss for the next meeting")

        do {
            try await controller.start(outputPath: tempDir.appendingPathComponent("recording2.wav").path)
        } catch {
            XCTFail("the next start() must succeed after a stop failure, got \(error)")
        }
        XCTAssertTrue(controller.isRecording)
    }
}

private final class ThrowingStopFakeCapture: SystemAudioCapturing {
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var micCapture: MicCapture?
    var startHostTime: UInt64 = 0

    func start() async throws { startHostTime = mach_absolute_time() }
    func stop() {}
}

private final class SilentFakeCapture: SystemAudioCapturing {
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var micCapture: MicCapture?
    var startHostTime: UInt64 = 0

    func start() async throws { startHostTime = mach_absolute_time() }
    func stop() {}
}

private extension RecordingController.State {
    var startedAt: Date? {
        if case .recording(let startedAt) = self {
            return startedAt
        }
        return nil
    }
}
