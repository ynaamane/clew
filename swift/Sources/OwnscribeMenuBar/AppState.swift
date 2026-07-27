import AppKit
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
    public private(set) var isMuted: Bool = false
    public private(set) var muteWarning: String?
    public private(set) var muteIndicator: MuteIndicator = .notMuted

    var unmuteOnQuitAttempts = 3

    private let recordingController = RecordingController()
    private let muteDevice: AudioMuteDevice
    private let hotKeyRegistration = GlobalHotKeyRegistration()
    private let homeDir: URL
    private var pipelineRunner: PipelineRunner?

    public init(
        homeDir: URL = FileManager.default.homeDirectoryForCurrentUser,
        muteDevice: AudioMuteDevice = DefaultInputAudioMuteDevice()
    ) {
        self.homeDir = homeDir
        self.muteDevice = muteDevice
        self.pipelineRunner = PipelineRunner.makeDefault(homeDir: homeDir)
        applyConfigSettings()
        refreshRecentMeetings()
        registerMuteHotKey()
        registerTerminationObserver()
        registerTerminationSignalHandlers()
    }

    private func applyConfigSettings() {
        let configPath = homeDir.appendingPathComponent(".config/ownscribe/config.toml")
        let configText = try? String(contentsOf: configPath, encoding: .utf8)
        let audioSettings = OwnscribeConfigReader.parseAudioSettings(fromTOML: configText)
        recordingController.enableMic = audioSettings.mic
        recordingController.silenceTimeout = audioSettings.silenceTimeout
        recordingController.onSilenceTimeout = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.stopRecordingIfStillRecording()
            }
        }
    }

    private func stopRecordingIfStillRecording() async {
        guard case .recording = phase else { return }
        await stopRecordingAndProcess()
    }

    private func registerMuteHotKey() {
        _ = hotKeyRegistration.register(.defaultMuteToggle) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleMasterMute()
            }
        }
    }

    private func registerTerminationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restoreUnmutedOnQuit()
            }
        }
    }

    private var terminationSignalSources: [DispatchSourceSignal] = []

    private func registerTerminationSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.restoreUnmutedOnQuit()
                NSApplication.shared.terminate(nil)
            }
            source.resume()
            terminationSignalSources.append(source)
        }
    }

    public func toggleMasterMute() {
        let outcome = applyMasterMute(!isMuted, device: muteDevice) { [weak self] muted in
            self?.recordingController.setLocalMicMute(muted)
        }
        isMuted = outcome.displayMuted
        muteWarning = outcome.warning
        muteIndicator = indicator(for: outcome)
    }

    private func indicator(for outcome: MasterMuteOutcome) -> MuteIndicator {
        guard outcome.displayMuted else { return .notMuted }
        return outcome.usedLocalFallback ? .mutedUnverified : .mutedVerified
    }

    public func restoreUnmutedOnQuit() {
        guard isMuted else { return }

        for _ in 0..<unmuteOnQuitAttempts {
            let outcome = applyMasterMute(false, device: muteDevice) { [weak self] muted in
                self?.recordingController.setLocalMicMute(muted)
            }
            if !outcome.usedLocalFallback {
                isMuted = false
                muteWarning = nil
                return
            }
            muteWarning = outcome.warning
        }

        FileHandle.standardError.write(Data(
            "[MUTE_NOT_RESTORED] Quitting with the microphone still muted system-wide — unmute it in System Settings > Sound > Input.\n".utf8))
    }

    public var outputDir: URL {
        let configPath = homeDir.appendingPathComponent(".config/ownscribe/config.toml")
        let configText = try? String(contentsOf: configPath, encoding: .utf8)
        return OwnscribeConfigReader.resolvedOutputDir(configText: configText, homeDir: homeDir)
    }

    public var isCliAvailable: Bool {
        pipelineRunner != nil
    }

    public var isMicCaptureEnabled: Bool {
        get { recordingController.enableMic }
        set { recordingController.enableMic = newValue }
    }

    var systemCaptureFactory: ((String) -> SystemAudioCapturing)? {
        get { recordingController.makeSystemCapture }
        set { recordingController.makeSystemCapture = newValue }
    }

    public var recordingControllerSilenceTimeout: TimeInterval {
        recordingController.silenceTimeout
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
