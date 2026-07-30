import SwiftUI

/// Single-line, monochrome stats bar shown below a finalized assistant
/// message. Replaces the previous capsule grid for finalized messages.
///
/// `28.3 tok/s · 481 tok · 17.0s · 1469 MB`
struct MessageStatsBar: View {
    let stats: GenerationStats

    var body: some View {
        let pieces: [String] = [
            stats.formattedTokensPerSecond,
            stats.formattedTokenCount,
            stats.formattedTime,
            stats.formattedMemory
        ]

        Text(pieces.joined(separator: "  ·  "))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.tail)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(stats.formattedTokensPerSecond), \(stats.formattedTokenCount), \(stats.formattedTime), \(stats.formattedMemory)")
    }
}

#Preview("Stats bar") {
    MessageStatsBar(
        stats: GenerationStats(
            tokensPerSecond: 28.3,
            totalTokens: 481,
            promptTokens: 12,
            generationTime: 17.0,
            peakMemoryMB: 1469
        )
    )
    .padding()
}
