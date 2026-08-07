import XCTest
@testable import OwnscribeMenuBar

final class SettingsAudioFormTests: XCTestCase {
    private static let fakeToken = "hf_TESTONLY"

    private static let realWorldConfigShape = """
    [diarization]
    enabled = true
    hf_token = "hf_TESTONLY"
    min_speakers = 2
    max_speakers = 6
    telemetry = false
    """

    private func makeTempConfig(_ contents: String?) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ownscribe-settings-form-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("config.toml")
        if let contents {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    private func removeParent(of url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func testLoadsTheValuesTheRealReaderReports() throws {
        let url = try makeTempConfig("""
        [audio]
        mic = false
        silence_timeout = 45
        """)
        defer { removeParent(of: url) }

        let form = SettingsAudioForm(loadedFrom: url)

        XCTAssertEqual(form.micEnabled, false, "The toggle must show the configured state, not the default")
        XCTAssertEqual(form.silenceTimeoutText, "45", "The field must show the configured seconds, not the 300 default")
    }

    func testLoadsReaderDefaultsWhenTheConfigHasNoAudioSection() throws {
        let url = try makeTempConfig(Self.realWorldConfigShape)
        defer { removeParent(of: url) }

        let form = SettingsAudioForm(loadedFrom: url)

        XCTAssertEqual(form.micEnabled, true, "An absent [audio] section means mic ON, so the toggle must show ON or the user sees a state the app is not in")
        XCTAssertEqual(form.silenceTimeoutText, "300")
    }

    func testSavingKeepsTheHuggingFaceTokenAndRoundTripsThroughTheRealReader() throws {
        let url = try makeTempConfig(Self.realWorldConfigShape)
        defer { removeParent(of: url) }

        var form = SettingsAudioForm(loadedFrom: url)
        form.micEnabled = false
        form.silenceTimeoutText = "75"

        try form.save(to: url)

        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(
            onDisk.contains("hf_token = \"\(Self.fakeToken)\""),
            "Saving audio settings from the Settings pane must not destroy the HuggingFace token. Got:\n\(onDisk)")

        let reloaded = SettingsAudioForm(loadedFrom: url)
        XCTAssertEqual(reloaded.micEnabled, false, "Got:\n\(onDisk)")
        XCTAssertEqual(reloaded.silenceTimeoutText, "75", "75 differs from the 300 default in both directions, so a fallback read cannot fake this. Got:\n\(onDisk)")
    }

    func testAnUnparseableTimeoutIsRejectedInsteadOfSilentlyWritingTheDefault() throws {
        let url = try makeTempConfig("""
        [audio]
        mic = true
        silence_timeout = 45
        """)
        defer { removeParent(of: url) }

        var form = SettingsAudioForm(loadedFrom: url)
        form.silenceTimeoutText = "five minutes"

        XCTAssertNil(
            form.validatedSettings,
            "A non-numeric timeout must be reported as invalid; writing it anyway makes the reader fall back to 300 and the user's 45 disappears with no error")
        XCTAssertThrowsError(try form.save(to: url), "save must refuse invalid input rather than corrupting the configured value")

        let onDisk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(onDisk.contains("silence_timeout = 45"), "The previously configured value must be untouched by a rejected save. Got:\n\(onDisk)")
    }

    func testANegativeTimeoutIsRejected() throws {
        let url = try makeTempConfig("[audio]\nsilence_timeout = 45")
        defer { removeParent(of: url) }

        var form = SettingsAudioForm(loadedFrom: url)
        form.silenceTimeoutText = "-30"

        XCTAssertNil(form.validatedSettings, "A negative number of seconds is not a timeout the recorder can honour")
        XCTAssertThrowsError(try form.save(to: url))
    }

    func testZeroIsAcceptedBecauseTheConfigDocumentsItAsDisabled() throws {
        let url = try makeTempConfig(Self.realWorldConfigShape)
        defer { removeParent(of: url) }

        var form = SettingsAudioForm(loadedFrom: url)
        form.silenceTimeoutText = "0"

        XCTAssertEqual(form.validatedSettings?.silenceTimeout, 0, "0 means auto-stop disabled in config.toml and must be a reachable setting")
        try form.save(to: url)
        XCTAssertEqual(SettingsAudioForm(loadedFrom: url).silenceTimeoutText, "0")
    }

    func testSurroundingWhitespaceInTheFieldIsAccepted() throws {
        let url = try makeTempConfig(Self.realWorldConfigShape)
        defer { removeParent(of: url) }

        var form = SettingsAudioForm(loadedFrom: url)
        form.silenceTimeoutText = "  90 "

        XCTAssertEqual(form.validatedSettings?.silenceTimeout, 90, "A pasted value with spaces must not be treated as a typo")
        try form.save(to: url)
        XCTAssertEqual(SettingsAudioForm(loadedFrom: url).silenceTimeoutText, "90")
    }

    func testSavingCreatesAnOwnerOnlyConfigWhenNoneExists() throws {
        let url = try makeTempConfig(nil)
        defer { removeParent(of: url) }

        var form = SettingsAudioForm(loadedFrom: url)
        form.micEnabled = false
        form.silenceTimeoutText = "60"
        try form.save(to: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(
            (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
            0o600,
            "A config this pane creates will hold the HuggingFace token later, so it must be owner-only from the start")
        XCTAssertEqual(SettingsAudioForm(loadedFrom: url).micEnabled, false)
    }

    func testTheDefaultConfigURLIsResolvedUnderTheGivenHomeDirectory() {
        let home = URL(fileURLWithPath: "/tmp/ownscribe-fake-home")

        let url = OwnscribeConfigWriter.defaultConfigURL(homeDir: home)

        XCTAssertEqual(
            url.path,
            "/tmp/ownscribe-fake-home/.config/clew/config.toml",
            "The pane must resolve its config path from an injectable home directory so a test can never be pointed at the real one")
    }

    func testTheSettingsPaneOwnsBothAudioControlsAndKeepsTheTokenField() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/OwnscribeMenuBar/SettingsView.swift"),
            encoding: .utf8)

        XCTAssertTrue(source.contains("SettingsAudioForm"), "SettingsView must drive the tested form model, otherwise these tests guard a type the pane does not use")
        XCTAssertTrue(source.contains("Toggle"), "SettingsView must expose the mic setting as a Toggle")
        XCTAssertTrue(source.contains("audioForm.micEnabled"), "The Toggle must bind to the form's mic state")
        XCTAssertTrue(source.contains("audioForm.silenceTimeoutText"), "The timeout field must bind to the form's text")
        XCTAssertTrue(source.contains("SecureField"), "The existing HuggingFace token field must still be present")
        XCTAssertTrue(source.contains("tokenStore.save"), "The token Save action must still be wired to the Keychain store")
    }
}
