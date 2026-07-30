import Foundation

public struct BadgeText {
    public static func badgeText(for item: LibrarySidebarItem) -> String? {
        guard let count = item.count else {
            return nil
        }
        guard item.hasUnknowns else { return String(count) }
        return count > 0 ? "\(count)+" : nil
    }
}
