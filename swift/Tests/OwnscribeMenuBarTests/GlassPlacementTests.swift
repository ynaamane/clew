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

    /// Scoped to LibraryWindow.swift alone (this lane's sole ownership). MeetingInspector.swift
    /// is owned by a sibling lane and was found mid-rewrite during this batch — it no longer has
    /// the ZStack-wrapping-Form shape this target check depends on, so hardcoding its structure
    /// here would couple this test to another lane's in-progress work. See the proximity check
    /// below, which still guards it without assuming a specific container/scrollable pair.
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

    func testMeetingInspectorHidesTheScrollBackgroundThatWouldCoverItsGlass() throws {
        let all = try lines("MeetingInspector.swift")
        guard let glass = all.firstIndex(where: { $0.contains(".glassEffect()") }) else {
            XCTFail("MeetingInspector.swift no longer applies glass; this guard needs updating")
            return
        }

        let above = all[..<glass].suffix(6)
        XCTAssertTrue(
            above.contains { $0.contains(".scrollContentBackground(.hidden)") },
            "MeetingInspector.swift: a scrollable view keeps an opaque default background that renders IN FRONT of the glass, so glass without .scrollContentBackground(.hidden) is glass nobody can see.")
        XCTAssertFalse(
            above.contains { $0.contains(".background(.background)") },
            "MeetingInspector.swift: .background(.background) paints an opaque layer over the glass behind it — strictly less glass than before the change, while reading as a correct fix.")
    }

    func testSidebarGlassPassesAnExplicitRectangularShape() throws {
        let all = try lines("LibraryWindow.swift")
        let containerChain = modifierChain(attachedTo: "ZStack(alignment: .top)", in: all)

        XCTAssertTrue(
            containerChain.contains { $0.contains(".glassEffect(") && $0.contains("in:") },
            "The sidebar's glassEffect must pass an explicit shape (glassEffect(_:in:)) — the bare .glassEffect() defaults to DefaultGlassEffectShape(), the exact configuration that produced the deformed-oval rail when it sat on a List. Container's own modifier chain: \(containerChain)")
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
