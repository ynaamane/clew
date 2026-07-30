import SwiftUI

struct LibraryWindow: View {
    static let sceneID = "library"

    @Environment(AppState.self) private var appState
    @State private var selectedFilter: LibraryFilter = .all
    @State private var selectedMeeting: MeetingSummary?
    @State private var showBannerDetail = false

    private var sections: [LibrarySidebarSection] {
        LibrarySidebar.sections(for: appState.recentMeetings, enrolledSpeakers: appState.enrolledSpeakers)
    }

    private var shownMeetings: [MeetingSummary] {
        selectedFilter.apply(to: appState.recentMeetings)
    }

    var body: some View {
        NavigationSplitView {
            ZStack(alignment: .top) {
                List(selection: $selectedFilter) {
                    ForEach(sections) { section in
                        Section(section.title) {
                            ForEach(section.items) { item in
                                Label(item.title, systemImage: item.filter.symbolName)
                                    .badge(BadgeText.badgeText(for: item))
                                    .tag(item.filter)
                            }
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 216, max: 280)
                .glassEffect()

                if let banner = currentBanner, showBannerDetail || banner.severity == .warning {
                    VStack {
                        InlineBanner(state: banner) {
                            appState.dismissFailure()
                            showBannerDetail = false
                        }
                        .padding(12)
                        Spacer()
                    }
                }
            }
        } content: {
            MeetingListColumn(meetings: shownMeetings, selection: $selectedMeeting)
                .navigationSplitViewColumnWidth(min: 240, ideal: 292, max: 380)
        } detail: {
            if let meeting = selectedMeeting {
                MeetingDetailView(meeting: meeting)
            } else {
                LibraryEmptyState(hasMeetings: !appState.recentMeetings.isEmpty)
            }
        }
        .navigationTitle("Réunions")
        .toolbar {
            ToolbarItemGroup {
                if case .processing(let step, _) = appState.phase {
                    Label(step, systemImage: "circle.lefthalf.filled")
                        .foregroundStyle(.orange)
                }
                if case .failed = appState.phase {
                    Button {
                        showBannerDetail.toggle()
                    } label: {
                        Label("Error", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                Button {
                    Task { await appState.toggleRecording() }
                } label: {
                    Label(appState.isRecording ? "Arrêter" : "Enregistrer", systemImage: "record.circle")
                }
            }
        }
        .task {
            appState.refreshRecentMeetings()
            appState.refreshCliAvailability()
        }
        .onChange(of: appState.phase) { _, newPhase in
            if case .failed = newPhase {
                showBannerDetail = true
            }
        }
    }

    private var currentBanner: BannerState? {
        BannerState.bannerState(
            phase: appState.phase,
            muteWarning: appState.muteWarning,
            muteIndicator: appState.muteIndicator,
            isCliAvailable: appState.isCliAvailable
        )
    }
}

private struct MeetingListColumn: View {
    let meetings: [MeetingSummary]
    @Binding var selection: MeetingSummary?

    var body: some View {
        List(meetings, selection: $selection) { meeting in
            MeetingRow(meeting: meeting)
                .tag(meeting)
        }
        .navigationTitle("Réunions")
    }
}

private struct MeetingRow: View {
    let meeting: MeetingSummary
    @State private var summaryExcerpt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.displayTitle)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(meeting.displayDate)
                if let count = meeting.unanchoredClaimCount, count > 0 {
                    MeetingStatusBadge(variant: .unanchored(count: count))
                }
                if let count = meeting.actionItemCount, count > 0 {
                    MeetingStatusBadge(variant: .actionItems(count: count))
                }
                if !meeting.hasSummary {
                    Text("non indexée")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let excerpt = summaryExcerpt {
                Text(excerpt)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .task {
            loadSummaryExcerpt()
        }
    }

    private func loadSummaryExcerpt() {
        guard meeting.hasSummary, summaryExcerpt == nil else { return }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configPath = homeDir.appendingPathComponent(".config/ownscribe/config.toml")

        summaryExcerpt = MeetingRowSummary.loadExcerpt(
            from: meeting.directory,
            configURL: configPath
        )
    }
}

private struct LibraryEmptyState: View {
    let hasMeetings: Bool

    var body: some View {
        ContentUnavailableView {
            Label(hasMeetings ? "Aucune réunion sélectionnée" : "Aucune réunion", systemImage: "waveform")
        } description: {
            Text(hasMeetings
                ? "Choisis une réunion à gauche pour lire son transcript."
                : "Lance un enregistrement pendant un appel : le transcript et le résumé apparaîtront ici.")
        }
    }
}
