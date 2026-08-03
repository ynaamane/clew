import AppKit
import SwiftUI

struct LibraryWindow: View {
    static let sceneID = "library"

    @Environment(AppState.self) private var appState
    @State private var selectedFilter: LibraryFilter = .all
    @State private var selectedMeeting: MeetingSummary?
    @State private var showBannerDetail = false
    @State private var searchQuery: String = ""
    @State private var meetingDurations: [String: TimeInterval] = [:]

    private var sections: [LibrarySidebarSection] {
        LibrarySidebar.sections(for: appState.recentMeetings, enrolledSpeakers: appState.enrolledSpeakers)
    }

    private var shownMeetings: [MeetingSummary] {
        let filtered = selectedFilter.apply(to: appState.recentMeetings)
        return MeetingSearchFilter.filter(filtered, query: searchQuery)
    }

    private var navigationSubtitleText: String {
        let known = appState.recentMeetings.compactMap { meetingDurations[$0.id] }
        return LibraryNavigationSubtitle.text(meetingCount: appState.recentMeetings.count, knownDurations: known)
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
                .scrollContentBackground(.hidden)

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
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .navigationSplitViewColumnWidth(min: 180, ideal: 216, max: 280)
            .accessibilityIdentifier("library.sidebar")
        } content: {
            MeetingListColumn(meetings: shownMeetings, selection: $selectedMeeting, searchQuery: $searchQuery)
                .navigationSplitViewColumnWidth(min: 240, ideal: 292, max: 380)
        } detail: {
            if let meeting = selectedMeeting {
                MeetingDetailView(meeting: meeting)
            } else {
                LibraryEmptyState(hasMeetings: !appState.recentMeetings.isEmpty)
            }
        }
        .navigationTitle("Réunions")
        .navigationSubtitle(navigationSubtitleText)
        .tint(AppAccentColor.color)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup {
                if case .processing(let step, _, let detail) = appState.phase {
                    Label(detail ?? step, systemImage: "circle.lefthalf.filled")
                        .foregroundStyle(.orange)
                    Button {
                        appState.cancelProcessing()
                    } label: {
                        Label("Annuler", systemImage: "stop.circle")
                    }
                    .accessibilityIdentifier("library.cancelButton")
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
                .accessibilityIdentifier("library.recordButton")
            }
        }
        .task {
            appState.refreshRecentMeetings()
            appState.refreshCliAvailability()
            let resolved: MeetingSummary? = LibrarySelection.resolve(current: selectedMeeting, shown: appState.recentMeetings)
            selectedMeeting = resolved
            loadMeetingDurations()
        }
        .onChange(of: appState.recentMeetings) { _, newMeetings in
            let resolved: MeetingSummary? = LibrarySelection.resolve(current: selectedMeeting, shown: newMeetings)
            selectedMeeting = resolved
            loadMeetingDurations()
        }
        .onChange(of: shownMeetings) { _, newShown in
            let resolved: MeetingSummary? = LibrarySelection.resolve(current: selectedMeeting, shown: newShown)
            selectedMeeting = resolved
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

    private func loadMeetingDurations() {
        var result: [String: TimeInterval] = [:]
        for meeting in appState.recentMeetings {
            let transcriptURL = meeting.directory.appendingPathComponent("transcript.md")
            if let document = try? TranscriptDocument(contentsOf: transcriptURL), document.duration > 0 {
                result[meeting.id] = document.duration
            }
        }
        meetingDurations = result
    }
}

private struct MeetingListColumn: View {
    let meetings: [MeetingSummary]
    @Binding var selection: MeetingSummary?
    @Binding var searchQuery: String

    var body: some View {
        List(meetings, selection: $selection) { meeting in
            MeetingRow(meeting: meeting)
                .tag(meeting)
        }
        .accessibilityIdentifier("library.meetingList")
        .searchable(text: $searchQuery, placement: .toolbar, prompt: "Rechercher dans les réunions…")
        .accessibilityIdentifier("library.search")
    }
}

private struct MeetingRow: View {
    let meeting: MeetingSummary
    @State private var summaryExcerpt: String?
    @State private var transcriptFacts: TranscriptDocument?

    private var anchorState: UnanchoredClaimBadge {
        UnanchoredClaimBadge.state(unanchoredClaimCount: meeting.unanchoredClaimCount)
    }

    private var rowMetaText: String {
        MeetingRowMeta.text(
            date: meeting.displayDate,
            duration: transcriptFacts?.duration,
            speakerCount: transcriptFacts?.speakers.count
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.displayTitle)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(rowMetaText)
                if let badge = MeetingStatusBadge.Variant(anchorState: anchorState) {
                    MeetingStatusBadge(variant: badge)
                }
                if let count = meeting.actionItemCount, count > 0 {
                    MeetingStatusBadge(variant: .actionItems(count: count))
                }
                if !meeting.hasSummary {
                    MeetingStatusBadge(variant: .notIndexed)
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
            loadTranscriptFacts()
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

    private func loadTranscriptFacts() {
        guard transcriptFacts == nil else { return }
        let transcriptURL = meeting.directory.appendingPathComponent("transcript.md")
        transcriptFacts = try? TranscriptDocument(contentsOf: transcriptURL)
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
