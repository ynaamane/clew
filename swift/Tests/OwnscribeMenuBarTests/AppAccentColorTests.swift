import XCTest
import SwiftUI
@testable import OwnscribeMenuBar

final class AppAccentColorTests: XCTestCase {
    func testAppAccentIsPurple() {
        XCTAssertEqual(
            AppAccentColor.color, .purple,
            "design/direction-b-glass.png, the validated mockup, is purple throughout (selection, pills, envelope, timestamps); mockup.html's blue predates it and lost.")
    }

    private func lines(_ name: String) throws -> [String] {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OwnscribeMenuBar/\(name)"),
            encoding: .utf8
        ).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    func testTintAppliesToTheWholeSplitViewNotOneColumn() throws {
        let all = try lines("LibraryWindow.swift")

        guard let titleIndex = all.firstIndex(where: { $0.contains(".navigationTitle(\"Réunions\")") }) else {
            XCTFail("could not find .navigationTitle(\"Réunions\") — this test anchors on it to confirm .tint sits at the same NavigationSplitView level")
            return
        }
        guard let tintIndex = all.firstIndex(where: { $0.contains(".tint(AppAccentColor.color)") }) else {
            XCTFail("LibraryWindow does not apply .tint(AppAccentColor.color) — the validated design is purple throughout and the app currently declares no accent at all, which falls back to system blue")
            return
        }

        let titleIndent = all[titleIndex].prefix { $0 == " " }
        let tintIndent = all[tintIndex].prefix { $0 == " " }
        XCTAssertEqual(
            tintIndent.count, titleIndent.count,
            ".tint must be chained at the same level as .navigationTitle — on the whole NavigationSplitView, not nested inside one column, or it would not reach the sidebar's selection highlight and the row pills")
    }
}
