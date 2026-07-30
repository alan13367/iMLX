import Foundation

@Observable
final class ModelManagerViewModel {
    var availableModels: [ModelInfo] = []
    var externallyManagedModelIDs: Set<String> = []
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
        Task { [weak self] in
            guard let self else { return }
            let downloadedModels = await appState.reconcileModelCatalogState()
            let downloadedById = Dictionary(
                uniqueKeysWithValues: downloadedModels.map { ($0.id, $0) })
            let externallyManagedModelIDs = await downloadService.externallyManagedModelIDs()

            await MainActor.run {
                var refreshedModels = Constants.ModelRegistry.curatedModels
                let importedModels = downloadedModels.filter { downloaded in
                    !refreshedModels.contains(where: { $0.id == downloaded.id })
                }
                refreshedModels.append(contentsOf: importedModels)

                for index in refreshedModels.indices {
                    let modelId = refreshedModels[index].id
                    if let downloaded = downloadedById[modelId] {
                        refreshedModels[index] = downloaded
                    } else {
                        refreshedModels[index].isDownloaded = false
                        refreshedModels[index].localURL = nil
                    }
                }
                self.availableModels = refreshedModels
                self.externallyManagedModelIDs = externallyManagedModelIDs
            }
        }
    }

    var isAnyDownloading: Bool {
        appState.modelDownloadSnapshots.values.contains { $0.isActive }
    }

    var downloadProgress: [String: Float] {
        Dictionary(
            uniqueKeysWithValues: appState.modelDownloadSnapshots.map {
                ($0.key, $0.value.progress)
            })
    }

    var isDownloading: [String: Bool] {
        Dictionary(
            uniqueKeysWithValues: appState.modelDownloadSnapshots.map {
                ($0.key, $0.value.isActive)
            })
    }

    var downloadableModels: [ModelInfo] {
        availableModels.filter { deviceCapability.canRunModel($0) }
    }

    var downloadableModelsGroupedByFamily: [(family: ModelInfo.ModelFamily, models: [ModelInfo])] {
        let grouped = Dictionary(grouping: downloadableModels, by: { $0.family })
        return
            grouped
            .map {
                (
                    family: $0.key,
                    models: $0.value.sorted { $0.estimatedSizeGB < $1.estimatedSizeGB }
                )
            }
            .sorted { $0.family.sortOrder < $1.family.sortOrder }
    }

    var incompatibleModels: [ModelInfo] {
        availableModels.filter { !deviceCapability.canRunModel($0) }
    }

    func models(for family: ModelInfo.ModelFamily) -> [ModelInfo] {
        availableModels
            .filter { $0.family == family && deviceCapability.canRunModel($0) }
            .sorted { $0.estimatedSizeGB < $1.estimatedSizeGB }
            .map(resolvePresentationModel)
    }

    func download(model: ModelInfo) {
        guard !isAnyDownloading else { return }
        guard isDownloading[model.id] != true else { return }
        guard !manifestService.isDownloaded(modelId: model.id) else { return }
        errorMessage = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.downloadService.startDownload(for: model)
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func cancelDownload(model: ModelInfo) {
        Task { [weak self] in
            guard let self else { return }
            let succeeded = await self.downloadService.cancelDownload(for: model)
            if !succeeded {
                await MainActor.run {
                    self.errorMessage = String.appLocalized("models.card.cancel_cleanup_failed")
                }
            }
        }
    }

    func delete(model: ModelInfo) {
        Task {
            if await downloadService.isModelManagedExternally(modelID: model.id) {
                await MainActor.run {
                    self.errorMessage = String.appLocalized("models.external.delete_unavailable")
                }
                return
            }

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

    private func resolvePresentationModel(_ model: ModelInfo) -> ModelInfo {
        var updated = model
        if manifestService.isDownloaded(modelId: model.id) {
            updated.isDownloaded = true
        } else {
            updated.isDownloaded = false
        }
        return updated
    }
}
