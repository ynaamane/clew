import SwiftUI

enum SpeakerAvatarStyle {
    static func color(for speaker: String) -> Color {
        switch speaker {
        case "Owner": return .green
        case "Unknown": return .secondary
        default:
            if let index = diarizationIndex(in: speaker) {
                return palette[index % palette.count]
            }
            return hashColor(for: speaker)
        }
    }

    private static let palette: [Color] = [.blue, .purple, .orange, .pink, .indigo, .teal, .cyan]

    private static func diarizationIndex(in speaker: String) -> Int? {
        guard speaker.hasPrefix("SPEAKER_"),
              let index = Int(speaker.dropFirst("SPEAKER_".count)),
              index >= 0
        else { return nil }
        return index
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
        let hash = fnv1aHash(name)
        return palette[Int(hash % UInt32(palette.count))]
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
