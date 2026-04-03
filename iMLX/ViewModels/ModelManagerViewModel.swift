import Foundation

@Observable
final class ModelManagerViewModel {
    var availableModels: [ModelInfo] = []
    var downloadProgress: [String: Float] = [:]
    var isDownloading: [String: Bool] = [:]
    var errorMessage: String?

    private let appState: AppState
    private let downloadService: ModelDownloadService
    private let deviceCapability = DeviceCapabilityService()
    private let manifestService: ManifestService

    init(appState: AppState) {
        self.appState = appState
        self.downloadService = appState.downloadService
        self.manifestService = appState.manifestService
        let models = Constants.ModelRegistry.curatedModels.map { model in
            var updated = model
            updated.isDownloaded = manifestService.isDownloaded(modelId: model.id)
            return updated
        }
        self.availableModels = models
        refreshDownloadStatusFromDisk()
    }

    func refreshDownloadStatusFromDisk() {
        Task {
            var refreshedModels = availableModels
            var staleModelIds: [String] = []

            for index in refreshedModels.indices {
                let model = refreshedModels[index]
                let isAvailableOnDisk = await downloadService.isModelDownloaded(model)
                refreshedModels[index].isDownloaded = isAvailableOnDisk
                refreshedModels[index].localURL = isAvailableOnDisk
                    ? await downloadService.localURL(for: model)
                    : nil

                if !isAvailableOnDisk, manifestService.isDownloaded(modelId: model.id) {
                    staleModelIds.append(model.id)
                }
            }

            await MainActor.run {
                self.availableModels = refreshedModels

                for modelId in staleModelIds {
                    self.manifestService.removeDownloaded(modelId: modelId)
                    if self.appState.selectedModel?.id == modelId {
                        self.appState.selectModel(nil)
                    }
                    if self.appState.loadedModelId == modelId {
                        self.appState.setLoadedModel(id: nil)
                    }
                }
            }
        }
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
                let localURL = await downloadService.localURL(for: model)
                await MainActor.run {
                    if let index = self.availableModels.firstIndex(where: { $0.id == model.id }) {
                        self.availableModels[index].isDownloaded = true
                        self.availableModels[index].localURL = localURL
                    }
                    self.manifestService.addDownloaded(
                        modelId: model.id,
                        displayName: model.displayName,
                        huggingFaceId: model.huggingFaceId,
                        localPath: model.id,
                        sizeOnDiskBytes: Int64(sizeOnDisk)
                    )
                    self.downloadProgress[model.id] = 1.0
                    self.isDownloading[model.id] = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isDownloading[model.id] = false
                    self.downloadProgress.removeValue(forKey: model.id)
                }
            }
        }
    }

    func delete(model: ModelInfo) {
        Task {
            if appState.loadedModelId == model.id {
                await appState.inferenceService.unload()
                await MainActor.run {
                    appState.setLoadedModel(id: nil)
                }
            }
            await MainActor.run {
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
