import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            muteSection
            Divider()
            recordingSection
            Divider()
            recentMeetingsSection
            Divider()
            Button("Ouvrir Clew") {
                openWindow(id: LibraryWindow.sceneID)
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("0", modifiers: .command)

            SettingsLink {
                Text("Settings…")
            }
            Button("Quit Clew") {
                appState.restoreUnmutedOnQuit()
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
        .task {
            appState.refreshRecentMeetings()
        }
    }

    @ViewBuilder
    private var muteSection: some View {
        Button {
            appState.toggleMasterMute()
        } label: {
            Label(muteButtonTitle, systemImage: appState.muteIndicator.symbolName)
        }
        .font(.headline)
        .tint(muteTint)

        if appState.muteIndicator == .mutedUnverified {
            Text("Recording only — the call may still hear you")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        if let warning = appState.muteWarning {
            Text(warning)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var recordingSection: some View {
        switch appState.phase {
        case .idle, .done, .failed:
            Button(startButtonTitle) {
                Task { await appState.toggleRecording() }
            }
            if case .failed(let message) = appState.phase {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        case .recording(let startedAt):
            Button("Stop Recording") {
                Task { await appState.toggleRecording() }
            }
            Text("Recording since \(startedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .processing(let step, let fraction, let detail):
            Button(startButtonTitle) {
                Task { await appState.toggleRecording() }
            }
            HStack {
                ProgressView(value: fraction)
                Text(detail ?? step)
                    .font(.caption)
            }
        }
    }

    private var muteButtonTitle: String {
        switch appState.muteIndicator {
        case .notMuted: return "Mute (\u{2318}\u{21E7}M)"
        case .mutedVerified: return "Unmute (\u{2318}\u{21E7}M)"
        case .mutedUnverified: return "Mute not confirmed (\u{2318}\u{21E7}M)"
        }
    }

    private var muteTint: Color {
        switch appState.muteIndicator {
        case .notMuted: return .primary
        case .mutedVerified: return .red
        case .mutedUnverified: return .orange
        }
    }

    private var startButtonTitle: String {
        if case .done = appState.phase { return "Start Recording (last meeting saved)" }
        if case .processing = appState.phase { return "Start Next Recording" }
        return "Start Recording"
    }

    @ViewBuilder
    private var recentMeetingsSection: some View {
        if appState.recentMeetings.isEmpty {
            Text("No meetings yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(appState.recentMeetings.prefix(5)) { meeting in
                Button {
                    NSWorkspace.shared.open(meeting.directory)
                } label: {
                    HStack {
                        Text(meeting.directory.lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        if !meeting.hasSummary {
                            Text("no summary")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
