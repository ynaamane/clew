import Foundation

public struct MeetingSearchFilter {
    public static func filter(_ meetings: [MeetingSummary], query: String) -> [MeetingSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return meetings }

        let normalizedQuery = trimmed.lowercased().folding(options: .diacriticInsensitive, locale: .current)

        return meetings.filter { meeting in
            let title = meeting.displayTitle.lowercased().folding(options: .diacriticInsensitive, locale: .current)
            let date = meeting.displayDate.lowercased()

            return title.contains(normalizedQuery) || date.contains(normalizedQuery)
        }
    }
}
