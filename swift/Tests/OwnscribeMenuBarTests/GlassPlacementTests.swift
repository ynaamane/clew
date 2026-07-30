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

    func testEveryGlassSurfaceHidesTheScrollBackgroundThatWouldCoverIt() throws {
        for file in ["LibraryWindow.swift", "MeetingInspector.swift"] {
            let all = try lines(file)
            guard let glass = all.firstIndex(where: { $0.contains(".glassEffect()") }) else {
                XCTFail("\(file) no longer applies glass; this guard needs updating")
                continue
            }

            let above = all[..<glass].suffix(6)
            XCTAssertTrue(
                above.contains { $0.contains(".scrollContentBackground(.hidden)") },
                "\(file): a List/Form keeps an opaque default background that renders IN FRONT of the container's glass, so glass without .scrollContentBackground(.hidden) is glass nobody can see. This shipped once and no render could catch it — glassEffect and no-glass produce byte-identical output off-screen.")
            XCTAssertFalse(
                above.contains { $0.contains(".background(.background)") },
                "\(file): .background(.background) paints an opaque layer over the glass behind it — strictly less glass than before the change, while reading as a correct fix.")
        }
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
