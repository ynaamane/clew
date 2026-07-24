import Foundation

public struct MeetingSummary: Identifiable, Equatable {
    public let id: String
    public let directory: URL
    public let hasTranscript: Bool
    public let hasSummary: Bool

    public init(directory: URL, hasTranscript: Bool, hasSummary: Bool) {
        self.id = directory.path
        self.directory = directory
        self.hasTranscript = hasTranscript
        self.hasSummary = hasSummary
    }
}

public struct RecentTranscriptsStore {
    public static func recentMeetings(
        in outputDir: URL,
        limit: Int = 10,
        fileManager: FileManager = .default
    ) -> [MeetingSummary] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: outputDir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let directories = entries.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }

        let summaries = directories.map { dir in
            MeetingSummary(
                directory: dir,
                hasTranscript: hasAny(named: "transcript", in: dir, fileManager: fileManager),
                hasSummary: hasAny(named: "summary", in: dir, fileManager: fileManager)
            )
        }

        return Array(
            summaries
                .sorted { $0.directory.lastPathComponent > $1.directory.lastPathComponent }
                .prefix(limit)
        )
    }

    private static func hasAny(named stem: String, in directory: URL, fileManager: FileManager) -> Bool {
        ["md", "json"].contains { ext in
            fileManager.fileExists(atPath: directory.appendingPathComponent("\(stem).\(ext)").path)
        }
    }
}
