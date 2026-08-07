import SwiftUI

struct MeetingInspector: View {
    let meeting: MeetingSummary
    let transcript: TranscriptDocument?
    let onScrollToAnchor: (AnchorEvidenceChip) -> Void

    @State private var summary: SummaryDocument?
    @State private var keyPointsWithAnchors: [KeyPointWithAnchors]?
    @State private var tracks: [AudioTrackPresence] = []

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let summary {
                        section("Résumé") {
                            Text(summary.prose)
                                .font(.callout)
                        }
                        Divider()

                        if let keyPoints = keyPointsWithAnchors, !keyPoints.isEmpty {
                            section(keyPointsCaption(for: keyPoints)) {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(Array(keyPoints.enumerated()), id: \.offset) { _, keyPoint in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(keyPoint.text)
                                                .font(.callout)
                                            evidenceRow(for: keyPoint)
                                        }
                                    }
                                }
                            }
                            Divider()
                        }

                        section("Actions") {
                            if summary.actionItems.isEmpty {
                                Text(summary.actionItemsPlaceholder)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .italic()
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                                        Text(item)
                                            .font(.callout)
                                    }
                                }
                            }
                        }
                        Divider()
                    } else {
                        section(nil) {
                            Text("Pas encore de résumé — cette réunion n'est pas indexée par la recherche.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Divider()
                    }

                    if let transcript, !transcript.speakers.isEmpty {
                        section("Voix") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(transcript.speakers, id: \.self) { speaker in
                                    Text(speaker)
                                        .font(.callout)
                                }
                            }
                        }
                        Divider()
                    }

                    section("Pistes audio") {
                        VStack(alignment: .leading, spacing: 6) {
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
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .accessibilityIdentifier("inspector.form")
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .task(id: meeting.id) {
            summary = loadSummary()
            keyPointsWithAnchors = MeetingInspectorState.loadKeyPointsWithAnchors(from: meeting.directory)
            tracks = AudioTracksPresence.checkTracks(in: meeting.directory)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
            }
            content()
        }
        .padding(.vertical, 9)
    }

    private func keyPointsCaption(for keyPoints: [KeyPointWithAnchors]) -> String {
        PointsClesCaption.text(for: AnchoringSummaryCalculator.summary(for: keyPoints))
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
        let timestampText = Text(chip.timestamp)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.tint)
        switch AnchorScrollTargeting.interactivity(forAnchorTimestamp: chip.timestamp, in: utterances) {
        case .scrollButton:
            Button {
                onScrollToAnchor(chip)
            } label: {
                timestampText
            }
            .buttonStyle(.plain)
        case .staticText:
            timestampText
        }
    }

    private func loadSummary() -> SummaryDocument? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configURL = homeDir.appendingPathComponent(".config/clew/config.toml")
        return MeetingInspectorState.loadSummary(
            from: meeting.directory,
            configURL: configURL,
            fileManager: FileManager.default
        )
    }
}
