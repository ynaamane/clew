import SwiftUI

enum SpeakerAvatarStyle {
    static func color(for speaker: String) -> Color {
        switch speaker {
        case "Owner": return .green
        case "Unknown": return .secondary
        default: return speaker.hasSuffix("0") ? .blue : .purple
        }
    }

    static func displayLabel(for speaker: String) -> String {
        if speaker == "Owner" || speaker == "Unknown" {
            return speaker
        }
        if let suffix = speaker.split(separator: "_").last, suffix.count <= 2 {
            return String(suffix)
        }
        return speaker
    }
}
