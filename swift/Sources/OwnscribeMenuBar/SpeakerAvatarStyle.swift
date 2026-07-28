import SwiftUI

enum SpeakerAvatarStyle {
    static func color(for speaker: String) -> Color {
        switch speaker {
        case "Owner": return .green
        case "Unknown": return .secondary
        default:
            if speaker.hasPrefix("SPEAKER_") {
                return speaker.hasSuffix("0") ? .blue : .purple
            }
            return hashColor(for: speaker)
        }
    }

    static func displayLabel(for speaker: String) -> String {
        if speaker == "Owner" || speaker == "Unknown" {
            return speaker
        }
        if speaker.hasPrefix("SPEAKER_"), let suffix = speaker.split(separator: "_").last {
            return String(suffix)
        }
        return speaker
    }

    private static func hashColor(for name: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .indigo, .teal, .cyan]
        let hash = fnv1aHash(name)
        return colors[Int(hash % UInt32(colors.count))]
    }

    private static func fnv1aHash(_ string: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for scalar in string.unicodeScalars {
            hash ^= UInt32(scalar.value)
            hash = hash &* 16777619
        }
        return hash
    }
}
