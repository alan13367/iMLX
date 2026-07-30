import Foundation

@Observable
final class ManifestService {
    private let manifestURL: URL
    private(set) var manifest: DownloadedModelManifest
    
    init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.manifestURL = appSupport.appendingPathComponent(Constants.Storage.downloadedModelsManifest)
        self.manifest = Self.loadManifest(from: manifestURL)

        let modelsDir = appSupport.appendingPathComponent(Constants.Storage.modelsDirectory)
        try? fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
    }

    init(manifestURL: URL) {
        self.manifestURL = manifestURL
        self.manifest = Self.loadManifest(from: manifestURL)
        try? FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
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
    
    func removeDownloaded(modelIds: Set<String>) {
        manifest.downloadedModels.removeAll { modelIds.contains($0.id) }
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

    var totalStorageUsedGB: Double {
        let totalBytes = manifest.downloadedModels.reduce(Int64(0)) { $0 + $1.sizeOnDiskBytes }
        return Double(totalBytes) / (1024 * 1024 * 1024)
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(manifest) {
            try? encoded.write(to: manifestURL, options: [.atomic])
        }
    }

    private static func loadManifest(from url: URL) -> DownloadedModelManifest {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(DownloadedModelManifest.self, from: data) else {
            return DownloadedModelManifest()
        }
        return decoded
    }
}
