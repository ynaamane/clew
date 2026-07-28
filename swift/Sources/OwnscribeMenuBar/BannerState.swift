import Foundation

public struct BannerState: Equatable {
    public enum Severity: Equatable {
        case error
        case warning
    }

    public let message: String
    public let severity: Severity
    public let isDismissible: Bool

    public init(message: String, severity: Severity, isDismissible: Bool) {
        self.message = message
        self.severity = severity
        self.isDismissible = isDismissible
    }

    public static func bannerState(
        phase: AppState.Phase,
        muteWarning: String?,
        muteIndicator: MuteIndicator,
        isCliAvailable: Bool
    ) -> BannerState? {
        if case .failed(let message) = phase {
            return BannerState(
                message: message,
                severity: .error,
                isDismissible: true
            )
        }

        if muteIndicator == .mutedUnverified, let warning = muteWarning {
            return BannerState(
                message: warning,
                severity: .warning,
                isDismissible: false
            )
        }

        if !isCliAvailable {
            return BannerState(
                message: "Audio will be recorded but not transcribed — the ownscribe CLI is missing. Restore it, then run ./rec.sh redo <dir> to transcribe this meeting from its retained audio.",
                severity: .warning,
                isDismissible: false
            )
        }

        return nil
    }
}
