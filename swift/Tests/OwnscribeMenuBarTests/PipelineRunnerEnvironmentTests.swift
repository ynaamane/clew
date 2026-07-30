import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class PipelineRunnerEnvironmentTests: XCTestCase {
    private static let launchdPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    private func runnerEchoingItsEnvironment(
        inheritedPath: String = launchdPath
    ) throws -> (PipelineRunner, URL) {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("echo-path-\(UUID().uuidString).sh")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("path-\(UUID().uuidString).txt")

        try #"""
        #!/bin/sh
        printf '%s' "$PATH" > "OUTPUT"
        command -v ffmpeg >> "OUTPUT" 2>/dev/null
        exit 0
        """#
            .replacingOccurrences(of: "OUTPUT", with: output.path)
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let runner = PipelineRunner(binary: script, tokenStore: NoTokenStore())
        runner.inheritedEnvironment = ["PATH": inheritedPath]
        return (runner, output)
    }

    private func childObservation(inheritedPath: String) async throws -> String {
        let (runner, output) = try runnerEchoingItsEnvironment(inheritedPath: inheritedPath)
        try await runner.run(arguments: ["resume", "/tmp/nowhere"]) { _ in }
        let observed = try String(contentsOf: output, encoding: .utf8)
        XCTAssertFalse(
            observed.isEmpty,
            "the script did not run, so this test proves nothing about the child's environment")
        return observed
    }

    func testTheChildGetsHomebrewEvenWhenTheAppWasLaunchedFromFinder() async throws {
        let observed = try await childObservation(inheritedPath: Self.launchdPath)

        XCTAssertTrue(
            observed.contains("/opt/homebrew/bin") || observed.contains("/usr/local/bin"),
            "starting from launchd's PATH — what a Finder-launched app really inherits — the child "
                + "must still reach Homebrew. Passing the inherited PATH through is how the app "
                + "recorded a meeting it could never transcribe: whisperx exits 1 with 'ffmpeg is "
                + "not installed' AFTER the audio is on disk.")
    }

    func testFfmpegIsReachableByTheChildFromTheFinderPath() async throws {
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg")
                || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ffmpeg"),
            "ffmpeg is not installed here, so there is nothing for the child to find")

        let observed = try await childObservation(inheritedPath: Self.launchdPath)

        XCTAssertTrue(
            observed.contains("ffmpeg"),
            "`command -v ffmpeg` found nothing on the child's PATH. This is the exact 2026-07-30 "
                + "failure, reproduced: transcription dies after the recording exists.")
    }

    func testAShellLaunchedRunIsNotDisturbed() async throws {
        let shellPath = "/opt/homebrew/bin:" + Self.launchdPath

        let observed = try await childObservation(inheritedPath: shellPath)

        XCTAssertTrue(
            observed.hasPrefix(shellPath),
            "a run from the terminal already has what it needs; the user's own ordering must survive")
    }
}

private struct NoTokenStore: TokenSource {
    func loadHuggingFaceToken() -> String? { nil }
}
