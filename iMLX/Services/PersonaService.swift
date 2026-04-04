import Foundation

final class PersonaService {
    private let fileManager = FileManager.default
    private let personasDirectory: URL

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        personasDirectory = appSupport.appendingPathComponent(Constants.Storage.personasDirectory, isDirectory: true)
        try? fileManager.createDirectory(at: personasDirectory, withIntermediateDirectories: true)
        seedStarterPersonasIfNeeded()
    }

    func listAll() -> [Persona] {
        guard let urls = try? fileManager.contentsOfDirectory(at: personasDirectory, includingPropertiesForKeys: nil) else {
            return Persona.starterPersonas()
        }

        let personas = urls
            .filter { $0.pathExtension == "json" }
            .compactMap(load(from:))
            .sorted {
                if $0.isBuiltIn != $1.isBuiltIn {
                    return $0.isBuiltIn
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }

        return personas.isEmpty ? Persona.starterPersonas() : personas
    }

    func load(id: String) -> Persona? {
        load(from: fileURL(for: id))
    }

    func save(_ persona: Persona) {
        let updated = persona.refreshedTimestamp()
        guard let data = try? JSONEncoder().encode(updated) else { return }
        try? data.write(to: fileURL(for: persona.id), options: .atomic)
    }

    func delete(id: String) {
        try? fileManager.removeItem(at: fileURL(for: id))
    }

    private func seedStarterPersonasIfNeeded() {
        let existingIDs = Set(listExistingIDs())

        for persona in Persona.starterPersonas() where !existingIDs.contains(persona.id) {
            save(persona)
        }
    }

    private func listExistingIDs() -> [String] {
        guard let urls = try? fileManager.contentsOfDirectory(at: personasDirectory, includingPropertiesForKeys: nil) else {
            return []
        }

        return urls
            .filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
    }

    private func load(from url: URL) -> Persona? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Persona.self, from: data)
    }

    private func fileURL(for id: String) -> URL {
        personasDirectory.appendingPathComponent(id).appendingPathExtension("json")
    }
}
