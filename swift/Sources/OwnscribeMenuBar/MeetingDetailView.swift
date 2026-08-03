import SwiftUI

struct MeetingDetailView: View {
    let meeting: MeetingSummary

    @State private var transcript: TranscriptDocument?
    @State private var envelope: EnvelopeDocument?
    @State private var keyPointsWithAnchors: [KeyPointWithAnchors]?
    @State private var showBackchannel = false
    @State private var highlightedUtteranceID: UUID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if let anchoringSummary {
                        anchoringCallout(anchoringSummary)
                    }
                    if let envelope {
                        EnvelopeStrip(buckets: envelope.buckets)
                            .padding(.horizontal, 26)
                            .padding(.bottom, 14)
                            .accessibilityIdentifier("meeting.envelope")
                    }
                    transcriptBody
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.background)
            .accessibilityIdentifier("meeting.transcript")
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
            keyPointsWithAnchors = MeetingInspectorState.loadKeyPointsWithAnchors(from: meeting.directory)
        }
    }

    private var anchoringSummary: AnchoringSummary? {
        AnchoringSummaryCalculator.summary(for: keyPointsWithAnchors ?? [])
    }

    private func anchoringCallout(_ summary: AnchoringSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Image(systemName: "flag.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(AnchoringCalloutText.text(for: summary))
                .font(.callout)
        }
        .padding(EdgeInsets(top: 9, leading: 11, bottom: 9, trailing: 11))
        .background(Color.orange.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 26)
        .padding(.bottom, 8)
        .accessibilityIdentifier("meeting.anchoringCallout")
    }

    private func scrollToAnchor(_ chip: AnchorEvidenceChip, using proxy: ScrollViewProxy) {
        guard let target = AnchorScrollTargeting.target(
            forAnchorTimestamp: chip.timestamp,
            provingToken: chip.token,
            in: transcript?.utterances ?? [],
            backchannelVisible: showBackchannel
        ) else { return }

        highlightedUtteranceID = target.utteranceID

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
        MeetingHeaderDetail.text(
            date: meeting.displayDate,
            duration: transcript?.duration,
            language: transcript?.language ?? "",
            speakerCount: transcript?.speakers.count
        )
    }

    @ViewBuilder
    private var transcriptBody: some View {
        if let transcript, !transcript.utterances.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if let foldLabel = backchannelFoldLabel {
                    backchannelFoldPill(foldLabel)
                }
                ForEach(TranscriptTurnGrouping.turns(from: visibleUtterances)) { turn in
                    TurnView(turn: turn, highlightedUtteranceID: highlightedUtteranceID)
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

    private var backchannelFoldLabel: BackchannelFoldLabel? {
        guard let transcript else { return nil }
        return BackchannelFoldSummary.label(for: transcript.utterances)
    }

    private func backchannelFoldPill(_ label: BackchannelFoldLabel) -> some View {
        Button {
            showBackchannel.toggle()
        } label: {
            Text((showBackchannel ? "▾ " : "▸ ") + BackchannelFoldSummary.text(for: label))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.09))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("meeting.backchannelToggle")
    }

    private var visibleUtterances: [Utterance] {
        guard let transcript else { return [] }
        return showBackchannel ? transcript.utterances : transcript.utterances.filter { !$0.isBackchannel }
    }
}

private struct TurnView: View {
    let turn: TranscriptTurn
    let highlightedUtteranceID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                speakerAvatar
                Text(turn.speaker)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpeakerAvatarStyle.color(for: turn.speaker))
                Text(turn.firstTimecode)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            ForEach(turn.utterances) { utterance in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(utterance.timecode)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 40, alignment: .leading)
                    Text(utterance.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 1)
                .padding(.horizontal, 4)
                .background(
                    LineHighlightDecision.isHighlighted(lineID: utterance.id, highlightedID: highlightedUtteranceID)
                        ? Color.accentColor.opacity(0.12)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .id(utterance.id)
            }
        }
        .padding(.top, 6)
    }

    private var speakerAvatar: some View {
        ZStack {
            Circle()
                .fill(SpeakerAvatarStyle.color(for: turn.speaker))
                .frame(width: 18, height: 18)
            Text(SpeakerAvatarStyle.displayLabel(for: turn.speaker))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}
