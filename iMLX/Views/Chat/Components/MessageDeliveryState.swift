import Foundation

/// View-level delivery status of a user message, derived purely from `ChatViewModel` state.
///
/// `sending` is shown while the latest user message is awaiting an assistant reply
/// (`isGenerating == true` and `currentResponse` empty / `messages` last role is `.user`).
/// `failed` is shown when `lastFailedUserMessageId` matches.
enum MessageDeliveryState: Equatable {
    case sent
    case sending
    case failed
}

struct MessageDeliveryContext: Equatable {
    let isGenerating: Bool
    let hasStartedStreaming: Bool
    let lastFailedUserMessageId: UUID?
    let lastUserMessageId: UUID?

    func state(for messageId: UUID) -> MessageDeliveryState {
        if lastFailedUserMessageId == messageId {
            return .failed
        }
        if isGenerating, !hasStartedStreaming, lastUserMessageId == messageId {
            return .sending
        }
        return .sent
    }
}
