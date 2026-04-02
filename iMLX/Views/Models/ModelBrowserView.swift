import SwiftUI

struct ModelBrowserView: View {
    @State private var viewModel: ModelManagerViewModel
    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        let vm = ModelManagerViewModel()
        vm.appState = appState
        self._viewModel = State(initialValue: vm)
    }

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Section {
                    errorRow(message: error)
                }
            }

            if !viewModel.downloadableModels.isEmpty {
                Section("Available Models") {
                    ForEach(viewModel.downloadableModels) { model in
                        ModelCardView(
                            model: model,
                            progress: viewModel.downloadProgress[model.id] ?? 0,
                            isDownloading: viewModel.isDownloading[model.id] ?? false,
                            isSelected: appState.loadedModelId == model.id,
                            onLoad: { selectModelForChat(model) },
                            onUnload: { unloadModel() },
                            onDownload: {
                                viewModel.errorMessage = nil
                                viewModel.download(model: model)
                            },
                            onDelete: { viewModel.delete(model: model) }
                        )
                    }
                }
            }
            if !viewModel.incompatibleModels.isEmpty {
                Section("Not Enough Memory") {
                    ForEach(viewModel.incompatibleModels) { model in
                        ModelCardView(
                            model: model,
                            progress: 0,
                            isDownloading: false,
                            isSelected: false,
                            onLoad: {},
                            onUnload: {},
                            onDownload: {},
                            onDelete: {}
                        )
                        .dimmed(true)
                    }
                }
            }
        }
        .navigationTitle("Models")
        .task {
            viewModel.refreshDownloadStatusFromDisk()
        }
    }

    private func errorRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private func selectModelForChat(_ model: ModelInfo) {
        guard model.isDownloaded else { return }
        Task {
            guard await appState.downloadService.isModelDownloaded(model) else {
                await MainActor.run {
                    viewModel.errorMessage = "Model files are missing for \(model.displayName). Re-download it from the Models tab."
                }
                return
            }
            await appState.inferenceService.unload()
            appState.setLoadedModel(id: nil)
            let localURL = await appState.downloadService.localURL(for: model)
            do {
                try await appState.inferenceService.load(
                    modelId: model.id,
                    localDirectory: localURL
                )
                await MainActor.run {
                    var updatedModel = model
                    updatedModel.isDownloaded = true
                    updatedModel.localURL = localURL
                    appState.setLoadedModel(id: model.id)
                    appState.selectModel(updatedModel)
                    viewModel.errorMessage = nil
                    Haptics.notificationSuccess()
                }
            } catch {
                await MainActor.run {
                    appState.selectModel(nil)
                    appState.setLoadedModel(id: nil)
                    viewModel.errorMessage = error.localizedDescription
                    Haptics.notificationError()
                }
            }
        }
    }

    private func unloadModel() {
        Task {
            await appState.inferenceService.unload()
            await MainActor.run {
                appState.clearModel()
                viewModel.errorMessage = nil
            }
        }
    }
}

private extension View {
    func dimmed(_ dimmed: Bool) -> some View {
        self.opacity(dimmed ? 0.4 : 1.0)
    }
}
