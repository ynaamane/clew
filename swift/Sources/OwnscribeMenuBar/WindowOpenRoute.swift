import Foundation

public struct WindowOpenRoute {
    public static let scheme = "ownscribe"

    public static func scene(for url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }

        let destination = (url.host?.isEmpty == false ? url.host : url.pathComponents.last { $0 != "/" })

        switch destination?.lowercased() {
        case "library": return LibraryWindow.sceneID
        default: return nil
        }
    }
}
