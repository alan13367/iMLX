import Foundation

nonisolated final class ConversationService: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let conversationsDirectory: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.conversationsDirectory = appSupport.appendingPathComponent(Constants.Storage.conversationsDirectory)
        try? fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
    }

    func save(_ conversation: Conversation) {
        var updated = conversation
        updated.updatedAt = Date()
        let url = fileURL(for: conversation.id)
        guard let data = try? JSONEncoder().encode(updated) else { return }
        try? data.write(to: url)
    }

    func load(id: UUID) -> Conversation? {
        let url = fileURL(for: id)
        guard let data = try? Data(contentsOf: url),
              let conversation = try? JSONDecoder().decode(Conversation.self, from: data) else {
            return nil
        }
        return conversation
    }

    func listAll() -> [Conversation] {
        guard let files = try? fileManager.contentsOfDirectory(at: conversationsDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Conversation? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Conversation.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func delete(id: UUID) {
        let url = fileURL(for: id)
        try? fileManager.removeItem(at: url)
    }

    func deleteAll() {
        guard let files = try? fileManager.contentsOfDirectory(
            at: conversationsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for file in files where file.pathExtension == "json" {
            try? fileManager.removeItem(at: file)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
    }
}
