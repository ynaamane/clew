import Foundation

public struct MeetingCounts {
    public static func compute(
        summaryDirectory: URL,
        configURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> (actionItemCount: Int?, unanchoredClaimCount: Int?) {
        let resolvedConfigURL: URL
        if let configURL {
            resolvedConfigURL = configURL
        } else {
            let homeDir = fileManager.homeDirectoryForCurrentUser
            resolvedConfigURL = homeDir.appendingPathComponent(".config/ownscribe/config.toml")
        }

        guard let summary = MeetingInspectorState.loadSummary(
            from: summaryDirectory,
            configURL: resolvedConfigURL,
            fileManager: fileManager
        ) else {
            return (nil, nil)
        }

        let anchorsURL = summaryDirectory.appendingPathComponent("anchors.json")
        let actionCount = summary.actionItems.count
        let unanchoredCount = countUnanchoredClaims(
            summary: summary,
            anchorsURL: anchorsURL,
            fileManager: fileManager
        )

        return (actionCount, unanchoredCount)
    }

    private static func countUnanchoredClaims(
        summary: SummaryDocument,
        anchorsURL: URL,
        fileManager: FileManager
    ) -> Int? {
        guard let anchors = AnchorsReader.loadAnchors(from: anchorsURL, fileManager: fileManager) else {
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
