import SwiftUI

struct MeetingInspector: View {
    let meeting: MeetingSummary
    let transcript: TranscriptDocument?

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
                                if keyPoint.anchors.isEmpty {
                                    Text("—")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                } else {
                                    HStack(spacing: 8) {
                                        ForEach(Array(keyPoint.anchors.keys.sorted()), id: \.self) { token in
                                            if let anchors = keyPoint.anchors[token], let first = anchors.first {
                                                Text("\(token)→\(first.timestamp)")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
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
                        if track.isPresent {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
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
