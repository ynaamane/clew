import SwiftUI

struct MeetingStatusBadge: View {
    let variant: Variant

    var body: some View {
        Text(variant.text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(variant.backgroundColor)
            .foregroundStyle(variant.foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    enum Variant: Equatable {
        case unanchored(count: Int)
        case neverChecked
        case actionItems(count: Int)
        case mutedTrack
        case notIndexed

        init?(anchorState: UnanchoredClaimBadge) {
            switch anchorState {
            case .neverChecked: self = .neverChecked
            case .allAnchored: return nil
            case .unanchored(let count): self = .unanchored(count: count)
            }
        }

        var text: String {
            switch self {
            case .unanchored(let count):
                return count == 1 ? "1 non ancré" : "\(count) non ancrés"
            case .neverChecked:
                return "non vérifiée"
            case .actionItems(let count):
                return count == 1 ? "1 action" : "\(count) actions"
            case .mutedTrack:
                return "piste système muette"
            case .notIndexed:
                return "non indexée"
            }
        }

        var foregroundColor: Color {
            switch self {
            case .unanchored:
                return .orange
            case .neverChecked, .mutedTrack, .notIndexed:
                return .secondary
            case .actionItems:
                return .green
            }
        }

        var backgroundColor: Color {
            switch self {
            case .unanchored:
                return Color.orange.opacity(0.16)
            case .actionItems:
                return Color.green.opacity(0.16)
            case .neverChecked, .mutedTrack, .notIndexed:
                return Color(white: 0.5, opacity: 0.16)
            }
        }
    }
}
