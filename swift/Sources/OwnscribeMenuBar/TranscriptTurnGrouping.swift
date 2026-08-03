import Foundation

public struct TranscriptTurn: Identifiable, Equatable {
    public let id: UUID
    public let speaker: String
    public let firstTimecode: String
    public let utterances: [Utterance]

    public init(speaker: String, utterances: [Utterance]) {
        self.id = utterances.first?.id ?? UUID()
        self.speaker = speaker
        self.firstTimecode = utterances.first?.timecode ?? ""
        self.utterances = utterances
    }
}

public enum TranscriptTurnGrouping {
    public static func turns(from utterances: [Utterance]) -> [TranscriptTurn] {
        var result: [TranscriptTurn] = []

        for utterance in utterances {
            if let last = result.last, last.speaker == utterance.speaker {
                result[result.count - 1] = TranscriptTurn(
                    speaker: last.speaker, utterances: last.utterances + [utterance])
            } else {
                result.append(TranscriptTurn(speaker: utterance.speaker, utterances: [utterance]))
            }
        }

        return result
    }
}
