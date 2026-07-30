import Foundation

nonisolated struct GenerationStats: Codable, Hashable {
    let tokensPerSecond: Double
    let totalTokens: Int
    let promptTokens: Int
    let generationTime: TimeInterval
    let peakMemoryMB: UInt64

    var formattedTokensPerSecond: String {
        String(format: String.appLocalized("stats.tok_per_s"), tokensPerSecond)
    }

    var formattedMemory: String {
        String(format: String.appLocalized("stats.mb"), peakMemoryMB)
    }

    var formattedTime: String {
        String(format: String.appLocalized("stats.seconds"), generationTime)
    }

    var formattedTokenCount: String {
        String(format: String.appLocalized("stats.tok_count"), Int64(totalTokens))
    }
}
