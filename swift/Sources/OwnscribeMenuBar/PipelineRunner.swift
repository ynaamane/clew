import Foundation
import OSLog

@MainActor
public protocol PipelineRunning {
    func run(
        arguments: [String],
        onEvent: @escaping @Sendable (ProgressEvent) -> Void
    ) async throws
}

@MainActor
public final class PipelineRunner: PipelineRunning {
    public enum RunError: Error, CustomStringConvertible {
        case binaryNotFound
        case processExitedNonZero(Int32)

        public var description: String {
            switch self {
            case .binaryNotFound:
                return "Could not find the ownscribe CLI in the repo venv (.venv/bin/ownscribe)."
            case .processExitedNonZero(let code):
                return "ownscribe exited with status \(code)."
            }
        }
    }

    internal let binary: URL
    private let tokenStore: TokenSource
    private var process: Process?

    var inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment

    public init(binary: URL, tokenStore: TokenSource = KeychainTokenStore()) {
        self.binary = binary
        self.tokenStore = tokenStore
    }

    public static func makeDefault(homeDir: URL = FileManager.default.homeDirectoryForCurrentUser) -> PipelineRunner? {
        guard let binary = OwnscribeBinaryResolver.resolve(homeDir: homeDir) else { return nil }
        return PipelineRunner(binary: binary)
    }

    public func run(
        arguments: [String],
        onEvent: @escaping @Sendable (ProgressEvent) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--progress", "json"] + arguments

        var env = inheritedEnvironment
        if let token = tokenStore.loadHuggingFaceToken() {
            env["HF_TOKEN"] = token
        }
        env["PATH"] = ChildProcessPath.resolve(inheritedPath: env["PATH"] ?? "")
        process.environment = env

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        let lineBuffer = NDJSONLineBuffer()
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            for line in lineBuffer.feed(chunk) {
                if let event = ProgressEventParser.parse(line: line) {
                    onEvent(event)
                }
            }
        }

        let subcommand = arguments.first ?? ""
        AppLogger.pipeline.info("Launching pipeline process: \(self.binary.lastPathComponent, privacy: .public) \(subcommand, privacy: .public)")

        self.process = process
        try process.run()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            process.terminationHandler = { _ in continuation.resume() }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let status = process.terminationStatus
        self.process = nil

        if status == 0 {
            AppLogger.pipeline.info("Pipeline process exited successfully")
        } else {
            AppLogger.pipeline.error("Pipeline process exited with status \(status)")
        }

        guard status == 0 else {
            throw RunError.processExitedNonZero(status)
        }
    }

    public func cancel() {
        process?.terminate()
    }
}
