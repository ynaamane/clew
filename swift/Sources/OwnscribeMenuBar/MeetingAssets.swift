import Foundation

public struct MeetingAssets {
    public let transcript: TranscriptDocument?
    public let envelope: EnvelopeDocument?
}

public func loadMeetingAssets(from meeting: MeetingSummary) -> MeetingAssets {
    let transcriptPath = meeting.directory.appendingPathComponent("transcript.md")
    let transcript = try? TranscriptDocument(contentsOf: transcriptPath)

    let envelope = EnvelopeDocument.load(from: meeting.directory)

    return MeetingAssets(transcript: transcript, envelope: envelope)
}
