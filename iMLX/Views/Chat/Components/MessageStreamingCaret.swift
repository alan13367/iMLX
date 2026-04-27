import SwiftUI

/// Animated caret rendered at the trailing edge of streaming assistant text.
///
/// Falls back to a static dot when Reduce Motion is enabled.
struct MessageStreamingCaret: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible: Bool = true

    var body: some View {
        Capsule(style: .continuous)
            .fill(BrandPalette.accent)
            .frame(width: 2, height: 14)
            .opacity(reduceMotion ? 1 : (isVisible ? 1 : 0.15))
            .accessibilityHidden(true)
            .task(id: reduceMotion) {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    withAnimation(.easeInOut(duration: 0.55)) {
                        isVisible.toggle()
                    }
                    try? await Task.sleep(for: .milliseconds(550))
                }
            }
    }
}

/// Three-dot pulsing indicator used while the assistant is "thinking" but has not
/// produced any visible final answer yet.
struct ThinkingActivityIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(BrandPalette.cyan)
                    .frame(width: 5, height: 5)
                    .opacity(opacity(for: index))
                    .scaleEffect(scale(for: index))
            }
        }
        .accessibilityLabel(String.appLocalized("message.waiting_final"))
        .accessibilityAddTraits(.updatesFrequently)
        .task(id: reduceMotion) {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.42)) {
                    phase = (phase + 1) % 3
                }
                try? await Task.sleep(for: .milliseconds(420))
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        if reduceMotion { return 0.6 }
        return phase == index ? 1.0 : 0.35
    }

    private func scale(for index: Int) -> CGFloat {
        if reduceMotion { return 1.0 }
        return phase == index ? 1.15 : 0.9
    }
}

#Preview("Streaming caret + thinking dots") {
    VStack(spacing: 24) {
        MessageStreamingCaret()
        ThinkingActivityIndicator()
    }
    .padding()
}
