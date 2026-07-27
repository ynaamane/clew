import AVFoundation
import XCTest
@testable import OwnscribeCapture

final class MergeSampleRateTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merge-rate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testMergedSystemAudioKeepsItsRealDurationWhenCapturedAt48k() throws {
        let systemPath = tempDir.appendingPathComponent("sys-temp.wav").path
        let micPath = tempDir.appendingPathComponent("mic-temp.wav").path
        let outputPath = tempDir.appendingPathComponent("recording.wav").path

        try writeTone(at: systemPath, sampleRate: 48000, seconds: 2.0, channels: 2)
        try writeTone(at: micPath, sampleRate: 48000, seconds: 2.0, channels: 1)

        try mergeAudioFiles(
            systemPath: systemPath,
            micPath: micPath,
            systemStartHostTime: 0,
            micStartHostTime: 0,
            outputPath: outputPath)

        let merged = try AVAudioFile(forReading: URL(fileURLWithPath: outputPath))
        let mergedSeconds = Double(merged.length) / merged.fileFormat.sampleRate

        XCTAssertEqual(
            mergedSeconds, 2.0, accuracy: 0.05,
            "A 2s capture must merge to a 2s file. A hardcoded output rate that differs from the captured rate replays the call at the wrong speed.")
    }

    func testMergedFileAdoptsTheCapturedSampleRateRatherThanAHardcodedOne() throws {
        let systemPath = tempDir.appendingPathComponent("sys-temp.wav").path
        let micPath = tempDir.appendingPathComponent("mic-temp.wav").path
        let outputPath = tempDir.appendingPathComponent("recording.wav").path

        try writeTone(at: systemPath, sampleRate: 48000, seconds: 1.0, channels: 2)
        try writeTone(at: micPath, sampleRate: 48000, seconds: 1.0, channels: 1)

        try mergeAudioFiles(
            systemPath: systemPath,
            micPath: micPath,
            systemStartHostTime: 0,
            micStartHostTime: 0,
            outputPath: outputPath)

        let merged = try AVAudioFile(forReading: URL(fileURLWithPath: outputPath))

        XCTAssertEqual(
            merged.fileFormat.sampleRate, 48000,
            "The merge must follow the rate the hardware actually captured at, not a compile-time constant.")
    }

    func testMicOnlyCaptureAlsoKeepsItsRealDuration() throws {
        let systemPath = tempDir.appendingPathComponent("sys-temp.wav").path
        let micPath = tempDir.appendingPathComponent("mic-temp.wav").path
        let outputPath = tempDir.appendingPathComponent("recording.wav").path

        try writeTone(at: micPath, sampleRate: 44100, seconds: 2.0, channels: 1)

        try mergeAudioFiles(
            systemPath: systemPath,
            micPath: micPath,
            systemStartHostTime: 0,
            micStartHostTime: 0,
            outputPath: outputPath)

        let merged = try AVAudioFile(forReading: URL(fileURLWithPath: outputPath))
        let mergedSeconds = Double(merged.length) / merged.fileFormat.sampleRate

        XCTAssertEqual(
            mergedSeconds, 2.0, accuracy: 0.05,
            "With no system track the mic rate must drive the output, so a mic-only recording is not resampled to a wrong duration.")
    }

    private func writeTone(at path: String, sampleRate: Double, seconds: Double, channels: AVAudioChannelCount) throws {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: true)!
        let file = try AVAudioFile(
            forWriting: URL(fileURLWithPath: path),
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: true)

        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for frame in 0..<Int(frames) {
            let value = Float(sin(2.0 * Double.pi * 440.0 * Double(frame) / sampleRate)) * 0.5
            for channel in 0..<Int(channels) {
                samples[frame * Int(channels) + channel] = value
            }
        }
        try file.write(from: buffer)
    }
}
