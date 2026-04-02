import Foundation
import Hub

actor ModelDownloadService {
    private let fileManager = FileManager.default

    private let modelsBaseURL: URL
    private let hubCacheBaseURL: URL
    private let sandboxRootURL: URL
    private let hubApi: HubApi

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.modelsBaseURL = appSupport.appendingPathComponent("Models")
        self.hubCacheBaseURL = caches
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
        self.sandboxRootURL = modelsBaseURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: modelsBaseURL, withIntermediateDirectories: true)
        self.hubApi = HubApi(downloadBase: modelsBaseURL)
        Self.migrateOldDownloads(fileManager: fileManager, modelsBaseURL: modelsBaseURL)
    }

    private nonisolated static func migrateOldDownloads(fileManager: FileManager, modelsBaseURL: URL) {
        let entries = (try? fileManager.contentsOfDirectory(at: modelsBaseURL, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        for entry in entries {
            let name = entry.lastPathComponent
            let attrs = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey])
            if attrs?.isSymbolicLink == true {
                continue
            }
            if name.hasPrefix("models--") {
                continue
            }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue else {
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
                    var lastEmittedProgress: Float = 0

                    let snapshotURL = try await hubApi.snapshot(
                        from: repo,
                        matching: modelFiles,
                        progressHandler: { progress in
                            let fraction = Float(progress.fractionCompleted)
                            let clamped = min(max(fraction, lastEmittedProgress), 1.0)
                            lastEmittedProgress = clamped
                            continuation.yield(clamped)
                        }
                    )

                    let symlinkPath = modelsBaseURL.appendingPathComponent(model.id)
                    try? fileManager.removeItem(at: symlinkPath)

                    guard isUsableModelDirectory(snapshotURL) else {
                        throw DownloadError.corruptedDownload(model.displayName)
                    }

                    try createModelSymlink(at: symlinkPath, targetURL: snapshotURL)

                    continuation.yield(1.0)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func sizeOfModel(_ model: ModelInfo) -> Int64 {
        let destination = preferredModelDirectory(for: model) ?? modelsBaseURL.appendingPathComponent(model.id)
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
        let symlinkPath = modelsBaseURL.appendingPathComponent(model.id)
        if fileManager.fileExists(atPath: symlinkPath.path) {
            try fileManager.removeItem(at: symlinkPath)
        }

        let appSupportRepoPath = modelsBaseURL
            .appendingPathComponent("models")
            .appendingPathComponent(model.huggingFaceId)
        if fileManager.fileExists(atPath: appSupportRepoPath.path) {
            try fileManager.removeItem(at: appSupportRepoPath)
        }

        let cachePath = hubCacheBaseURL.appendingPathComponent(cacheDirectoryName(for: model))
        if fileManager.fileExists(atPath: cachePath.path) {
            try fileManager.removeItem(at: cachePath)
        }

        let lockPath = hubCacheBaseURL
            .appendingPathComponent(".locks")
            .appendingPathComponent(cacheDirectoryName(for: model))
        if fileManager.fileExists(atPath: lockPath.path) {
            try fileManager.removeItem(at: lockPath)
        }
    }

    func isModelDownloaded(_ model: ModelInfo) -> Bool {
        preferredModelDirectory(for: model) != nil
    }

    func localURL(for model: ModelInfo) -> URL {
        preferredModelDirectory(for: model) ?? modelsBaseURL.appendingPathComponent(model.id)
    }

    private func preferredModelDirectory(for model: ModelInfo) -> URL? {
        let symlinkPath = modelsBaseURL.appendingPathComponent(model.id)
        if let symlinkTarget = usableSymlinkTarget(at: symlinkPath) {
            return symlinkTarget
        }

        if let snapshotDirectory = newestSnapshotDirectory(for: model) {
            try? createModelSymlink(at: symlinkPath, targetURL: snapshotDirectory)
            return snapshotDirectory
        }

        let appSupportRepoPath = modelsBaseURL
            .appendingPathComponent("models")
            .appendingPathComponent(model.huggingFaceId)
        if isUsableModelDirectory(appSupportRepoPath) {
            return appSupportRepoPath
        }

        let cacheDirectory = hubCacheBaseURL.appendingPathComponent(cacheDirectoryName(for: model))
        if isUsableModelDirectory(cacheDirectory) {
            return cacheDirectory
        }

        return nil
    }

    private func newestSnapshotDirectory(for model: ModelInfo) -> URL? {
        let snapshotsDirectory = hubCacheBaseURL
            .appendingPathComponent(cacheDirectoryName(for: model))
            .appendingPathComponent("snapshots")

        guard let snapshots = try? fileManager.contentsOfDirectory(
            at: snapshotsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let sortedSnapshots = snapshots.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        for snapshot in sortedSnapshots where isUsableModelDirectory(snapshot) {
            return snapshot
        }

        return nil
    }

    private func cacheDirectoryName(for model: ModelInfo) -> String {
        "models--" + model.huggingFaceId.replacingOccurrences(of: "/", with: "--")
    }

    private func usableSymlinkTarget(at symlinkPath: URL) -> URL? {
        guard let values = try? symlinkPath.resourceValues(forKeys: [.isSymbolicLinkKey]),
              values.isSymbolicLink == true,
              let destinationPath = try? fileManager.destinationOfSymbolicLink(atPath: symlinkPath.path) else {
            return nil
        }

        let destinationURL = URL(fileURLWithPath: destinationPath, relativeTo: symlinkPath.deletingLastPathComponent())
            .standardizedFileURL
            .resolvingSymlinksInPath()
        if isUsableModelDirectory(destinationURL) {
            return destinationURL
        }

        try? fileManager.removeItem(at: symlinkPath)
        return nil
    }

    private func isUsableModelDirectory(_ directory: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        let configURL = directory.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL), !configData.isEmpty else {
            return false
        }

        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return false
        }

        return contents.contains { $0.pathExtension == "safetensors" }
    }

    private func createModelSymlink(at symlinkPath: URL, targetURL: URL) throws {
        let relativeTarget = relativePath(from: symlinkPath.deletingLastPathComponent(), to: targetURL)
        try? fileManager.removeItem(at: symlinkPath)
        try fileManager.createSymbolicLink(atPath: symlinkPath.path, withDestinationPath: relativeTarget)
    }

    private func relativePath(from baseURL: URL, to targetURL: URL) -> String {
        let baseComponents = baseURL.standardizedFileURL.pathComponents
        let targetComponents = targetURL.standardizedFileURL.pathComponents

        guard targetURL.standardizedFileURL.path.hasPrefix(sandboxRootURL.standardizedFileURL.path) else {
            return targetURL.path
        }

        var sharedIndex = 0
        while sharedIndex < min(baseComponents.count, targetComponents.count),
              baseComponents[sharedIndex] == targetComponents[sharedIndex] {
            sharedIndex += 1
        }

        let upPath = Array(repeating: "..", count: baseComponents.count - sharedIndex)
        let downPath = Array(targetComponents.dropFirst(sharedIndex))
        return (upPath + downPath).joined(separator: "/")
    }
}

private enum DownloadError: Error, LocalizedError {
    case networkError
    case insufficientStorage(required: Double, available: Double)
    case unableToCheckStorage
    case corruptedDownload(String)

    var errorDescription: String? {
        switch self {
        case .networkError: "Network error occurred"
        case .insufficientStorage(let required, let available):
            "Insufficient storage. Required: \(String(format: "%.1f", required))GB, Available: \(String(format: "%.1f", available))GB"
        case .unableToCheckStorage: "Unable to check available storage space"
        case .corruptedDownload(let modelName):
            "Downloaded files for \(modelName) look incomplete. Delete the model and download it again."
        }
    }
}
