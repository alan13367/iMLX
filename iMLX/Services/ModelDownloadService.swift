import Foundation
import Hub

actor ModelDownloadService {
    private let fileManager = FileManager.default

    private let modelsBaseURL: URL
    private let hubApi: HubApi

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.modelsBaseURL = appSupport.appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: modelsBaseURL, withIntermediateDirectories: true)
        self.hubApi = HubApi(downloadBase: modelsBaseURL)
        migrateOldDownloads()
    }

    private func migrateOldDownloads() {
        let entries = (try? fileManager.contentsOfDirectory(at: modelsBaseURL, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        for entry in entries {
            let attrs = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey])
            if attrs?.isSymbolicLink == true {
                continue
            }
            let contents = (try? fileManager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []
            let hasNestedModelDirs = contents.contains { url in
                let name = url.lastPathComponent
                return name == "models--\(entry.lastPathComponent)" || name.hasPrefix("models--")
            }
            if hasNestedModelDirs {
                try? fileManager.removeItem(at: entry)
                continue
            }
            let hasConfigJson = fileManager.fileExists(atPath: entry.appendingPathComponent("config.json").path)
            let hasSafetensors = (try? fileManager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil))?.contains { $0.pathExtension == "safetensors" } ?? false
            if !hasConfigJson || !hasSafetensors {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    func downloadModel(_ model: ModelInfo) -> AsyncThrowingStream<Float, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let availableSpace = try getAvailableDiskSpace()
                    let bytesPerGB: Double = 1024 * 1024 * 1024
                    let requiredBytes = model.estimatedSizeGB * bytesPerGB * 1.2
                    let requiredSpace = Int64(requiredBytes)
                    guard availableSpace > requiredSpace else {
                        throw DownloadError.insufficientStorage(
                            required: model.estimatedSizeGB,
                            available: Double(availableSpace) / bytesPerGB
                        )
                    }

                    let repo = Hub.Repo(id: model.huggingFaceId)
                    let modelFiles = ["*.safetensors", "*.json", "*.jinja", "*.txt", "*.model"]

                    let snapshotURL = try await hubApi.snapshot(
                        from: repo,
                        matching: modelFiles,
                        progressHandler: { progress in
                            let fraction: Float
                            if progress.totalUnitCount > 0 {
                                fraction = Float(progress.completedUnitCount) / Float(progress.totalUnitCount)
                            } else {
                                fraction = 0
                            }
                            continuation.yield(fraction)
                        }
                    )

                    let symlinkPath = modelsBaseURL.appendingPathComponent(model.id)
                    if fileManager.fileExists(atPath: symlinkPath.path) {
                        try fileManager.removeItem(at: symlinkPath)
                    }
                    try fileManager.createSymbolicLink(at: symlinkPath, withDestinationURL: snapshotURL)

                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func sizeOfModel(_ model: ModelInfo) -> Int64 {
        let destination = modelsBaseURL.appendingPathComponent(model.id)
        var totalSize: Int64 = 0
        let enumerator = fileManager.enumerator(at: destination, includingPropertiesForKeys: [.fileSizeKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        return totalSize
    }

    private func getAvailableDiskSpace() throws -> Int64 {
        let systemAttributes = try fileManager.attributesOfFileSystem(forPath: modelsBaseURL.path)
        guard let freeSize = systemAttributes[.systemFreeSize] as? NSNumber else {
            throw DownloadError.unableToCheckStorage
        }
        return freeSize.int64Value
    }

    func deleteModel(_ model: ModelInfo) async throws {
        let destination = modelsBaseURL.appendingPathComponent(model.id)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
    }

    func isModelDownloaded(_ model: ModelInfo) -> Bool {
        let symlinkPath = modelsBaseURL.appendingPathComponent(model.id)
        let destination: URL
        if fileManager.fileExists(atPath: symlinkPath.path) {
            destination = (try? symlinkPath.resolvingSymlinksInPath()) ?? symlinkPath
        } else {
            return false
        }
        return fileManager.fileExists(atPath: destination.appendingPathComponent("config.json").path)
    }

    func localURL(for model: ModelInfo) -> URL {
        modelsBaseURL.appendingPathComponent(model.id)
    }
}

private enum DownloadError: Error, LocalizedError {
    case networkError
    case insufficientStorage(required: Double, available: Double)
    case unableToCheckStorage

    var errorDescription: String? {
        switch self {
        case .networkError: "Network error occurred"
        case .insufficientStorage(let required, let available):
            "Insufficient storage. Required: \(String(format: "%.1f", required))GB, Available: \(String(format: "%.1f", available))GB"
        case .unableToCheckStorage: "Unable to check available storage space"
        }
    }
}

