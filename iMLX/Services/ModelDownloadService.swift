import Foundation

actor ModelDownloadService {
    static let backgroundSessionIdentifier = "com.alan13367.iMLX.model-downloads"

    private static let defaultRevision = "main"
    private static let modelFileGlobs = ["*.safetensors", "*.json", "*.jinja", "*.txt", "*.model"]

    typealias SnapshotObserver = @Sendable ([String: ModelDownloadSnapshot]) async -> Void

    private let fileManager = FileManager.default

    private let modelsBaseURL: URL
    private let repoDownloadsBaseURL: URL
    private let hubCacheBaseURL: URL
    private let sandboxRootURL: URL
    private let stagingDirectoryURL: URL
    private let jobsFileURL: URL
    private let hostURL: URL
    private let manifestService: ManifestService
    private let metadataSession: URLSession
    private let session: URLSession

    private var jobsByModelId: [String: ModelDownloadJob]
    private var snapshotObserver: SnapshotObserver?
    private var lastEmittedSnapshots: [String: ModelDownloadSnapshot] = [:]

    init(manifestService: ManifestService) {
        self.manifestService = manifestService

        let fileManager = FileManager.default
        let appSupport =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let caches =
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        self.modelsBaseURL = appSupport.appendingPathComponent(Constants.Storage.modelsDirectory)
        self.repoDownloadsBaseURL = self.modelsBaseURL.appendingPathComponent("models")
        self.hubCacheBaseURL =
            caches
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
        self.sandboxRootURL = self.modelsBaseURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        self.stagingDirectoryURL = appSupport.appendingPathComponent(
            Constants.Storage.modelDownloadStagingDirectory)
        self.jobsFileURL = appSupport.appendingPathComponent(
            Constants.Storage.modelDownloadJobsManifest)

        try? fileManager.createDirectory(at: self.modelsBaseURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(
            at: self.repoDownloadsBaseURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(
            at: self.stagingDirectoryURL, withIntermediateDirectories: true)

        self.hostURL = URL(string: "https://huggingface.co")!
        let metadataConfiguration = URLSessionConfiguration.ephemeral
        metadataConfiguration.waitsForConnectivity = true
        metadataConfiguration.timeoutIntervalForRequest = 60
        metadataConfiguration.timeoutIntervalForResource = 60
        self.metadataSession = URLSession(configuration: metadataConfiguration)

        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.backgroundSessionIdentifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60 * 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24

        let delegate = BackgroundDownloadSessionDelegate(
            stagingDirectoryURL: self.stagingDirectoryURL)
        let session = URLSession(
            configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        self.jobsByModelId = Self.loadPersistedJobs(from: self.jobsFileURL)

        delegate.service = self

        Self.migrateOldDownloads(fileManager: fileManager, modelsBaseURL: self.modelsBaseURL)
        Self.cleanupStagingDirectory(
            fileManager: fileManager, stagingDirectoryURL: self.stagingDirectoryURL)
    }

    func setSnapshotObserver(_ observer: @escaping SnapshotObserver) async {
        snapshotObserver = observer
        await notifyObserverIfNeeded(force: true)
    }

    func startDownload(for model: ModelInfo) async throws {
        let activeJobs = jobsByModelId.values.filter {
            $0.status == .queued || $0.status == .downloading
        }
        if let activeJob = activeJobs.first, activeJob.id != model.id {
            throw DownloadError.anotherDownloadInProgress(activeJob.displayName)
        }

        guard await manifestService.isDownloaded(modelId: model.id) == false else {
            return
        }

        try checkAvailableDiskSpace(for: model)

        var job = try await buildJob(for: model)
        let taskDescriptions = Set(await fetchAllSessionTasks().compactMap(\.taskDescription))

        if let existingJob = jobsByModelId[model.id],
            existingJob.status == .downloading || existingJob.status == .queued
        {
            job = merge(job, withExistingJob: existingJob, activeTaskDescriptions: taskDescriptions)
        }

        jobsByModelId[model.id] = job
        savePersistedJobs()
        await schedulePendingTasks(for: model.id, activeTaskDescriptions: taskDescriptions)
        await notifyObserverIfNeeded(force: true)
    }

    func restorePendingDownloads() async {
        await reconcilePersistedJobsWithDisk()

        let tasks = await fetchAllSessionTasks()
        let activeTaskDescriptions = Set(tasks.compactMap(\.taskDescription))

        for task in tasks {
            guard let descriptor = parseTaskDescription(task.taskDescription) else { continue }
            guard var job = jobsByModelId[descriptor.modelId] else { continue }
            guard
                let index = job.files.firstIndex(where: {
                    $0.relativePath == descriptor.relativePath
                })
            else { continue }

            job.files[index].status = .downloading
            job.files[index].writtenBytes = max(
                job.files[index].writtenBytes, task.countOfBytesReceived)
            if task.countOfBytesExpectedToReceive > 0 {
                job.files[index].expectedBytes = task.countOfBytesExpectedToReceive
            }
            if job.status != .failed {
                job.status = .downloading
            }
            job.updatedAt = Date()
            jobsByModelId[descriptor.modelId] = job
        }

        savePersistedJobs()

        for job in jobsByModelId.values.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard job.status == .queued || job.status == .downloading else { continue }
            await schedulePendingTasks(for: job.id, activeTaskDescriptions: activeTaskDescriptions)
            await attemptFinalizeIfReady(for: job.id)
        }

        await notifyObserverIfNeeded(force: true)
    }

    func handleBackgroundEventsFinished() async {
        await restorePendingDownloads()
    }

    func handleTaskProgress(
        taskDescription: String,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) async {
        guard let descriptor = parseTaskDescription(taskDescription) else { return }
        guard var job = jobsByModelId[descriptor.modelId] else { return }
        guard
            let index = job.files.firstIndex(where: { $0.relativePath == descriptor.relativePath })
        else { return }

        job.files[index].writtenBytes = max(job.files[index].writtenBytes, totalBytesWritten)
        if totalBytesExpectedToWrite > 0 {
            job.files[index].expectedBytes = totalBytesExpectedToWrite
        }
        job.files[index].status = .downloading
        job.files[index].lastErrorMessage = nil
        if job.status != .failed {
            job.status = .downloading
        }
        job.updatedAt = Date()
        jobsByModelId[descriptor.modelId] = job

        await notifyObserverIfNeeded(force: false)
    }

    func handleDownloadedFile(taskDescription: String, stagedFileURL: URL) async {
        guard let descriptor = parseTaskDescription(taskDescription) else {
            try? fileManager.removeItem(at: stagedFileURL)
            return
        }
        guard var job = jobsByModelId[descriptor.modelId] else {
            try? fileManager.removeItem(at: stagedFileURL)
            return
        }
        guard
            let index = job.files.firstIndex(where: { $0.relativePath == descriptor.relativePath })
        else {
            try? fileManager.removeItem(at: stagedFileURL)
            return
        }

        let destinationURL = repositoryDirectory(for: job.huggingFaceId).appending(
            path: descriptor.relativePath)

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: stagedFileURL, to: destinationURL)

            let fileSize = fileSizeIfExists(at: destinationURL)
            job.files[index].writtenBytes = fileSize
            if fileSize > 0 {
                job.files[index].expectedBytes = max(job.files[index].expectedBytes ?? 0, fileSize)
            }
            job.files[index].status = .completed
            job.files[index].lastErrorMessage = nil
            if job.status != .failed {
                job.status = .downloading
            }
            job.updatedAt = Date()
            jobsByModelId[descriptor.modelId] = job
            savePersistedJobs()

            await attemptFinalizeIfReady(for: descriptor.modelId)
            await notifyObserverIfNeeded(force: true)
        } catch {
            try? fileManager.removeItem(at: stagedFileURL)
            await failJob(
                modelId: descriptor.modelId, message: error.localizedDescription,
                cancelRemainingTasks: true)
        }
    }

    func handleTaskFailure(taskDescription: String, message: String, isCancellation: Bool) async {
        guard let descriptor = parseTaskDescription(taskDescription) else { return }
        guard var job = jobsByModelId[descriptor.modelId] else { return }
        guard
            let index = job.files.firstIndex(where: { $0.relativePath == descriptor.relativePath })
        else { return }

        if isCancellation {
            if job.status == .failed {
                return
            }
            job.files[index].status = .pending
            job.updatedAt = Date()
            jobsByModelId[descriptor.modelId] = job
            savePersistedJobs()
            await notifyObserverIfNeeded(force: true)
            return
        }

        await failJob(modelId: descriptor.modelId, message: message, cancelRemainingTasks: true)
    }

    func sizeOfModel(_ model: ModelInfo) -> Int64 {
        let destination =
            preferredModelDirectory(for: model) ?? modelsBaseURL.appendingPathComponent(model.id)
        return sizeOfDirectory(at: destination)
    }

    @discardableResult
    func cancelDownload(for model: ModelInfo) async -> Bool {
        await cancelDownload(modelId: model.id, huggingFaceId: model.huggingFaceId)
    }

    @discardableResult
    private func cancelDownload(modelId: String, huggingFaceId: String) async -> Bool {
        guard jobsByModelId[modelId] != nil else { return true }

        jobsByModelId.removeValue(forKey: modelId)
        savePersistedJobs()

        await cancelTasks(for: modelId)

        do {
            try removeDownloadArtifacts(modelId: modelId, huggingFaceId: huggingFaceId)
        } catch {
            print("[ModelDownloadService] cancelDownload cleanup failed for \(modelId): \(error)")
            await notifyObserverIfNeeded(force: true)
            return false
        }

        await notifyObserverIfNeeded(force: true)
        return true
    }

    func deleteModel(_ model: ModelInfo) async throws {
        try await deleteModel(modelId: model.id, huggingFaceId: model.huggingFaceId)
    }

    func deleteModel(modelId: String, huggingFaceId: String) async throws {
        await cancelTasks(for: modelId)
        jobsByModelId.removeValue(forKey: modelId)
        savePersistedJobs()

        try removeDownloadArtifacts(modelId: modelId, huggingFaceId: huggingFaceId)
        await manifestService.removeDownloaded(modelId: modelId)
        await notifyObserverIfNeeded(force: true)
    }

    func isModelDownloaded(_ model: ModelInfo) -> Bool {
        preferredModelDirectory(for: model) != nil
    }

    func localURL(for model: ModelInfo) -> URL {
        preferredModelDirectory(for: model) ?? modelsBaseURL.appendingPathComponent(model.id)
    }

    private func buildJob(for model: ModelInfo) async throws -> ModelDownloadJob {
        let filenames = try await fetchRepositoryFilenames(for: model)
        guard filenames.isEmpty == false else {
            throw DownloadError.corruptedDownload(model.displayName)
        }

        let expectedBytesByFile = await fetchExpectedBytes(
            for: filenames,
            huggingFaceId: model.huggingFaceId,
            revision: Self.defaultRevision
        )

        let repoDirectory = repositoryDirectory(for: model.huggingFaceId)
        var files: [ModelDownloadFileState] = []

        for filename in filenames {
            let destinationURL = repoDirectory.appending(path: filename)
            let existingBytes = fileSizeIfExists(at: destinationURL)
            let expectedBytes = expectedBytesByFile[filename] ?? nil
            let isComplete = isCompleteFile(
                existingBytes: existingBytes, expectedBytes: expectedBytes)

            files.append(
                ModelDownloadFileState(
                    relativePath: filename,
                    remoteURL: remoteFileURL(
                        for: model.huggingFaceId, revision: Self.defaultRevision,
                        relativePath: filename),
                    expectedBytes: expectedBytes,
                    writtenBytes: isComplete ? existingBytes : 0,
                    status: isComplete ? .completed : .pending,
                    lastErrorMessage: nil
                )
            )
        }

        return ModelDownloadJob(
            id: model.id,
            displayName: model.displayName,
            huggingFaceId: model.huggingFaceId,
            revision: Self.defaultRevision,
            createdAt: Date(),
            updatedAt: Date(),
            status: .queued,
            lastErrorMessage: nil,
            files: files
        )
    }

    private func fetchRepositoryFilenames(for model: ModelInfo) async throws -> [String] {
        let requestURL =
            hostURL
            .appending(path: "api")
            .appending(path: "models")
            .appending(path: model.huggingFaceId)

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await metadataSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                throw DownloadError.unableToListRepository(model.displayName)
            }

            let repository = try JSONDecoder().decode(
                HuggingFaceRepositoryResponse.self, from: data)
            return repository.siblings
                .map(\.rfilename)
                .filter { Self.matchesAnyGlob($0, globs: Self.modelFileGlobs) }
                .sorted()
        } catch let error as DownloadError {
            throw error
        } catch {
            throw DownloadError.unableToListRepository(model.displayName)
        }
    }

    private func fetchExpectedBytes(
        for filenames: [String],
        huggingFaceId: String,
        revision: String
    ) async -> [String: Int64?] {
        var expectedBytesByFile: [String: Int64?] = [:]

        for filename in filenames {
            expectedBytesByFile[filename] = await fetchExpectedBytes(
                for: filename,
                huggingFaceId: huggingFaceId,
                revision: revision
            )
        }

        return expectedBytesByFile
    }

    private func fetchExpectedBytes(
        for relativePath: String,
        huggingFaceId: String,
        revision: String
    ) async -> Int64? {
        var request = URLRequest(
            url: remoteFileURL(for: huggingFaceId, revision: revision, relativePath: relativePath))
        request.httpMethod = "HEAD"
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (_, response) = try await metadataSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode)
            else {
                return nil
            }

            if let headerValue = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                let fileSize = Int64(headerValue)
            {
                return fileSize
            }

            return response.expectedContentLength > 0 ? response.expectedContentLength : nil
        } catch {
            return nil
        }
    }

    private func merge(
        _ freshJob: ModelDownloadJob,
        withExistingJob existingJob: ModelDownloadJob,
        activeTaskDescriptions: Set<String>
    ) -> ModelDownloadJob {
        var mergedJob = freshJob
        mergedJob.createdAt = existingJob.createdAt

        for index in mergedJob.files.indices {
            let relativePath = mergedJob.files[index].relativePath
            let description = taskDescription(modelId: mergedJob.id, relativePath: relativePath)
            if activeTaskDescriptions.contains(description) {
                mergedJob.files[index].status = .downloading
            } else if let existingFile = existingJob.files.first(where: {
                $0.relativePath == relativePath
            }) {
                mergedJob.files[index].writtenBytes = max(
                    mergedJob.files[index].writtenBytes, existingFile.writtenBytes)
                mergedJob.files[index].expectedBytes =
                    mergedJob.files[index].expectedBytes ?? existingFile.expectedBytes
                if mergedJob.files[index].status != .completed {
                    mergedJob.files[index].status =
                        existingFile.status == .completed ? .completed : .pending
                }
            }
        }

        if mergedJob.files.contains(where: { $0.status == .downloading }) {
            mergedJob.status = .downloading
        } else {
            mergedJob.status = existingJob.status == .failed ? .failed : .queued
        }
        mergedJob.lastErrorMessage = existingJob.lastErrorMessage
        mergedJob.updatedAt = Date()
        return mergedJob
    }

    private func reconcilePersistedJobsWithDisk() async {
        for jobId in jobsByModelId.keys.sorted() {
            guard var job = jobsByModelId[jobId] else { continue }
            let repoDirectory = repositoryDirectory(for: job.huggingFaceId)

            for index in job.files.indices {
                let destinationURL = repoDirectory.appending(path: job.files[index].relativePath)
                let fileSize = fileSizeIfExists(at: destinationURL)
                if isCompleteFile(
                    existingBytes: fileSize, expectedBytes: job.files[index].expectedBytes)
                {
                    job.files[index].writtenBytes = fileSize
                    job.files[index].status = .completed
                    job.files[index].lastErrorMessage = nil
                } else if job.files[index].status == .completed {
                    job.files[index].writtenBytes = 0
                    job.files[index].status = .pending
                }
            }

            jobsByModelId[jobId] = job
        }

        savePersistedJobs()
    }

    private func schedulePendingTasks(for modelId: String, activeTaskDescriptions: Set<String>)
        async
    {
        guard var job = jobsByModelId[modelId] else { return }
        guard job.status != .failed else { return }

        var scheduledAnyTask = false
        for index in job.files.indices {
            let file = job.files[index]
            guard file.status != .completed else { continue }

            let description = taskDescription(modelId: modelId, relativePath: file.relativePath)
            if activeTaskDescriptions.contains(description) {
                job.files[index].status = .downloading
                continue
            }

            var request = URLRequest(url: file.remoteURL)
            request.allowsExpensiveNetworkAccess = true
            request.allowsConstrainedNetworkAccess = true
            request.timeoutInterval = 60 * 60

            let task = session.downloadTask(with: request)
            task.taskDescription = description
            job.files[index].status = .queued
            task.resume()
            scheduledAnyTask = true
        }

        if scheduledAnyTask
            || job.files.contains(where: { $0.status == .downloading || $0.status == .queued })
        {
            job.status =
                job.files.contains(where: { $0.status == .downloading }) ? .downloading : .queued
        }
        job.updatedAt = Date()
        jobsByModelId[modelId] = job
        savePersistedJobs()
    }

    private func attemptFinalizeIfReady(for modelId: String) async {
        guard let job = jobsByModelId[modelId] else { return }
        guard job.status != .failed else { return }
        guard job.files.allSatisfy({ $0.status == .completed }) else { return }
        guard let model = Constants.ModelRegistry.curatedModels.first(where: { $0.id == modelId })
        else {
            await failJob(
                modelId: modelId, message: "Unable to find model metadata for \(modelId).",
                cancelRemainingTasks: false)
            return
        }

        let repoDirectory = repositoryDirectory(for: job.huggingFaceId)
        guard isUsableModelDirectory(repoDirectory, for: model) else {
            await failJob(
                modelId: modelId,
                message: DownloadError.corruptedDownload(model.displayName).localizedDescription,
                cancelRemainingTasks: false)
            return
        }

        do {
            let symlinkPath = modelsBaseURL.appendingPathComponent(model.id)
            try? fileManager.removeItem(at: symlinkPath)
            try createModelSymlink(at: symlinkPath, targetURL: repoDirectory)

            let sizeOnDisk = sizeOfDirectory(at: repoDirectory)
            await manifestService.addDownloaded(
                modelId: model.id,
                displayName: model.displayName,
                huggingFaceId: model.huggingFaceId,
                localPath: model.id,
                sizeOnDiskBytes: sizeOnDisk
            )

            jobsByModelId.removeValue(forKey: modelId)
            savePersistedJobs()
            await notifyObserverIfNeeded(force: true)
        } catch {
            await failJob(
                modelId: modelId, message: error.localizedDescription, cancelRemainingTasks: false)
        }
    }

    private func failJob(modelId: String, message: String, cancelRemainingTasks: Bool) async {
        guard var job = jobsByModelId[modelId] else { return }

        job.status = .failed
        job.lastErrorMessage = message
        job.updatedAt = Date()
        for index in job.files.indices where job.files[index].status != .completed {
            job.files[index].status = .failed
            job.files[index].lastErrorMessage = message
        }

        jobsByModelId[modelId] = job
        savePersistedJobs()

        if cancelRemainingTasks {
            await cancelTasks(for: modelId)
        }

        await notifyObserverIfNeeded(force: true)
    }

    private func cancelTasks(for modelId: String) async {
        let tasks = await fetchAllSessionTasks()
        for task in tasks {
            guard let descriptor = parseTaskDescription(task.taskDescription),
                descriptor.modelId == modelId
            else { continue }
            task.cancel()
        }
    }

    private func removeDownloadArtifacts(modelId: String, huggingFaceId: String) throws {
        let symlinkPath = modelsBaseURL.appendingPathComponent(modelId)
        if fileManager.fileExists(atPath: symlinkPath.path) {
            try fileManager.removeItem(at: symlinkPath)
        }

        let appSupportRepoPath = repositoryDirectory(for: huggingFaceId)
        if fileManager.fileExists(atPath: appSupportRepoPath.path) {
            try fileManager.removeItem(at: appSupportRepoPath)
        }

        let cachePath = hubCacheBaseURL.appendingPathComponent(
            cacheDirectoryName(for: huggingFaceId))
        if fileManager.fileExists(atPath: cachePath.path) {
            try fileManager.removeItem(at: cachePath)
        }

        let lockPath =
            hubCacheBaseURL
            .appendingPathComponent(".locks")
            .appendingPathComponent(cacheDirectoryName(for: huggingFaceId))
        if fileManager.fileExists(atPath: lockPath.path) {
            try fileManager.removeItem(at: lockPath)
        }
    }

    private func savePersistedJobs() {
        let manifest = ModelDownloadJobsManifest(
            jobs: jobsByModelId.values.sorted { $0.createdAt < $1.createdAt })
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: jobsFileURL, options: [.atomic])
        }
    }

    private func notifyObserverIfNeeded(force: Bool) async {
        let snapshots = currentSnapshots()
        guard force || snapshots != lastEmittedSnapshots else { return }
        lastEmittedSnapshots = snapshots
        guard let snapshotObserver else { return }
        await snapshotObserver(snapshots)
    }

    private func currentSnapshots() -> [String: ModelDownloadSnapshot] {
        Dictionary(
            uniqueKeysWithValues: jobsByModelId.values.map { job in
                let totalBytesExpected = totalBytesExpected(for: job)
                let bytesWritten = totalBytesWritten(for: job)
                return (
                    job.id,
                    ModelDownloadSnapshot(
                        modelId: job.id,
                        displayName: job.displayName,
                        progress: progress(
                            for: job, bytesWritten: bytesWritten,
                            totalBytesExpected: totalBytesExpected),
                        bytesWritten: bytesWritten,
                        totalBytesExpected: totalBytesExpected,
                        status: snapshotStatus(for: job.status),
                        lastErrorMessage: job.lastErrorMessage
                    )
                )
            }
        )
    }

    private func snapshotStatus(for status: ModelDownloadJob.Status) -> ModelDownloadSnapshot.Status
    {
        switch status {
        case .queued:
            return .queued
        case .downloading:
            return .downloading
        case .failed:
            return .failed
        }
    }

    private func totalBytesExpected(for job: ModelDownloadJob) -> Int64? {
        let expectedValues = job.files.compactMap(\.expectedBytes)
        guard expectedValues.count == job.files.count else { return nil }
        return expectedValues.reduce(0, +)
    }

    private func totalBytesWritten(for job: ModelDownloadJob) -> Int64 {
        job.files.reduce(0) { $0 + min($1.writtenBytes, $1.expectedBytes ?? $1.writtenBytes) }
    }

    private func progress(
        for job: ModelDownloadJob, bytesWritten: Int64, totalBytesExpected: Int64?
    ) -> Float {
        if let totalBytesExpected, totalBytesExpected > 0 {
            return min(max(Float(bytesWritten) / Float(totalBytesExpected), 0), 1)
        }

        guard job.files.isEmpty == false else { return 0 }

        let totalProgress = job.files.reduce(0.0) { partialResult, file in
            switch file.status {
            case .completed:
                return partialResult + 1
            case .downloading, .queued:
                if let expectedBytes = file.expectedBytes, expectedBytes > 0 {
                    return partialResult + min(Double(file.writtenBytes) / Double(expectedBytes), 1)
                }
                return partialResult
            case .failed, .pending:
                return partialResult
            }
        }

        return Float(min(max(totalProgress / Double(job.files.count), 0), 1))
    }

    private func fetchAllSessionTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                continuation.resume(returning: tasks)
            }
        }
    }

    private func repositoryDirectory(for huggingFaceId: String) -> URL {
        repoDownloadsBaseURL.appendingPathComponent(huggingFaceId)
    }

    private func remoteFileURL(for huggingFaceId: String, revision: String, relativePath: String)
        -> URL
    {
        hostURL
            .appending(path: huggingFaceId)
            .appending(path: "resolve")
            .appending(component: revision)
            .appending(path: relativePath)
    }

    private func taskDescription(modelId: String, relativePath: String) -> String {
        let descriptor = TaskDescriptor(modelId: modelId, relativePath: relativePath)
        if let data = try? JSONEncoder().encode(descriptor),
            let encoded = String(data: data, encoding: .utf8)
        {
            return encoded
        }
        return "\(modelId)|\(relativePath)"
    }

    private func parseTaskDescription(_ taskDescription: String?) -> TaskDescriptor? {
        guard let taskDescription else { return nil }
        if let data = taskDescription.data(using: .utf8),
            let descriptor = try? JSONDecoder().decode(TaskDescriptor.self, from: data)
        {
            return descriptor
        }

        let components = taskDescription.split(separator: "|", maxSplits: 1).map(String.init)
        guard components.count == 2 else { return nil }
        return TaskDescriptor(modelId: components[0], relativePath: components[1])
    }

    private func checkAvailableDiskSpace(for model: ModelInfo) throws {
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
    }

    private func fileSizeIfExists(at url: URL) -> Int64 {
        guard fileManager.fileExists(atPath: url.path) else { return 0 }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    private func isCompleteFile(existingBytes: Int64, expectedBytes: Int64?) -> Bool {
        guard existingBytes > 0 else { return false }
        guard let expectedBytes, expectedBytes > 0 else { return true }
        return existingBytes >= expectedBytes
    }

    private func sizeOfDirectory(at url: URL) -> Int64 {
        var totalSize: Int64 = 0
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
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

    private func preferredModelDirectory(for model: ModelInfo) -> URL? {
        let symlinkPath = modelsBaseURL.appendingPathComponent(model.id)
        if let symlinkTarget = usableSymlinkTarget(at: symlinkPath, for: model) {
            return symlinkTarget
        }

        let appSupportRepoPath = repositoryDirectory(for: model.huggingFaceId)
        if isUsableModelDirectory(appSupportRepoPath, for: model) {
            return appSupportRepoPath
        }

        if let snapshotDirectory = newestSnapshotDirectory(for: model) {
            try? createModelSymlink(at: symlinkPath, targetURL: snapshotDirectory)
            return snapshotDirectory
        }

        let cacheDirectory = hubCacheBaseURL.appendingPathComponent(cacheDirectoryName(for: model))
        if isUsableModelDirectory(cacheDirectory, for: model) {
            return cacheDirectory
        }

        return nil
    }

    private func newestSnapshotDirectory(for model: ModelInfo) -> URL? {
        let snapshotsDirectory =
            hubCacheBaseURL
            .appendingPathComponent(cacheDirectoryName(for: model))
            .appendingPathComponent("snapshots")

        guard
            let snapshots = try? fileManager.contentsOfDirectory(
                at: snapshotsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }

        let sortedSnapshots = snapshots.sorted { lhs, rhs in
            let lhsDate =
                (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
            let rhsDate =
                (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        for snapshot in sortedSnapshots where isUsableModelDirectory(snapshot, for: model) {
            return snapshot
        }

        return nil
    }

    private func cacheDirectoryName(for model: ModelInfo) -> String {
        cacheDirectoryName(for: model.huggingFaceId)
    }

    private func cacheDirectoryName(for huggingFaceId: String) -> String {
        "models--" + huggingFaceId.replacingOccurrences(of: "/", with: "--")
    }

    private func usableSymlinkTarget(at symlinkPath: URL, for model: ModelInfo) -> URL? {
        guard let values = try? symlinkPath.resourceValues(forKeys: [.isSymbolicLinkKey]),
            values.isSymbolicLink == true,
            let destinationPath = try? fileManager.destinationOfSymbolicLink(
                atPath: symlinkPath.path)
        else {
            return nil
        }

        let destinationURL = URL(
            fileURLWithPath: destinationPath, relativeTo: symlinkPath.deletingLastPathComponent()
        )
        .standardizedFileURL
        .resolvingSymlinksInPath()
        if isUsableModelDirectory(destinationURL, for: model) {
            return destinationURL
        }

        try? fileManager.removeItem(at: symlinkPath)
        return nil
    }

    private func isUsableModelDirectory(_ directory: URL, for model: ModelInfo) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else {
            return false
        }

        let configURL = directory.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL), !configData.isEmpty else {
            return false
        }

        guard let configObject = try? JSONSerialization.jsonObject(with: configData),
            let config = configObject as? [String: Any]
        else {
            return false
        }

        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else {
            return false
        }

        let hasWeights = contents.contains { $0.pathExtension == "safetensors" }
        guard hasWeights else {
            return false
        }

        if model.supportsVision {
            let hasVisionConfig = config["vision_config"] != nil
            if !hasVisionConfig {
                return false
            }

            let hasPreprocessor = fileManager.fileExists(
                atPath: directory.appendingPathComponent("preprocessor_config.json").path)
            let hasProcessor = fileManager.fileExists(
                atPath: directory.appendingPathComponent("processor_config.json").path)
            if !hasPreprocessor && !hasProcessor {
                return false
            }
        }

        return true
    }

    private func createModelSymlink(at symlinkPath: URL, targetURL: URL) throws {
        let relativeTarget = relativePath(
            from: symlinkPath.deletingLastPathComponent(), to: targetURL)
        try? fileManager.removeItem(at: symlinkPath)
        try fileManager.createSymbolicLink(
            atPath: symlinkPath.path, withDestinationPath: relativeTarget)
    }

    private func relativePath(from baseURL: URL, to targetURL: URL) -> String {
        let baseComponents = baseURL.standardizedFileURL.pathComponents
        let targetComponents = targetURL.standardizedFileURL.pathComponents

        guard targetURL.standardizedFileURL.path.hasPrefix(sandboxRootURL.standardizedFileURL.path)
        else {
            return targetURL.path
        }

        var sharedIndex = 0
        while sharedIndex < min(baseComponents.count, targetComponents.count),
            baseComponents[sharedIndex] == targetComponents[sharedIndex]
        {
            sharedIndex += 1
        }

        let upPath = Array(repeating: "..", count: baseComponents.count - sharedIndex)
        let downPath = Array(targetComponents.dropFirst(sharedIndex))
        return (upPath + downPath).joined(separator: "/")
    }

    private nonisolated static let infrastructureDirectoryNames: Set<String> = [
        "models",
        Constants.Storage.modelDownloadStagingDirectory,
    ]

    private nonisolated static func matchesAnyGlob(_ value: String, globs: [String]) -> Bool {
        globs.contains { glob in
            let escaped = NSRegularExpression.escapedPattern(for: glob)
            let regex =
                "^"
                + escaped
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".") + "$"
            return value.range(of: regex, options: .regularExpression) != nil
        }
    }

    private nonisolated static func migrateOldDownloads(
        fileManager: FileManager, modelsBaseURL: URL
    ) {
        let entries =
            (try? fileManager.contentsOfDirectory(
                at: modelsBaseURL, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
        for entry in entries {
            let name = entry.lastPathComponent
            let attrs = try? entry.resourceValues(forKeys: [.isSymbolicLinkKey])
            if attrs?.isSymbolicLink == true {
                continue
            }
            if name.hasPrefix("models--") {
                continue
            }
            if infrastructureDirectoryNames.contains(name) {
                continue
            }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: entry.path, isDirectory: &isDir), isDir.boolValue
            else {
                continue
            }
            let hasConfigJson = fileManager.fileExists(
                atPath: entry.appendingPathComponent("config.json").path)
            let hasSafetensors =
                (try? fileManager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil))?
                .contains { $0.pathExtension == "safetensors" } ?? false
            if !hasConfigJson || !hasSafetensors {
                try? fileManager.removeItem(at: entry)
            }
        }
    }

    private nonisolated static func cleanupStagingDirectory(
        fileManager: FileManager, stagingDirectoryURL: URL
    ) {
        let entries =
            (try? fileManager.contentsOfDirectory(
                at: stagingDirectoryURL, includingPropertiesForKeys: nil)) ?? []
        for entry in entries {
            try? fileManager.removeItem(at: entry)
        }
    }

    private nonisolated static func loadPersistedJobs(from jobsFileURL: URL) -> [String:
        ModelDownloadJob]
    {
        guard let data = try? Data(contentsOf: jobsFileURL),
            let manifest = try? JSONDecoder().decode(ModelDownloadJobsManifest.self, from: data)
        else {
            return [:]
        }

        return Dictionary(uniqueKeysWithValues: manifest.jobs.map { ($0.id, $0) })
    }
}

private nonisolated struct TaskDescriptor: Codable, Sendable {
    let modelId: String
    let relativePath: String
}

private nonisolated struct HuggingFaceRepositoryResponse: Decodable, Sendable {
    let siblings: [Sibling]

    struct Sibling: Decodable, Sendable {
        let rfilename: String
    }
}

private final class BackgroundDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate,
    URLSessionTaskDelegate, URLSessionDelegate, @unchecked Sendable
{
    weak var service: ModelDownloadService?

    private let fileManager = FileManager.default
    private let stagingDirectoryURL: URL

    init(stagingDirectoryURL: URL) {
        self.stagingDirectoryURL = stagingDirectoryURL
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let taskDescription = downloadTask.taskDescription,
            let service
        else { return }

        Task {
            await service.handleTaskProgress(
                taskDescription: taskDescription,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let taskDescription = downloadTask.taskDescription,
            let service
        else { return }

        do {
            try fileManager.createDirectory(
                at: stagingDirectoryURL, withIntermediateDirectories: true)
            let stagedFileURL = stagingDirectoryURL.appendingPathComponent(UUID().uuidString)
            if fileManager.fileExists(atPath: stagedFileURL.path) {
                try fileManager.removeItem(at: stagedFileURL)
            }
            try fileManager.moveItem(at: location, to: stagedFileURL)

            Task {
                await service.handleDownloadedFile(
                    taskDescription: taskDescription, stagedFileURL: stagedFileURL)
            }
        } catch {
            Task {
                await service.handleTaskFailure(
                    taskDescription: taskDescription,
                    message: error.localizedDescription,
                    isCancellation: false
                )
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?)
    {
        guard let error,
            let taskDescription = task.taskDescription,
            let service
        else { return }

        let nsError = error as NSError
        let isCancellation =
            nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled

        Task {
            await service.handleTaskFailure(
                taskDescription: taskDescription,
                message: error.localizedDescription,
                isCancellation: isCancellation
            )
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        guard let service else { return }
        Task {
            await service.handleBackgroundEventsFinished()
        }
    }
}

private enum DownloadError: Error, LocalizedError {
    case anotherDownloadInProgress(String)
    case insufficientStorage(required: Double, available: Double)
    case unableToCheckStorage
    case unableToListRepository(String)
    case corruptedDownload(String)

    var errorDescription: String? {
        switch self {
        case .anotherDownloadInProgress(let modelName):
            "Another model download is already in progress (\(modelName))."
        case .insufficientStorage(let required, let available):
            "Insufficient storage. Required: \(String(format: "%.1f", required))GB, Available: \(String(format: "%.1f", available))GB"
        case .unableToCheckStorage:
            "Unable to check available storage space"
        case .unableToListRepository(let modelName):
            "Couldn't read the Hugging Face file list for \(modelName). Try again."
        case .corruptedDownload(let modelName):
            "Downloaded files for \(modelName) look incomplete. Delete the model and download it again."
        }
    }
}
