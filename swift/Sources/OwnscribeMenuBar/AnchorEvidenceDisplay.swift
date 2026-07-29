import Foundation

public struct AnchorEvidenceChip: Equatable {
    public let token: String
    public let timestamp: String

    public init(token: String, timestamp: String) {
        self.token = token
        self.timestamp = timestamp
    }

    public var label: String { "\(token)→\(timestamp)" }
}

public enum AnchorEvidenceDisplay: Equatable {
    case notYetVerified
    case noEvidenceFound
    case evidence([AnchorEvidenceChip])

    public var placeholderText: String? {
        switch self {
        case .notYetVerified: return "(pas encore vérifié)"
        case .noEvidenceFound: return "—"
        case .evidence: return nil
        }
    }

    public var chips: [AnchorEvidenceChip] {
        switch self {
        case .evidence(let chips): return chips
        case .notYetVerified, .noEvidenceFound: return []
        }
    }
}

public struct AnchorEvidenceDisplayModel {
    public static func display(for keyPoint: KeyPointWithAnchors) -> AnchorEvidenceDisplay {
        guard let anchors = keyPoint.anchors else { return .notYetVerified }

        let chips = anchors.keys.sorted().compactMap { token -> AnchorEvidenceChip? in
            guard let first = anchors[token]?.first else { return nil }
            return AnchorEvidenceChip(token: token, timestamp: first.timestamp)
        }

        return chips.isEmpty ? .noEvidenceFound : .evidence(chips)
    }
}
