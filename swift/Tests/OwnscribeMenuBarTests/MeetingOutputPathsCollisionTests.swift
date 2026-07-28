import XCTest
@testable import OwnscribeMenuBar

final class MeetingOutputPathsCollisionTests: XCTestCase {
    private var tempBase: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("collision-test-\(UUID().uuidString)")
    }

    func testTwoPathsInSameMinuteWithoutContentDoNotCollide() throws {
        let base = tempBase
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let fixedMoment = Date(timeIntervalSince1970: 1737803400)
        let first = MeetingOutputPaths(baseDir: base, now: fixedMoment)
        let second = MeetingOutputPaths(baseDir: base, now: fixedMoment)

        XCTAssertEqual(
            first.directory, second.directory,
            "Two paths created at the same instant with no existing content should use the same directory")
    }

    func testTwoPathsInSameMinuteWithExistingContentDoNotCollide() throws {
        let base = tempBase
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let fixedMoment = Date(timeIntervalSince1970: 1737803400)
        let first = MeetingOutputPaths(baseDir: base, now: fixedMoment)
        try first.createDirectory()
        try "test audio".write(to: first.recordingPath, atomically: true, encoding: .utf8)

        let second = MeetingOutputPaths(baseDir: base, now: fixedMoment)

        XCTAssertNotEqual(
            first.recordingPath, second.recordingPath,
            "Two recordings started in the same minute must NOT resolve to the same recording.wav — the second would overwrite the first meeting's audio, which is data loss")
        XCTAssertTrue(
            second.directory.lastPathComponent.hasSuffix("_2"),
            "The second path should have a _2 suffix")
    }

    func testThirdPathInSameMinuteGetsSuffix3() throws {
        let base = tempBase
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let fixedMoment = Date(timeIntervalSince1970: 1737803400)

        let first = MeetingOutputPaths(baseDir: base, now: fixedMoment)
        try first.createDirectory()
        try "audio1".write(to: first.recordingPath, atomically: true, encoding: .utf8)

        let second = MeetingOutputPaths(baseDir: base, now: fixedMoment)
        try second.createDirectory()
        try "audio2".write(to: second.recordingPath, atomically: true, encoding: .utf8)

        let third = MeetingOutputPaths(baseDir: base, now: fixedMoment)

        XCTAssertTrue(
            third.directory.lastPathComponent.hasSuffix("_3"),
            "The third path should have a _3 suffix")

        let firstContent = try String(contentsOf: first.recordingPath, encoding: .utf8)
        XCTAssertEqual(firstContent, "audio1", "First recording must not be destroyed")

        let secondContent = try String(contentsOf: second.recordingPath, encoding: .utf8)
        XCTAssertEqual(secondContent, "audio2", "Second recording must not be destroyed")
    }

    func testEmptyExistingDirectoryCanBeReused() throws {
        let base = tempBase
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let fixedMoment = Date(timeIntervalSince1970: 1737803400)
        let first = MeetingOutputPaths(baseDir: base, now: fixedMoment)
        try first.createDirectory()

        let second = MeetingOutputPaths(baseDir: base, now: fixedMoment)

        XCTAssertEqual(
            first.directory.path, second.directory.path,
            "An empty existing directory should be reused, not skipped — no data loss risk")
    }

    func testOriginalFormatPreservedForParsing() throws {
        let base = tempBase
        let fixedMoment = Date(timeIntervalSince1970: 1706443800)
        let paths = MeetingOutputPaths(baseDir: base, now: fixedMoment)

        let name = paths.directory.lastPathComponent
        XCTAssertTrue(
            name.starts(with: "2024-01-28_1310"),
            "Directory name must start with yyyy-MM-dd_HHmm format for RecentTranscriptsStore parser compatibility")
    }

    func testCollidedPathParsesCorrectlyInMeetingSummary() throws {
        let base = tempBase
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let fixedMoment = Date(timeIntervalSince1970: 1706443800)
        let first = MeetingOutputPaths(baseDir: base, now: fixedMoment)
        try first.createDirectory()
        try "audio1".write(to: first.recordingPath, atomically: true, encoding: .utf8)

        let second = MeetingOutputPaths(baseDir: base, now: fixedMoment)

        let summary = MeetingSummary(
            directory: second.directory,
            hasTranscript: false,
            hasSummary: false)

        XCTAssertFalse(
            summary.displayDate.isEmpty,
            "A collided path with _2 suffix must parse correctly through RecentTranscriptsStore — blank dates in the window are the regression this test prevents")

        XCTAssertEqual(
            summary.displayDate, "28 Jan · 13:10",
            "The parsed date must be exact, not garbage or truncated")
    }

    func testNonCollidedPostRenameParsesCorrectly() throws {
        let base = tempBase
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let fixedMoment = Date(timeIntervalSince1970: 1706443800)
        let paths = MeetingOutputPaths(baseDir: base, now: fixedMoment)
        try paths.createDirectory()

        let preName = paths.directory.lastPathComponent
        let postRenameDir = base.appendingPathComponent("\(preName)_project-technical-review")
        try? FileManager.default.moveItem(at: paths.directory, to: postRenameDir)

        let summary = MeetingSummary(
            directory: postRenameDir,
            hasTranscript: false,
            hasSummary: false)

        XCTAssertEqual(
            summary.displayDate, "28 Jan · 13:10",
            "Date must parse correctly after Python appends slug to non-collided name")

        XCTAssertEqual(
            summary.displayTitle, "Project technical review",
            "Title must extract cleanly without timestamp or Swift's collision marker")
    }

    func testCollidedPostRenameParsesCorrectly() throws {
        let base = tempBase
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let fixedMoment = Date(timeIntervalSince1970: 1706443800)
        let first = MeetingOutputPaths(baseDir: base, now: fixedMoment)
        try first.createDirectory()
        try "audio1".write(to: first.recordingPath, atomically: true, encoding: .utf8)

        let second = MeetingOutputPaths(baseDir: base, now: fixedMoment)
        try second.createDirectory()

        let secondPreName = second.directory.lastPathComponent
        let secondPostRenameDir = base.appendingPathComponent("\(secondPreName)_project-technical-review")
        try? FileManager.default.moveItem(at: second.directory, to: secondPostRenameDir)

        let summary = MeetingSummary(
            directory: secondPostRenameDir,
            hasTranscript: false,
            hasSummary: false)

        XCTAssertEqual(
            summary.displayDate, "28 Jan · 13:10",
            "Date must parse correctly when Swift added _2 and Python appended slug")

        XCTAssertTrue(
            summary.displayTitle.hasSuffix(" 2") || summary.displayTitle == "2_project technical review",
            "Title should either show clean '2' suffix if Python stripped, or '2_...' if not")
    }

    func testPythonStrippedCollisionParsesCleanly() throws {
        let base = tempBase
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let fixedMoment = Date(timeIntervalSince1970: 1706443800)
        let paths = MeetingOutputPaths(baseDir: base, now: fixedMoment)
        try paths.createDirectory()

        let strippedPostRenameDir = base.appendingPathComponent("2024-01-28_1310_project-technical-review-2")
        try FileManager.default.createDirectory(at: strippedPostRenameDir, withIntermediateDirectories: true)

        let summary = MeetingSummary(
            directory: strippedPostRenameDir,
            hasTranscript: false,
            hasSummary: false)

        XCTAssertEqual(
            summary.displayDate, "28 Jan · 13:10",
            "Date must parse after Python strips _2 and appends slug with collision -2")

        XCTAssertEqual(
            summary.displayTitle, "Project technical review 2",
            "Title must show clean trailing number when Python handles both strip and slug collision")
    }
}
