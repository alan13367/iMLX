import Foundation

nonisolated enum InferenceWiredMemory {
    static let isSupported = false

    static func estimatedModelWeightBytes(in directory: URL) -> Int? {
        nil
    }

    static func budgetBytes(weightBytes: Int?) -> Int? {
        nil
    }

    static func withBudget<R>(bytes: Int?, _ body: () async throws -> R) async rethrows -> R {
        try await body()
    }
}
