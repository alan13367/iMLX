import SwiftUI

struct ModelBrowserView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    @State private var viewModel: ModelManagerViewModel
    @State private var selectedFamily: ModelInfo.ModelFamily?

    init(appState: AppState) {
        self.appState = appState
        self._viewModel = State(initialValue: ModelManagerViewModel(appState: appState))
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                ModelBrowserErrorRow(message: error, onDismiss: dismissError)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            }

            ForEach(viewModel.downloadableModelsGroupedByFamily, id: \.family) { group in
                Button {
                    selectedFamily = group.family
                } label: {
                    ModelFamilyRow(
                        family: group.family,
                        modelCount: group.models.count,
                        downloadedCount: group.models.count(where: \.isDownloaded)
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String.appLocalized("models.browser.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    CloseButtonLabel()
                }
                .accessibilityLabel(String.appLocalized("common.close"))
            }
        }
        .navigationDestination(item: $selectedFamily) { family in
            FamilyModelsView(family: family, viewModel: viewModel)
        }
        .task {
            refreshDownloadStatus()
        }
        .task(id: appState.modelDownloadSnapshots.count) {
            refreshDownloadStatus()
        }
    }

    private func refreshDownloadStatus() {
        viewModel.refreshDownloadStatusFromDisk()
    }

    private func dismissError() {
        viewModel.errorMessage = nil
    }
}

private struct ModelBrowserErrorRow: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel(String.appLocalized("models.browser.dismiss_error_a11y"))
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .liquidGlassSurface(
            tint: Color.orange.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            fallback: AnyShapeStyle(Color.orange.opacity(0.08))
        )
    }
}

private struct ModelFamilyRow: View {
    let family: ModelInfo.ModelFamily
    let modelCount: Int
    let downloadedCount: Int

    var body: some View {
        HStack(spacing: 14) {
            ModelLogoView(family: family, size: 44)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(family.displayName)
                    .font(.headline)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .contentShape(Rectangle())
        .liquidGlassSurface(
            tint: downloadedCount > 0 ? Color.green.opacity(0.04) : nil,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            fallback: AnyShapeStyle(.thinMaterial)
        )
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if downloadedCount > 0 {
            return String(
                format: String.appLocalized("models.family.downloaded_count"),
                downloadedCount,
                modelCount
            )
        }

        return String(
            format: String.appLocalized("models.family.model_count"),
            modelCount
        )
    }
}

struct FamilyModelsView: View {
    let family: ModelInfo.ModelFamily
    let viewModel: ModelManagerViewModel

    var body: some View {
        let models = viewModel.models(for: family)
        let progressByModelID = viewModel.downloadProgress
        let downloadingByModelID = viewModel.isDownloading
        let isAnyModelDownloading = viewModel.isAnyDownloading

        List {
            if let error = viewModel.errorMessage {
                ModelBrowserErrorRow(
                    message: error,
                    onDismiss: { viewModel.errorMessage = nil }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
            }

            ModelFamilyOverview(
                family: family,
                modelCount: models.count
            )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            ForEach(models) { model in
                ModelCardView(
                    model: model,
                    progress: progressByModelID[model.id] ?? 0,
                    isDownloading: downloadingByModelID[model.id] ?? false,
                    anyModelDownloading: isAnyModelDownloading,
                    onDownload: {
                        viewModel.errorMessage = nil
                        viewModel.download(model: model)
                    },
                    onCancelDownload: {
                        viewModel.errorMessage = nil
                        viewModel.cancelDownload(model: model)
                    },
                    onDelete: { viewModel.delete(model: model) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(family.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ModelFamilyOverview: View {
    let family: ModelInfo.ModelFamily
    let modelCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ModelLogoView(family: family, size: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(
                    String(
                        format: String.appLocalized("models.family.model_count"),
                        modelCount
                    )
                )
                .font(.subheadline.weight(.semibold))

                Text(family.familyDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlassSurface(
            tint: BrandPalette.navy.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            fallback: AnyShapeStyle(.thinMaterial)
        )
        .accessibilityElement(children: .combine)
    }
}
