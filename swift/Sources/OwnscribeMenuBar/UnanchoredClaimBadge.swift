enum UnanchoredClaimBadge: Equatable {
    case neverChecked
    case allAnchored
    case unanchored(String)

    static func state(unanchoredClaimCount: Int?) -> UnanchoredClaimBadge {
        guard let count = unanchoredClaimCount else { return .neverChecked }
        guard count > 0 else { return .allAnchored }
        return .unanchored("^[\(count) non ancré](inflect: true)")
    }

    var rowText: String? {
        switch self {
        case .neverChecked: return "non vérifiée"
        case .allAnchored: return nil
        case .unanchored(let text): return text
        }
    }
}
