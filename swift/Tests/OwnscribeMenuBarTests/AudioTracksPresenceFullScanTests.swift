import Testing
import Foundation
import AVFoundation
@testable import OwnscribeMenuBar

@Suite struct AudioTracksPresenceFullScanTests {

    private func createWavFile(at url: URL, sampleRate: Double, channels: AVAudioChannelCount, durationSeconds: Double, silentLeadingSeconds: Double) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false)!
        let totalFrames = AVAudioFrameCount(durationSeconds * sampleRate)
        let silentFrames = AVAudioFrameCount(silentLeadingSeconds * sampleRate)

        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)

        let chunkSize: AVAudioFrameCount = 8192
        var written: AVAudioFrameCount = 0

        while written < totalFrames {
            let framesToWrite = min(chunkSize, totalFrames - written)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesToWrite) else { break }
            buffer.frameLength = framesToWrite

            let isSilentChunk = written < silentFrames

            if !isSilentChunk {
                for ch in 0..<Int(channels) {
                    let channelData = buffer.floatChannelData![ch]
                    for frame in 0..<Int(framesToWrite) {
                        channelData[frame] = sin(2.0 * .pi * 440.0 * Float(written + AVAudioFrameCount(frame)) / Float(sampleRate)) * 0.5
                    }
                }
            }

            try file.write(from: buffer)
            written += framesToWrite
        }
    }

    private func createZeroFrameWav(at url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!
        _ = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    @Test func firstSecondSilentButLaterHasContent() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let path = tempDir.appendingPathComponent("recording.wav")
        try createWavFile(at: path, sampleRate: 48000, channels: 2, durationSeconds: 10.0, silentLeadingSeconds: 5.5)

        let tracks = AudioTracksPresence.checkTracks(in: tempDir)
        let recording = tracks.first { $0.filename == "recording.wav" }
        #expect(recording?.hasContent == true)
    }

    @Test func entirelyAllSilent() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let path = tempDir.appendingPathComponent("recording.wav")
        try createWavFile(at: path, sampleRate: 48000, channels: 2, durationSeconds: 33.6, silentLeadingSeconds: 33.6)

        let tracks = AudioTracksPresence.checkTracks(in: tempDir)
        let recording = tracks.first { $0.filename == "recording.wav" }
        #expect(recording?.hasContent == false)
    }

    @Test func zeroDurationFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let path = tempDir.appendingPathComponent("recording.wav")
        try createZeroFrameWav(at: path)

        let tracks = AudioTracksPresence.checkTracks(in: tempDir)
        let recording = tracks.first { $0.filename == "recording.wav" }
        #expect(recording?.hasContent == false)
    }
}
