import Foundation

actor LLMProfilingStore {
    private static let recoverableInterruptionStages: Set<String> = [
        "tokenized_input",
        "first_output_chunk",
        "decode_progress"
    ]

    private let archiveFilename = "llm-profiling-history.json"
    private let inProgressFilename = "llm-inference-in-progress.json"
    private let activeSessionID = UUID()
    private let activeSessionStartedAt = Date()

    func loadPersistedState() -> (
        sessions: [LLMProfilingSessionRecord],
        profiles: [LLMExecutionProfile],
        crashReports: [LLMInferenceCrashReport]
    ) {
        var archive = normalizedArchive()

        if let snapshot = readInProgressSnapshot() {
            if Self.recoverableInterruptionStages.contains(snapshot.stage),
               !archive.profiles.contains(where: { $0.id == snapshot.id }) {
                let report = LLMInferenceCrashReport(
                    snapshot: snapshot,
                    recoveryProcessMemoryFootprintBytes: LLMProfiler.currentMemoryFootprintBytes(),
                    recoveryThermalState: LLMProfiler.thermalStateDescription()
                )
                var session = sessionRecord(
                    id: snapshot.sessionID,
                    startedAt: snapshot.sessionStartedAt,
                    in: &archive
                )
                session.addCrashReport(report)
                upsert(session, in: &archive)
                writeSession(session)
            }
            removeInProgressSnapshot()
            writeArchive(archive)
        }

        return persistedState(from: archive)
    }

    @discardableResult
    func saveInProgressProfile(
        _ profile: LLMExecutionProfile,
        stage: String,
        memoryFootprintBytes: UInt64?,
        thermalState: String?,
        batteryLevel: Double?,
        emittedTextChunkCount: Int? = nil,
        emittedTextCharacterCount: Int? = nil,
        persistInProgressSnapshot: Bool = true,
        writeSessionExport: Bool = true
    ) -> LLMProfilingSessionRecord {
        var archive = normalizedArchive()
        var session = sessionRecord(
            id: activeSessionID,
            startedAt: activeSessionStartedAt,
            in: &archive
        )
        guard !session.profiles.contains(where: { $0.id == profile.id }) else {
            return session
        }
        let snapshot = LLMInferenceInProgressSnapshot(
            sessionID: session.id,
            sessionStartedAt: session.startedAt,
            profile: profile,
            stage: stage,
            memoryFootprintBytes: memoryFootprintBytes,
            thermalState: thermalState,
            batteryLevel: batteryLevel,
            emittedTextChunkCount: emittedTextChunkCount,
            emittedTextCharacterCount: emittedTextCharacterCount
        )
        session.saveActiveSnapshot(snapshot)
        upsert(session, in: &archive)
        if persistInProgressSnapshot {
            write(snapshot, to: inProgressURL)
        }
        writeArchive(archive)
        if writeSessionExport {
            writeSession(session)
        }
        return session
    }

    @discardableResult
    func recordCompletedProfile(_ profile: LLMExecutionProfile) -> LLMProfilingSessionRecord {
        var archive = normalizedArchive()
        var session = sessionRecord(
            id: activeSessionID,
            startedAt: activeSessionStartedAt,
            in: &archive
        )
        session.upsertProfile(profile)
        upsert(session, in: &archive)
        writeArchive(archive)
        writeSession(session)

        if let snapshot = readInProgressSnapshot(),
           snapshot.id == profile.id {
            removeInProgressSnapshot()
        }
        return session
    }

    func deleteSession(id: UUID) -> (
        sessions: [LLMProfilingSessionRecord],
        profiles: [LLMExecutionProfile],
        crashReports: [LLMInferenceCrashReport]
    ) {
        var archive = normalizedArchive()
        archive.sessions.removeAll { $0.id == id }
        normalize(&archive)
        writeArchive(archive)
        removeSessionFiles(id: id)

        if let snapshot = readInProgressSnapshot(),
           snapshot.sessionID == id {
            removeInProgressSnapshot()
        }

        return persistedState(from: archive)
    }

    private var directoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("iMLX", isDirectory: true)
            .appendingPathComponent("LLMProfiling", isDirectory: true)
    }

    private var sessionsDirectoryURL: URL {
        directoryURL.appendingPathComponent("Sessions", isDirectory: true)
    }

    private var archiveURL: URL {
        directoryURL.appendingPathComponent(archiveFilename, isDirectory: false)
    }

    private var inProgressURL: URL {
        directoryURL.appendingPathComponent(inProgressFilename, isDirectory: false)
    }

    private func normalizedArchive() -> LLMProfilingHistoryArchive {
        var archive = readArchive()
        normalize(&archive)
        return archive
    }

    private func readArchive() -> LLMProfilingHistoryArchive {
        guard let data = try? Data(contentsOf: archiveURL),
              let archive = try? decoder.decode(LLMProfilingHistoryArchive.self, from: data) else {
            return LLMProfilingHistoryArchive()
        }
        return archive
    }

    private func readInProgressSnapshot() -> LLMInferenceInProgressSnapshot? {
        guard let data = try? Data(contentsOf: inProgressURL) else {
            return nil
        }
        return try? decoder.decode(LLMInferenceInProgressSnapshot.self, from: data)
    }

    private func sessionRecord(
        id: UUID,
        startedAt: Date,
        in archive: inout LLMProfilingHistoryArchive
    ) -> LLMProfilingSessionRecord {
        if let session = archive.sessions.first(where: { $0.id == id }) {
            return session
        }
        let session = LLMProfilingSessionRecord(
            id: id,
            startedAt: startedAt,
            updatedAt: startedAt
        )
        archive.sessions.append(session)
        normalize(&archive)
        return session
    }

    private func upsert(_ session: LLMProfilingSessionRecord, in archive: inout LLMProfilingHistoryArchive) {
        if let index = archive.sessions.firstIndex(where: { $0.id == session.id }) {
            archive.sessions[index] = session
        } else {
            archive.sessions.append(session)
        }
        normalize(&archive)
    }

    private func normalize(_ archive: inout LLMProfilingHistoryArchive) {
        archive.sessions.sort { $0.startedAt < $1.startedAt }
        archive.profiles = archive.sessions
            .flatMap(\.profiles)
            .sorted { $0.createdAt < $1.createdAt }
        archive.crashReports = archive.sessions
            .flatMap(\.crashReports)
            .sorted { $0.recoveredAt < $1.recoveredAt }
        archive.updatedAt = Date()
    }

    private func persistedState(from archive: LLMProfilingHistoryArchive) -> (
        sessions: [LLMProfilingSessionRecord],
        profiles: [LLMExecutionProfile],
        crashReports: [LLMInferenceCrashReport]
    ) {
        (
            sessions: archive.sessions.sorted { $0.startedAt < $1.startedAt },
            profiles: archive.profiles.sorted { $0.createdAt < $1.createdAt },
            crashReports: archive.crashReports.sorted { $0.recoveredAt < $1.recoveredAt }
        )
    }

    private func writeArchive(_ archive: LLMProfilingHistoryArchive) {
        var archive = archive
        normalize(&archive)
        write(archive, to: archiveURL)
    }

    private func writeSession(_ session: LLMProfilingSessionRecord) {
        let filename = "llm-profiling-session-\(Self.filenameTimestamp(from: session.startedAt))-\(session.id.uuidString).json"
        let url = sessionsDirectoryURL.appendingPathComponent(filename, isDirectory: false)
        write(LLMProfilingSessionExport(session: session), to: url)
    }

    private func removeSessionFiles(id: UUID) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in urls where url.lastPathComponent.contains(id.uuidString) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sessionsDirectoryURL, withIntermediateDirectories: true)
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Profiling persistence is best-effort and must never change inference behavior.
        }
    }

    private func removeInProgressSnapshot() {
        do {
            try FileManager.default.removeItem(at: inProgressURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
        } catch {
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func filenameTimestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}
