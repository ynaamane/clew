import AppKit
import Foundation
import OSLog
import OwnscribeCapture

@MainActor
@Observable
public final class AppState {
    public enum Phase: Equatable {
        case idle
        case recording(startedAt: Date)
        case processing(step: String, fraction: Double?, detail: String? = nil)
        case done(directory: URL)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle {
        didSet {
            guard phase != oldValue else { return }
            AppLogger.recording.info("Phase transition: \(oldValue.logDescription()) -> \(self.phase.logDescription())")
            if case .failed(let message) = phase {
                AppLogger.recording.error("Recording failed: \(message)")
            }
        }
    }
    public private(set) var recentMeetings: [MeetingSummary] = []
    public private(set) var isMuted: Bool = false
    public private(set) var muteWarning: String?
    public private(set) var muteIndicator: MuteIndicator = .notMuted

    var unmuteOnQuitAttempts = 3
    private var appOwnsMute = false

    private let recordingController = RecordingController()
    private let muteDevice: AudioMuteDevice
    private let hotKeyRegistration = GlobalHotKeyRegistration()
    private let terminationSignals: TerminationSignalHandlers
    private let homeDir: URL
    private var pipelineRunner: PipelineRunning?

    public init(
        homeDir: URL = FileManager.default.homeDirectoryForCurrentUser,
        muteDevice: AudioMuteDevice = DefaultInputAudioMuteDevice(),
        terminationSignals: TerminationSignalHandlers? = nil
    ) {
        self.homeDir = homeDir
        self.muteDevice = muteDevice
        self.terminationSignals = terminationSignals ?? TerminationSignalHandlers()
        self.pipelineRunner = PipelineRunner.makeDefault(homeDir: homeDir)
        seedMuteStateFromHardware()
        applyConfigSettings()
        refreshRecentMeetings()
        registerMuteHotKey()
        registerTerminationObserver()
        registerTerminationSignalHandlers()
    }

    private func seedMuteStateFromHardware() {
        guard let hardwareMuted = muteDevice.readInputMute() else {
            isMuted = false
            muteIndicator = .notMuted
            appOwnsMute = false
            return
        }

        isMuted = hardwareMuted
        muteIndicator = hardwareMuted ? .mutedVerified : .notMuted
        appOwnsMute = false
    }

    private func applyConfigSettings() {
        let configPath = homeDir.appendingPathComponent(".config/clew/config.toml")
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

    private func registerTerminationSignalHandlers() {
        terminationSignals.register { [weak self] in
            self?.restoreUnmutedOnQuit()
        }
    }

    public func toggleMasterMute() {
        let requestedMuted = !isMuted
        AppLogger.mute.info("Mute toggle requested: \(requestedMuted)")

        let outcome = applyMasterMute(requestedMuted, device: muteDevice) { [weak self] muted in
            self?.recordingController.setLocalMicMute(muted)
        }

        let verified = !outcome.usedLocalFallback
        AppLogger.mute.info("Mute outcome: requested=\(requestedMuted), display=\(outcome.displayMuted), verified=\(verified)")

        isMuted = outcome.displayMuted
        muteWarning = outcome.warning
        muteIndicator = indicator(for: outcome)
        if verified {
            appOwnsMute = true
            AppLogger.mute.info("App took mute ownership")
        }
    }

    private func indicator(for outcome: MasterMuteOutcome) -> MuteIndicator {
        guard outcome.displayMuted else { return .notMuted }
        return outcome.usedLocalFallback ? .mutedUnverified : .mutedVerified
    }

    public func restoreUnmutedOnQuit() {
        guard isMuted, appOwnsMute else {
            AppLogger.mute.info("restoreUnmutedOnQuit: skipped (isMuted=\(self.isMuted), appOwnsMute=\(self.appOwnsMute))")
            return
        }

        AppLogger.mute.info("restoreUnmutedOnQuit: attempting unmute with \(self.unmuteOnQuitAttempts) attempts")

        for attempt in 1...unmuteOnQuitAttempts {
            let outcome = applyMasterMute(false, device: muteDevice) { [weak self] muted in
                self?.recordingController.setLocalMicMute(muted)
            }
            if !outcome.usedLocalFallback {
                isMuted = false
                muteWarning = nil
                AppLogger.mute.info("restoreUnmutedOnQuit: succeeded on attempt \(attempt)")
                return
            }
            AppLogger.mute.warning("restoreUnmutedOnQuit: attempt \(attempt) failed")
            muteWarning = outcome.warning
        }

        let failureMessage = "[MUTE_NOT_RESTORED] Quitting with the microphone still muted system-wide — unmute it in System Settings > Sound > Input.\n"
        AppLogger.mute.fault("restoreUnmutedOnQuit: FAILED after all attempts")
        FileHandle.standardError.write(Data(failureMessage.utf8))
    }

    public var outputDir: URL {
        let configPath = homeDir.appendingPathComponent(".config/clew/config.toml")
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

    public var isRecording: Bool {
        if case .recording = phase { return true }
        return false
    }

    public var enrolledSpeakers: [String] {
        EnrolledSpeakerStore.names(in: homeDir)
    }

    var systemCaptureFactory: ((String) -> SystemAudioCapturing)? {
        get { recordingController.makeSystemCapture }
        set { recordingController.makeSystemCapture = newValue }
    }

    var micCaptureFactory: (() -> MicCapture?) {
        get { recordingController.makeMicCapture }
        set { recordingController.makeMicCapture = newValue }
    }

    var pipelineRunnerFactory: (() -> PipelineRunning?)? {
        didSet {
            if let factory = pipelineRunnerFactory {
                pipelineRunner = factory()
            }
        }
    }

    public var recordingControllerSilenceTimeout: TimeInterval {
        recordingController.silenceTimeout
    }

    public func refreshRecentMeetings() {
        let meetings = RecentTranscriptsStore.recentMeetings(in: outputDir)
        AppLogger.library.info("Refreshed recent meetings: found \(meetings.count) meetings")
        recentMeetings = meetings
    }

    public func refreshCliAvailability() {
        if let factory = pipelineRunnerFactory {
            pipelineRunner = factory()
        } else {
            pipelineRunner = PipelineRunner.makeDefault(homeDir: homeDir)
        }

        if let runner = pipelineRunner as? PipelineRunner {
            AppLogger.pipeline.info("CLI binary found at: \(runner.binary.path, privacy: .public)")
        } else if pipelineRunner != nil {
            AppLogger.pipeline.info("CLI available via factory")
        } else {
            AppLogger.pipeline.warning("CLI binary not found")
        }
    }

    public func dismissFailure() {
        guard case .failed = phase else { return }
        phase = .idle
    }

    public func toggleRecording() async {
        switch phase {
        case .idle, .done, .failed, .processing:
            refreshCliAvailability()
            await startRecording()
        case .recording:
            await stopRecordingAndProcess()
        }
    }

    private func startRecording() async {
        let paths = MeetingOutputPaths(baseDir: outputDir)
        let micEnabled = recordingController.enableMic
        let silenceTimeout = recordingController.silenceTimeout

        let timestamp = AppLogger.timestampPrefix(from: paths.directory.lastPathComponent)
        AppLogger.recording.info("Starting recording: directory=\(timestamp, privacy: .public), micEnabled=\(micEnabled), silenceTimeout=\(silenceTimeout)s")

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

    public enum CancelDecision: Equatable {
        case cancel
        case refuse
    }

    static func cancelDecision(for currentPhase: Phase) -> CancelDecision {
        guard case .processing = currentPhase else { return .refuse }
        return .cancel
    }

    static func phaseAfterCancellation() -> Phase {
        .idle
    }

    public var isProcessing: Bool {
        Self.cancelDecision(for: phase) == .cancel
    }

    public func cancelProcessing() {
        guard Self.cancelDecision(for: phase) == .cancel else { return }

        AppLogger.pipeline.info("Cancellation requested by the user")
        pipelineRunner?.cancel()
        phase = Self.phaseAfterCancellation()
    }

    static func terminalPhase(after currentPhase: Phase, completedWith directory: URL) -> Phase? {
        guard case .processing = currentPhase else { return nil }
        return .done(directory: directory)
    }

    static func terminalPhase(after currentPhase: Phase, failedWith error: String) -> Phase? {
        guard case .processing = currentPhase else { return nil }
        return .failed(error)
    }

    private func runPipeline(on recordingURL: URL) async {
        guard let pipelineRunner else {
            phase = .failed(PipelineRunner.RunError.binaryNotFound.description)
            return
        }
        phase = .processing(step: "starting", fraction: nil)

        let directory = recordingURL.deletingLastPathComponent()
        let timestamp = AppLogger.timestampPrefix(from: directory.lastPathComponent)
        AppLogger.pipeline.info("Pipeline started: directory=\(timestamp, privacy: .public)")

        do {
            try await pipelineRunner.run(arguments: ["resume", directory.path]) { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handle(event)
                }
            }
            if let nextPhase = Self.terminalPhase(after: phase, completedWith: directory) {
                phase = nextPhase
                refreshRecentMeetings()
                AppLogger.pipeline.info("Pipeline completed: directory=\(timestamp, privacy: .public)")
            }
        } catch {
            if let nextPhase = Self.terminalPhase(after: phase, failedWith: String(describing: error)) {
                phase = nextPhase
                AppLogger.pipeline.error("Pipeline failed: \(String(describing: error))")
            }
        }
    }

    internal func handle(_ event: ProgressEvent) {
        guard case .processing(let currentStep, let currentFraction, _) = phase else { return }

        AppLogger.pipeline.debug("Pipeline progress: event=\(event.event.rawValue, privacy: .public), step=\(event.step, privacy: .public)")

        switch event.event {
        case .begin, .update:
            phase = .processing(step: event.step, fraction: event.fraction, detail: nil)
        case .detail:
            phase = .processing(step: currentStep, fraction: currentFraction, detail: event.detail)
        case .complete, .fail:
            break
        }
    }
}
