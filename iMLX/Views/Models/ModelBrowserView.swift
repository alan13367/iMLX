import SwiftUI

struct ModelBrowserView: View {
    @State private var viewModel: ModelManagerViewModel
    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        self._viewModel = State(initialValue: ModelManagerViewModel(appState: appState))
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    errorRow(message: error)
                }
            }

            ForEach(viewModel.downloadableModelsGroupedByFamily, id: \.family) { group in
                NavigationLink {
                    FamilyModelsView(
                        family: group.family,
                        viewModel: viewModel
                    )
                } label: {
                    familyRow(family: group.family, models: group.models)
                }
            }
        }
        .navigationTitle(String.appLocalized("models.browser.title"))
        .task {
            viewModel.refreshDownloadStatusFromDisk()
        }
        .task(id: appState.modelDownloadSnapshots.count) {
            viewModel.refreshDownloadStatusFromDisk()
        }
    }

    private func familyRow(family: ModelInfo.ModelFamily, models: [ModelInfo]) -> some View {
        HStack(spacing: 12) {
            ModelLogoView(family: family)

            VStack(alignment: .leading, spacing: 2) {
                Text(family.displayName)
                    .font(.headline)
                Text(String(format: String.appLocalized("models.family.model_count"), models.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(.vertical, 4)
    }

    private func errorRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.vertical, 4)
    }
}

struct FamilyModelsView: View {
    let family: ModelInfo.ModelFamily
    let viewModel: ModelManagerViewModel

    var body: some View {
        List {
            familyDescriptionCard
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            ForEach(viewModel.models(for: family)) { model in
                ModelCardView(
                    model: model,
                    progress: viewModel.downloadProgress[model.id] ?? 0,
                    isDownloading: viewModel.isDownloading[model.id] ?? false,
                    anyModelDownloading: viewModel.isAnyDownloading,
                    onDownload: {
                        viewModel.errorMessage = nil
                        viewModel.download(model: model)
                    },
                    onDelete: { viewModel.delete(model: model) }
                )
            }
        }
        .navigationTitle(family.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var familyDescriptionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(family.displayName) Family")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Text(family.familyDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlassSurface(
            tint: BrandPalette.navy.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            fallback: AnyShapeStyle(.thinMaterial)
        )
    }
}
