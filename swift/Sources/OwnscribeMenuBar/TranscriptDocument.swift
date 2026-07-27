import Foundation

public struct Utterance: Identifiable, Equatable {
    public let id = UUID()
    public let speaker: String
    public let start: TimeInterval
    public let text: String

    public var isBackchannel: Bool {
        text.split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" }).count <= 3
    }

    public var timecode: String {
        let total = Int(start.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

public struct TranscriptDocument: Equatable {
    public let language: String
    public let duration: TimeInterval
    public let utterances: [Utterance]

    public var speakers: [String] {
        var seen: Set<String> = []
        return utterances.compactMap { seen.insert($0.speaker).inserted ? $0.speaker : nil }
    }

    public init(markdown: String) throws {
        var language = ""
        var duration: TimeInterval = 0
        var parsed: [Utterance] = []
        var speaker = "Unknown"
        var headerTimestamp: TimeInterval?

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let value = Self.metadataValue(in: line, key: "Language") {
                language = value
                continue
            }
            if let value = Self.metadataValue(in: line, key: "Duration") {
                duration = Self.seconds(fromTimecode: value) ?? 0
                continue
            }
            if let header = Self.speakerHeader(in: line) {
                speaker = header.speaker
                headerTimestamp = header.start
                continue
            }
            if let stamped = Self.timestampedUtterance(in: line) {
                parsed.append(Utterance(speaker: speaker, start: stamped.start, text: stamped.text))
                headerTimestamp = nil
                continue
            }
            if line.hasPrefix("#") || line.hasPrefix("**") { continue }
            if let inherited = headerTimestamp {
                parsed.append(Utterance(speaker: speaker, start: inherited, text: line))
                headerTimestamp = nil
            }
        }

        self.language = language
        self.duration = duration
        self.utterances = parsed
    }

    public init(contentsOf url: URL) throws {
        try self.init(markdown: String(contentsOf: url, encoding: .utf8))
    }

    private static func metadataValue(in line: String, key: String) -> String? {
        let marker = "**\(key):**"
        guard line.hasPrefix(marker) else { return nil }
        return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func speakerHeader(in line: String) -> (speaker: String, start: TimeInterval)? {
        guard line.hasPrefix("**"), let closing = line.range(of: "**", range: line.index(line.startIndex, offsetBy: 2)..<line.endIndex) else {
            return nil
        }
        let name = String(line[line.index(line.startIndex, offsetBy: 2)..<closing.lowerBound])
        guard !name.hasSuffix(":") else { return nil }
        let remainder = String(line[closing.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard let stamp = bracketedTimecode(at: remainder), stamp.rest.isEmpty else { return nil }
        return (name, stamp.start)
    }

    private static func timestampedUtterance(in line: String) -> (start: TimeInterval, text: String)? {
        guard let stamp = bracketedTimecode(at: line), !stamp.rest.isEmpty else { return nil }
        return (stamp.start, stamp.rest)
    }

    private static func bracketedTimecode(at line: String) -> (start: TimeInterval, rest: String)? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return nil }
        let inside = String(line[line.index(after: line.startIndex)..<close])
        guard let start = seconds(fromTimecode: inside) else { return nil }
        let rest = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        return (start, rest)
    }

    private static func seconds(fromTimecode text: String) -> TimeInterval? {
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count >= 2, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return parts.reduce(0) { $0 * 60 + TimeInterval(Int($1)!) }
    }
}
