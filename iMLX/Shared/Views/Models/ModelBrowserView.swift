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
                Section {
                    ModelBrowserErrorRow(message: error, onDismiss: dismissError)
                }
            }

            Section {
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
                }
            }
        }
        .navigationTitle(String.appLocalized("models.browser.title"))
        .modifier(ModelBrowserCloseToolbarModifier(dismiss: { dismiss() }))
        .navigationDestination(item: $selectedFamily) { family in
            FamilyModelsView(family: family, viewModel: viewModel)
        }
        .task {
            refreshDownloadStatus()
        }
        .task(id: appState.modelDownloadSnapshots.count) {
            refreshDownloadStatus()
        }
        .task(id: appState.modelCatalogRevision) {
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.footnote)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
            .accessibilityLabel(String.appLocalized("models.browser.dismiss_error_a11y"))
        }
    }
}

private struct ModelFamilyRow: View {
    let family: ModelInfo.ModelFamily
    let modelCount: Int
    let downloadedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            ModelLogoView(family: family, size: 38)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(family.displayName)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
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
                Section {
                    ModelBrowserErrorRow(
                        message: error,
                        onDismiss: { viewModel.errorMessage = nil }
                    )
                }
            }

            Section {
                ForEach(models) { model in
                    ModelCardView(
                        model: model,
                        progress: progressByModelID[model.id] ?? 0,
                        isDownloading: downloadingByModelID[model.id] ?? false,
                        anyModelDownloading: isAnyModelDownloading,
                        isExternallyManaged: viewModel.externallyManagedModelIDs.contains(model.id),
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
                }
            } header: {
                Text(
                    String(
                        format: String.appLocalized("models.family.model_count"),
                        models.count
                    )
                )
            } footer: {
                Text(family.familyDescription)
            }
        }
        .navigationTitle(family.displayName)
        .imlxInlineNavigationTitle()
    }
}
