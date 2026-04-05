import SwiftUI

struct ModelCardView: View {
    let model: ModelInfo
    let progress: Float
    let isDownloading: Bool
    let anyModelDownloading: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(model.logoName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.headline)
                    Text(String(format: String.appLocalized("models.card.parameters"), model.parameterCount, model.quantization))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: String.appLocalized("models.card.size_gb"), model.estimatedSizeGB))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if model.supportsVision || model.supportsThinking {
                HStack(spacing: 6) {
                    if model.supportsThinking {
                        Label(String.appLocalized("models.card.thinking"), systemImage: "brain.head.profile")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    if model.supportsVision {
                        Label(String.appLocalized("models.card.vision"), systemImage: "eye")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 2)
            }

            if isDownloading {
                ProgressView(value: progress) {
                    Text(String(format: String.appLocalized("models.card.progress"), progress * 100))
                        .font(.caption)
                }
            }

            HStack {
                if model.isDownloaded {
                    Button(role: .destructive, action: onDelete) {
                        Label(String.appLocalized("common.delete"), systemImage: "trash")
                    }
                    .controlSize(.small)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Delete model")
                } else if !isDownloading {
                    Button(action: onDownload) {
                        Label(String.appLocalized("models.card.download"), systemImage: "arrow.down.circle")
                    }
                    .controlSize(.small)
                    .frame(minHeight: 44)
                    .disabled(anyModelDownloading)
                    .opacity(anyModelDownloading ? 0.4 : 1.0)
                    .accessibilityLabel(anyModelDownloading ? "Download unavailable — another model is downloading" : "Download model")
                }
            }
        }
        .padding(.vertical, 4)
    }
}
