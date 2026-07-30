import Foundation
import MLX
import MLXLMCommon

nonisolated enum InferenceWiredMemory {
    private static let tensorFileExtensions: Set<String> = ["safetensors", "bin", "gguf"]
    static let isSupported = true

    static func estimatedModelWeightBytes(in directory: URL) -> Int? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let total = entries.reduce(into: 0) { runningTotal, entry in
            guard tensorFileExtensions.contains(entry.pathExtension.lowercased()) else { return }
            runningTotal += (try? entry.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total > 0 ? total : nil
    }

    static func budgetBytes(weightBytes: Int?) -> Int? {
        guard let weightBytes, weightBytes > 0 else { return nil }
        let margin = max(512 * Int(HostMemoryProfile.megabyte), weightBytes / 4)
        return weightBytes + margin
    }

    static func withBudget<R>(bytes: Int?, _ body: () async throws -> R) async rethrows -> R {
        guard let bytes, bytes > 0 else {
            return try await body()
        }
        let ticket = WiredMemoryTicket(
            size: bytes,
            policy: MLXLMCommon.WiredSumPolicy(),
            kind: .active
        )
        return try await ticket.withWiredLimit(body)
    }
}
