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
        guard let anchorSeconds = seconds(fromAnchorTimestamp: timestamp) else { return nil }
        guard let lastAtOrBefore = utterances.lastIndex(where: { $0.start <= anchorSeconds }) else { return nil }

        var index = lastAtOrBefore
        while index > 0, utterances[index - 1].start == utterances[index].start {
            index -= 1
        }

        let utterance = utterances[index]
        let needsReveal = utterance.isBackchannel && !backchannelVisible

        return AnchorScrollTarget(utteranceID: utterance.id, revealsBackchannel: needsReveal)
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
