import Foundation

public struct AnchorScrollTarget: Equatable {
    public let utteranceID: UUID
    public let revealsBackchannel: Bool

    public init(utteranceID: UUID, revealsBackchannel: Bool) {
        self.utteranceID = utteranceID
        self.revealsBackchannel = revealsBackchannel
    }
}

public enum AnchorChipInteractivity: Equatable {
    case staticText
    case scrollButton
}

public struct AnchorScrollTargeting {
    public static func seconds(fromAnchorTimestamp text: String) -> TimeInterval? {
        let parts = text.split(separator: ":").map(String.init)
        guard parts.count >= 2, parts.allSatisfy({ Int($0) != nil }) else { return nil }
        return parts.reduce(0) { $0 * 60 + TimeInterval(Int($1)!) }
    }

    public static func target(
        forAnchorTimestamp timestamp: String,
        in utterances: [Utterance],
        backchannelVisible: Bool
    ) -> AnchorScrollTarget? {
        return target(
            forAnchorTimestamp: timestamp,
            provingToken: nil,
            in: utterances,
            backchannelVisible: backchannelVisible)
    }

    public static func target(
        forAnchorTimestamp timestamp: String,
        provingToken token: String?,
        in utterances: [Utterance],
        backchannelVisible: Bool
    ) -> AnchorScrollTarget? {
        guard let anchorSeconds = seconds(fromAnchorTimestamp: timestamp) else { return nil }
        guard let lastAtOrBefore = utterances.lastIndex(where: { $0.start <= anchorSeconds }) else { return nil }

        var earliestSharingTimecode = lastAtOrBefore
        while earliestSharingTimecode > 0,
              utterances[earliestSharingTimecode - 1].start == utterances[earliestSharingTimecode].start {
            earliestSharingTimecode -= 1
        }

        let sharedRange = earliestSharingTimecode...lastAtOrBefore
        let index = token
            .flatMap { needle in sharedRange.first { containsToken(needle, in: utterances[$0].text) } }
            ?? earliestSharingTimecode

        let utterance = utterances[index]
        let needsReveal = utterance.isBackchannel && !backchannelVisible

        return AnchorScrollTarget(utteranceID: utterance.id, revealsBackchannel: needsReveal)
    }

    static func containsToken(_ token: String, in text: String) -> Bool {
        let needle = token.lowercased()
        return text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { $0.lowercased() == needle }
    }

    public static func canReach(anchorTimestamp: String, in utterances: [Utterance]) -> Bool {
        return target(forAnchorTimestamp: anchorTimestamp, in: utterances, backchannelVisible: true) != nil
    }

    public static func interactivity(
        forAnchorTimestamp timestamp: String,
        in utterances: [Utterance]
    ) -> AnchorChipInteractivity {
        return canReach(anchorTimestamp: timestamp, in: utterances) ? .scrollButton : .staticText
    }
}
