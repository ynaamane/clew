import XCTest
@testable import OwnscribeMenuBar

/// Source guards for LibraryWindow.swift render-site wiring that a view-host test cannot reach
/// (swift-suite-hygiene.md: "A view-host test is not the only way to reach a render"). Each of
/// these pins a call site to a pure function that already has its own direct unit tests
/// (MeetingRowMetaTests, LibraryNavigationSubtitleTests, MeetingStatusBadgeTests) — the risk this
/// guards against is the tested helper going uncalled, not the helper itself being wrong
/// (swift-suite-hygiene.md: "Tested helper, untested call site").
final class LibraryWindowRenderTests: XCTestCase {
    private func source() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OwnscribeMenuBar/LibraryWindow.swift"),
            encoding: .utf8)
    }

    func testRowUsesMeetingRowMetaRatherThanTheBareDate() throws {
        let all = try source()

        XCTAssertTrue(
            all.contains("MeetingRowMeta.text("),
            "MeetingRow must call MeetingRowMeta.text(...) to show date · duration · voice count, not just meeting.displayDate")
        XCTAssertFalse(
            all.contains("Text(meeting.displayDate)"),
            "the bare date Text must be replaced by the composed row meta line")
    }

    func testNotIndexedRendersAsAPillNotBareText() throws {
        let all = try source()

        XCTAssertTrue(
            all.contains("MeetingStatusBadge(variant: .notIndexed)"),
            "\"non indexée\" must render as the grey MeetingStatusBadge pill, consistent with its two sibling pills, not a bare secondary Text")
        XCTAssertFalse(
            all.contains("Text(\"non indexée\")"),
            "the bare-Text rendering of \"non indexée\" must be gone once the pill replaces it")
    }

    func testNavigationSubtitleAggregateIsWired() throws {
        let all = try source()

        XCTAssertTrue(
            all.contains(".navigationSubtitle("),
            "the title bar must carry a .navigationSubtitle aggregate like the mockup's \"42 réunions · 18 h 12 min\"")
        XCTAssertTrue(
            all.contains("LibraryNavigationSubtitle.text("),
            "the subtitle must be composed by LibraryNavigationSubtitle.text, not a hand-rolled string at the call site")
    }

    func testWindowBackgroundUsesASemanticDynamicColorNeverAHardcodedAppearance() throws {
        let all = try source()

        XCTAssertTrue(
            all.contains(".windowBackgroundColor"),
            "the window-level background must use the semantic system color (NSColor.windowBackgroundColor) so it tracks the user's light/dark setting automatically, per mockup.html's --bg-window token")
        XCTAssertFalse(
            all.contains("preferredColorScheme"),
            "CLAUDE.md: hardcoding an appearance would override the user's auto light/dark switch — already struck once in TODO.md item 6")
    }
}
