enum UnanchoredClaimBadge: Equatable {
    case neverChecked
    case allAnchored
    case unanchored(count: Int)

    static func state(unanchoredClaimCount: Int?) -> UnanchoredClaimBadge {
        guard let count = unanchoredClaimCount else { return .neverChecked }
        guard count > 0 else { return .allAnchored }
        return .unanchored(count: count)
    }

    var rowText: String? {
        switch self {
        case .neverChecked: return "non vérifiée"
        case .allAnchored: return nil
        case .unanchored(let count): return count == 1 ? "1 non ancré" : "\(count) non ancrés"
        }
    }
}
