import Foundation

public struct OwnscribeBinaryResolver {
    // Matches the real, deliberately-unrenamed repo checkout directory name
    // (/Users/yanisnaamane/meeting-scribe stays meeting-scribe; only the product
    // and package are called clew now).
    public static let defaultRepoRelativePath = "meeting-scribe"

    public static func resolve(
        homeDir: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutableFile: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        if let overridePath = (environment["CLEW_BIN"] ?? environment["OWNSCRIBE_BIN"]), isExecutableFile(overridePath) {
            return URL(fileURLWithPath: overridePath)
        }

        let repoRoot = (environment["CLEW_REPO_ROOT"] ?? environment["OWNSCRIBE_REPO_ROOT"]).map { URL(fileURLWithPath: $0) }
            ?? homeDir.appendingPathComponent(defaultRepoRelativePath)
        let venvBin = repoRoot.appendingPathComponent(".venv/bin")
        // `clew` is the primary console script; `ownscribe` is kept as a muscle-memory
        // alias (same entry point) for a venv that hasn't been re-synced yet.
        let clewCandidate = venvBin.appendingPathComponent("clew")
        if isExecutableFile(clewCandidate.path) {
            return clewCandidate
        }
        let legacyCandidate = venvBin.appendingPathComponent("ownscribe")
        return isExecutableFile(legacyCandidate.path) ? legacyCandidate : nil
    }
}
