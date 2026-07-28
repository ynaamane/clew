import Foundation

public struct TokenAnchor: Equatable {
    public let timestamp: String
    public let context: String

    public init(timestamp: String, context: String) {
        self.timestamp = timestamp
        self.context = context
    }
}

public struct AnchorsReader {
    public static func loadAnchors(
        from url: URL,
        fileManager: FileManager = .default
    ) -> [String: [TokenAnchor]]? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let anchorsDict = json["anchors"] as? [String: [[String: Any]]] else {
            return nil
        }

        var result: [String: [TokenAnchor]] = [:]
        for (token, occurrences) in anchorsDict {
            result[token] = occurrences.compactMap { occurrence in
                guard let timestamp = occurrence["timestamp"] as? String,
                      let context = occurrence["context"] as? String else {
                    return nil
                }
                return TokenAnchor(timestamp: timestamp, context: context)
            }
        }

        return result
    }

    public static func findAnchorsForText(
        _ text: String,
        in anchors: [String: [TokenAnchor]]
    ) -> [String: [TokenAnchor]] {
        var matches: [String: [TokenAnchor]] = [:]

        for (token, occurrences) in anchors {
            if hasToken(token, in: text) {
                matches[token] = occurrences
            }
        }

        return matches
    }

    public static func hasAnchoredToken(
        in text: String,
        anchors: [String: [TokenAnchor]]
    ) -> Bool {
        for token in anchors.keys {
            if hasToken(token, in: text) {
                return true
            }
        }
        return false
    }

    private static func hasToken(_ token: String, in text: String) -> Bool {
        let lowercaseToken = token.lowercased()
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for word in words {
            if String(word).lowercased() == lowercaseToken {
                return true
            }
        }
        return false
    }
}
