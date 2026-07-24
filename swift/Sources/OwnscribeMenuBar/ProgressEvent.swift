import Foundation

public struct ProgressEvent: Decodable, Equatable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case begin, complete, fail, update, detail
    }

    public let event: Kind
    public let step: String
    public let fraction: Double?
    public let detail: String?

    public init(event: Kind, step: String, fraction: Double? = nil, detail: String? = nil) {
        self.event = event
        self.step = step
        self.fraction = fraction
        self.detail = detail
    }
}

public enum ProgressEventParser {
    public static func parse(line: String) -> ProgressEvent? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ProgressEvent.self, from: data)
    }
}

public final class NDJSONLineBuffer {
    private var buffer = ""

    public init() {}

    public func feed(_ chunk: String) -> [String] {
        buffer += chunk
        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            lines.append(String(buffer[buffer.startIndex..<newlineIndex]))
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
        }
        return lines
    }
}
