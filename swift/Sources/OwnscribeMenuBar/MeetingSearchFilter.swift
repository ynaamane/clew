import Foundation

public struct MeetingSearchFilter {
    public static func filter(_ meetings: [MeetingSummary], query: String) -> [MeetingSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return meetings }

        let needle = normalized(trimmed)

        return meetings.filter { meeting in
            normalized(meeting.displayTitle).contains(needle)
                || normalized(meeting.displayDate).contains(needle)
        }
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
