import SwiftUI

/// Navigation-title-style model status. Sits inside the toolbar, which already
/// supplies its own background, so this draws no surface of its own.
struct ChatModelStatusLabel: View {
    let isModelLoading: Bool
    let selectedModelDisplayName: String?
    let loadedModelDisplayName: String?

    var body: some View {
        HStack(spacing: 5) {
            if isModelLoading {
                ProgressView()
                    .controlSize(.mini)
            } else if loadedModelDisplayName == nil {
                Image(systemName: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if !isModelLoading {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var title: String {
        if isModelLoading {
            return selectedModelDisplayName ?? String.appLocalized("chat.loading_model")
        }
        if let loadedModelDisplayName {
            return loadedModelDisplayName
        }
        return String.appLocalized("chat.select_model")
    }
}
