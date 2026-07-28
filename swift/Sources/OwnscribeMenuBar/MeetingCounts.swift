import Foundation

public struct MeetingCounts {
    public static func compute(
        summaryDirectory: URL,
        fileManager: FileManager = .default
    ) -> (actionItemCount: Int?, unanchoredClaimCount: Int?) {
        let summaryURL = summaryDirectory.appendingPathComponent("summary.md")
        let anchorsURL = summaryDirectory.appendingPathComponent("anchors.json")

        guard fileManager.fileExists(atPath: summaryURL.path) else {
            return (nil, nil)
        }

        let actionCount = countActionItems(summaryURL: summaryURL)
        let unanchoredCount = countUnanchoredClaims(
            summaryURL: summaryURL,
            anchorsURL: anchorsURL,
            fileManager: fileManager
        )

        return (actionCount, unanchoredCount)
    }

    private static func countActionItems(summaryURL: URL) -> Int? {
        guard let summary = try? SummaryDocument(contentsOf: summaryURL) else {
            return nil
        }
        return summary.actionItems.count
    }

    private static func countUnanchoredClaims(
        summaryURL: URL,
        anchorsURL: URL,
        fileManager: FileManager
    ) -> Int? {
        guard fileManager.fileExists(atPath: anchorsURL.path) else {
            return nil
        }

        guard let summary = try? SummaryDocument(contentsOf: summaryURL),
              let anchorsData = try? Data(contentsOf: anchorsURL),
              let json = try? JSONSerialization.jsonObject(with: anchorsData) as? [String: Any],
              let anchorsDict = json["anchors"] as? [String: [[String: Any]]] else {
            return nil
        }

        let anchoredTokens = Set(anchorsDict.keys)

        var unanchoredCount = 0
        for keyPoint in summary.keyPoints {
            if !hasAnchoredToken(in: keyPoint, anchoredTokens: anchoredTokens) {
                unanchoredCount += 1
            }
        }

        return unanchoredCount
    }

    private static func hasAnchoredToken(in text: String, anchoredTokens: Set<String>) -> Bool {
        let lowercaseAnchors = Set(anchoredTokens.map { $0.lowercased() })
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for word in words {
            let normalized = String(word).lowercased()
            if lowercaseAnchors.contains(normalized) {
                return true
            }
        }
        return false
    }
}
