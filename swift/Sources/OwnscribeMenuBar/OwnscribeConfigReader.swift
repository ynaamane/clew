import Foundation

public struct AudioSettings {
    public var mic: Bool
    public var silenceTimeout: TimeInterval
}

public struct OutputSettings {
    public var format: String
}

public struct OwnscribeConfigReader {
    public static let defaultOutputDirName = "ownscribe"

    public static func resolvedOutputDir(configText: String?, homeDir: URL) -> URL {
        if let configText, let dir = parseOutputDir(fromTOML: configText) {
            return expand(path: dir, homeDir: homeDir)
        }
        return homeDir.appendingPathComponent(defaultOutputDirName)
    }

    public static func parseAudioSettings(fromTOML text: String?) -> AudioSettings {
        guard let text else {
            return AudioSettings(mic: true, silenceTimeout: 300)
        }

        var mic: Bool?
        var silenceTimeout: TimeInterval?
        var inAudioSection = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inAudioSection = line == "[audio]"
                continue
            }
            guard inAudioSection, let eqIndex = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)

            if key == "mic" {
                if let value = valueAfterEquals(in: line) {
                    if value == "true" {
                        mic = true
                    } else if value == "false" {
                        mic = false
                    }
                }
            } else if key == "silence_timeout" {
                if let value = valueAfterEquals(in: line), let intValue = Int(value) {
                    silenceTimeout = TimeInterval(intValue)
                }
            }
        }

        return AudioSettings(
            mic: mic ?? true,
            silenceTimeout: silenceTimeout ?? 300
        )
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
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    public static func parseOutputSettings(fromTOML text: String?) -> OutputSettings {
        guard let text else {
            return OutputSettings(format: "markdown")
        }

        var format: String?
        var inOutputSection = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inOutputSection = line == "[output]"
                continue
            }
            guard inOutputSection, let eqIndex = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)

            if key == "format" {
                if let value = valueAfterEquals(in: line) {
                    format = value
                }
            }
        }

        return OutputSettings(format: format ?? "markdown")
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
