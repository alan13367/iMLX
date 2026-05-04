import SwiftUI

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
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(titleColor)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(dismissLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassSurface(
            tint: tintColor,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            fallback: AnyShapeStyle(fallbackColor)
        )
        .padding(.horizontal)
    }

    private var iconName: String {
        switch style {
        case .error(let isOOM):
            isOOM ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
        case .info:
            "globe"
        }
    }

    private var iconColor: Color {
        switch style {
        case .error(let isOOM):
            isOOM ? .red : .orange
        case .info:
            BrandPalette.cyan
        }
    }

    private var titleColor: Color {
        switch style {
        case .error:
            .red
        case .info:
            .primary
        }
    }

    private var tintColor: Color {
        switch style {
        case .error(let isOOM):
            return isOOM ? .red.opacity(0.18) : .orange.opacity(0.18)
        case .info:
            return BrandPalette.cyan.opacity(0.16)
        }
    }

    private var fallbackColor: Color {
        switch style {
        case .error(let isOOM):
            return isOOM ? Color.red.opacity(0.1) : Color.orange.opacity(0.12)
        case .info:
            return BrandPalette.cyan.opacity(0.08)
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
