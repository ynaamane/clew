import Foundation

enum MeetingHeaderDetail {
    static func text(date: String, duration: TimeInterval?, language: String, speakerCount: Int?) -> String {
        var parts = [date]
        if let duration, duration > 0 { parts.append(durationText(duration)) }
        if !language.isEmpty { parts.append(language) }
        if let speakerCount, speakerCount > 0 { parts.append("\(speakerCount) voix") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
