import Foundation

public enum LineHighlightDecision {
    public static func isHighlighted(lineID: UUID, highlightedID: UUID?) -> Bool {
        lineID == highlightedID
    }
}
