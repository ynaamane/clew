import AVFoundation
import XCTest
@testable import OwnscribeCapture

final class OpenAudioFileWithFramesTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("open-audio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testZeroFrameFileReturnsNil() throws {
        let path = tempDir.appendingPathComponent("zero.wav").path
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        _ = try AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)

        let result = openAudioFileWithFrames(atPath: path)
        XCTAssertNil(result)
    }

    func testNonExistentFileReturnsNil() throws {
        let path = tempDir.appendingPathComponent("nonexistent.wav").path
        let result = openAudioFileWithFrames(atPath: path)
        XCTAssertNil(result)
    }

    func testFileWithFramesReturnsFile() throws {
        let path = tempDir.appendingPathComponent("with-audio.wav").path
        try writeOneTone(at: path, sampleRate: 48000, seconds: 1.0, channels: 2)

        let result = openAudioFileWithFrames(atPath: path)
        XCTAssertNotNil(result)
        XCTAssertGreaterThan(result!.length, 0)
    }

    private func writeOneTone(at path: String, sampleRate: Double, seconds: Double, channels: AVAudioChannelCount) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: path), settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)

        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames

        for ch in 0..<Int(channels) {
            let channelData = buffer.floatChannelData![ch]
            for frame in 0..<Int(frames) {
                channelData[frame] = sin(2.0 * .pi * 440.0 * Float(frame) / Float(sampleRate)) * 0.5
            }
        }

        try file.write(from: buffer)
    }
}
