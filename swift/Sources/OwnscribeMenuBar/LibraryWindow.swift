import SwiftUI

struct LibraryWindow: View {
    static let sceneID = "library"

    @Environment(AppState.self) private var appState
    @State private var selectedFilter: LibraryFilter = .all
    @State private var selectedMeeting: MeetingSummary?

    private var sections: [LibrarySidebarSection] {
        LibrarySidebar.sections(for: appState.recentMeetings, enrolledSpeakers: appState.enrolledSpeakers)
    }

    private var shownMeetings: [MeetingSummary] {
        selectedFilter.apply(to: appState.recentMeetings)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedFilter) {
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            Label(item.title, systemImage: item.filter.symbolName)
                                .badge(item.count ?? 0)
                                .tag(item.filter)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 216, max: 280)
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
                Button {
                    Task { await appState.toggleRecording() }
                } label: {
                    Label(appState.isRecording ? "Arrêter" : "Enregistrer", systemImage: "record.circle")
                }
            }
        }
        .task { appState.refreshRecentMeetings() }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(meeting.displayTitle)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(meeting.displayDate)
                if meeting.unanchoredClaimCount > 0 {
                    Text("^[\(meeting.unanchoredClaimCount) non ancré](inflect: true)")
                        .foregroundStyle(.orange)
                }
                if !meeting.hasSummary {
                    Text("non indexée")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
