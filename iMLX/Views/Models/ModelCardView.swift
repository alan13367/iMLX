import SwiftUI

struct ModelCardView: View {
    let model: ModelInfo
    let progress: Float
    let isDownloading: Bool
    let isSelected: Bool
    let onLoad: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.headline)
                    Text("\(model.parameterCount) parameters (\(model.quantization))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f GB", model.estimatedSizeGB))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if isDownloading {
                ProgressView(value: progress) {
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.caption)
                }
            }

            HStack {
                if model.isDownloaded {
                    Button(action: onLoad) {
                        Label(
                            isSelected ? "Loaded" : "Load",
                            systemImage: isSelected ? "checkmark.circle.fill" : "play.circle"
                        )
                    }
                    .controlSize(.small)
                    .tint(isSelected ? .green : .accentColor)

                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                    .controlSize(.small)
                } else if !isDownloading {
                    Button(action: onDownload) {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
