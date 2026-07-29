import XCTest
@testable import OwnscribeCapture
@testable import OwnscribeMenuBar

@MainActor
final class InjectedCaptureSkipsHardwareTests: XCTestCase {
    func testAnInjectedCaptureIsConsultedBeforeAnySystemPermissionCall() async throws {
        let controller = RecordingController()
        let fake = HardwareFreeFakeCapture()
        var permissionProbes = 0

        controller.makeSystemCapture = { _ in fake }
        controller.systemPermissionCheck = { _ in
            permissionProbes += 1
            return false
        }
        controller.enableMic = false

        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("injected-\(UUID().uuidString).wav").path

        try await controller.start(outputPath: outputPath)

        XCTAssertEqual(
            permissionProbes, 0,
            "A test that injects a fake capture must never reach the real permission check: that call creates a CoreAudio tap, coreaudiod refuses it, and the churn renegotiates AirPods into the 24 kHz HFP profile — the suite degraded the user's audio")
        XCTAssertTrue(fake.didStart, "The injected fake must be the thing that gets started")

        _ = try? controller.stop()
    }

    func testTheGateStillFiresWhenNoFakeIsInjected() async {
        let controller = RecordingController()
        var probes = 0
        controller.systemPermissionCheck = { _ in
            probes += 1
            return false
        }
        controller.enableMic = false

        let outputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("denied-\(UUID().uuidString).wav").path

        do {
            try await controller.start(outputPath: outputPath)
            XCTFail("Recording must not start when system audio permission is denied")
        } catch RecordingController.RecordingError.permissionDenied {

        } catch {
            XCTFail("Moving the gate must not weaken production: with no fake injected it still has to refuse with .permissionDenied; got \(error)")
        }

        XCTAssertEqual(probes, 1, "The real path must consult the permission gate exactly once")
    }
}

private final class HardwareFreeFakeCapture: SystemAudioCapturing {
    var silenceTimeout: TimeInterval = 0
    var onSilenceTimeout: (() -> Void)?
    var micCapture: MicCapture?
    var startHostTime: UInt64 = 0
    var didStart = false

    func start() async throws {
        didStart = true
        startHostTime = mach_absolute_time()
    }

    func stop() {}
}

final class PermissionErrorNamesTheMissingOneTests: XCTestCase {
    @MainActor
    private func controllerDenying(_ missing: RecordingController.RecordingError?) -> RecordingController {
        let controller = RecordingController()
        controller.systemPermissionCheck = { _ in false }
        controller.missingPermission = { missing }
        return controller
    }

    @MainActor
    func testSystemAudioDenialNamesSystemAudioAndTellsTheUserWhereToGo() async {
        let controller = controllerDenying(.systemAudioPermissionDenied)
        do {
            try await controller.start(outputPath: "/tmp/never-written-\(UUID().uuidString).wav")
            XCTFail("a denied permission must not start a recording")
        } catch let error as RecordingController.RecordingError {
            XCTAssertEqual(error, .systemAudioPermissionDenied)
            XCTAssertTrue(
                error.description.contains("System Settings"),
                "the message must say where to fix it; the old text named neither permission nor a "
                    + "destination, and the preflight's detail goes to stderr, which a Finder-launched "
                    + "app has nowhere to show")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testMicDenialSaysTheCallIsStillRecordedWithoutYourVoice() async {
        let controller = controllerDenying(.microphonePermissionDenied)
        do {
            try await controller.start(outputPath: "/tmp/never-written-\(UUID().uuidString).wav")
            XCTFail("a denied permission must not start a recording")
        } catch let error as RecordingController.RecordingError {
            XCTAssertEqual(error, .microphonePermissionDenied)
            XCTAssertTrue(error.description.contains("Microphone"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    @MainActor
    func testAnUnattributableDenialStillFailsClosed() async {
        let controller = controllerDenying(nil)
        do {
            try await controller.start(outputPath: "/tmp/never-written-\(UUID().uuidString).wav")
            XCTFail("must not start")
        } catch let error as RecordingController.RecordingError {
            XCTAssertEqual(error, .permissionDenied, "no attribution must never become a pass")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
