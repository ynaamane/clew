import Foundation

public struct MeetingOutputPaths {
    public let directory: URL
    public let recordingPath: URL

    public init(baseDir: URL, now: Date = Date()) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd_HHmm"

        let timestamp = formatter.string(from: now)
        directory = baseDir.appendingPathComponent(timestamp)
        recordingPath = directory.appendingPathComponent("recording.wav")
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
