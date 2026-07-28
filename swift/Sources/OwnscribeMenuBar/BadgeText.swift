import Foundation

public struct BadgeText {
    public static func badgeText(for item: LibrarySidebarItem) -> String? {
        guard let count = item.count else {
            return nil
        }
        return String(count)
    }
}
