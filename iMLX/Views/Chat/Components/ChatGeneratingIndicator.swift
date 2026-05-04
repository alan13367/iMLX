import SwiftUI

struct ChatGeneratingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(BrandPalette.cyan)
            Text(String.appLocalized("chat.generating"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}
