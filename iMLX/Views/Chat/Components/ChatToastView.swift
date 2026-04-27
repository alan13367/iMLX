import SwiftUI

/// Lightweight chat-level toast presenter. The toast is owned by the chat
/// surface (not by individual message bubbles) so it never gets clipped by
/// the message list and can be triggered from anywhere via a single trigger
/// counter.
struct ChatToastModel: Equatable {
    let id: UUID
    let message: String
    let symbol: String?

    init(message: String, symbol: String? = nil) {
        self.id = UUID()
        self.message = message
        self.symbol = symbol
    }
}

struct ChatToastView: View {
    let toast: ChatToastModel?

    var body: some View {
        Group {
            if let toast {
                HStack(spacing: 8) {
                    if let symbol = toast.symbol {
                        Image(systemName: symbol)
                            .font(.caption.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.green)
                    }
                    Text(toast.message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 4)
                .id(toast.id)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeOut(duration: 0.22), value: toast?.id)
    }
}
