import Foundation

public struct OwnscribeConfigReader {
    public static let defaultOutputDirName = "ownscribe"

    public static func resolvedOutputDir(configText: String?, homeDir: URL) -> URL {
        if let configText, let dir = parseOutputDir(fromTOML: configText) {
            return expand(path: dir, homeDir: homeDir)
        }
        return homeDir.appendingPathComponent(defaultOutputDirName)
    }

    static func parseOutputDir(fromTOML text: String) -> String? {
        var inOutputSection = false
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOutputSection = line == "[output]"
                continue
            }
            guard inOutputSection, let eqIndex = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
            guard key == "dir" else { continue }
            return valueAfterEquals(in: line)
        }
        return nil
    }

    private static func valueAfterEquals(in line: String) -> String? {
        guard let eqIndex = line.firstIndex(of: "=") else { return nil }
        var value = line[line.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)
        if let hashIndex = value.firstIndex(of: "#") {
            value = String(value[..<hashIndex]).trimmingCharacters(in: .whitespaces)
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    public static func expand(path: String, homeDir: URL) -> URL {
        if path.hasPrefix("~/") {
            return homeDir.appendingPathComponent(String(path.dropFirst(2)))
        }
        if path == "~" {
            return homeDir
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return homeDir.appendingPathComponent(path)
    }
}
