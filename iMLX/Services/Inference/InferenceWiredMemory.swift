import Foundation
import MLX
import MLXLMCommon

/// Wired memory coordination for the loaded model.
///
/// Without a wired budget the Metal driver is free to page model weights out while the app is
/// idle, which shows up as a slow first token after a pause and as stutter mid-generation. A
/// ticket keeps the working set resident for the duration of the work and releases it afterwards.
///
/// This is macOS-only on purpose: wiring memory on iOS competes with jetsam rather than with the
/// pager, so the mobile path keeps relying on the buffer cache and memory limits instead.
nonisolated enum InferenceWiredMemory {
    private static let tensorFileExtensions: Set<String> = ["safetensors", "bin", "gguf"]

    static var isSupported: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Estimates resident weight bytes from the tensor files on disk.
    ///
    /// File totals include container metadata and therefore run slightly above the in-memory
    /// `nbytes` sum, which is the safe direction for a budget.
    static func estimatedModelWeightBytes(in directory: URL) -> Int? {
        guard isSupported else { return nil }
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

    /// Weights plus a margin for the KV cache and transient prefill workspace.
    static func budgetBytes(weightBytes: Int?) -> Int? {
        guard isSupported, let weightBytes, weightBytes > 0 else { return nil }
        let margin = max(512 * Int(HostMemoryProfile.megabyte), weightBytes / 4)
        return weightBytes + margin
    }

    /// Runs `body` while holding a wired memory ticket for `bytes`.
    ///
    /// The policy clamps the requested limit to Metal's recommended working set, so an
    /// over-estimated budget degrades to the largest limit the device will honor.
    static func withBudget<R>(bytes: Int?, _ body: () async throws -> R) async rethrows -> R {
        #if os(macOS)
        guard let bytes, bytes > 0 else {
            return try await body()
        }
        let ticket = WiredMemoryTicket(
            size: bytes,
            policy: MLXLMCommon.WiredSumPolicy(),
            kind: .active
        )
        return try await ticket.withWiredLimit(body)
        #else
        return try await body()
        #endif
    }
}
