import SwiftUI

struct MeetingInspector: View {
    let meeting: MeetingSummary
    let transcript: TranscriptDocument?
    let onScrollToAnchor: (String) -> Void

    @State private var summary: SummaryDocument?
    @State private var keyPointsWithAnchors: [KeyPointWithAnchors]?
    @State private var tracks: [AudioTrackPresence] = []

    var body: some View {
        Form {
            if let summary {
                Section("Résumé") {
                    Text(summary.prose)
                        .font(.callout)
                }
                if let keyPoints = keyPointsWithAnchors, !keyPoints.isEmpty {
                    Section("Points clés") {
                        ForEach(Array(keyPoints.enumerated()), id: \.offset) { _, keyPoint in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(keyPoint.text)
                                    .font(.callout)
                                evidenceRow(for: keyPoint)
                            }
                        }
                    }
                }
                Section("Actions") {
                    if summary.actionItems.isEmpty {
                        Text(summary.actionItemsPlaceholder)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                            Text(item)
                                .font(.callout)
                        }
                    }
                }
            } else {
                Section {
                    Text("Pas encore de résumé — cette réunion n'est pas indexée par la recherche.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let transcript, !transcript.speakers.isEmpty {
                Section("Voix") {
                    ForEach(transcript.speakers, id: \.self) { speaker in
                        Text(speaker)
                            .font(.callout)
                    }
                }
            }

            Section("Pistes audio") {
                ForEach(tracks, id: \.filename) { track in
                    HStack {
                        Text(track.filename)
                            .font(.callout)
                        Spacer()
                        Text(track.displayStatus)
                            .foregroundStyle(track.hasContent ? .green : .secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .glassEffect()
        .task(id: meeting.id) {
            summary = loadSummary()
            keyPointsWithAnchors = MeetingInspectorState.loadKeyPointsWithAnchors(from: meeting.directory)
            tracks = AudioTracksPresence.checkTracks(in: meeting.directory)
        }
    }

    @ViewBuilder
    private func evidenceRow(for keyPoint: KeyPointWithAnchors) -> some View {
        let display = AnchorEvidenceDisplayModel.display(for: keyPoint)
        switch display {
        case .notYetVerified:
            Text(display.placeholderText ?? "")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .italic()
        case .noEvidenceFound:
            Text(display.placeholderText ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .evidence(let chips):
            HStack(spacing: 8) {
                ForEach(chips, id: \.label) { chip in
                    evidenceChip(chip)
                }
            }
        }
    }

    @ViewBuilder
    private func evidenceChip(_ chip: AnchorEvidenceChip) -> some View {
        let utterances = transcript?.utterances ?? []
        switch AnchorScrollTargeting.interactivity(forAnchorTimestamp: chip.timestamp, in: utterances) {
        case .scrollButton:
            Button(chip.label) { onScrollToAnchor(chip.timestamp) }
                .buttonStyle(.link)
                .font(.caption2)
        case .staticText:
            Text(chip.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func loadSummary() -> SummaryDocument? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configURL = homeDir.appendingPathComponent(".config/ownscribe/config.toml")
        return MeetingInspectorState.loadSummary(
            from: meeting.directory,
            configURL: configURL,
            fileManager: FileManager.default
        )
    }
}
