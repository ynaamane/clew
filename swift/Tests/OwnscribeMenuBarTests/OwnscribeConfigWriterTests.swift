import XCTest
@testable import OwnscribeMenuBar

final class OwnscribeConfigWriterTests: XCTestCase {
    private static let fakeToken = "hf_TESTONLY"

    private static let realWorldConfigShape = """
    [diarization]
    enabled = true
    hf_token = "hf_TESTONLY"
    min_speakers = 2
    max_speakers = 6
    telemetry = false
    """

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ownscribe-config-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func posixMode(of url: URL) throws -> UInt16? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.uint16Value
    }

    func testWritingMicKeepsTheHuggingFaceTokenLineIntact() {
        let updated = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 300),
            to: Self.realWorldConfigShape)

        XCTAssertTrue(
            updated.contains("hf_token = \"\(Self.fakeToken)\""),
            "The HuggingFace token line must survive an audio-settings write: the config is the only place it lives, it is chmod 600 outside the repo, and losing it silently disables diarization. Got:\n\(updated)")
        XCTAssertTrue(updated.contains("[diarization]"), "The [diarization] section header must survive")
        for key in ["enabled = true", "min_speakers = 2", "max_speakers = 6", "telemetry = false"] {
            XCTAssertTrue(updated.contains(key), "Unmodelled key '\(key)' must survive unchanged. Got:\n\(updated)")
        }
    }

    func testAddsAudioSectionWhenAbsentAndTheRealReaderReadsItBack() {
        let updated = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 45),
            to: Self.realWorldConfigShape)

        let readBack = OwnscribeConfigReader.parseAudioSettings(fromTOML: updated)

        XCTAssertEqual(readBack.mic, false, "Reader must see mic = false; a default fallback would also report true, so this direction proves the write landed. Got:\n\(updated)")
        XCTAssertEqual(readBack.silenceTimeout, 45, "Reader must see silence_timeout = 45, which differs from the 300 default so an unparseable write cannot masquerade as success. Got:\n\(updated)")
    }

    func testRoundTripsValuesThatDifferFromTheReaderDefaultsInBothDirections() {
        let startedFromNonDefaults = """
        [audio]
        mic = false
        silence_timeout = 45
        """

        let updated = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: true, silenceTimeout: 900),
            to: startedFromNonDefaults)

        let readBack = OwnscribeConfigReader.parseAudioSettings(fromTOML: updated)

        XCTAssertEqual(readBack.silenceTimeout, 900, "silence_timeout must move 45 -> 900; 900 differs from the 300 default so this cannot pass on a fallback. Got:\n\(updated)")
        XCTAssertEqual(readBack.mic, true, "mic must move false -> true")
        XCTAssertFalse(
            updated.contains("mic = false"),
            "The old mic = false line must be gone, not shadowed: reading back true is also what the reader returns for an unparseable value, so the raw text has to be checked too. Got:\n\(updated)")
    }

    func testUpdatesKeysInPlaceWithoutDisturbingOtherAudioKeys() {
        let existing = """
        [audio]
        backend = "coreaudio"
        device = ""
        mic = true
        capture_mode = "all"
        silence_timeout = 300
        """

        let updated = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 90),
            to: existing)

        let readBack = OwnscribeConfigReader.parseAudioSettings(fromTOML: updated)
        XCTAssertEqual(readBack.mic, false)
        XCTAssertEqual(readBack.silenceTimeout, 90)
        for key in ["backend = \"coreaudio\"", "device = \"\"", "capture_mode = \"all\""] {
            XCTAssertTrue(updated.contains(key), "Sibling [audio] key '\(key)' must survive unchanged. Got:\n\(updated)")
        }
        XCTAssertEqual(
            updated.components(separatedBy: "[audio]").count - 1,
            1,
            "An existing [audio] section must be edited, never duplicated. Got:\n\(updated)")
    }

    func testAddsAMissingKeyInsideTheExistingAudioSectionNotAfterTheNextSection() {
        let existing = """
        [audio]
        backend = "coreaudio"

        [transcription]
        model = "large-v3"
        """

        let updated = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 60),
            to: existing)

        let readBack = OwnscribeConfigReader.parseAudioSettings(fromTOML: updated)
        XCTAssertEqual(readBack.mic, false, "The inserted mic must land inside [audio]; the reader ignores it anywhere else, so a wrong insertion point reads back as the default. Got:\n\(updated)")
        XCTAssertEqual(readBack.silenceTimeout, 60, "The inserted silence_timeout must land inside [audio]. Got:\n\(updated)")
        XCTAssertTrue(updated.contains("model = \"large-v3\""), "[transcription] must survive unchanged. Got:\n\(updated)")
        XCTAssertTrue(updated.contains("backend = \"coreaudio\""), "The existing [audio] key must survive. Got:\n\(updated)")
    }

    func testPreservesLeadingCommentsAndUnknownSections() {
        let existing = """
        # clew configuration
        # edited by hand

        [summarization]
        provider = "llamacpp"
        some_future_key = 42

        [diarization]
        hf_token = "hf_TESTONLY"
        """

        let updated = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: true, silenceTimeout: 300),
            to: existing)

        for preserved in [
            "# clew configuration",
            "# edited by hand",
            "[summarization]",
            "provider = \"llamacpp\"",
            "some_future_key = 42",
            "hf_token = \"\(Self.fakeToken)\"",
        ] {
            XCTAssertTrue(updated.contains(preserved), "'\(preserved)' must survive unchanged. Got:\n\(updated)")
        }
    }

    func testPreservesAnInlineCommentOnAKeyItRewrites() {
        let existing = """
        [audio]
        mic = true  # also capture microphone input
        silence_timeout = 300     # seconds of silence before auto-stop
        """

        let updated = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 120),
            to: existing)

        XCTAssertTrue(
            updated.contains("# also capture microphone input"),
            "The inline comment explaining mic must survive the rewrite. Got:\n\(updated)")
        XCTAssertTrue(
            updated.contains("# seconds of silence before auto-stop"),
            "The inline comment explaining silence_timeout must survive the rewrite. Got:\n\(updated)")

        let readBack = OwnscribeConfigReader.parseAudioSettings(fromTOML: updated)
        XCTAssertEqual(readBack.mic, false)
        XCTAssertEqual(readBack.silenceTimeout, 120)
    }

    func testACommentedOutKeyIsNotMistakenForTheRealKey() {
        let existing = """
        [audio]
        # mic = true
        backend = "coreaudio"
        """

        let updated = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 75),
            to: existing)

        XCTAssertTrue(
            updated.contains("# mic = true"),
            "A commented-out key must stay a comment, not be rewritten into an active setting. Got:\n\(updated)")

        let readBack = OwnscribeConfigReader.parseAudioSettings(fromTOML: updated)
        XCTAssertEqual(readBack.mic, false, "A real mic line must be added alongside the comment. Got:\n\(updated)")
        XCTAssertEqual(readBack.silenceTimeout, 75)
    }

    func testRepeatedWritesDoNotAccumulateSections() {
        let once = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 60),
            to: Self.realWorldConfigShape)
        let twice = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: true, silenceTimeout: 150),
            to: once)

        XCTAssertEqual(
            twice.components(separatedBy: "[audio]").count - 1,
            1,
            "Saving twice must not append a second [audio] section. Got:\n\(twice)")
        let readBack = OwnscribeConfigReader.parseAudioSettings(fromTOML: twice)
        XCTAssertEqual(readBack.silenceTimeout, 150, "The second write must win. Got:\n\(twice)")
        XCTAssertTrue(twice.contains("hf_token = \"\(Self.fakeToken)\""), "The token must survive both writes. Got:\n\(twice)")
    }

    func testWritesToAnEmptyConfigText() {
        let updated = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 30),
            to: "")

        let readBack = OwnscribeConfigReader.parseAudioSettings(fromTOML: updated)
        XCTAssertEqual(readBack.mic, false, "Got:\n\(updated)")
        XCTAssertEqual(readBack.silenceTimeout, 30, "Got:\n\(updated)")
    }

    func testFileWriteRoundTripsThroughTheRealReaderAndKeepsTheToken() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")
        try Self.realWorldConfigShape.write(to: url, atomically: true, encoding: .utf8)

        try OwnscribeConfigWriter.writeAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 42),
            to: url)

        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("hf_token = \"\(Self.fakeToken)\""), "Token must survive a real file write. Got:\n\(onDisk)")

        let readBack = OwnscribeConfigWriter.readAudioSettings(from: url)
        XCTAssertEqual(readBack.mic, false, "Got:\n\(onDisk)")
        XCTAssertEqual(readBack.silenceTimeout, 42, "Got:\n\(onDisk)")
    }

    func testFileWritePreservesMode600() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.toml")
        try Self.realWorldConfigShape.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: UInt16(0o600))],
            ofItemAtPath: url.path)

        try OwnscribeConfigWriter.writeAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 60),
            to: url)

        let mode = try posixMode(of: url)
        XCTAssertEqual(
            mode,
            0o600,
            "A file holding the HuggingFace token must stay owner-only; a temp-file-and-rename write silently relaxes it to 0644")
    }

    func testANewConfigFileIsCreatedOwnerOnly() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("nested").appendingPathComponent("config.toml")

        try OwnscribeConfigWriter.writeAudioSettings(
            AudioSettings(mic: false, silenceTimeout: 60),
            to: url)

        let mode = try posixMode(of: url)
        XCTAssertEqual(mode, 0o600, "A config file this app creates will later hold a token, so it must be owner-only from the start")
        XCTAssertEqual(OwnscribeConfigWriter.readAudioSettings(from: url).silenceTimeout, 60)
    }

    func testOutOfRangeTimeoutIsWrittenAsAValueTheReaderCanParse() {
        let negative = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: true, silenceTimeout: -5),
            to: "[audio]\n")
        XCTAssertEqual(
            OwnscribeConfigReader.parseAudioSettings(fromTOML: negative).silenceTimeout,
            0,
            "A negative timeout must clamp to 0, which the config documents as disabled, rather than emitting a value the reader silently turns back into 300. Got:\n\(negative)")

        let notFinite = OwnscribeConfigWriter.applyingAudioSettings(
            AudioSettings(mic: true, silenceTimeout: .infinity),
            to: "[audio]\n")
        XCTAssertEqual(
            OwnscribeConfigReader.parseAudioSettings(fromTOML: notFinite).silenceTimeout,
            300,
            "A non-finite timeout must fall back to the documented default instead of trapping on the Int conversion. Got:\n\(notFinite)")
    }

    func testReadAudioSettingsReturnsReaderDefaultsForAMissingFile() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("ownscribe-absent-\(UUID().uuidString)")
            .appendingPathComponent("config.toml")

        let settings = OwnscribeConfigWriter.readAudioSettings(from: missing)

        XCTAssertEqual(settings.mic, true, "An absent config must mean mic ON, matching the reader so Settings never shows a state the app is not in")
        XCTAssertEqual(settings.silenceTimeout, 300)
    }
}
