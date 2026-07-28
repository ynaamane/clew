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
        guard let summary = try? SummaryDocument(contentsOf: summaryURL),
              let anchors = AnchorsReader.loadAnchors(from: anchorsURL, fileManager: fileManager) else {
            return nil
        }

        var unanchoredCount = 0
        for keyPoint in summary.keyPoints {
            if !AnchorsReader.hasAnchoredToken(in: keyPoint, anchors: anchors) {
                unanchoredCount += 1
            }
        }

        return unanchoredCount
    }
}
