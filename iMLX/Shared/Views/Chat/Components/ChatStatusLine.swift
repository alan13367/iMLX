import SwiftUI

/// Single quiet status line shown directly above the composer.
///
/// Replaces the separate model-loading card and generating indicator: both were
/// the same information at different visual weights, and neither needed a
/// surface of its own.
struct ChatStatusLine: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview("Status — loading model") {
    ChatStatusLine(
        title: String.appLocalized("chat.loading_model_title"),
        detail: "Ternary Bonsai 8B"
    )
}

#Preview("Status — generating") {
    ChatStatusLine(title: String.appLocalized("chat.generating"), detail: nil)
}
