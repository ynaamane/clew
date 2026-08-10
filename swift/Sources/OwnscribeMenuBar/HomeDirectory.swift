import Foundation

/// Resolves the directory the app treats as the user's home.
///
/// When `CLEW_HOME` is set and non-empty it overrides the account home. It
/// exists so demo, screenshot and test runs can point a real app instance at
/// an isolated data directory: `FileManager.homeDirectoryForCurrentUser`
/// ignores the `HOME` environment variable, so exporting `HOME` is not enough
/// to keep a launched app away from real user data.
public enum HomeDirectory {
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallback: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = activeOverride(environment: environment) {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return fallback
    }

    /// The CLEW_HOME override in effect, or nil. Callers that honor it must
    /// say so out loud (the app logs it at startup): pointing an instance at
    /// another home has to stay observable, never silent.
    public static func activeOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        guard let override = environment["CLEW_HOME"], !override.isEmpty else { return nil }
        return override
    }
}
