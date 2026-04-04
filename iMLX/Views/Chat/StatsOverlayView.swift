import SwiftUI

struct StatsOverlayView: View {
    let stats: GenerationStats
    let isLive: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                StatItem(icon: "gauge.with.dots.needle.33percent", value: stats.formattedTokensPerSecond, isLive: isLive)
                StatItem(icon: "text.word.spacing", value: stats.formattedTokenCount, isLive: isLive)
                StatItem(icon: "clock", value: stats.formattedTime, isLive: isLive)
                StatItem(icon: "memorychip", value: stats.formattedMemory, isLive: isLive)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let isLive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(isLive ? .blue : .secondary)
            Text(value)
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isLive ? Color.blue.opacity(0.10) : Color.secondary.opacity(0.12))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: true)
    }
}
