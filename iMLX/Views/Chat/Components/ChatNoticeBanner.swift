import SwiftUI

/// Transient notice shown above the composer. A flat tinted row rather than a
/// floating card: the tint carries the severity and a hairline separates it
/// from the transcript.
struct ChatNoticeBanner: View {
    enum Style {
        case error(isOOM: Bool)
        case info
    }

    let style: Style
    let message: String
    let title: String?
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.footnote)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .accessibilityLabel(dismissLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(alignment: .top) {
            VStack(spacing: 0) {
                Divider()
                accentColor.opacity(0.08)
            }
        }
    }

    private var iconName: String {
        switch style {
        case .error(let isOOM):
            isOOM ? "exclamationmark.triangle" : "exclamationmark.circle"
        case .info:
            "globe"
        }
    }

    private var accentColor: Color {
        switch style {
        case .error(let isOOM):
            isOOM ? .red : .orange
        case .info:
            .secondary
        }
    }

    private var dismissLabel: LocalizedStringKey {
        switch style {
        case .error:
            "Dismiss error"
        case .info:
            "Dismiss notice"
        }
    }
}

#Preview("Notice — OOM error") {
    ChatNoticeBanner(
        style: .error(isOOM: true),
        message: "Try a smaller model or a shorter conversation.",
        title: "Out of memory",
        onDismiss: {}
    )
}

#Preview("Notice — info") {
    ChatNoticeBanner(
        style: .info,
        message: "Web search stayed off for this answer.",
        title: nil,
        onDismiss: {}
    )
}
