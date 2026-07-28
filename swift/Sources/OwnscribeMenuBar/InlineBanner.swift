import SwiftUI

struct InlineBanner: View {
    let state: BannerState
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(foregroundColor)

            Text(state.message)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if state.isDismissible, let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .glassEffect()
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        }
    }

    private var iconName: String {
        switch state.severity {
        case .error: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var foregroundColor: Color {
        switch state.severity {
        case .error: return .red
        case .warning: return .orange
        }
    }

    private var backgroundColor: Color {
        switch state.severity {
        case .error: return .red.opacity(0.1)
        case .warning: return .orange.opacity(0.1)
        }
    }
}
