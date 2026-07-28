import Foundation

public struct MeetingOutputPaths {
    public let directory: URL
    public let recordingPath: URL

    public init(baseDir: URL, now: Date = Date(), fileManager: FileManager = .default) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HHmm"

        let timestamp = formatter.string(from: now)
        let baseDirectory = baseDir.appendingPathComponent(timestamp)

        directory = Self.findNextAvailableDirectory(base: baseDirectory, fileManager: fileManager)
        recordingPath = directory.appendingPathComponent("recording.wav")
    }

    private static func findNextAvailableDirectory(base: URL, fileManager: FileManager) -> URL {
        var candidate = base
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let contents = (try? fileManager.contentsOfDirectory(atPath: candidate.path)) ?? []
            if contents.isEmpty {
                return candidate
            }
            candidate = URL(fileURLWithPath: base.path + "_\(suffix)")
            suffix += 1
        }

        return candidate
    }

    public func createDirectory(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

public struct RecordingTempPaths {
    public let systemPath: String
    public let micPath: String

    public init(outputPath: String, micEnabled: Bool) {
        systemPath = micEnabled ? outputPath + ".sys.tmp.wav" : outputPath
        micPath = outputPath + ".mic.tmp.wav"
    }
}
