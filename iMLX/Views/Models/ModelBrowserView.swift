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
                        models: group.models,
                        viewModel: viewModel
                    )
                } label: {
                    familyRow(family: group.family, models: group.models)
                }
            }

            if !viewModel.incompatibleModels.isEmpty {
                Section(String.appLocalized("models.section.low_memory")) {
                    ForEach(viewModel.incompatibleModels) { model in
                        ModelCardView(
                            model: model,
                            progress: 0,
                            isDownloading: false,
                            anyModelDownloading: false,
                            onDownload: {},
                            onDelete: {}
                        )
                        .dimmed(true)
                    }
                }
            }
        }
        .navigationTitle(String.appLocalized("models.browser.title"))
        .task {
            viewModel.refreshDownloadStatusFromDisk()
        }
    }

    private func familyRow(family: ModelInfo.ModelFamily, models: [ModelInfo]) -> some View {
        HStack(spacing: 12) {
            Image(family.logoName)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 1))

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
    let models: [ModelInfo]
    let viewModel: ModelManagerViewModel

    var body: some View {
        List {
            ForEach(models) { model in
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
}

private extension View {
    func dimmed(_ dimmed: Bool) -> some View {
        self.opacity(dimmed ? 0.4 : 1.0)
    }
}
