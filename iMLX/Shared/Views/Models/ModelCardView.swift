import SwiftUI

/// Model row for the browser list.
///
/// Renders as a standard list row rather than a floating card: the logo,
/// identity text, and a single trailing action. Capability badges are plain
/// secondary text so the row reads like the rest of the app's lists.
struct ModelCardView: View {
    let model: ModelInfo
    let progress: Float
    let isDownloading: Bool
    let anyModelDownloading: Bool
    let isExternallyManaged: Bool
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                ModelLogoStatusView(
                    family: model.family,
                    isDownloaded: model.isDownloaded,
                    isDownloading: isDownloading
                )

                ModelCardIdentity(
                    displayName: model.displayName,
                    parameterCount: model.parameterCount,
                    quantization: model.quantization,
                    estimatedSizeGB: model.estimatedSizeGB,
                    supportsThinking: model.supportsThinking,
                    supportsVision: model.supportsVision,
                    isExternallyManaged: isExternallyManaged
                )

                Spacer(minLength: 8)

                ModelCardActionButton(
                    displayName: model.displayName,
                    estimatedSizeGB: model.estimatedSizeGB,
                    isDownloaded: model.isDownloaded,
                    isDownloading: isDownloading,
                    anyModelDownloading: anyModelDownloading,
                    isExternallyManaged: isExternallyManaged,
                    onDownload: onDownload,
                    onCancelDownload: onCancelDownload,
                    onDelete: onDelete
                )
            }

            if isDownloading {
                ModelDownloadFooter(progress: progress)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ModelLogoStatusView: View {
    let family: ModelInfo.ModelFamily
    let isDownloaded: Bool
    let isDownloading: Bool

    var body: some View {
        ModelLogoView(family: family, size: 38)
            .overlay(alignment: .bottomTrailing) {
                if isDownloaded && !isDownloading {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .font(.system(size: 13, weight: .semibold))
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
    let isExternallyManaged: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayName)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(detailLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private var detailLine: String {
        var pieces = [
            String(
                format: String.appLocalized("models.card.parameters"),
                parameterCount,
                quantization
            ),
            String(
                format: String.appLocalized("models.card.size_gb"),
                estimatedSizeGB
            )
        ]
        if supportsThinking {
            pieces.append(String.appLocalized("models.card.thinking"))
        }
        if supportsVision {
            pieces.append(String.appLocalized("models.card.vision"))
        }
        if isExternallyManaged {
            pieces.append(String.appLocalized("models.external.folder_badge"))
        }
        return pieces.joined(separator: " · ")
    }
}

private struct ModelCardActionButton: View {
    let displayName: String
    let estimatedSizeGB: Double
    let isDownloaded: Bool
    let isDownloading: Bool
    let anyModelDownloading: Bool
    let isExternallyManaged: Bool
    let onDownload: () -> Void
    let onCancelDownload: () -> Void
    let onDelete: () -> Void

    @State private var showCancelConfirmation = false

    var body: some View {
        Button(role: role, action: performAction) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(foregroundStyle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
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
        isDownloading || (isDownloaded && !isExternallyManaged) ? .destructive : nil
    }

    private var systemImage: String {
        if isDownloading { return "stop.circle" }
        if isDownloaded && isExternallyManaged { return "externaldrive.fill" }
        if isDownloaded { return "trash" }
        return "arrow.down.circle"
    }

    private var foregroundStyle: Color {
        if isDownloading { return .orange }
        if isDownloaded && isExternallyManaged { return .secondary }
        if isDownloaded { return .red }
        return isEnabled ? BrandPalette.accent : .secondary
    }

    private var isEnabled: Bool {
        if isDownloaded && isExternallyManaged { return false }
        return isDownloading || isDownloaded || !anyModelDownloading
    }

    private var accessibilityLabel: String {
        if isDownloading {
            return String.appLocalized("models.card.stop_download_a11y")
        }
        if isDownloaded && isExternallyManaged {
            return String.appLocalized("models.external.folder_badge")
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
        HStack(spacing: 8) {
            ProgressView(value: clampedProgress)
                .progressViewStyle(.linear)
                .accessibilityLabel(String.appLocalized("models.card.progress_a11y"))
                .accessibilityValue(
                    clampedProgress.formatted(.percent.precision(.fractionLength(0)))
                )

            Text(clampedProgress, format: .percent.precision(.fractionLength(0)))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private var clampedProgress: Double {
        min(max(Double(progress), 0), 1)
    }
}
