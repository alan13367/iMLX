import Foundation

@Observable
final class ManifestService {
    private let manifestURL: URL
    private(set) var manifest: DownloadedModelManifest
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport.appendingPathComponent(Constants.Storage.modelsDirectory)
        
        try? FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        
        self.manifestURL = appSupport.appendingPathComponent(Constants.Storage.downloadedModelsManifest)
        
        if let data = try? Data(contentsOf: manifestURL),
           let decoded = try? JSONDecoder().decode(DownloadedModelManifest.self, from: data) {
            self.manifest = decoded
        } else {
            self.manifest = DownloadedModelManifest()
        }
    }
    
    func addDownloaded(modelId: String, displayName: String, huggingFaceId: String, localPath: String, sizeOnDiskBytes: Int64) {
        let entry = DownloadedModelEntry(
            id: modelId,
            displayName: displayName,
            huggingFaceId: huggingFaceId,
            downloadDate: Date(),
            localPath: localPath,
            sizeOnDiskBytes: sizeOnDiskBytes
        )
        manifest.downloadedModels.removeAll { $0.id == modelId }
        manifest.downloadedModels.append(entry)
        save()
    }
    
    func removeDownloaded(modelId: String) {
        manifest.downloadedModels.removeAll { $0.id == modelId }
        save()
    }
    
    func isDownloaded(modelId: String) -> Bool {
        manifest.downloadedModels.contains { $0.id == modelId }
    }
    
    func getDownloadedModels() -> [DownloadedModelEntry] {
        manifest.downloadedModels
    }
    
    func getEntry(for modelId: String) -> DownloadedModelEntry? {
        manifest.downloadedModels.first { $0.id == modelId }
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(manifest) {
            try? encoded.write(to: manifestURL)
        }
    }
}
