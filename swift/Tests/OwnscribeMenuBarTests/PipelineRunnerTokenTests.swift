import XCTest
@testable import OwnscribeMenuBar

@MainActor
final class PipelineRunnerTokenTests: XCTestCase {
    func testPassesKeychainHFTokenToChildEnvironment() async throws {
        let fakeToken = "hf_test123456789"
        let tokenStore = FakeTokenStore(token: fakeToken)

        let envFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: envFile) }

        let tempBinary = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-ownscribe-\(UUID().uuidString)")
        let script = "#!/bin/bash\necho \"HF_TOKEN=${HF_TOKEN:-<unset>}\" > \"\(envFile.path)\""
        try script.write(to: tempBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempBinary.path)
        defer { try? FileManager.default.removeItem(at: tempBinary) }

        let runner = PipelineRunner(binary: tempBinary, tokenStore: tokenStore)

        try await runner.run(arguments: ["resume", "/tmp"]) { _ in }

        XCTAssertTrue(
            tokenStore.loadWasCalled,
            "PipelineRunner must read the token from the store before launching the child")

        let childEnv = try String(contentsOf: envFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            childEnv,
            "HF_TOKEN=\(fakeToken)",
            "Child process must receive HF_TOKEN in its environment so diarization can authenticate with HuggingFace")
    }

    func testDoesNotClobberInheritedEnvironment() async throws {
        let tokenStore = FakeTokenStore(token: "hf_test")

        let envFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: envFile) }

        let tempBinary = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-ownscribe-\(UUID().uuidString)")
        let script = """
        #!/bin/bash
        echo "PATH=${PATH:-<unset>}" > "\(envFile.path)"
        echo "HOME=${HOME:-<unset>}" >> "\(envFile.path)"
        echo "HF_TOKEN=${HF_TOKEN:-<unset>}" >> "\(envFile.path)"
        """
        try script.write(to: tempBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempBinary.path)
        defer { try? FileManager.default.removeItem(at: tempBinary) }

        let runner = PipelineRunner(binary: tempBinary, tokenStore: tokenStore)

        try await runner.run(arguments: ["resume", "/tmp"]) { _ in }

        let childEnv = try String(contentsOf: envFile, encoding: .utf8)
        XCTAssertTrue(childEnv.contains("PATH=") && !childEnv.contains("PATH=<unset>"), "Child must inherit PATH from parent environment")
        XCTAssertTrue(childEnv.contains("HOME=") && !childEnv.contains("HOME=<unset>"), "Child must inherit HOME from parent environment")
        XCTAssertTrue(childEnv.contains("HF_TOKEN=hf_test"), "Child must receive HF_TOKEN without clobbering inherited variables")
    }

    func testSkipsHFTokenWhenKeychainReturnsNil() async throws {
        let tokenStore = FakeTokenStore(token: nil)

        let envFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: envFile) }

        let tempBinary = FileManager.default.temporaryDirectory
            .appendingPathComponent("fake-ownscribe-\(UUID().uuidString)")
        let script = "#!/bin/bash\necho \"HF_TOKEN=${HF_TOKEN:-<unset>}\" > \"\(envFile.path)\""
        try script.write(to: tempBinary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tempBinary.path)
        defer { try? FileManager.default.removeItem(at: tempBinary) }

        let runner = PipelineRunner(binary: tempBinary, tokenStore: tokenStore)

        try await runner.run(arguments: ["resume", "/tmp"]) { _ in }

        let childEnv = try String(contentsOf: envFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(
            childEnv,
            "HF_TOKEN=<unset>",
            "When Keychain returns nil, child must not receive HF_TOKEN so it falls back to config.toml")
    }
}

private final class FakeTokenStore: TokenSource {
    private let token: String?
    private(set) var loadWasCalled = false

    init(token: String?) {
        self.token = token
    }

    func loadHuggingFaceToken() -> String? {
        loadWasCalled = true
        return token
    }
}
