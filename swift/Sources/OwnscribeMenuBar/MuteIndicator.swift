import Foundation

public enum MuteIndicator: Equatable {
    case notMuted
    case mutedVerified
    case mutedUnverified

    public var symbolName: String {
        switch self {
        case .notMuted: return "waveform"
        case .mutedVerified: return "mic.slash.fill"
        case .mutedUnverified: return "exclamationmark.triangle.fill"
        }
    }

    public var isMuted: Bool {
        self != .notMuted
    }
}
