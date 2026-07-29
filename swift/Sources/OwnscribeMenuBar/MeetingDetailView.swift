import SwiftUI

struct MeetingDetailView: View {
    let meeting: MeetingSummary

    @State private var transcript: TranscriptDocument?
    @State private var envelope: EnvelopeDocument?
    @State private var showBackchannel = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if let envelope {
                        EnvelopeStrip(buckets: envelope.buckets)
                            .padding(.horizontal, 26)
                            .padding(.bottom, 14)
                    }
                    transcriptBody
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.background)
            .inspector(isPresented: .constant(true)) {
                MeetingInspector(
                    meeting: meeting,
                    transcript: transcript,
                    onScrollToAnchor: { chip in scrollToAnchor(chip, using: proxy) }
                )
                .inspectorColumnWidth(min: 240, ideal: 286, max: 360)
            }
        }
        .navigationTitle(meeting.displayTitle)
        .task(id: meeting.id) {
            let assets = loadMeetingAssets(from: meeting)
            transcript = assets.transcript
            envelope = assets.envelope
        }
    }

    private func scrollToAnchor(_ chip: AnchorEvidenceChip, using proxy: ScrollViewProxy) {
        guard let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: chip.timestamp,
            provingToken: chip.token,
            in: transcript?.utterances ?? [],
            backchannelVisible: showBackchannel
        ) else { return }

        guard target.revealsBackchannel else {
            withAnimation { proxy.scrollTo(target.utteranceID, anchor: .center) }
            return
        }

        showBackchannel = true
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(target.utteranceID, anchor: .center) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.displayTitle)
                .font(.title3.weight(.bold))
            Text(headerDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(EdgeInsets(top: 22, leading: 26, bottom: 14, trailing: 26))
    }

    private var headerDetail: String {
        var parts = [meeting.displayDate]
        if let transcript {
            if transcript.duration > 0 { parts.append(Self.durationText(transcript.duration)) }
            if !transcript.language.isEmpty { parts.append(transcript.language) }
            if !transcript.speakers.isEmpty { parts.append("^[\(transcript.speakers.count) voix](inflect: true)") }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if let transcript, !transcript.utterances.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if transcript.utterances.contains(where: \.isBackchannel) {
                    Toggle("Afficher les interventions courtes", isOn: $showBackchannel)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.caption)
                }
                ForEach(visibleUtterances) { utterance in
                    UtteranceRow(utterance: utterance)
                        .id(utterance.id)
                }
            }
            .padding(EdgeInsets(top: 4, leading: 26, bottom: 30, trailing: 26))
        } else {
            Text(meeting.hasTranscript ? "Transcript illisible." : "Pas encore de transcript pour cette réunion.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(26)
        }
    }

    private var visibleUtterances: [Utterance] {
        guard let transcript else { return [] }
        return showBackchannel ? transcript.utterances : transcript.utterances.filter { !$0.isBackchannel }
    }


    static func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct UtteranceRow: View {
    let utterance: Utterance

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(utterance.timecode)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    speakerAvatar
                    Text(utterance.speaker)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SpeakerAvatarStyle.color(for: utterance.speaker))
                }
                Text(utterance.text)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }

    private var speakerAvatar: some View {
        ZStack {
            Circle()
                .fill(SpeakerAvatarStyle.color(for: utterance.speaker))
                .frame(width: 18, height: 18)
            Text(SpeakerAvatarStyle.displayLabel(for: utterance.speaker))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
