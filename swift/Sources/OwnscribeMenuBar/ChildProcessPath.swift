import Foundation

public struct ChildProcessPath {
    static let toolDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    public static func resolve(
        inheritedPath: String,
        directoryHasExecutables: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> String {
        var directories = inheritedPath.split(separator: ":").map(String.init)

        for directory in toolDirectories
        where directoryHasExecutables(directory) && !directories.contains(directory) {
            directories.append(directory)
        }

        return directories.joined(separator: ":")
    }
}
