import Foundation

public struct BannerState: Equatable {
    public enum Severity: Equatable {
        case error
        case warning
    }

    public let message: String
    public let headline: String?
    public let severity: Severity
    public let isDismissible: Bool

    public init(message: String, headline: String? = nil, severity: Severity, isDismissible: Bool) {
        self.message = message
        self.headline = headline
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
                message: "L'audio sera enregistré mais pas transcrit : le CLI clew est absent. Restaurez-le, puis lancez ./rec.sh redo <répertoire> pour transcrire cette réunion depuis son audio conservé.",
                headline: "CLI absent : audio enregistré seulement",
                severity: .warning,
                isDismissible: false
            )
        }

        return nil
    }
}
