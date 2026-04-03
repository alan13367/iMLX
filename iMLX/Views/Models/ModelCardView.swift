import SwiftUI

struct ModelCardView: View {
    let model: ModelInfo
    let progress: Float
    let isDownloading: Bool
    let isSelected: Bool
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
                    Text("\(model.parameterCount) parameters (\(model.quantization))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "%.1f GB", model.estimatedSizeGB))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if model.supportsVision || model.supportsThinking {
                HStack(spacing: 6) {
                    if model.supportsThinking {
                        Label("Thinking", systemImage: "brain.head.profile")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .foregroundStyle(.purple)
                            .clipShape(Capsule())
                    }
                    if model.supportsVision {
                        Label("Vision", systemImage: "eye")
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
                    Text(String(format: "%.0f%%", progress * 100))
                        .font(.caption)
                }
            }

            HStack {
                if model.isDownloaded {
                    if isSelected {
                        Label("Loaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.trailing, 8)
                    }

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
