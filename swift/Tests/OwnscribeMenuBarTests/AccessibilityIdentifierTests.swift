import XCTest
@testable import OwnscribeMenuBar

final class AccessibilityIdentifierTests: XCTestCase {
    private func source(_ name: String) throws -> String {
        try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OwnscribeMenuBar/\(name)"),
            encoding: .utf8)
    }

    func testEveryIdentifierIsDeclaredOnceSoTheTreeCannotBeAmbiguous() throws {
        var seen: [String: String] = [:]

        for file in ["LibraryWindow.swift", "MeetingDetailView.swift", "MeetingInspector.swift", "InlineBanner.swift"] {
            let text = try source(file)
            for raw in text.components(separatedBy: ".accessibilityIdentifier(\"").dropFirst() {
                let identifier = String(raw.prefix(while: { $0 != "\"" }))
                if let owner = seen[identifier] {
                    XCTFail("\(identifier) is declared in both \(owner) and \(file); a duplicate identifier makes the AX tree ambiguous, so a review script cannot tell which element it addressed")
                }
                seen[identifier] = file
            }
        }

        XCTAssertFalse(
            seen.isEmpty,
            "No accessibility identifiers found. The AX tree yields the window's text with pixel frames, but nothing that ADDRESSES a control by name, so a review can read the window and cannot drive it.")
    }

    func testTheControlsAReviewHasToDriveAreAddressable() throws {
        let expected: [String: [String]] = [
            "LibraryWindow.swift": [
                "library.sidebar",
                "library.meetingList",
                "library.recordButton",
                "library.search",
            ],
            "MeetingDetailView.swift": [
                "meeting.transcript",
                "meeting.backchannelToggle",
                "meeting.envelope",
            ],
            "MeetingInspector.swift": [
                "inspector.form",
            ],
            "InlineBanner.swift": [
                "banner",
            ],
        ]

        for (file, identifiers) in expected {
            let text = try source(file)
            for identifier in identifiers {
                XCTAssertTrue(
                    text.contains(".accessibilityIdentifier(\"\(identifier)\")"),
                    "\(file) no longer declares \(identifier). These are the elements a design review has to name: without them the AX tree returns text and frames but no stable handle, so findings stay visual instead of measured. If a control was renamed, rename it here too rather than deleting the guard.")
            }
        }
    }

    func testTheRecordButtonKeepsAStableIdentifierAcrossItsTwoTitles() throws {
        let window = try source("LibraryWindow.swift")

        XCTAssertTrue(
            window.contains(#"Label(appState.isRecording ? "Arrêter" : "Enregistrer""#),
            "the record button's two titles moved; this guard exists because the identifier must not move with them")
        XCTAssertTrue(
            window.contains(".accessibilityIdentifier(\"library.recordButton\")"),
            "The record button's TITLE changes with state (Enregistrer / Arrêter), so addressing it by title means a script silently stops finding it the moment a recording starts — exactly when a test would want to press stop. The identifier must be stable while the title is not.")
    }
}
