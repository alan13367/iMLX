import Foundation

struct GenerationStats: Codable, Hashable {
    let tokensPerSecond: Double
    let totalTokens: Int
    let promptTokens: Int
    let generationTime: TimeInterval
    let peakMemoryMB: UInt64

    var formattedTokensPerSecond: String {
        String(format: "%.1f tok/s", tokensPerSecond)
    }

    var formattedMemory: String {
        "\(peakMemoryMB) MB"
    }

    var formattedTime: String {
        String(format: "%.1fs", generationTime)
    }
}
