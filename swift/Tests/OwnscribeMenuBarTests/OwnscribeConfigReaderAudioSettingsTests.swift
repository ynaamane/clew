import XCTest
@testable import OwnscribeMenuBar

final class OwnscribeConfigReaderAudioSettingsTests: XCTestCase {
    func testParsesMicFromAudioSection() {
        let toml = """
        [audio]
        mic = true
        """

        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: toml)

        XCTAssertEqual(result.mic, true, "Must parse mic = true from [audio] section")
    }

    func testParsesSilenceTimeoutFromAudioSection() {
        let toml = """
        [audio]
        silence_timeout = 120
        """

        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: toml)

        XCTAssertEqual(result.silenceTimeout, 120, "Must parse silence_timeout from [audio] section")
    }

    func testParsesBothMicAndSilenceTimeout() {
        let toml = """
        [audio]
        mic = false
        silence_timeout = 600
        """

        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: toml)

        XCTAssertEqual(result.mic, false)
        XCTAssertEqual(result.silenceTimeout, 600)
    }

    func testDefaultsToMicTrueWhenAbsent() {
        let toml = """
        [audio]
        silence_timeout = 300
        """

        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: toml)

        XCTAssertEqual(result.mic, true, "Must default to mic = true matching CLI effective behavior (rec.sh always passes --mic) when key is absent")
    }

    func testDefaultsToSilenceTimeout300WhenAbsent() {
        let toml = """
        [audio]
        mic = true
        """

        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: toml)

        XCTAssertEqual(result.silenceTimeout, 300, "Must default to 300 seconds matching CLI default when key is absent")
    }

    func testDefaultsWhenAudioSectionAbsent() {
        let toml = """
        [output]
        dir = "~/clew"
        """

        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: toml)

        XCTAssertEqual(result.mic, true, "Absent [audio] section must default to mic ON, preserving BUG4 fix where owner's voice must be recorded")
        XCTAssertEqual(result.silenceTimeout, 300)
    }

    func testDefaultsWhenTOMLIsNil() {
        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: nil)

        XCTAssertEqual(result.mic, true, "Nil config must default to mic ON, preserving BUG4 fix where owner's voice must be recorded")
        XCTAssertEqual(result.silenceTimeout, 300)
    }

    func testExplicitMicFalseIsHonored() {
        let toml = """
        [audio]
        mic = false
        """

        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: toml)

        XCTAssertEqual(result.mic, false, "Explicit mic = false must be honored so users can turn off their own mic capture")
    }

    func testMalformedMicValueFallsBackToDefaultWithoutCrashing() {
        let toml = """
        [audio]
        mic = maybe
        """

        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: toml)

        XCTAssertEqual(result.mic, true, "Malformed mic value must fall back to ON without crashing since this parses at app launch")
    }

    func testIgnoresCommentsInValues() {
        let toml = """
        [audio]
        mic = true  # enable microphone
        silence_timeout = 180  # 3 minutes
        """

        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: toml)

        XCTAssertEqual(result.mic, true)
        XCTAssertEqual(result.silenceTimeout, 180)
    }

    func testIgnoresMicFromNonAudioSection() {
        let toml = """
        [audio]
        silence_timeout = 300
        [correction]
        mic = false
        """

        let result = OwnscribeConfigReader.parseAudioSettings(fromTOML: toml)

        XCTAssertEqual(result.mic, true, "mic = false under [correction] must be ignored; only [audio] mic matters, otherwise owner's voice is silently lost")
        XCTAssertEqual(result.silenceTimeout, 300)
    }
}
