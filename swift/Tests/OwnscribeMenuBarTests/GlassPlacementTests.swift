import XCTest
@testable import OwnscribeMenuBar

final class GlassPlacementTests: XCTestCase {
    private func source(_ name: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OwnscribeMenuBar/\(name)"),
            encoding: .utf8)
    }

    private func lines(_ name: String) throws -> [String] {
        try source(name).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Returns the modifier lines chained directly onto the construct whose opening line
    /// contains `marker` — found by balancing braces from that line forward until they close,
    /// then collecting every subsequent line that starts with `.` (stopping at the first line
    /// that doesn't). This is a TARGET assertion: it names which construct a modifier attaches
    /// to, rather than merely checking what text sits near it.
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

    func testSidebarGlassAttachesToTheZStackContainerNotTheList() throws {
        let all = try lines("LibraryWindow.swift")

        let listChain = modifierChain(attachedTo: "List(selection: $selectedFilter)", in: all)
        XCTAssertTrue(
            listChain.contains { $0.contains(".scrollContentBackground(.hidden)") },
            "LibraryWindow.swift: the List must hide its own opaque background, or it paints in front of the container's glass. Its own modifier chain: \(listChain)")
        XCTAssertFalse(
            listChain.contains { $0.contains(".glassEffect(") },
            "LibraryWindow.swift: glassEffect must not be chained directly onto the List — that clips the glass to the List's own bounds, which is what produced the deformed-oval sidebar rail. Its own modifier chain: \(listChain)")

        let containerChain = modifierChain(attachedTo: "ZStack(alignment: .top)", in: all)
        XCTAssertTrue(
            containerChain.contains { $0.contains(".glassEffect(") },
            "LibraryWindow.swift: glassEffect must be chained onto the sidebar's ZStack container, not the List inside it. Container's own modifier chain: \(containerChain)")
        XCTAssertFalse(
            containerChain.contains { $0.contains(".background(.background)") },
            "LibraryWindow.swift: .background(.background) paints an opaque layer over the glass behind it — strictly less glass than before the change, while reading as a correct fix.")
    }

    /// Was a softer within-6-lines proximity check while MeetingInspector.swift was mid-rewrite
    /// by a sibling lane (b8963ff had dissolved its ZStack, chaining glassEffect straight onto the
    /// ScrollView — the same clipped-glass anti-pattern the sidebar escaped in 9ccbf79). Now that
    /// eeaae05 restored the ZStack wrapper, this asserts the same TARGET check as the sidebar's:
    /// which construct the modifier attaches to, not merely what sits near it.
    func testInspectorGlassAttachesToTheZStackContainerNotTheScrollView() throws {
        let all = try lines("MeetingInspector.swift")

        let scrollableChain = modifierChain(attachedTo: "ScrollView {", in: all)
        XCTAssertTrue(
            scrollableChain.contains { $0.contains(".scrollContentBackground(.hidden)") },
            "MeetingInspector.swift: the ScrollView must hide its own opaque background, or it paints in front of the container's glass. Its own modifier chain: \(scrollableChain)")
        XCTAssertFalse(
            scrollableChain.contains { $0.contains(".glassEffect(") },
            "MeetingInspector.swift: glassEffect must not be chained directly onto the ScrollView — that clips the glass to the scrollable content's own bounds, the same anti-pattern the sidebar escaped. Its own modifier chain: \(scrollableChain)")

        let containerChain = modifierChain(attachedTo: "ZStack {", in: all)
        XCTAssertTrue(
            containerChain.contains { $0.contains(".glassEffect(") },
            "MeetingInspector.swift: glassEffect must be chained onto the ZStack container, not the ScrollView inside it. Container's own modifier chain: \(containerChain)")
        XCTAssertFalse(
            containerChain.contains { $0.contains(".background(.background)") },
            "MeetingInspector.swift: .background(.background) paints an opaque layer over the glass behind it — strictly less glass than before the change, while reading as a correct fix.")
    }

    func testSidebarGlassPassesAnExplicitRectangularShape() throws {
        let all = try lines("LibraryWindow.swift")
        let containerChain = modifierChain(attachedTo: "ZStack(alignment: .top)", in: all)

        XCTAssertTrue(
            containerChain.contains { $0.contains(".glassEffect(") && $0.contains("in:") },
            "The sidebar's glassEffect must pass an explicit shape (glassEffect(_:in:)) — the bare .glassEffect() defaults to DefaultGlassEffectShape(), the exact configuration that produced the deformed-oval rail when it sat on a List. Container's own modifier chain: \(containerChain)")
    }

    func testInspectorGlassPassesAnExplicitRectangularShape() throws {
        let all = try lines("MeetingInspector.swift")
        let containerChain = modifierChain(attachedTo: "ZStack {", in: all)

        XCTAssertTrue(
            containerChain.contains { $0.contains(".glassEffect(") && $0.contains("in:") },
            "MeetingInspector.swift: the container's glassEffect must pass an explicit shape (glassEffect(_:in:)) — the bare .glassEffect() defaults to DefaultGlassEffectShape(), the exact configuration that clipped the sidebar into a deformed oval. Container's own modifier chain: \(containerChain)")
    }

    func testTheTranscriptKeepsAnOpaqueBackgroundBecauseItIsTheContentLayer() throws {
        let detail = try source("MeetingDetailView.swift")

        XCTAssertTrue(
            detail.contains(".background(.background)"),
            "The transcript is the content layer and must stay opaque.")
        XCTAssertFalse(
            detail.contains(".glassEffect()"),
            "HIG: \"Don't use Liquid Glass in the content layer.\" A transcript is text that gets reread the next morning; glass behind it costs legibility, which is the one thing this view exists for.")
    }
}
