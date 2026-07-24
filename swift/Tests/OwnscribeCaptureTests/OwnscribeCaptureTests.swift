import XCTest
@testable import OwnscribeCapture

final class SustainedActivityDetectorTests: XCTestCase {
    func testImmediateObservationNeverTriggers() {
        let detector = SustainedActivityDetector(sustainedSeconds: 3.0)
        let now = Date()
        XCTAssertFalse(detector.observe(running: true, now: now))
    }

    func testExactThresholdTriggers() {
        let detector = SustainedActivityDetector(sustainedSeconds: 3.0)
        let start = Date()
        XCTAssertFalse(detector.observe(running: true, now: start))
        XCTAssertTrue(detector.observe(running: true, now: start.addingTimeInterval(3.0)))
    }

    func testJustUnderThresholdDoesNotTrigger() {
        let detector = SustainedActivityDetector(sustainedSeconds: 3.0)
        let start = Date()
        XCTAssertFalse(detector.observe(running: true, now: start))
        XCTAssertFalse(detector.observe(running: true, now: start.addingTimeInterval(2.999)))
    }

    func testGapResetsTheClock() {
        let detector = SustainedActivityDetector(sustainedSeconds: 3.0)
        let start = Date()
        XCTAssertFalse(detector.observe(running: true, now: start))
        XCTAssertFalse(detector.observe(running: true, now: start.addingTimeInterval(2.0)))
        XCTAssertFalse(detector.observe(running: false, now: start.addingTimeInterval(2.5)))
        XCTAssertFalse(detector.observe(running: true, now: start.addingTimeInterval(2.6)))
    }

    func testPostResetStillEventuallyTriggers() {
        let detector = SustainedActivityDetector(sustainedSeconds: 3.0)
        let start = Date()
        XCTAssertFalse(detector.observe(running: true, now: start))
        XCTAssertFalse(detector.observe(running: false, now: start.addingTimeInterval(1.0)))
        XCTAssertFalse(detector.observe(running: true, now: start.addingTimeInterval(1.5)))
        XCTAssertTrue(detector.observe(running: true, now: start.addingTimeInterval(4.5)))
    }

    func testNeverRunningNeverTriggers() {
        let detector = SustainedActivityDetector(sustainedSeconds: 3.0)
        let start = Date()
        XCTAssertFalse(detector.observe(running: false, now: start))
        XCTAssertFalse(detector.observe(running: false, now: start.addingTimeInterval(10.0)))
    }

    func testZeroThresholdTriggersOnTheVeryFirstRunningObservation() {
        let detector = SustainedActivityDetector(sustainedSeconds: 0.0)
        XCTAssertTrue(detector.observe(running: true, now: Date()))
    }
}

final class CombinedCallSignalTests: XCTestCase {
    func testBothTrueYieldsTrue() {
        XCTAssertEqual(combinedCallSignal(mic: true, output: true), true)
    }

    func testMicAloneYieldsFalse() {
        XCTAssertEqual(combinedCallSignal(mic: true, output: false), false)
    }

    func testOutputAloneYieldsFalse() {
        XCTAssertEqual(combinedCallSignal(mic: false, output: true), false)
    }

    func testBothFalseYieldsFalse() {
        XCTAssertEqual(combinedCallSignal(mic: false, output: false), false)
    }

    func testMicUnknownYieldsNil() {
        XCTAssertNil(combinedCallSignal(mic: nil, output: true))
    }

    func testOutputUnknownYieldsNil() {
        XCTAssertNil(combinedCallSignal(mic: true, output: nil))
    }

    func testBothUnknownYieldsNil() {
        XCTAssertNil(combinedCallSignal(mic: nil, output: nil))
    }
}

final class ComputePeakLevelTests: XCTestCase {
    private func withChannelBuffers(_ values: [[Float]], _ body: (UnsafePointer<UnsafeMutablePointer<Float>>, Int, Int) -> Void) {
        let channels = values.count
        let frames = values.first?.count ?? 0
        let pointers = values.map { channel -> UnsafeMutablePointer<Float> in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: channel.count)
            p.initialize(from: channel, count: channel.count)
            return p
        }
        defer { pointers.forEach { $0.deallocate() } }

        let array = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: channels)
        array.initialize(from: pointers, count: channels)
        defer { array.deallocate() }

        body(UnsafePointer(array), channels, frames)
    }

    func testSingleChannelPositivePeak() {
        withChannelBuffers([[0.1, 0.5, -0.3, 0.2]]) { ptr, channels, frames in
            XCTAssertEqual(computePeakLevel(in: ptr, channels: channels, frames: frames), 0.5, accuracy: 1e-6)
        }
    }

    func testNegativeValuesUseAbsoluteValue() {
        withChannelBuffers([[-0.9, 0.1, 0.2]]) { ptr, channels, frames in
            XCTAssertEqual(computePeakLevel(in: ptr, channels: channels, frames: frames), 0.9, accuracy: 1e-6)
        }
    }

    func testMultiChannelTakesMaxAcrossChannels() {
        withChannelBuffers([[0.1, 0.2], [0.05, 0.8]]) { ptr, channels, frames in
            XCTAssertEqual(computePeakLevel(in: ptr, channels: channels, frames: frames), 0.8, accuracy: 1e-6)
        }
    }

    func testAllZerosYieldsZeroPeak() {
        withChannelBuffers([[0.0, 0.0, 0.0]]) { ptr, channels, frames in
            XCTAssertEqual(computePeakLevel(in: ptr, channels: channels, frames: frames), 0.0, accuracy: 1e-6)
        }
    }

    func testZeroFramesYieldsZeroPeak() {
        withChannelBuffers([[]]) { ptr, channels, _ in
            XCTAssertEqual(computePeakLevel(in: ptr, channels: channels, frames: 0), 0.0, accuracy: 1e-6)
        }
    }
}

final class ComputeMicStartOffsetTests: XCTestCase {
    private let sampleRate: Double = 24000

    func testMicStartsAfterSystemYieldsPositiveOffset() {
        // 1 tick == 1 nanosecond for a 1:1 timebase, so a 300ms delta in host-time
        // ticks is directly 0.3s.
        let result = computeMicStartOffset(
            systemStartHostTime: 0,
            micStartHostTime: 300_000_000,
            ticksToNanos: 1.0,
            sampleRate: sampleRate)

        XCTAssertEqual(result.offsetSeconds, 0.3, accuracy: 1e-9)
        XCTAssertEqual(result.offsetFrames, Int64(0.3 * sampleRate))
    }

    func testMicStartsBeforeSystemYieldsNegativeOffset() {
        let result = computeMicStartOffset(
            systemStartHostTime: 300_000_000,
            micStartHostTime: 0,
            ticksToNanos: 1.0,
            sampleRate: sampleRate)

        XCTAssertEqual(result.offsetSeconds, -0.3, accuracy: 1e-9)
        XCTAssertEqual(result.offsetFrames, Int64(-0.3 * sampleRate))
    }

    func testSimultaneousStartYieldsZeroOffset() {
        let result = computeMicStartOffset(
            systemStartHostTime: 42,
            micStartHostTime: 42,
            ticksToNanos: 1.0,
            sampleRate: sampleRate)

        XCTAssertEqual(result.offsetSeconds, 0.0, accuracy: 1e-9)
        XCTAssertEqual(result.offsetFrames, 0)
    }

    func testNonUnityTimebaseScalesCorrectly() {
        // Apple Silicon's real mach_timebase_info is commonly numer=125, denom=3
        // (1 tick == 125/3 ns, so 1s == 1e9/(125/3) == 24,000,000 ticks).
        let ticksToNanos = 125.0 / 3.0
        let result = computeMicStartOffset(
            systemStartHostTime: 0,
            micStartHostTime: 24_000_000,
            ticksToNanos: ticksToNanos,
            sampleRate: sampleRate)

        XCTAssertEqual(result.offsetSeconds, 1.0, accuracy: 1e-6)
        XCTAssertEqual(result.offsetFrames, Int64(sampleRate))
    }

    func testRealWorldSkewMatchesEmpiricallyMeasuredValue() {
        // BUG3 repro (~/ownscribe/2026-07-24_1756_emerging-internet-force-impact):
        // mic's AVAudioEngine.start() is called first and starts near-instantly, while
        // the CoreAudio process tap's async setup (AudioHardwareCreateProcessTap ->
        // AudioHardwareCreateAggregateDevice -> IOProc creation -> AudioDeviceStart)
        // takes much longer to produce its first sample. On this real run the tap took
        // ~28.28s longer, matching an independent acoustic cross-correlation of the
        // retained mic.wav/system.wav (28.36s) and same-utterance-position comparison
        // (28.29s) to within 1% -- confirms computeMicStartOffset's sign/magnitude are
        // correct; the bug this pins was one level up, in how the Python pipeline
        // consumed a negative offset.
        let ticksToNanos = 1.0
        let systemStartHostTime: UInt64 = 28_277_794_125
        let micStartHostTime: UInt64 = 0
        let result = computeMicStartOffset(
            systemStartHostTime: systemStartHostTime,
            micStartHostTime: micStartHostTime,
            ticksToNanos: ticksToNanos,
            sampleRate: sampleRate)

        XCTAssertEqual(result.offsetSeconds, -28.277794125, accuracy: 1e-6)
        XCTAssertLessThan(result.offsetFrames, 0)
    }
}

final class RunCoreAudioTapPermissionPreflightTests: XCTestCase {
    func testBothGrantedAndMicNotNeededPasses() {
        let ok = runCoreAudioTapPermissionPreflight(
            needsMic: false, hasScreenCaptureAccess: true, hasMicrophoneAccess: false)
        XCTAssertTrue(ok)
    }

    func testBothGrantedAndMicNeededPasses() {
        let ok = runCoreAudioTapPermissionPreflight(
            needsMic: true, hasScreenCaptureAccess: true, hasMicrophoneAccess: true)
        XCTAssertTrue(ok)
    }

    func testScreenCaptureDeniedFailsRegardlessOfMic() {
        let ok = runCoreAudioTapPermissionPreflight(
            needsMic: false, hasScreenCaptureAccess: false, hasMicrophoneAccess: true)
        XCTAssertFalse(ok)
    }

    func testMicDeniedButNotNeededPasses() {
        let ok = runCoreAudioTapPermissionPreflight(
            needsMic: false, hasScreenCaptureAccess: true, hasMicrophoneAccess: false)
        XCTAssertTrue(ok)
    }

    func testMicDeniedAndNeededFails() {
        let ok = runCoreAudioTapPermissionPreflight(
            needsMic: true, hasScreenCaptureAccess: true, hasMicrophoneAccess: false)
        XCTAssertFalse(ok)
    }

    func testBothDeniedFails() {
        let ok = runCoreAudioTapPermissionPreflight(
            needsMic: true, hasScreenCaptureAccess: false, hasMicrophoneAccess: false)
        XCTAssertFalse(ok)
    }
}
