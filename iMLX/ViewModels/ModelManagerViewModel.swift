import Foundation

@Observable
final class ModelManagerViewModel {
    var availableModels: [ModelInfo] = []
    var downloadProgress: [String: Float] = [:]
    var isDownloading: [String: Bool] = [:]
    var errorMessage: String?

    private let downloadService = ModelDownloadService()
    private let deviceCapability = DeviceCapabilityService()
    private let manifestService = ManifestService()
    weak var appState: AppState?

    init() {
        let models = Constants.ModelRegistry.curatedModels.map { model in
            var updated = model
            updated.isDownloaded = manifestService.isDownloaded(modelId: model.id)
            return updated
        }
        self.availableModels = models
    }

    var downloadableModels: [ModelInfo] {
        availableModels.filter { deviceCapability.canRunModel($0) }
    }

    var incompatibleModels: [ModelInfo] {
        availableModels.filter { !deviceCapability.canRunModel($0) }
    }

    func download(model: ModelInfo) {
        guard isDownloading[model.id] != true else { return }
        guard !manifestService.isDownloaded(modelId: model.id) else { return }
        isDownloading[model.id] = true
        downloadProgress[model.id] = 0
        errorMessage = nil

        Task {
            let stream = await downloadService.downloadModel(model)
            do {
                for try await progress in stream {
                    await MainActor.run {
                        self.downloadProgress[model.id] = progress
                    }
                }
                let sizeOnDisk = await downloadService.sizeOfModel(model)
                await MainActor.run {
                    if let index = self.availableModels.firstIndex(where: { $0.id == model.id }) {
                        self.availableModels[index].isDownloaded = true
                        self.availableModels[index].localURL = URL(fileURLWithPath: Constants.Storage.modelsDirectory)
                            .appendingPathComponent(model.id)
                    }
                    self.manifestService.addDownloaded(
                        modelId: model.id,
                        displayName: model.displayName,
                        huggingFaceId: model.huggingFaceId,
                        localPath: model.id,
                        sizeOnDiskBytes: Int64(sizeOnDisk)
                    )
                    self.isDownloading[model.id] = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isDownloading[model.id] = false
                }
            }
        }
    }

    func delete(model: ModelInfo) {
        Task {
            if let appState {
                await appState.inferenceService.unload()
                if appState.loadedModelId == model.id {
                    appState.setLoadedModel(id: nil)
                }
                if appState.selectedModel?.id == model.id {
                    appState.selectModel(nil)
                }
            }
            do {
                try await downloadService.deleteModel(model)
                await MainActor.run {
                    self.manifestService.removeDownloaded(modelId: model.id)
                    if let index = self.availableModels.firstIndex(where: { $0.id == model.id }) {
                        self.availableModels[index].isDownloaded = false
                        self.availableModels[index].localURL = nil
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    var downloadedModels: [ModelInfo] {
        availableModels.filter { $0.isDownloaded }
    }
}
