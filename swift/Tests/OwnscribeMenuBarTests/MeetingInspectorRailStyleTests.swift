import XCTest
@testable import OwnscribeMenuBar

final class MeetingInspectorRailStyleTests: XCTestCase {
    private func source() throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OwnscribeMenuBar/MeetingInspector.swift"),
            encoding: .utf8)
    }

    func testTheInsetGroupedBoxesAreGoneInFavourOfAFlatRail() throws {
        let text = try source()

        XCTAssertFalse(
            text.contains(".formStyle(.grouped)"),
            "formStyle(.grouped) draws the inset boxes the mockup's flat rail does not have")
    }

    func testSectionCaptionsAreUppercaseAndTracked() throws {
        let text = try source()

        XCTAssertTrue(
            text.contains(".tracking("),
            "The mockup's section captions are letter-spaced (uppercase tracked caption2); "
                + "a bare Text(title) without .tracking() is not that treatment")
    }

    func testKeyPointsHeaderUsesTheSharedRatioFormatterNotAHardcodedString() throws {
        let text = try source()

        XCTAssertTrue(
            text.contains("PointsClesCaption.text(for:"),
            "\"Points clés · N/M ancrés\" must come from the same formatter MeetingDetailView's callout is built "
                + "from, so the ratio and the callout can never show different numbers for the same meeting")
    }

    func testEvidenceChipTimestampIsMonospacedAndUsesTheAmbientTint() throws {
        let text = try source()

        XCTAssertTrue(
            text.contains(".monospacedDigit()"),
            "The evidence chip's timestamp must line up in a table-like column, which needs monospaced digits")
        XCTAssertTrue(
            text.contains(".tint"),
            "The chip must resolve to whatever tint the app sets (LibraryWindow's .tint()), never a literal "
                + "Color — hardcoding one here would silently diverge from the accent-color ruling made elsewhere")
        XCTAssertFalse(
            text.contains("foregroundStyle(.blue)") || text.contains("foregroundStyle(Color.blue)")
                || text.contains("foregroundStyle(.purple)") || text.contains("foregroundStyle(Color.purple)"),
            "A literal accent color here would silently diverge from the one true tint decision")
    }

    func testInspectorFormIdentifierSurvivesTheRailRewrite() throws {
        let text = try source()

        XCTAssertTrue(
            text.contains(".accessibilityIdentifier(\"inspector.form\")"),
            "AccessibilityIdentifierTests pins this identifier; renaming the container must not silently drop it")
    }
}
