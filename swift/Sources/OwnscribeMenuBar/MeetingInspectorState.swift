import Foundation

public struct KeyPointWithAnchors: Equatable {
    public let text: String
    public let anchors: [String: [TokenAnchor]]

    public init(text: String, anchors: [String: [TokenAnchor]]) {
        self.text = text
        self.anchors = anchors
    }
}

public struct MeetingInspectorState {
    public static func loadSummary(
        from directory: URL,
        configURL: URL,
        fileManager: FileManager = .default
    ) -> SummaryDocument? {
        let configText = try? String(contentsOf: configURL, encoding: .utf8)
        let outputSettings = OwnscribeConfigReader.parseOutputSettings(fromTOML: configText)

        let filename = outputSettings.format == "json" ? "summary.json" : "summary.md"
        let summaryURL = directory.appendingPathComponent(filename)

        return try? SummaryDocument(contentsOf: summaryURL)
    }

    public static func loadKeyPointsWithAnchors(
        from directory: URL,
        configURL: URL,
        fileManager: FileManager = .default
    ) -> [KeyPointWithAnchors]? {
        guard let summary = loadSummary(from: directory, configURL: configURL, fileManager: fileManager) else {
            return nil
        }

        let anchorsURL = directory.appendingPathComponent("anchors.json")
        let allAnchors = AnchorsReader.loadAnchors(from: anchorsURL, fileManager: fileManager) ?? [:]

        return summary.keyPoints.map { keyPoint in
            let matchingAnchors = AnchorsReader.findAnchorsForText(keyPoint, in: allAnchors)
            return KeyPointWithAnchors(text: keyPoint, anchors: matchingAnchors)
        }
    }

    public static func loadKeyPointsWithAnchors(
        from directory: URL,
        fileManager: FileManager = .default
    ) -> [KeyPointWithAnchors]? {
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let configURL = homeDir.appendingPathComponent(".config/ownscribe/config.toml")
        return loadKeyPointsWithAnchors(from: directory, configURL: configURL, fileManager: fileManager)
    }
}
