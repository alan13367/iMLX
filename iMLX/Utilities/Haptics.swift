import UIKit

/// UIKit haptics utility for non-View contexts (ViewModels, AppState, etc.).
/// SwiftUI views should prefer `.sensoryFeedback()` directly.
enum Haptics {
    static func impactLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func impactMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func notificationSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func notificationError() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func notificationWarning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selectionChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
