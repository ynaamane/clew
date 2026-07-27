import Foundation

public struct MeetingSummary: Identifiable, Hashable {
    public let id: String
    public let directory: URL
    public let hasTranscript: Bool
    public let hasSummary: Bool
    public let actionItemCount: Int
    public let unanchoredClaimCount: Int

    public init(
        directory: URL,
        hasTranscript: Bool,
        hasSummary: Bool,
        actionItemCount: Int = 0,
        unanchoredClaimCount: Int = 0
    ) {
        self.id = directory.path
        self.directory = directory
        self.hasTranscript = hasTranscript
        self.hasSummary = hasSummary
        self.actionItemCount = actionItemCount
        self.unanchoredClaimCount = unanchoredClaimCount
    }

    public var displayTitle: String {
        let parts = directory.lastPathComponent.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false)
        let slug = parts.count >= 3 ? String(parts[2]) : (parts.count == 1 ? String(parts[0]) : "")
        guard !slug.isEmpty else { return "Sans titre" }
        return slug.replacingOccurrences(of: "-", with: " ").capitalizedFirstLetter
    }

    public var displayDate: String {
        let name = directory.lastPathComponent
        let parts = name.split(separator: "_")
        guard parts.count >= 2, let day = Self.folderDateFormatter.date(from: "\(parts[0])_\(parts[1])") else {
            return ""
        }
        return Self.readableDateFormatter.string(from: day)
    }

    private static let folderDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let readableDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM · HH:mm"
        return f
    }()
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
