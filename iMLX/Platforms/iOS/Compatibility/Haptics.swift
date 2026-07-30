import UIKit

enum Haptics {
    @MainActor
    static func impactLight() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @MainActor
    static func impactMedium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    @MainActor
    static func notificationSuccess() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor
    static func notificationError() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    @MainActor
    static func notificationWarning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    @MainActor
    static func selectionChanged() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
