import SwiftUI

/// Memory saved/pending notice shown above the composer. Matches
/// `ChatNoticeBanner`: a flat row with a hairline, no shadow or glass.
struct ChatMemoryNoticeView: View {
    let notice: ChatMemoryNotice
    let title: String
    let onOpenMemoryLibrary: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.footnote)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if notice.kind == .pending {
                    Button(String.appLocalized("settings.manage_memory"), action: onOpenMemoryLibrary)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(BrandPalette.accent)
                        .padding(.top, 2)
                }
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
            .accessibilityLabel(String.appLocalized("memory.notice.dismiss"))
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
        notice.kind == .pending ? "brain" : "checkmark.circle"
    }

    private var accentColor: Color {
        notice.kind == .pending ? .secondary : .green
    }
}
