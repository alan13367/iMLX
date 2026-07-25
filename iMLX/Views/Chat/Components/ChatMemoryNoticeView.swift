import SwiftUI

struct ChatMemoryNoticeView: View {
    let notice: ChatMemoryNotice
    let title: String
    let onOpenMemoryLibrary: () -> Void
    let onDismiss: () -> Void

    private var iconName: String {
        notice.kind == .pending ? "brain.head.profile" : "checkmark.circle.fill"
    }

    private var iconColor: Color {
        notice.kind == .pending ? BrandPalette.cyan : .green
    }

    private var iconTint: Color {
        notice.kind == .pending ? BrandPalette.cyan.opacity(0.18) : Color.green.opacity(0.18)
    }

    private var iconFallback: Color {
        notice.kind == .pending ? BrandPalette.cyan.opacity(0.1) : Color.green.opacity(0.1)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconView
            contentView
            Spacer(minLength: 8)
            dismissButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(backgroundView)
        .overlay(borderView)
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
    }

    private var iconView: some View {
        Image(systemName: iconName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(iconColor)
            .frame(width: 30, height: 30)
            .liquidGlassSurface(
                tint: iconTint,
                in: Circle(),
                fallback: AnyShapeStyle(iconFallback)
            )
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(notice.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if notice.kind == .pending {
                Button(String.appLocalized("settings.manage_memory"), action: onOpenMemoryLibrary)
                    .liquidGlassButtonStyle(tint: BrandPalette.cyan)
                    .controlSize(.small)
                    .frame(minHeight: 32)
            }
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .liquidGlassSurface(
                    in: Circle(),
                    fallback: AnyShapeStyle(Color.secondary.opacity(0.1)),
                    interactive: true
                )
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(String.appLocalized("memory.notice.dismiss"))
    }

    private var backgroundView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.10))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(notice.kind == .pending ? BrandPalette.cyan.opacity(0.18) : Color.green.opacity(0.16))
        }
    }

    private var borderView: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(notice.kind == .pending ? BrandPalette.cyan.opacity(0.30) : Color.green.opacity(0.24), lineWidth: 1)
    }
}
