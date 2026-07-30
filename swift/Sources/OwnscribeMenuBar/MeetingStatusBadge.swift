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

    enum Variant {
        case unanchored(count: Int)
        case actionItems(count: Int)
        case mutedTrack

        var text: String {
            switch self {
            case .unanchored(let count):
                return count == 1 ? "1 non ancré" : "\(count) non ancrés"
            case .actionItems(let count):
                return count == 1 ? "1 action" : "\(count) actions"
            case .mutedTrack:
                return "piste système muette"
            }
        }

        var foregroundColor: Color {
            switch self {
            case .unanchored:
                return .orange
            case .actionItems:
                return .green
            case .mutedTrack:
                return .secondary
            }
        }

        var backgroundColor: Color {
            switch self {
            case .unanchored:
                return Color.orange.opacity(0.16)
            case .actionItems:
                return Color.green.opacity(0.16)
            case .mutedTrack:
                return Color(white: 0.5, opacity: 0.16)
            }
        }
    }
}
