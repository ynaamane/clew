import XCTest
@testable import OwnscribeMenuBar

final class SearchPlacementDecisionTests: XCTestCase {
    private func source(_ name: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OwnscribeMenuBar/\(name)"),
            encoding: .utf8)
    }

    func testTheLibraryKeepsSystemSearchRatherThanAHandRolledHeaderField() throws {
        let window = try source("LibraryWindow.swift")

        XCTAssertTrue(
            window.contains(".searchable(text:"),
            "The mockup draws search inside the list header (mockup.html:267-269, .list-hdr). Matching it means DROPPING .searchable for a plain TextField, which costs ⌘F, the system clear button, the find-bar focus ring and VoiceOver's search rotor. That trade was evaluated and declined: the toolbar is where macOS puts search (Mail, Notes, Finder), and this window is read the morning after a call, when reaching for ⌘F is the reflex. If you reverse this, reverse it deliberately — not while chasing a placement argument, which cannot work: see testTheSearchPlacementArgumentIsNotTheLeverItLooksLike.")
    }

    func testTheSearchPlacementArgumentIsNotTheLeverItLooksLike() throws {
        let window = try source("LibraryWindow.swift")

        XCTAssertTrue(
            window.contains("placement: .toolbar"),
            "On macOS NavigationSplitView a .searchable field lands in the window toolbar whatever placement you pass. MEASURED: .toolbar, .sidebar and .automatic rendered BYTE-IDENTICAL output off-screen (55218 bytes ×3). CONFIRMED against the SDK: SearchToolbarBehavior.minimize is @available(macOS, unavailable), so .automatic is the only value this platform accepts — there is no API lever. Changing this argument is a no-op that reads like a fix, so it stays pinned at the placement that says what actually happens.")
    }

    func testTheWindowNamesItselfOnceSoTheTitleCannotDisagreeWithItself() throws {
        let window = try source("LibraryWindow.swift")
        let titles = window.components(separatedBy: ".navigationTitle(").count - 1

        XCTAssertEqual(
            titles, 1,
            "Two .navigationTitle(\"Réunions\") calls existed — one on the NavigationSplitView and one on the content column inside it — so the same string was declared in two places that are free to drift. The split view's own title is the one the window chrome shows; the column's was redundant. One declaration, one source of truth.")
    }
}
