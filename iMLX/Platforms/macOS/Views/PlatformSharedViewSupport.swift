import SwiftUI

enum PlatformChatLayout {
    static let accessoryBottomPadding: CGFloat = 14
}

enum PlatformChatCapabilities {
    static let supportsCameraCapture = false
}

struct PlatformConversationMenuItem: View {
    let action: () -> Void

    var body: some View {
        EmptyView()
    }
}

struct PlatformSettingsMenuItem: View {
    let action: () -> Void

    var body: some View {
        SettingsLink {
            Label(String.appLocalized("tab.settings"), systemImage: "gearshape")
        }
    }
}

struct SendKeyboardShortcut: ViewModifier {
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.keyboardShortcut(.return, modifiers: .command)
        } else {
            content
        }
    }
}

struct OnboardingTabViewStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.tabViewStyle(.automatic)
    }
}

struct ModelBrowserCloseToolbarModifier: ViewModifier {
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content
    }
}
