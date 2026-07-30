import Foundation

nonisolated struct TaskDescriptor: Codable, Sendable {
    let modelId: String
    let relativePath: String
}

nonisolated struct HuggingFaceRepositoryResponse: Decodable, Sendable {
    let siblings: [Sibling]

    struct Sibling: Decodable, Sendable {
        let rfilename: String
    }
}

final class BackgroundDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate,
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
              let service else {
            return
        }

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
              let service else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: stagingDirectoryURL,
                withIntermediateDirectories: true
            )
            let stagedFileURL = stagingDirectoryURL.appendingPathComponent(UUID().uuidString)
            if fileManager.fileExists(atPath: stagedFileURL.path) {
                try fileManager.removeItem(at: stagedFileURL)
            }
            try fileManager.moveItem(at: location, to: stagedFileURL)

            Task {
                await service.handleDownloadedFile(
                    taskDescription: taskDescription,
                    stagedFileURL: stagedFileURL
                )
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

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error,
              let taskDescription = task.taskDescription,
              let service else {
            return
        }

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

enum DownloadError: Error, LocalizedError {
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
