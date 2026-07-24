import SwiftUI

struct MenuBarContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            muteSection
            Divider()
            recordingSection
            Divider()
            recentMeetingsSection
            Divider()
            SettingsLink {
                Text("Settings…")
            }
            Button("Quit ownscribe") {
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
            Label(
                appState.isMuted ? "Unmute (\u{2318}\u{21E7}M)" : "Mute (\u{2318}\u{21E7}M)",
                systemImage: appState.isMuted ? "mic.slash.fill" : "mic.fill"
            )
        }
        .font(.headline)
        .tint(appState.isMuted ? .red : .primary)

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
        case .processing(let step, let fraction):
            HStack {
                ProgressView(value: fraction)
                Text(step)
                    .font(.caption)
            }
        }
    }

    private var startButtonTitle: String {
        if case .done = appState.phase { return "Start Recording (last meeting saved)" }
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
