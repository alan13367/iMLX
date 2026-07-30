import Foundation

nonisolated struct ModelDownloadJobsManifest: Codable, Sendable {
    var jobs: [ModelDownloadJob]

    init(jobs: [ModelDownloadJob] = []) {
        self.jobs = jobs
    }
}

nonisolated struct ModelDownloadJob: Codable, Identifiable, Sendable {
    nonisolated enum Status: String, Codable, Sendable {
        case queued
        case downloading
        case failed
    }

    let id: String
    let displayName: String
    let huggingFaceId: String
    let revision: String
    var createdAt: Date
    var updatedAt: Date
    var status: Status
    var lastErrorMessage: String?
    var files: [ModelDownloadFileState]
}

nonisolated struct ModelDownloadFileState: Codable, Identifiable, Sendable {
    nonisolated enum Status: String, Codable, Sendable {
        case pending
        case queued
        case downloading
        case completed
        case failed
    }

    var id: String { relativePath }

    let relativePath: String
    let remoteURL: URL
    var expectedBytes: Int64?
    var writtenBytes: Int64
    var status: Status
    var lastErrorMessage: String?
}

nonisolated struct ModelDownloadSnapshot: Equatable, Sendable {
    nonisolated enum Status: String, Sendable {
        case queued
        case downloading
        case failed
    }

    let modelId: String
    let displayName: String
    let progress: Float
    let bytesWritten: Int64
    let totalBytesExpected: Int64?
    let status: Status
    let lastErrorMessage: String?

    var isActive: Bool {
        switch status {
        case .queued, .downloading:
            return true
        case .failed:
            return false
        }
    }

    var displayStatus: String {
        switch status {
        case .queued:
            return "Queued"
        case .downloading:
            return String(format: "Downloading %.0f%%", progress * 100)
        case .failed:
            return lastErrorMessage ?? "Download failed"
        }
    }
}
