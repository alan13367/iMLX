import Foundation
import SwiftUI

enum ChatUtilitySheet: String, Identifiable {
    case conversations
    case models
    case memoryLibrary
    case settings

    var id: String { rawValue }
}

struct ChatScrollState: Equatable {
    let canScrollToBottom: Bool
    let isPinnedToBottom: Bool
}

enum ConversationHistorySwipe {
    static let edgeActivationWidth: CGFloat = 24
    static let minimumDistance: CGFloat = 32
    static let primeHorizontalDistance: CGFloat = 90
    static let primePredictedDistance: CGFloat = 150
    static let commitHorizontalDistance: CGFloat = 140
    static let commitPredictedDistance: CGFloat = 190
    static let horizontalDominance: CGFloat = 2.2
}
