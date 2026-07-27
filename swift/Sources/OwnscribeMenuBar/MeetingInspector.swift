import SwiftUI

struct MeetingInspector: View {
    let meeting: MeetingSummary
    let transcript: TranscriptDocument?

    @State private var summary: SummaryDocument?

    var body: some View {
        Form {
            if let summary {
                Section("Résumé") {
                    Text(summary.prose)
                        .font(.callout)
                }
                if !summary.keyPoints.isEmpty {
                    Section("Points clés") {
                        ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { _, point in
                            Text(point)
                                .font(.callout)
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
        }
        .formStyle(.grouped)
        .task(id: meeting.id) { summary = loadSummary() }
    }

    private func loadSummary() -> SummaryDocument? {
        let path = meeting.directory.appendingPathComponent("summary.md")
        return try? SummaryDocument(contentsOf: path)
    }
}
