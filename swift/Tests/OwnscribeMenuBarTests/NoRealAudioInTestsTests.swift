import XCTest
@testable import OwnscribeCapture
@testable import OwnscribeMenuBar

@MainActor
final class NoRealAudioInTestsTests: XCTestCase {
    func testStartAsksTheSeamBeforeConstructingAnyMicCapture() async throws {
        let controller = RecordingController()
        controller.enableMic = true
        controller.makeSystemCapture = { _ in CountingFakeCapture() }

        var seamConsulted = 0
        controller.makeMicCapture = { seamConsulted += 1; return nil }

        try await startAndStop(controller)

        XCTAssertEqual(
            seamConsulted, 1,
            "start() must obtain its MicCapture through makeMicCapture. Constructing MicCapture directly reserves the real default input device — AVAudioEngine is a stored property, so the device is claimed at init, before start() is ever called. On AirPods that forces the HFP profile: the mic drops to 24 kHz and playback degrades for every app on the machine until the profile renegotiates.")
    }

    func testMicCaptureIsNotRequestedWhenMicIsDisabled() async throws {
        let controller = RecordingController()
        controller.enableMic = false
        controller.makeSystemCapture = { _ in CountingFakeCapture() }

        var seamConsulted = 0
        controller.makeMicCapture = { seamConsulted += 1; return nil }

        try await startAndStop(controller)

        XCTAssertEqual(
            seamConsulted, 0,
            "With the mic disabled, nothing may touch the input device at all — not even to construct the object.")
    }

    func testTheDefaultSeamIsTheOneProductionUses() {
        let controller = RecordingController()

        XCTAssertNotNil(
            controller.makeMicCapture(),
            "The production default must really build a MicCapture; a seam that returns nil by default would silently drop the owner's voice from every recording, which is BUG4 all over again.")
    }

    private func startAndStop(_ controller: RecordingController) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("noaudio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try await controller.start(outputPath: tempDir.appendingPathComponent("recording.wav").path)
        _ = try? controller.stop()
    }
}

private final class CountingFakeCapture: SystemAudioCapturing {
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var micCapture: MicCapture?
    var startHostTime: UInt64 = 0

    func start() async throws { startHostTime = mach_absolute_time() }
    func stop() {}
}
