import SwiftUI

struct ChatModelStatusLabel: View {
    let isModelLoading: Bool
    let selectedModelDisplayName: String?
    let loadedModelDisplayName: String?

    var body: some View {
        HStack(spacing: 6) {
            if isModelLoading {
                ProgressView()
                    .controlSize(.small)
                Text(selectedModelDisplayName ?? String.appLocalized("chat.loading_model"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            } else if let loadedModelDisplayName {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(loadedModelDisplayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(String.appLocalized("chat.select_model"))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassSurface(in: Capsule(), interactive: true)
    }
}
