enum UnanchoredClaimBadge {
    static func badge(unanchoredClaimCount: Int?) -> String? {
        guard let count = unanchoredClaimCount, count > 0 else {
            return nil
        }
        return "^[\(count) non ancré](inflect: true)"
    }
}
