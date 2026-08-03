import Foundation

/// The library window's title-bar subtitle, e.g. "8 réunions · 18 h 12 min"
/// (mockup.html:244). Duration is summed only over meetings whose duration is actually known —
/// the caller passes exactly that pre-filtered list — and drops out entirely when none is known,
/// rather than rendering a misleading "0 min" for a library nobody has measured.
public enum LibraryNavigationSubtitle {
    public static func text(meetingCount: Int, knownDurations: [TimeInterval]) -> String {
        let countText = meetingCount == 1 ? "1 réunion" : "\(meetingCount) réunions"

        let totalKnown = knownDurations.reduce(0, +)
        guard !knownDurations.isEmpty, totalKnown > 0 else { return countText }

        return "\(countText) · \(formatAggregateDuration(totalKnown))"
    }

    static func formatAggregateDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int((seconds / 60).rounded())
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours) h \(minutes) min" : "\(minutes) min"
    }
}
