import SwiftUI

struct ModelCardView: View {
    let model: ModelInfo
    let progress: Float
    let isDownloading: Bool
    let anyModelDownloading: Bool
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ModelCardHeader(
                family: model.family,
                displayName: model.displayName,
                parameterCount: model.parameterCount,
                quantization: model.quantization,
                estimatedSizeGB: model.estimatedSizeGB,
                supportsThinking: model.supportsThinking,
                supportsVision: model.supportsVision,
                isDownloaded: model.isDownloaded,
                isDownloading: isDownloading,
                anyModelDownloading: anyModelDownloading,
                onDownload: onDownload,
                onCancelDownload: onCancelDownload,
                onDelete: onDelete
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, isDownloading ? 10 : 14)

            if isDownloading {
                ModelDownloadFooter(progress: progress)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .liquidGlassSurface(
            tint: surfaceTint,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous),
            fallback: AnyShapeStyle(.thinMaterial)
        )
    }
}

private extension ModelCardView {
    private var surfaceTint: Color? {
        if isDownloading { return BrandPalette.accent.opacity(0.06) }
        if model.isDownloaded { return Color.green.opacity(0.04) }
        return nil
    }
}

private struct ModelCardHeader: View {
    let family: ModelInfo.ModelFamily
    let displayName: String
    let parameterCount: String
    let quantization: String
    let estimatedSizeGB: Double
    let supportsThinking: Bool
    let supportsVision: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let anyModelDownloading: Bool
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ModelLogoStatusView(
                family: family,
                isDownloaded: isDownloaded,
                isDownloading: isDownloading
            )

            ModelCardIdentity(
                displayName: displayName,
                parameterCount: parameterCount,
                quantization: quantization,
                estimatedSizeGB: estimatedSizeGB,
                supportsThinking: supportsThinking,
                supportsVision: supportsVision
            )

            Spacer(minLength: 4)

            ModelCardActionButton(
                displayName: displayName,
                estimatedSizeGB: estimatedSizeGB,
                isDownloaded: isDownloaded,
                isDownloading: isDownloading,
                anyModelDownloading: anyModelDownloading,
                onDownload: onDownload,
                onCancelDownload: onCancelDownload,
                onDelete: onDelete
            )
        }
    }
}

private struct ModelLogoStatusView: View {
    let family: ModelInfo.ModelFamily
    let isDownloaded: Bool
    let isDownloading: Bool

    var body: some View {
        ModelLogoView(family: family, size: 44)
            .overlay(alignment: .bottomTrailing) {
                if isDownloaded && !isDownloading {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .font(.system(size: 15, weight: .semibold))
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                }
            }
            .accessibilityHidden(true)
    }
}

private struct ModelCardIdentity: View {
    let displayName: String
    let parameterCount: String
    let quantization: String
    let estimatedSizeGB: Double
    let supportsThinking: Bool
    let supportsVision: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(displayName)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    parameterSummary
                    separator
                    sizeSummary
                }

                VStack(alignment: .leading, spacing: 2) {
                    parameterSummary
                    sizeSummary
                }
            }

            ModelCapabilityBadges(
                supportsThinking: supportsThinking,
                supportsVision: supportsVision
            )
            .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }

    private var parameterSummary: some View {
        Text(
            String(
                format: String.appLocalized("models.card.parameters"),
                parameterCount,
                quantization
            )
        )
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }

    private var separator: some View {
        Text(verbatim: "·")
            .font(.subheadline)
            .foregroundStyle(.tertiary)
    }

    private var sizeSummary: some View {
        Text(
            String(
                format: String.appLocalized("models.card.size_gb"),
                estimatedSizeGB
            )
        )
        .font(.subheadline.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

private struct ModelCapabilityBadges: View {
    let supportsThinking: Bool
    let supportsVision: Bool

    var body: some View {
        if supportsThinking || supportsVision {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    badges
                }

                VStack(alignment: .leading, spacing: 6) {
                    badges
                }
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        if supportsThinking {
            ModelCapabilityBadge(
                title: String.appLocalized("models.card.thinking"),
                systemImage: "lightbulb.fill",
                foreground: BrandPalette.magenta,
                tint: BrandPalette.magenta.opacity(0.18),
                fallback: AnyShapeStyle(BrandPalette.magenta.opacity(0.22))
            )
        }

        if supportsVision {
            ModelCapabilityBadge(
                title: String.appLocalized("models.card.vision"),
                systemImage: "eye.fill",
                foreground: .orange,
                tint: Color.orange.opacity(0.14),
                fallback: AnyShapeStyle(Color.orange.opacity(0.16))
            )
        }
    }
}

private struct ModelCapabilityBadge: View {
    let title: String
    let systemImage: String
    let foreground: Color
    let tint: Color
    let fallback: AnyShapeStyle

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .liquidGlassSurface(tint: tint, in: Capsule(), fallback: fallback)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

private struct ModelCardActionButton: View {
    let displayName: String
    let estimatedSizeGB: Double
    let isDownloaded: Bool
    let isDownloading: Bool
    let anyModelDownloading: Bool
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDelete: () -> Void

    @State private var showCancelConfirmation = false

    var body: some View {
        Button(role: role, action: performAction) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(foregroundStyle)
                .frame(width: 40, height: 40)
                .liquidGlassSurface(
                    tint: tint,
                    in: Circle(),
                    fallback: fallback,
                    interactive: isEnabled
                )
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.48)
        .accessibilityLabel(accessibilityLabel)
        .alert(
            String.appLocalized("models.card.cancel_confirm_title"),
            isPresented: $showCancelConfirmation
        ) {
            Button(String.appLocalized("models.card.cancel_confirm_action"), role: .destructive) {
                onCancelDownload()
            }
            Button(String.appLocalized("common.cancel"), role: .cancel) {}
        } message: {
            Text(
                String(
                    format: String.appLocalized("models.card.cancel_confirm_message"),
                    displayName
                )
            )
        }
    }

    private var role: ButtonRole? {
        isDownloading || isDownloaded ? .destructive : nil
    }

    private var systemImage: String {
        if isDownloading { return "stop.fill" }
        if isDownloaded { return "trash" }
        return "arrow.down"
    }

    private var foregroundStyle: Color {
        if isDownloading { return .orange }
        if isDownloaded { return .red }
        return isEnabled ? BrandPalette.accent : .secondary
    }

    private var tint: Color? {
        if isDownloading { return Color.orange.opacity(0.12) }
        if isDownloaded { return Color.red.opacity(0.12) }
        return isEnabled ? BrandPalette.accent.opacity(0.12) : nil
    }

    private var fallback: AnyShapeStyle {
        if isDownloading {
            return AnyShapeStyle(Color.orange.opacity(0.10))
        }
        if isDownloaded {
            return AnyShapeStyle(Color.red.opacity(0.10))
        }
        return AnyShapeStyle(
            isEnabled ? BrandPalette.accent.opacity(0.10) : Color.secondary.opacity(0.08)
        )
    }

    private var isEnabled: Bool {
        isDownloading || isDownloaded || !anyModelDownloading
    }

    private var accessibilityLabel: String {
        if isDownloading {
            return String.appLocalized("models.card.stop_download_a11y")
        }
        if isDownloaded {
            return String.appLocalized("models.card.delete_a11y")
        }
        if anyModelDownloading {
            return String.appLocalized("models.card.download_unavailable_a11y")
        }
        return String.appLocalized("models.card.download")
    }

    private func performAction() {
        if isDownloading {
            if estimatedSizeGB >= 2.0 {
                showCancelConfirmation = true
            } else {
                onCancelDownload()
            }
        } else if isDownloaded {
            onDelete()
        } else {
            onDownload()
        }
    }
}

private struct ModelDownloadFooter: View {
    let progress: Float

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(clampedProgress, format: .percent.precision(.fractionLength(0)))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(BrandPalette.accent)
                .contentTransition(.numericText())

            ProgressView(value: clampedProgress)
                .progressViewStyle(.linear)
                .tint(BrandPalette.accent)
                .accessibilityLabel(String.appLocalized("models.card.progress_a11y"))
                .accessibilityValue(
                    clampedProgress.formatted(.percent.precision(.fractionLength(0)))
                )
        }
    }

    private var clampedProgress: Double {
        min(max(Double(progress), 0), 1)
    }
}
