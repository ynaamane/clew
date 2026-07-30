import Foundation

public enum LibraryFilter: Hashable {
    case all
    case withActions
    case unanchored
    case notIndexed
    case speaker(String)
    case enroll

    public func apply(to meetings: [MeetingSummary]) -> [MeetingSummary] {
        switch self {
        case .all, .enroll:
            return meetings
        case .withActions:
            return meetings.filter { ($0.actionItemCount ?? 0) > 0 }
        case .unanchored:
            return meetings.filter { ($0.unanchoredClaimCount ?? 0) > 0 }
        case .notIndexed:
            return meetings.filter { !$0.hasSummary }
        case .speaker:
            return meetings
        }
    }

    public var symbolName: String {
        switch self {
        case .all: return "square.stack"
        case .withActions: return "star"
        case .unanchored: return "flag"
        case .notIndexed: return "slash.circle"
        case .speaker: return "circle.circle"
        case .enroll: return "plus"
        }
    }
}

public struct LibrarySidebarItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let filter: LibraryFilter
    public let count: Int?
    public let hasUnknowns: Bool
    public let children: [LibrarySidebarItem]

    public var speakerName: String? {
        if case .speaker(let name) = filter { return name }
        return nil
    }
}

public struct LibrarySidebarSection: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let items: [LibrarySidebarItem]
}

public struct LibrarySidebar {
    public static func sections(
        for meetings: [MeetingSummary],
        enrolledSpeakers: [String]
    ) -> [LibrarySidebarSection] {
        let allHaveActionData = meetings.allSatisfy { $0.actionItemCount != nil }
        let allHaveAnchoringData = meetings.allSatisfy { $0.unanchoredClaimCount != nil }

        let library = [
            item("all", "Toutes", .all, LibraryFilter.all.apply(to: meetings).count, false),
            item("actions", "Actions", .withActions, LibraryFilter.withActions.apply(to: meetings).count, !allHaveActionData),
            item("unanchored", "Ancres", .unanchored, LibraryFilter.unanchored.apply(to: meetings).count, !allHaveAnchoringData),
            item("notIndexed", "Sans index", .notIndexed, LibraryFilter.notIndexed.apply(to: meetings).count, false),
        ]

        let people = enrolledSpeakers.map { name in
            item("speaker-\(name)", name, .speaker(name), nil, false)
        } + [item("enroll", "Enrôler…", .enroll, nil, false)]

        return [
            LibrarySidebarSection(id: "library", title: "Bibliothèque", items: library),
            LibrarySidebarSection(id: "people", title: "Personnes", items: people),
        ]
    }

    private static func item(_ id: String, _ title: String, _ filter: LibraryFilter, _ count: Int?, _ hasUnknowns: Bool) -> LibrarySidebarItem {
        LibrarySidebarItem(id: id, title: title, filter: filter, count: count, hasUnknowns: hasUnknowns, children: [])
    }
}
