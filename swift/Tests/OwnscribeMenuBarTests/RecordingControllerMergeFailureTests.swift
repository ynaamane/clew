import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class RecordingControllerMergeFailureTests: XCTestCase {
    func testStateReturnsToIdleAfterMergeFailureSoSubsequentStartIsNotBricked() async throws {
        let controller = RecordingController()
        controller.mergeAudioFilesImpl = { _, _, _, _, _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Simulated merge failure"])
        }
        controller.enableMic = true

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
}

private extension RecordingController.State {
    var startedAt: Date? {
        if case .recording(let startedAt) = self {
            return startedAt
        }
        return nil
    }
}
