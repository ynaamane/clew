import Foundation

struct AudioTrackPresence {
    let filename: String
    let isPresent: Bool
    let duration: TimeInterval?
}

enum AudioTracksPresence {
    static func checkTracks(in directory: URL, fileManager: FileManager = .default) -> [AudioTrackPresence] {
        let candidates = ["system.wav", "mic.wav", "recording.wav"]
        return candidates.map { filename in
            let path = directory.appendingPathComponent(filename)
            let exists = fileManager.fileExists(atPath: path.path)
            return AudioTrackPresence(filename: filename, isPresent: exists, duration: nil)
        }
    }
}
