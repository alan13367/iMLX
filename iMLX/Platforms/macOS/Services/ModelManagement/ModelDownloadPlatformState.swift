import Foundation

nonisolated struct ModelDownloadPlatformConfiguration {
    static let backgroundSessionIdentifier = "com.alan13367.iMLX.macOS.model-downloads"
}

nonisolated struct PlatformAdditionalModelsProvider {
    private static let additionalModelsBookmarkKey = "additionalModelsFolderBookmark"

    private let fileManager = FileManager.default
    private var additionalModelsBaseURL: URL?
    private var isAccessingAdditionalModelsBaseURL = false

    init() {
        let restoredFolder = Self.restoreAdditionalModelsFolder()
        additionalModelsBaseURL = restoredFolder.url
        isAccessingAdditionalModelsBaseURL = restoredFolder.isAccessing
    }

    mutating func refreshAdditionalModels() -> [DiscoveredAdditionalModel] {
        guard let additionalModelsBaseURL else { return [] }
        return AdditionalModelDiscovery.discoverModels(in: additionalModelsBaseURL)
    }

    func additionalModelsFolderURL() -> URL? {
        additionalModelsBaseURL
    }

    mutating func setAdditionalModelsFolder(_ folderURL: URL) throws {
        let standardizedURL = folderURL.standardizedFileURL
        let didStartAccessing = standardizedURL.startAccessingSecurityScopedResource()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            if didStartAccessing {
                standardizedURL.stopAccessingSecurityScopedResource()
            }
            throw AdditionalModelsFolderError.notDirectory
        }

        do {
            let bookmark = try standardizedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: Self.additionalModelsBookmarkKey)
        } catch {
            if didStartAccessing {
                standardizedURL.stopAccessingSecurityScopedResource()
            }
            throw error
        }

        if isAccessingAdditionalModelsBaseURL {
            additionalModelsBaseURL?.stopAccessingSecurityScopedResource()
        }
        additionalModelsBaseURL = standardizedURL
        isAccessingAdditionalModelsBaseURL = didStartAccessing
    }

    mutating func clearAdditionalModelsFolder() {
        if isAccessingAdditionalModelsBaseURL {
            additionalModelsBaseURL?.stopAccessingSecurityScopedResource()
        }
        additionalModelsBaseURL = nil
        isAccessingAdditionalModelsBaseURL = false
        UserDefaults.standard.removeObject(forKey: Self.additionalModelsBookmarkKey)
    }

    private static func restoreAdditionalModelsFolder() -> (url: URL?, isAccessing: Bool) {
        guard let bookmark = UserDefaults.standard.data(forKey: additionalModelsBookmarkKey) else {
            return (nil, false)
        }

        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ).standardizedFileURL
            let isAccessing = url.startAccessingSecurityScopedResource()

            if isStale,
               let refreshedBookmark = try? url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
               ) {
                UserDefaults.standard.set(
                    refreshedBookmark,
                    forKey: additionalModelsBookmarkKey
                )
            }
            return (url, isAccessing)
        } catch {
            UserDefaults.standard.removeObject(forKey: additionalModelsBookmarkKey)
            return (nil, false)
        }
    }
}
