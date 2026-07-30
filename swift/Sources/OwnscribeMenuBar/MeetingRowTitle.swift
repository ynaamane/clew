import Foundation

public enum MeetingRowTitle {
    public struct Pair {
        public let title: String
        public let subtitle: String
    }

    public static func resolve(
        directory: URL,
        fileManager: FileManager = .default
    ) -> Pair {
        let parts = directory.lastPathComponent.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false)
        let slug = parts.count >= 3 ? String(parts[2]) : (parts.count == 1 ? String(parts[0]) : "")
        let timestamp = parts.count >= 2 ? "\(parts[0])_\(parts[1])" : ""

        if !slug.isEmpty, !isLLMRefusal(slug) {
            let titleText = slug.replacingOccurrences(of: "-", with: " ").capitalizedFirstLetter
            return Pair(title: titleText, subtitle: formatDate(timestamp, includeTime: true))
        }

        if let firstLine = firstTranscriptLine(directory: directory, fileManager: fileManager) {
            return Pair(title: firstLine, subtitle: formatDate(timestamp, includeTime: true))
        }

        let timeText = formatTime(timestamp)
        return Pair(title: timeText, subtitle: formatDate(timestamp, includeTime: false))
    }

    private static func firstTranscriptLine(directory: URL, fileManager: FileManager) -> String? {
        let transcriptURL = directory.appendingPathComponent("transcript.md")
        guard let doc = try? TranscriptDocument(contentsOf: transcriptURL),
              let first = doc.utterances.first(where: { !$0.isBackchannel }) else {
            return nil
        }

        let maxLength = 60
        let trimmed = first.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength {
            return trimmed
        }
        return String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func isLLMRefusal(_ slug: String) -> Bool {
        let lower = slug.lowercased()

        let firstPersonStarts = [
            "i-m-",
            "i-cannot-",
            "i-need-",
            "i-don-t-",
            "i-apologize-",
            "sorry-but-",
            "sorry-i-",
            "i-am-sorry-",
        ]

        if firstPersonStarts.contains(where: { lower.hasPrefix($0) }) {
            return true
        }

        let unambiguousRefusals = [
            "please-provide",
            "could-you",
            "transcript-of-the",
            "more-information",
        ]

        return unambiguousRefusals.contains { lower.contains($0) }
    }

    private static func formatTime(_ timestamp: String) -> String {
        let parts = timestamp.split(separator: "_")
        guard parts.count >= 2 else { return "" }

        let timeComponent = String(parts[1])
        guard timeComponent.count == 4 else { return "" }

        let hour = String(timeComponent.prefix(2))
        let minute = String(timeComponent.suffix(2))
        return "\(hour):\(minute)"
    }

    private static func formatDate(_ timestamp: String, includeTime: Bool) -> String {
        guard let day = folderDateFormatter.date(from: timestamp) else {
            return ""
        }

        if includeTime {
            return readableDateFormatter.string(from: day)
        } else {
            return dateOnlyFormatter.string(from: day)
        }
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

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()
}
