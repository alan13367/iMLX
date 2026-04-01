import SwiftUI

struct StatsOverlayView: View {
    let stats: GenerationStats
    let isLive: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                StatItem(
                    icon: "gauge.with.dots.needle.33percent",
                    label: "Speed",
                    value: stats.formattedTokensPerSecond,
                    isLive: isLive
                )
                StatItem(
                    icon: "text.word.spacing",
                    label: "Tokens",
                    value: "\(stats.totalTokens)",
                    isLive: isLive
                )
                StatItem(
                    icon: "clock",
                    label: "Time",
                    value: stats.formattedTime,
                    isLive: isLive
                )
                StatItem(
                    icon: "memorychip",
                    label: "RAM",
                    value: stats.formattedMemory,
                    isLive: isLive
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct StatItem: View {
    let icon: String
    let label: String
    let value: String
    let isLive: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(isLive ? .blue : .secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
