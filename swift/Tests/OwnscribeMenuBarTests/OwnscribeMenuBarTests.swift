import XCTest
@testable import OwnscribeMenuBar

final class OwnscribeConfigReaderTests: XCTestCase {
    private let homeDir = URL(fileURLWithPath: "/Users/testuser")

    func testDefaultsToTildeOwnscribeWhenConfigTextIsNil() {
        let dir = OwnscribeConfigReader.resolvedOutputDir(configText: nil, homeDir: homeDir)
        XCTAssertEqual(dir.path, "/Users/testuser/ownscribe")
    }

    func testDefaultsToTildeOwnscribeWhenDirKeyMissing() {
        let toml = "[audio]\nbackend = \"coreaudio\"\n"
        let dir = OwnscribeConfigReader.resolvedOutputDir(configText: toml, homeDir: homeDir)
        XCTAssertEqual(dir.path, "/Users/testuser/ownscribe")
    }

    func testParsesQuotedDirValueUnderOutputSection() {
        let toml = "[audio]\nbackend = \"coreaudio\"\n\n[output]\ndir = \"~/notes\"\nformat = \"markdown\"\n"
        let dir = OwnscribeConfigReader.resolvedOutputDir(configText: toml, homeDir: homeDir)
        XCTAssertEqual(dir.path, "/Users/testuser/notes")
    }

    func testIgnoresDirKeyOutsideOutputSection() {
        let toml = "[audio]\ndir = \"/should/not/be/used\"\n\n[output]\ndir = \"~/notes\"\n"
        let dir = OwnscribeConfigReader.resolvedOutputDir(configText: toml, homeDir: homeDir)
        XCTAssertEqual(dir.path, "/Users/testuser/notes")
    }

    func testStripsTrailingCommentFromValue() {
        let toml = "[output]\ndir = \"~/notes\"  # base output directory\n"
        let dir = OwnscribeConfigReader.resolvedOutputDir(configText: toml, homeDir: homeDir)
        XCTAssertEqual(dir.path, "/Users/testuser/notes")
    }

    func testHandlesAbsolutePathValue() {
        let toml = "[output]\ndir = \"/tmp/notes\"\n"
        let dir = OwnscribeConfigReader.resolvedOutputDir(configText: toml, homeDir: homeDir)
        XCTAssertEqual(dir.path, "/tmp/notes")
    }

    func testExpandBareTildeReturnsHomeDir() {
        let expanded = OwnscribeConfigReader.expand(path: "~", homeDir: homeDir)
        XCTAssertEqual(expanded.path, homeDir.path)
    }
}

final class OwnscribeBinaryResolverTests: XCTestCase {
    private let homeDir = URL(fileURLWithPath: "/Users/testuser")

    func testPrefersExplicitOverrideWhenExecutable() {
        let resolved = OwnscribeBinaryResolver.resolve(
            homeDir: homeDir,
            environment: ["OWNSCRIBE_BIN": "/opt/custom/ownscribe"],
            isExecutableFile: { $0 == "/opt/custom/ownscribe" }
        )
        XCTAssertEqual(resolved?.path, "/opt/custom/ownscribe")
    }

    func testIgnoresOverrideWhenNotExecutable() {
        let resolved = OwnscribeBinaryResolver.resolve(
            homeDir: homeDir,
            environment: ["OWNSCRIBE_BIN": "/opt/custom/ownscribe"],
            isExecutableFile: { _ in false }
        )
        XCTAssertNil(resolved)
    }

    func testFallsBackToRepoRootVenvUnderHome() {
        let expectedPath = "/Users/testuser/meeting-scribe/.venv/bin/ownscribe"
        let resolved = OwnscribeBinaryResolver.resolve(
            homeDir: homeDir,
            environment: [:],
            isExecutableFile: { $0 == expectedPath }
        )
        XCTAssertEqual(resolved?.path, expectedPath)
    }

    func testHonoursRepoRootOverrideEnvVar() {
        let expectedPath = "/opt/repo/.venv/bin/ownscribe"
        let resolved = OwnscribeBinaryResolver.resolve(
            homeDir: homeDir,
            environment: ["OWNSCRIBE_REPO_ROOT": "/opt/repo"],
            isExecutableFile: { $0 == expectedPath }
        )
        XCTAssertEqual(resolved?.path, expectedPath)
    }

    func testReturnsNilWhenNothingIsExecutable() {
        let resolved = OwnscribeBinaryResolver.resolve(
            homeDir: homeDir,
            environment: [:],
            isExecutableFile: { _ in false }
        )
        XCTAssertNil(resolved)
    }
}

final class ProgressEventParserTests: XCTestCase {
    func testParsesBeginEvent() {
        let event = ProgressEventParser.parse(line: #"{"event": "begin", "step": "transcribing"}"#)
        XCTAssertEqual(event, ProgressEvent(event: .begin, step: "transcribing"))
    }

    func testParsesUpdateEventWithFraction() {
        let event = ProgressEventParser.parse(line: #"{"event": "update", "step": "transcribing", "fraction": 0.5}"#)
        XCTAssertEqual(event, ProgressEvent(event: .update, step: "transcribing", fraction: 0.5))
    }

    func testParsesDetailEventWithNullDetail() {
        let event = ProgressEventParser.parse(line: #"{"event": "detail", "step": "transcribing", "detail": null}"#)
        XCTAssertEqual(event, ProgressEvent(event: .detail, step: "transcribing", detail: nil))
    }

    func testReturnsNilForMalformedJSON() {
        XCTAssertNil(ProgressEventParser.parse(line: "not json"))
    }

    func testReturnsNilForEmptyLine() {
        XCTAssertNil(ProgressEventParser.parse(line: ""))
    }

    func testReturnsNilForUnknownEventKind() {
        XCTAssertNil(ProgressEventParser.parse(line: #"{"event": "unknown", "step": "x"}"#))
    }
}

final class NDJSONLineBufferTests: XCTestCase {
    func testSingleCompleteLineIsReturnedImmediately() {
        let buffer = NDJSONLineBuffer()
        let lines = buffer.feed("{\"a\": 1}\n")
        XCTAssertEqual(lines, ["{\"a\": 1}"])
    }

    func testPartialLineIsHeldUntilNewlineArrives() {
        let buffer = NDJSONLineBuffer()
        XCTAssertEqual(buffer.feed("{\"a\":"), [])
        XCTAssertEqual(buffer.feed(" 1}\n"), ["{\"a\": 1}"])
    }

    func testMultipleLinesInOneChunkAreAllReturned() {
        let buffer = NDJSONLineBuffer()
        let lines = buffer.feed("{\"a\": 1}\n{\"a\": 2}\n{\"a\": 3}\n")
        XCTAssertEqual(lines, ["{\"a\": 1}", "{\"a\": 2}", "{\"a\": 3}"])
    }

    func testTrailingPartialLineIsNotReturned() {
        let buffer = NDJSONLineBuffer()
        let lines = buffer.feed("{\"a\": 1}\n{\"a\": 2")
        XCTAssertEqual(lines, ["{\"a\": 1}"])
    }
}

final class MeetingOutputPathsTests: XCTestCase {
    func testDirectoryNameMatchesPythonTimestampFormat() {
        let date = Date(timeIntervalSince1970: 1_772_200_000)
        let baseDir = URL(fileURLWithPath: "/tmp/ownscribe")
        let paths = MeetingOutputPaths(baseDir: baseDir, now: date)

        let referenceFormatter = DateFormatter()
        referenceFormatter.locale = Locale(identifier: "en_US_POSIX")
        referenceFormatter.calendar = Calendar(identifier: .gregorian)
        referenceFormatter.dateFormat = "yyyy-MM-dd_HHmm"
        let expectedName = referenceFormatter.string(from: date)

        XCTAssertEqual(paths.directory.lastPathComponent, expectedName)
        XCTAssertTrue(expectedName.range(of: #"^\d{4}-\d{2}-\d{2}_\d{4}$"#, options: .regularExpression) != nil)
        XCTAssertEqual(paths.recordingPath.lastPathComponent, "recording.wav")
        XCTAssertEqual(paths.recordingPath.deletingLastPathComponent().path, paths.directory.path)
    }
}

final class RecordingTempPathsTests: XCTestCase {
    func testMicEnabledUsesSystemTempSuffix() {
        let paths = RecordingTempPaths(outputPath: "/tmp/out/recording.wav", micEnabled: true)
        XCTAssertEqual(paths.systemPath, "/tmp/out/recording.wav.sys.tmp.wav")
        XCTAssertEqual(paths.micPath, "/tmp/out/recording.wav.mic.tmp.wav")
    }

    func testMicDisabledWritesSystemAudioDirectlyToOutputPath() {
        let paths = RecordingTempPaths(outputPath: "/tmp/out/recording.wav", micEnabled: false)
        XCTAssertEqual(paths.systemPath, "/tmp/out/recording.wav")
    }
}

final class RecentTranscriptsStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    private func makeMeetingDir(_ name: String, transcript: Bool, summary: Bool) throws {
        let dir = tempDir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if transcript {
            try "transcript".write(to: dir.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
        }
        if summary {
            try "summary".write(to: dir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
        }
    }

    func testEmptyDirectoryReturnsNoMeetings() {
        XCTAssertEqual(RecentTranscriptsStore.recentMeetings(in: tempDir), [])
    }

    func testFindsTranscriptAndSummaryFlags() throws {
        try makeMeetingDir("2026-01-01_0900", transcript: true, summary: true)
        try makeMeetingDir("2026-01-02_0900", transcript: true, summary: false)

        let meetings = RecentTranscriptsStore.recentMeetings(in: tempDir)
        XCTAssertEqual(meetings.count, 2)

        let withoutSummary = meetings.first { $0.directory.lastPathComponent == "2026-01-02_0900" }
        XCTAssertEqual(withoutSummary?.hasTranscript, true)
        XCTAssertEqual(withoutSummary?.hasSummary, false)
    }

    func testSortsNewestFirstByDirectoryName() throws {
        try makeMeetingDir("2026-01-01_0900", transcript: true, summary: true)
        try makeMeetingDir("2026-02-01_0900", transcript: true, summary: true)

        let meetings = RecentTranscriptsStore.recentMeetings(in: tempDir)
        XCTAssertEqual(meetings.first?.directory.lastPathComponent, "2026-02-01_0900")
    }

    func testRespectsLimit() throws {
        for i in 1...15 {
            try makeMeetingDir(String(format: "2026-01-%02d_0900", i), transcript: true, summary: true)
        }
        let meetings = RecentTranscriptsStore.recentMeetings(in: tempDir, limit: 3)
        XCTAssertEqual(meetings.count, 3)
    }

    func testIgnoresNonDirectoryEntries() throws {
        try "not a meeting".write(
            to: tempDir.appendingPathComponent("stray-file.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(RecentTranscriptsStore.recentMeetings(in: tempDir), [])
    }
}

final class KeychainTokenStoreTests: XCTestCase {
    private let store = KeychainTokenStore(service: "com.ownscribe.menubar.tests")

    override func tearDown() {
        store.delete(.huggingFace)
        store.delete(.openAI)
    }

    func testSaveThenLoadRoundTrips() {
        XCTAssertTrue(store.save("hf_abc123", for: .huggingFace))
        XCTAssertEqual(store.load(.huggingFace), "hf_abc123")
    }

    func testLoadWithoutSaveReturnsNil() {
        XCTAssertNil(store.load(.openAI))
    }

    func testSaveOverwritesPreviousValue() {
        XCTAssertTrue(store.save("first", for: .huggingFace))
        XCTAssertTrue(store.save("second", for: .huggingFace))
        XCTAssertEqual(store.load(.huggingFace), "second")
    }

    func testDeleteRemovesToken() {
        XCTAssertTrue(store.save("hf_abc123", for: .huggingFace))
        XCTAssertTrue(store.delete(.huggingFace))
        XCTAssertNil(store.load(.huggingFace))
    }

    func testDeleteWhenNothingStoredStillReportsSuccess() {
        XCTAssertTrue(store.delete(.openAI))
    }

    func testDifferentKindsAreIndependent() {
        XCTAssertTrue(store.save("hf_value", for: .huggingFace))
        XCTAssertTrue(store.save("oa_value", for: .openAI))
        XCTAssertEqual(store.load(.huggingFace), "hf_value")
        XCTAssertEqual(store.load(.openAI), "oa_value")
    }
}
