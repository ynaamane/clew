import Foundation

public struct MeetingSummary: Identifiable, Hashable {
    public let id: String
    public let directory: URL
    public let hasTranscript: Bool
    public let hasSummary: Bool
    public let actionItemCount: Int?
    public let unanchoredClaimCount: Int?

    public init(
        directory: URL,
        hasTranscript: Bool,
        hasSummary: Bool,
        actionItemCount: Int? = nil,
        unanchoredClaimCount: Int? = nil
    ) {
        self.id = directory.path
        self.directory = directory
        self.hasTranscript = hasTranscript
        self.hasSummary = hasSummary
        self.actionItemCount = actionItemCount
        self.unanchoredClaimCount = unanchoredClaimCount
    }

    public var displayTitle: String {
        MeetingRowTitle.resolve(directory: directory).title
    }

    public var displayDate: String {
        MeetingRowTitle.resolve(directory: directory).subtitle
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
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
            let counts = MeetingCounts.compute(
                summaryDirectory: dir,
                fileManager: fileManager
            )

            return MeetingSummary(
                directory: dir,
                hasTranscript: hasAny(named: "transcript", in: dir, fileManager: fileManager),
                hasSummary: hasAny(named: "summary", in: dir, fileManager: fileManager),
                actionItemCount: counts.actionItemCount,
                unanchoredClaimCount: counts.unanchoredClaimCount
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
