import SwiftUI

struct ModelCardView: View {
    let model: ModelInfo
    let progress: Float
    let isDownloading: Bool
    let anyModelDownloading: Bool
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ModelLogoView(family: model.family)

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.displayName)
                        .font(.headline)
                    Text(String(format: String.appLocalized("models.card.parameters"), model.parameterCount, model.quantization))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if model.supportsVision || model.supportsThinking {
                        HStack(spacing: 6) {
                            if model.supportsThinking {
                                capabilityBadge(
                                    title: String.appLocalized("models.card.thinking"),
                                    systemImage: "brain.head.profile",
                                    color: BrandPalette.magenta
                                )
                            }
                            if model.supportsVision {
                                capabilityBadge(
                                    title: String.appLocalized("models.card.vision"),
                                    systemImage: "eye",
                                    color: BrandPalette.cyan
                                )
                            }
                        }
                        .liquidGlassContainer(spacing: 8)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 10) {
                    Text(String(format: String.appLocalized("models.card.size_gb"), model.estimatedSizeGB))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if isDownloading {
                        Text(String(format: String.appLocalized("models.card.progress"), progress * 100))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandPalette.accent)
                    } else {
                        modelActionButton
                    }
                }
            }

            if isDownloading {
                ProgressView(value: progress) {
                    Text(String(format: String.appLocalized("models.card.progress"), progress * 100))
                        .font(.caption)
                }
                .tint(BrandPalette.accent)
            }
        }
        .padding(.vertical, 6)
    }

    private func capabilityBadge(title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .liquidGlassSurface(
                tint: color.opacity(0.18),
                in: Capsule(),
                fallback: AnyShapeStyle(color.opacity(0.12))
            )
    }

    @ViewBuilder
    private var modelActionButton: some View {
        if model.isDownloaded {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: 34, height: 34)
                .liquidGlassSurface(
                    tint: Color.red.opacity(0.10),
                    in: Circle(),
                    fallback: AnyShapeStyle(Color.red.opacity(0.08)),
                    interactive: true
                )
            }
            .buttonStyle(.plain)
            .frame(width: 36, height: 36)
            .accessibilityLabel("Delete model")
        } else {
            Button(action: onDownload) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(anyModelDownloading ? .secondary : BrandPalette.accent)
                    .frame(width: 34, height: 34)
                .liquidGlassSurface(
                    tint: anyModelDownloading ? nil : BrandPalette.accent.opacity(0.12),
                    in: Circle(),
                    fallback: AnyShapeStyle(anyModelDownloading ? Color.secondary.opacity(0.08) : BrandPalette.accent.opacity(0.10)),
                    interactive: !anyModelDownloading
                )
            }
            .buttonStyle(.plain)
            .frame(width: 36, height: 36)
            .disabled(anyModelDownloading)
            .opacity(anyModelDownloading ? 0.45 : 1.0)
            .accessibilityLabel(anyModelDownloading ? "Download unavailable — another model is downloading" : "Download model")
        }
    }
}
