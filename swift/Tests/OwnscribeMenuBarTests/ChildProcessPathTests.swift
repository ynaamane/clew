import XCTest
@testable import OwnscribeMenuBar

final class ChildProcessPathTests: XCTestCase {
    private let launchdPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    func testHomebrewIsAddedToTheMinimalPathAFinderLaunchedAppInherits() {
        let resolved = ChildProcessPath.resolve(
            inheritedPath: launchdPath,
            directoryHasExecutables: { $0 == "/opt/homebrew/bin" })

        XCTAssertTrue(
            resolved.split(separator: ":").contains("/opt/homebrew/bin"),
            "a Finder-launched app inherits launchd's PATH, which has no Homebrew; whisperx then "
                + "fails with 'ffmpeg is not installed' after the meeting is already recorded")
    }

    func testTheInheritedPathIsPreservedAndSearchedFirst() {
        let resolved = ChildProcessPath.resolve(
            inheritedPath: launchdPath,
            directoryHasExecutables: { _ in true })

        XCTAssertTrue(
            resolved.hasPrefix(launchdPath),
            "the user's own PATH must keep priority; prepending ours would let a stray Homebrew "
                + "binary shadow a system one")
    }

    func testADirectoryThatDoesNotExistIsNotAdded() {
        let resolved = ChildProcessPath.resolve(
            inheritedPath: launchdPath,
            directoryHasExecutables: { _ in false })

        XCTAssertEqual(
            resolved, launchdPath,
            "adding paths that hold nothing would make the failure harder to read, not easier")
    }

    func testADirectoryAlreadyPresentIsNotDuplicated() {
        let withHomebrew = "/opt/homebrew/bin:" + launchdPath

        let resolved = ChildProcessPath.resolve(
            inheritedPath: withHomebrew,
            directoryHasExecutables: { _ in true })

        XCTAssertEqual(
            resolved.components(separatedBy: "/opt/homebrew/bin").count - 1, 1,
            "a shell-launched run already has Homebrew; duplicating it is noise")
    }

    func testBothIntelAndAppleSiliconHomebrewPrefixesAreConsidered() {
        let intelOnly = ChildProcessPath.resolve(
            inheritedPath: launchdPath,
            directoryHasExecutables: { $0 == "/usr/local/bin" })

        XCTAssertTrue(
            intelOnly.split(separator: ":").contains("/usr/local/bin"),
            "Homebrew lives in /usr/local/bin on Intel and /opt/homebrew/bin on Apple Silicon; "
                + "hardcoding one breaks the other machine")
    }

    func testTheRealMachineCanFindFfmpegThroughTheResolvedPath() throws {
        let resolved = ChildProcessPath.resolve(inheritedPath: launchdPath)
        let directories = resolved.split(separator: ":").map(String.init)

        let ffmpeg = directories
            .map { $0 + "/ffmpeg" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }

        try XCTSkipIf(
            ffmpeg == nil && FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg") == false,
            "ffmpeg is not installed on this machine, so there is nothing to find")

        XCTAssertNotNil(
            ffmpeg,
            "this is the whole point: starting from the PATH a Finder-launched app really gets, "
                + "ffmpeg must be reachable. Transcription cannot run otherwise.")
    }
}
