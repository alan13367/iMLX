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

                    capabilityBadges
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 10) {
                    Text(String(format: String.appLocalized("models.card.size_gb"), model.estimatedSizeGB))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if !isDownloading {
                        modelActionButton
                    }
                }
            }

            if isDownloading {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Spacer()

                        Text(String(format: String.appLocalized("models.card.progress"), progress * 100))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(BrandPalette.accent)
                    }

                    DownloadProgressBar(progress: CGFloat(progress))
                }
                .padding(.top, 8)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var capabilityBadges: some View {
        if model.supportsVision || model.supportsThinking {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    badgeViews
                }

                VStack(alignment: .leading, spacing: 8) {
                    badgeViews
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var badgeViews: some View {
        if model.supportsThinking {
            capabilityBadge(
                title: String.appLocalized("models.card.thinking"),
                systemImage: "lightbulb.fill",
                foreground: BrandPalette.magenta,
                background: BrandPalette.magenta.opacity(0.24)
            )
        }

        if model.supportsVision {
            capabilityBadge(
                title: String.appLocalized("models.card.vision"),
                systemImage: "eye.fill",
                foreground: Color(red: 1.0, green: 0.82, blue: 0.02),
                background: Color(red: 0.42, green: 0.36, blue: 0.08).opacity(0.82)
            )
        }
    }

    private func capabilityBadge(title: String, systemImage: String, foreground: Color, background: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.bold))

            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(background, in: Capsule())
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var modelActionButton: some View {
        if model.isDownloaded {
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
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
                    .font(.body.weight(.semibold))
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

// MARK: - Custom Download Progress Bar

private struct DownloadProgressBar: View {
    let progress: CGFloat

    @State private var shimmerPhase: CGFloat = -1

    private let trackHeight: CGFloat = 6
    private let barGradient = LinearGradient(
        colors: [BrandPalette.accent, BrandPalette.cyan],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        GeometryReader { geo in
            let fillWidth = max(trackHeight, geo.size.width * min(progress, 1.0))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(barGradient)
                    .frame(width: fillWidth, height: trackHeight)
                    .overlay(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0),
                                        .white.opacity(0.35),
                                        .white.opacity(0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: fillWidth * 0.5)
                            .offset(x: fillWidth * shimmerPhase)
                            .clipShape(Capsule())
                    )
                    .shadow(color: BrandPalette.accent.opacity(0.35), radius: 4, y: 1)
            }
        }
        .frame(height: trackHeight)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.6)
                .repeatForever(autoreverses: false)
            ) {
                shimmerPhase = 1
            }
        }
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
