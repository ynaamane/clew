import Foundation
import AVFoundation

struct AudioTrackPresence {
    let filename: String
    let isPresent: Bool
    let duration: TimeInterval?
    let hasContent: Bool

    var displayStatus: String {
        if !isPresent { return "—" }
        if hasContent, let dur = duration {
            let minutes = Int(dur) / 60
            let seconds = Int(dur) % 60
            return String(format: "%d:%02d ✓", minutes, seconds)
        }
        if let dur = duration {
            let minutes = Int(dur) / 60
            let seconds = Int(dur) % 60
            return String(format: "%d:%02d ⚠", minutes, seconds)
        }
        return "⚠"
    }
}

enum AudioTracksPresence {
    static func checkTracks(in directory: URL, fileManager: FileManager = .default) -> [AudioTrackPresence] {
        let candidates = ["system.wav", "mic.wav", "recording.wav"]
        return candidates.map { filename in
            let path = directory.appendingPathComponent(filename)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory)

            guard exists, !isDirectory.boolValue else {
                return AudioTrackPresence(filename: filename, isPresent: false, duration: nil, hasContent: false)
            }

            guard let attrs = try? fileManager.attributesOfItem(atPath: path.path),
                  let fileSize = attrs[.size] as? UInt64,
                  fileSize > 0 else {
                return AudioTrackPresence(filename: filename, isPresent: true, duration: nil, hasContent: false)
            }

            let asset = AVURLAsset(url: path)
            let duration = asset.duration.seconds

            let hasContent = duration > 0 && checkHasAudio(path)
            return AudioTrackPresence(filename: filename, isPresent: true, duration: duration, hasContent: hasContent)
        }
    }

    private static func checkHasAudio(_ url: URL) -> Bool {
        guard let file = try? AVAudioFile(forReading: url) else { return false }

        let format = file.processingFormat
        let totalFrames = AVAudioFrameCount(file.length)
        guard totalFrames > 0 else { return false }

        let threshold: Float = 0.001
        let chunkSize: AVAudioFrameCount = 48000
        let channelCount = Int(format.channelCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else { return false }

        var framePosition: AVAudioFramePosition = 0

        while framePosition < file.length {
            let framesToRead = min(chunkSize, AVAudioFrameCount(file.length - framePosition))

            file.framePosition = framePosition

            guard (try? file.read(into: buffer, frameCount: framesToRead)) != nil else { return false }

            guard let floatData = buffer.floatChannelData else { return false }

            let framesToCheck = Int(buffer.frameLength)

            for channel in 0..<channelCount {
                let channelData = floatData[channel]
                for frame in 0..<framesToCheck {
                    if abs(channelData[frame]) > threshold {
                        return true
                    }
                }
            }

            framePosition += AVAudioFramePosition(framesToRead)
        }

        return false
    }
}
