import Foundation

public struct AnchoringSummary: Equatable {
    public let anchored: Int
    public let total: Int

    public init(anchored: Int, total: Int) {
        self.anchored = anchored
        self.total = total
    }
}

public enum AnchoringSummaryCalculator {
    /// nil means anchoring has never run for this meeting (anchors.json absent, so every key point
    /// carries `anchors == nil`) — that must never render as a ratio, not even 0/N.
    public static func summary(for keyPoints: [KeyPointWithAnchors]) -> AnchoringSummary? {
        guard !keyPoints.isEmpty else { return nil }
        guard keyPoints.contains(where: { $0.anchors != nil }) else { return nil }

        let anchored = keyPoints.filter { keyPoint in
            if case .evidence = AnchorEvidenceDisplayModel.display(for: keyPoint) { return true }
            return false
        }.count

        return AnchoringSummary(anchored: anchored, total: keyPoints.count)
    }
}

public enum PointsClesCaption {
    public static func text(for summary: AnchoringSummary?) -> String {
        guard let summary else { return "Points clés" }
        return "Points clés · \(summary.anchored)/\(summary.total) ancrés"
    }
}

public enum AnchoringCalloutText {
    public static func text(for summary: AnchoringSummary) -> String {
        "\(summary.anchored) des \(summary.total) points clés sont ancrés dans le transcript. "
            + "Clique un point clé pour sauter à sa preuve."
    }
}
