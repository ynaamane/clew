import Foundation

public struct OwnscribeConfigWriter {
    private static let audioSectionHeader = "[audio]"
    private static let micKey = "mic"
    private static let silenceTimeoutKey = "silence_timeout"
    private static let defaultSilenceTimeoutSeconds: TimeInterval = 300
    private static let maxSilenceTimeoutSeconds: TimeInterval = 86_400
    private static let ownerOnlyFileMode = NSNumber(value: UInt16(0o600))
    private static let ownerOnlyDirectoryMode = NSNumber(value: UInt16(0o700))

    public static func defaultConfigURL(
        homeDir: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDir.appendingPathComponent(".config/ownscribe/config.toml")
    }

    public static func applyingAudioSettings(_ settings: AudioSettings, to configText: String) -> String {
        var lines = configText.components(separatedBy: "\n")
        let assignments = [
            (micKey, settings.mic ? "true" : "false"),
            (silenceTimeoutKey, silenceTimeoutLiteral(settings.silenceTimeout)),
        ]

        guard let sectionRange = audioSectionRange(in: lines) else {
            return appendingAudioSection(assignments, to: lines)
        }

        var missingAssignments: [(String, String)] = []
        for (key, value) in assignments {
            if let existingIndex = indexOfAssignment(key: key, in: lines, sectionRange: sectionRange) {
                lines[existingIndex] = rewriting(line: lines[existingIndex], toValue: value)
            } else {
                missingAssignments.append((key, value))
            }
        }

        guard !missingAssignments.isEmpty else { return lines.joined(separator: "\n") }

        let insertionIndex = insertionIndexInSection(sectionRange, of: lines)
        lines.insert(contentsOf: missingAssignments.map { "\($0.0) = \($0.1)" }, at: insertionIndex)
        return lines.joined(separator: "\n")
    }

    public static func writeAudioSettings(
        _ settings: AudioSettings,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        let existingText = try? String(contentsOf: url, encoding: .utf8)
        let existingMode = (try? fileManager.attributesOfItem(atPath: url.path))
            .flatMap { $0[.posixPermissions] as? NSNumber }

        let updatedText = applyingAudioSettings(settings, to: existingText ?? "")

        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: ownerOnlyDirectoryMode])
        }

        try Data(updatedText.utf8).write(to: url, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: existingMode ?? ownerOnlyFileMode],
            ofItemAtPath: url.path)
    }

    public static func readAudioSettings(from url: URL) -> AudioSettings {
        let configText = try? String(contentsOf: url, encoding: .utf8)
        return OwnscribeConfigReader.parseAudioSettings(fromTOML: configText)
    }

    private static func silenceTimeoutLiteral(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return String(Int(defaultSilenceTimeoutSeconds)) }
        let bounded = min(max(seconds.rounded(), 0), maxSilenceTimeoutSeconds)
        return String(Int(bounded))
    }

    private static func audioSectionRange(in lines: [String]) -> Range<Int>? {
        guard let headerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == audioSectionHeader
        }) else {
            return nil
        }

        var endIndex = lines.count
        for index in (headerIndex + 1)..<lines.count
        where lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
            endIndex = index
            break
        }
        return headerIndex..<endIndex
    }

    private static func indexOfAssignment(key: String, in lines: [String], sectionRange: Range<Int>) -> Int? {
        sectionRange.dropFirst().first { assignedKey(in: lines[$0]) == key }
    }

    private static func insertionIndexInSection(_ sectionRange: Range<Int>, of lines: [String]) -> Int {
        var index = sectionRange.upperBound
        while index > sectionRange.lowerBound + 1,
              lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            index -= 1
        }
        return index
    }

    private static func assignedKey(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("#"), let equalsIndex = trimmed.firstIndex(of: "=") else { return nil }
        return String(trimmed[..<equalsIndex]).trimmingCharacters(in: .whitespaces)
    }

    private static func rewriting(line: String, toValue value: String) -> String {
        guard let equalsIndex = line.firstIndex(of: "=") else { return line }

        let head = String(line[...equalsIndex])
        let tail = line[line.index(after: equalsIndex)...]
        let commentIndex = tail.firstIndex(of: "#")
        let valueRegion = commentIndex.map { tail[..<$0] } ?? tail[...]
        let comment = commentIndex.map { String(tail[$0...]) } ?? ""

        let leadingGap = leadingHorizontalWhitespace(of: valueRegion)
        let trailingGap = comment.isEmpty ? "" : trailingHorizontalWhitespace(of: valueRegion)

        return head + (leadingGap.isEmpty ? " " : leadingGap) + value + trailingGap + comment
    }

    private static func leadingHorizontalWhitespace(of text: Substring) -> String {
        String(text.prefix(while: isHorizontalWhitespace))
    }

    private static func trailingHorizontalWhitespace(of text: Substring) -> String {
        String(text.reversed().prefix(while: isHorizontalWhitespace))
    }

    private static func isHorizontalWhitespace(_ character: Character) -> Bool {
        character == " " || character == "\t"
    }

    private static func appendingAudioSection(_ assignments: [(String, String)], to lines: [String]) -> String {
        var result = lines
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        if !result.isEmpty {
            result.append("")
        }
        result.append(audioSectionHeader)
        result.append(contentsOf: assignments.map { "\($0.0) = \($0.1)" })
        result.append("")
        return result.joined(separator: "\n")
    }
}
