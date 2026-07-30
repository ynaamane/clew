import Testing
import Foundation
@testable import OwnscribeMenuBar

@Suite("MeetingRowSummary")
struct MeetingRowSummaryTests {
    @Test("Loads summary prose for meeting with summary.md")
    func testLoadSummaryMarkdown() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let meetingDir = tmpDir.appendingPathComponent("2026-07-30_1500_test-meeting")
        try FileManager.default.createDirectory(at: meetingDir, withIntermediateDirectories: true)

        let summaryContent = """
        ## Summary
        This is a test summary with multiple sentences. It describes what the meeting was about.

        ## Key Points
        - First point
        - Second point
        """
        try summaryContent.write(to: meetingDir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)

        let configPath = tmpDir.appendingPathComponent("config.toml")
        try "[output]\nformat = \"markdown\"\n".write(to: configPath, atomically: true, encoding: .utf8)

        let excerpt = MeetingRowSummary.loadExcerpt(
            from: meetingDir,
            configURL: configPath,
            fileManager: FileManager.default
        )

        #expect(excerpt == "This is a test summary with multiple sentences. It describes what the meeting was about.")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @Test("Returns nil for meeting without summary")
    func testNoSummary() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let meetingDir = tmpDir.appendingPathComponent("2026-07-30_1500_no-summary")
        try FileManager.default.createDirectory(at: meetingDir, withIntermediateDirectories: true)

        let configPath = tmpDir.appendingPathComponent("config.toml")
        try "[output]\nformat = \"markdown\"\n".write(to: configPath, atomically: true, encoding: .utf8)

        let excerpt = MeetingRowSummary.loadExcerpt(
            from: meetingDir,
            configURL: configPath,
            fileManager: FileManager.default
        )

        #expect(excerpt == nil)

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @Test("Loads summary from JSON format")
    func testLoadSummaryJSON() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let meetingDir = tmpDir.appendingPathComponent("2026-07-30_1500_json-meeting")
        try FileManager.default.createDirectory(at: meetingDir, withIntermediateDirectories: true)

        let jsonContent = """
        {
            "summary": "JSON format summary text.",
            "key_points": ["Point one", "Point two"],
            "action_items": []
        }
        """
        try jsonContent.write(to: meetingDir.appendingPathComponent("summary.json"), atomically: true, encoding: .utf8)

        let configPath = tmpDir.appendingPathComponent("config.toml")
        try "[output]\nformat = \"json\"\n".write(to: configPath, atomically: true, encoding: .utf8)

        let excerpt = MeetingRowSummary.loadExcerpt(
            from: meetingDir,
            configURL: configPath,
            fileManager: FileManager.default
        )

        #expect(excerpt == "JSON format summary text.")

        try? FileManager.default.removeItem(at: tmpDir)
    }

    @Test("Truncates long summary to 120 characters")
    func testTruncateLongSummary() {
        let longText = "This is a very long summary that exceeds 120 characters and should be truncated at the boundary with an ellipsis to indicate continuation."

        let truncated = MeetingRowSummary.truncateForDisplay(longText)

        #expect(truncated.count <= 123)
        #expect(truncated.hasSuffix("…"))
        #expect(truncated.hasPrefix("This is a very long"))
    }

    @Test("Does not truncate short summary")
    func testNoTruncationNeeded() {
        let shortText = "Short summary."

        let result = MeetingRowSummary.truncateForDisplay(shortText)

        #expect(result == "Short summary.")
    }
}
