import Foundation
import OwnscribeCapture

@MainActor
@Observable
public final class AppState {
    public enum Phase: Equatable {
        case idle
        case recording(startedAt: Date)
        case processing(step: String, fraction: Double?)
        case done(directory: URL)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var recentMeetings: [MeetingSummary] = []

    private let recordingController = RecordingController()
    private let homeDir: URL
    private var pipelineRunner: PipelineRunner?

    public init(homeDir: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDir = homeDir
        self.pipelineRunner = PipelineRunner.makeDefault(homeDir: homeDir)
        refreshRecentMeetings()
    }

    public var outputDir: URL {
        let configPath = homeDir.appendingPathComponent(".config/ownscribe/config.toml")
        let configText = try? String(contentsOf: configPath, encoding: .utf8)
        return OwnscribeConfigReader.resolvedOutputDir(configText: configText, homeDir: homeDir)
    }

    public var isCliAvailable: Bool {
        pipelineRunner != nil
    }

    public func refreshRecentMeetings() {
        recentMeetings = RecentTranscriptsStore.recentMeetings(in: outputDir)
    }

    public func toggleRecording() async {
        switch phase {
        case .idle, .done, .failed:
            await startRecording()
        case .recording:
            await stopRecordingAndProcess()
        case .processing:
            break
        }
    }

    private func startRecording() async {
        let paths = MeetingOutputPaths(baseDir: outputDir)
        do {
            try paths.createDirectory()
            try await recordingController.start(outputPath: paths.recordingPath.path)
            phase = .recording(startedAt: Date())
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func stopRecordingAndProcess() async {
        do {
            let recordingURL = try recordingController.stop()
            await runPipeline(on: recordingURL)
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func runPipeline(on recordingURL: URL) async {
        guard let pipelineRunner else {
            phase = .failed(PipelineRunner.RunError.binaryNotFound.description)
            return
        }
        phase = .processing(step: "starting", fraction: nil)

        let directory = recordingURL.deletingLastPathComponent()
        do {
            try await pipelineRunner.run(arguments: ["resume", directory.path]) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
            phase = .done(directory: directory)
            refreshRecentMeetings()
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func handle(_ event: ProgressEvent) {
        guard case .processing = phase else { return }
        switch event.event {
        case .begin, .update:
            phase = .processing(step: event.step, fraction: event.fraction)
        case .complete, .fail, .detail:
            break
        }
    }
}
