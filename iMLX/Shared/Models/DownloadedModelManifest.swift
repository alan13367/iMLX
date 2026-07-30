import Foundation

struct DownloadedModelManifest: Codable {
    var downloadedModels: [DownloadedModelEntry]
    
    init(downloadedModels: [DownloadedModelEntry] = []) {
        self.downloadedModels = downloadedModels
    }
}

struct DownloadedModelEntry: Codable, Identifiable {
    let id: String
    let displayName: String
    let huggingFaceId: String
    let downloadDate: Date
    let localPath: String
    let sizeOnDiskBytes: Int64
}
