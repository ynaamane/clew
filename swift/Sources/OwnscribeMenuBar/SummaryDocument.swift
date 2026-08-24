import Foundation

public struct SummaryDocument: Equatable {
    public let prose: String
    public let keyPoints: [String]
    public let actionItems: [String]
    public let actionItemsPlaceholder: String

    public init(markdown: String) throws {
        var sections: [String: [String]] = [:]
        var current: String?

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                current = String(line.dropFirst(3)).lowercased()
                sections[current!] = []
                continue
            }
            if line.hasPrefix("#") || line.isEmpty { continue }
            if let key = current {
                sections[key, default: []].append(line)
            }
        }

        prose = (sections["summary"] ?? []).joined(separator: " ")
        keyPoints = Self.bullets(in: sections["key points"] ?? [])

        let actionLines = sections["action items"] ?? []
        actionItems = Self.bullets(in: actionLines)
        actionItemsPlaceholder = actionItems.isEmpty ? Self.stripBulletMarker(actionLines.first ?? "") : ""
    }

    public init(json data: Data) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "SummaryDocument", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }

        prose = json["summary"] as? String ?? ""
        keyPoints = json["key_points"] as? [String] ?? []
        let actionItemsArray = json["action_items"] as? [String] ?? []
        actionItems = actionItemsArray
        actionItemsPlaceholder = actionItemsArray.isEmpty ? "None mentioned." : ""
    }

    public init(contentsOf url: URL) throws {
        if url.pathExtension == "json" {
            try self.init(json: try Data(contentsOf: url))
        } else {
            try self.init(markdown: String(contentsOf: url, encoding: .utf8))
        }
    }

    private static let noneFamilyPlaceholders: Set<String> = [
        "none mentioned",
        "none noted",
        "none",
        "n/a",
        "na",
        "aucune mentionnée",
        "aucun mentionné",
        "aucune",
        "aucun",
    ]

    private static func stripBulletMarker(_ line: String) -> String {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return line }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func isNoneFamilyPlaceholder(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return noneFamilyPlaceholders.contains(normalized)
    }

    private static func bullets(in lines: [String]) -> [String] {
        lines.compactMap { line in
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { return nil }
            let text = stripBulletMarker(line)
            guard !isNoneFamilyPlaceholder(text) else { return nil }
            return text
        }
    }
}
