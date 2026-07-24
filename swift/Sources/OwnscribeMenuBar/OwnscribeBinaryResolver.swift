import Foundation

public struct OwnscribeBinaryResolver {
    public static let defaultRepoRelativePath = "meeting-scribe"

    public static func resolve(
        homeDir: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutableFile: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        if let overridePath = environment["OWNSCRIBE_BIN"], isExecutableFile(overridePath) {
            return URL(fileURLWithPath: overridePath)
        }

        let repoRoot = environment["OWNSCRIBE_REPO_ROOT"].map { URL(fileURLWithPath: $0) }
            ?? homeDir.appendingPathComponent(defaultRepoRelativePath)
        let candidate = repoRoot.appendingPathComponent(".venv/bin/ownscribe")
        return isExecutableFile(candidate.path) ? candidate : nil
    }
}
