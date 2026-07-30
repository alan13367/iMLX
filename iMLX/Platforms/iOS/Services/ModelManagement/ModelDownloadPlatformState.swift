import Foundation

nonisolated struct ModelDownloadPlatformConfiguration {
    static let backgroundSessionIdentifier = "com.alan13367.iMLX.model-downloads"
}

nonisolated struct PlatformAdditionalModelsProvider {
    init() {}

    mutating func refreshAdditionalModels() -> [DiscoveredAdditionalModel] {
        []
    }

    func additionalModelsFolderURL() -> URL? {
        nil
    }

    mutating func setAdditionalModelsFolder(_ folderURL: URL) throws {
        _ = folderURL
    }

    mutating func clearAdditionalModelsFolder() {}
}
