import Foundation

public struct BackchannelFoldLabel: Equatable {
    public let count: Int
    public let examples: [String]

    public init(count: Int, examples: [String]) {
        self.count = count
        self.examples = examples
    }
}

public enum BackchannelFoldSummary {
    public static func label(for utterances: [Utterance]) -> BackchannelFoldLabel? {
        let hidden = utterances.filter(\.isBackchannel)
        guard !hidden.isEmpty else { return nil }

        var examples: [String] = []
        for utterance in hidden {
            guard !examples.contains(utterance.text) else { continue }
            examples.append(utterance.text)
            if examples.count == 3 { break }
        }

        return BackchannelFoldLabel(count: hidden.count, examples: examples)
    }

    public static func text(for label: BackchannelFoldLabel) -> String {
        let plural = label.count > 1
        let base = "\(label.count) intervention\(plural ? "s" : "") courte\(plural ? "s" : "") masquée\(plural ? "s" : "")"
        guard !label.examples.isEmpty else { return base }

        let quoted = label.examples.map { "« \($0) »" }.joined(separator: ", ")
        return "\(base) — \(quoted)"
    }
}
