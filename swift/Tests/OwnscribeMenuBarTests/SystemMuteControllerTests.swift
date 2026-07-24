import XCTest
@testable import OwnscribeMenuBar

private final class FakeAudioMuteDevice: AudioMuteDevice {
    var setInputMuteCalls: [Bool] = []
    var setShouldSucceed = true
    var readBackValue: Bool?
    var bluetoothDevice = false
    var nominalSampleRateSequence: [Double?] = []
    private var sampleRateCallCount = 0

    func isBluetooth() -> Bool { bluetoothDevice }

    func setInputMute(_ muted: Bool) -> Bool {
        setInputMuteCalls.append(muted)
        return setShouldSucceed
    }

    func readInputMute() -> Bool? { readBackValue }

    func nominalSampleRate() -> Double? {
        defer { sampleRateCallCount += 1 }
        guard sampleRateCallCount < nominalSampleRateSequence.count else {
            return nominalSampleRateSequence.last ?? nil
        }
        return nominalSampleRateSequence[sampleRateCallCount]
    }
}

final class SystemMuteControllerTests: XCTestCase {
    func testSetSucceedsAndReadBackConfirmsMuted() {
        let device = FakeAudioMuteDevice()
        device.setShouldSucceed = true
        device.readBackValue = true

        let result = setSystemMuteVerified(true, device: device)

        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.verifiedMuted)
        XCTAssertEqual(device.setInputMuteCalls, [true])
    }

    func testSetSucceedsAndReadBackConfirmsUnmuted() {
        let device = FakeAudioMuteDevice()
        device.setShouldSucceed = true
        device.readBackValue = false

        let result = setSystemMuteVerified(false, device: device)

        XCTAssertTrue(result.succeeded)
        XCTAssertFalse(result.verifiedMuted)
    }

    func testSetCallReturnsFailureIsReportedAsNotSucceeded() {
        let device = FakeAudioMuteDevice()
        device.setShouldSucceed = false
        device.readBackValue = false

        let result = setSystemMuteVerified(true, device: device)

        XCTAssertFalse(result.succeeded)
    }

    func testSetReturnsSuccessButReadBackDisagreesWithRequestedStateIsReportedAsNotSucceeded() {
        let device = FakeAudioMuteDevice()
        device.setShouldSucceed = true
        device.readBackValue = false

        let result = setSystemMuteVerified(true, device: device)

        XCTAssertFalse(result.succeeded)
    }

    func testUnreadableMuteStateIsReportedAsNotSucceeded() {
        let device = FakeAudioMuteDevice()
        device.setShouldSucceed = true
        device.readBackValue = nil

        let result = setSystemMuteVerified(true, device: device)

        XCTAssertFalse(result.succeeded)
    }

    func testUnreadableMuteStateReportsVerifiedAsNotMuted() {
        let device = FakeAudioMuteDevice()
        device.setShouldSucceed = true
        device.readBackValue = nil

        let result = setSystemMuteVerified(true, device: device)

        XCTAssertFalse(result.verifiedMuted)
    }

    func testBluetoothFlagIsSurfacedRegardlessOfOutcome() {
        let device = FakeAudioMuteDevice()
        device.bluetoothDevice = true
        device.setShouldSucceed = true
        device.readBackValue = true

        let result = setSystemMuteVerified(true, device: device)

        XCTAssertTrue(result.isBluetoothDevice)
    }

    func testRequestedMutedReflectsWhatWasAsked() {
        let device = FakeAudioMuteDevice()
        device.readBackValue = true

        let result = setSystemMuteVerified(true, device: device)

        XCTAssertTrue(result.requestedMuted)
    }
}

final class MasterMuteOrchestrationTests: XCTestCase {
    private func noSettle(_: AudioMuteDevice) {}

    func testSystemWideSuccessNeedsNoFallbackAndShowsMuted() {
        let device = FakeAudioMuteDevice()
        device.setShouldSucceed = true
        device.readBackValue = true
        var localFallbackCalls: [Bool] = []

        let outcome = applyMasterMute(true, device: device, settle: noSettle) { muted in
            localFallbackCalls.append(muted)
        }

        XCTAssertEqual(outcome.displayMuted, true)
        XCTAssertFalse(outcome.usedLocalFallback)
        XCTAssertNil(outcome.warning)
        XCTAssertTrue(localFallbackCalls.isEmpty)
    }

    func testSystemWideFailureFallsBackToLocalAndWarns() {
        let device = FakeAudioMuteDevice()
        device.bluetoothDevice = true
        device.setShouldSucceed = true
        device.readBackValue = false
        var localFallbackCalls: [Bool] = []

        let outcome = applyMasterMute(true, device: device, settle: noSettle) { muted in
            localFallbackCalls.append(muted)
        }

        XCTAssertTrue(outcome.usedLocalFallback)
        XCTAssertEqual(localFallbackCalls, [true])
        XCTAssertNotNil(outcome.warning)
    }

    func testFallbackDisplayIsMutedEvenThoughSystemWideFailed() {
        let device = FakeAudioMuteDevice()
        device.setShouldSucceed = false
        device.readBackValue = false

        let outcome = applyMasterMute(true, device: device, settle: noSettle) { _ in }

        XCTAssertEqual(outcome.displayMuted, true)
    }

    func testUnmuteRestoresSystemWideWithoutFallback() {
        let device = FakeAudioMuteDevice()
        device.setShouldSucceed = true
        device.readBackValue = false
        var localFallbackCalls: [Bool] = []

        let outcome = applyMasterMute(false, device: device, settle: noSettle) { muted in
            localFallbackCalls.append(muted)
        }

        XCTAssertEqual(outcome.displayMuted, false)
        XCTAssertFalse(outcome.usedLocalFallback)
        XCTAssertTrue(localFallbackCalls.isEmpty)
    }

    func testUnmuteFailureStillTriggersLocalFallbackUnmute() {
        let device = FakeAudioMuteDevice()
        device.setShouldSucceed = false
        device.readBackValue = true
        var localFallbackCalls: [Bool] = []

        let outcome = applyMasterMute(false, device: device, settle: noSettle) { muted in
            localFallbackCalls.append(muted)
        }

        XCTAssertEqual(localFallbackCalls, [false])
        XCTAssertEqual(outcome.displayMuted, false)
    }

    func testDefaultSettleParameterExercisesTheRealBluetoothPathWithoutHanging() {
        let device = FakeAudioMuteDevice()
        device.bluetoothDevice = false
        device.setShouldSucceed = true
        device.readBackValue = true

        let outcome = applyMasterMute(true, device: device) { _ in }

        XCTAssertEqual(outcome.displayMuted, true)
    }
}

final class BluetoothHFPSettlingTests: XCTestCase {
    func testNonBluetoothDeviceSkipsSettlingEntirely() {
        let device = FakeAudioMuteDevice()
        device.bluetoothDevice = false
        var sleepCallCount = 0

        waitForBluetoothHFPSettling(device: device, maxPolls: 5) { sleepCallCount += 1 }

        XCTAssertEqual(sleepCallCount, 0)
    }

    func testBluetoothDeviceAlreadySettledSkipsSleeping() {
        let device = FakeAudioMuteDevice()
        device.bluetoothDevice = true
        device.nominalSampleRateSequence = [16000]
        var sleepCallCount = 0

        waitForBluetoothHFPSettling(device: device, maxPolls: 5) { sleepCallCount += 1 }

        XCTAssertEqual(sleepCallCount, 0)
    }

    func testBluetoothDevicePollsUntilRateDropsBelowA2DPThreshold() {
        let device = FakeAudioMuteDevice()
        device.bluetoothDevice = true
        device.nominalSampleRateSequence = [48000, 48000, 16000]
        var sleepCallCount = 0

        waitForBluetoothHFPSettling(device: device, maxPolls: 5) { sleepCallCount += 1 }

        XCTAssertEqual(sleepCallCount, 2)
    }

    func testBluetoothDeviceGivesUpAfterMaxPollsWithoutHanging() {
        let device = FakeAudioMuteDevice()
        device.bluetoothDevice = true
        device.nominalSampleRateSequence = [48000, 48000, 48000, 48000, 48000]
        var sleepCallCount = 0

        waitForBluetoothHFPSettling(device: device, maxPolls: 3) { sleepCallCount += 1 }

        XCTAssertEqual(sleepCallCount, 3)
    }

    func testUnreadableSampleRateGivesUpWithoutHanging() {
        let device = FakeAudioMuteDevice()
        device.bluetoothDevice = true
        device.nominalSampleRateSequence = [nil, nil]
        var sleepCallCount = 0

        waitForBluetoothHFPSettling(device: device, maxPolls: 3) { sleepCallCount += 1 }

        XCTAssertEqual(sleepCallCount, 3)
    }
}
