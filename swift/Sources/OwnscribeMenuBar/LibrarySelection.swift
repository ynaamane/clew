import Foundation

public struct LibrarySelection {
    public static func resolve(
        current: MeetingSummary?,
        shown: [MeetingSummary]
    ) -> MeetingSummary? {
        if let current, shown.contains(current) {
            return current
        }

        return shown.first
    }
}
