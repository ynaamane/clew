import Foundation

public struct MeetingRowSummary {
    public static func loadExcerpt(
        from directory: URL,
        configURL: URL,
        fileManager: FileManager = .default
    ) -> String? {
        guard let summary = MeetingInspectorState.loadSummary(
            from: directory,
            configURL: configURL,
            fileManager: fileManager
        ) else {
            return nil
        }

        let prose = summary.prose.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prose.isEmpty else { return nil }

        return truncateForDisplay(prose)
    }

    static func truncateForDisplay(_ text: String, maxLength: Int = 120) -> String {
        guard text.count > maxLength else { return text }

        let truncated = String(text.prefix(maxLength))
        return truncated + "…"
    }
}
