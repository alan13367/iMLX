import Foundation

extension AppState {
    @MainActor
    func setAdditionalModelsFolder(_ folderURL: URL) async throws {
        if let loadedModelId,
           await downloadService.isModelManagedExternally(modelID: loadedModelId) {
            await inferenceService.unload()
            setLoadedModel(id: nil)
        }
        try await downloadService.setAdditionalModelsFolder(folderURL)
        _ = await reconcileModelCatalogState()
        modelCatalogRevision += 1
    }

    @MainActor
    func clearAdditionalModelsFolder() async {
        if let loadedModelId,
           await downloadService.isModelManagedExternally(modelID: loadedModelId) {
            await inferenceService.unload()
            setLoadedModel(id: nil)
        }
        await downloadService.clearAdditionalModelsFolder()
        _ = await reconcileModelCatalogState()
        modelCatalogRevision += 1
    }

    @MainActor
    func rescanAdditionalModelsFolder() async {
        _ = await reconcileModelCatalogState()
        modelCatalogRevision += 1
    }
}
