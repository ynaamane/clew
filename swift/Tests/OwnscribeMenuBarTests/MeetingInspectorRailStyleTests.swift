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

    private func lines() throws -> [String] {
        try source().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Returns the modifier lines chained directly onto the construct whose opening line contains
    /// `marker` — found by balancing braces from that line forward until they close, then collecting
    /// every subsequent line that starts with `.` (stopping at the first line that doesn't). A TARGET
    /// assertion: it names which construct a modifier attaches to, not merely what text sits near it.
    /// Mirrors GlassPlacementTests.modifierChain(attachedTo:in:) (LibraryWindow.swift) — kept as a
    /// separate copy in this file rather than shared, so this lane's guard never depends on another
    /// lane's test file surviving unchanged.
    private func modifierChain(attachedTo marker: String, in lines: [String]) -> [String] {
        guard let openIndex = lines.firstIndex(where: { $0.contains(marker) }) else {
            XCTFail("could not find a construct opening with '\(marker)'")
            return []
        }

        var balance = 0
        var closeIndex: Int?
        for index in openIndex..<lines.count {
            balance += lines[index].filter { $0 == "{" }.count
            balance -= lines[index].filter { $0 == "}" }.count
            if balance == 0 {
                closeIndex = index
                break
            }
        }

        guard let closeIndex else {
            XCTFail("construct opened by '\(marker)' never balances its braces")
            return []
        }

        var chain: [String] = []
        var index = closeIndex + 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(".") else { break }
            chain.append(trimmed)
            index += 1
        }
        return chain
    }

    func testGlassAttachesToTheContainerNotTheScrollView() throws {
        let all = try lines()

        let scrollChain = modifierChain(attachedTo: "ScrollView {", in: all)
        XCTAssertTrue(
            scrollChain.contains { $0.contains(".scrollContentBackground(.hidden)") },
            "The ScrollView must hide its own opaque background, or it paints in front of the "
                + "container's glass. Its own modifier chain: \(scrollChain)")
        XCTAssertFalse(
            scrollChain.contains { $0.contains(".glassEffect(") },
            "glassEffect must not be chained directly onto the ScrollView — that clips the glass to "
                + "the scrollable's own bounds, the exact anti-pattern that produced the sidebar's "
                + "deformed-oval rail when glass sat on its List. Its own modifier chain: \(scrollChain)")

        let containerChain = modifierChain(attachedTo: "ZStack {", in: all)
        XCTAssertTrue(
            containerChain.contains { $0.contains(".glassEffect(") },
            "glassEffect must be chained onto a container wrapping the ScrollView, not the "
                + "ScrollView itself. Container's own modifier chain: \(containerChain)")
        XCTAssertTrue(
            containerChain.contains { $0.contains(".glassEffect(") && $0.contains("in:") },
            "The container's glassEffect must pass an explicit shape (glassEffect(_:in:)) — the bare "
                + ".glassEffect() defaults to DefaultGlassEffectShape(), the same default that produced "
                + "the sidebar's deformed-oval rail. Container's own modifier chain: \(containerChain)")
        XCTAssertFalse(
            containerChain.contains { $0.contains(".background(.background)") },
            "background(.background) on the container would paint an opaque layer over its own glass.")
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
