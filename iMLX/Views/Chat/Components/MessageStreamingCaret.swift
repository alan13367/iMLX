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

#Preview("Streaming caret") {
    MessageStreamingCaret()
        .padding()
}
