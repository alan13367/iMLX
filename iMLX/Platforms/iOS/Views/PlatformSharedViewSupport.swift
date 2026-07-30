import SwiftUI

enum PlatformChatLayout {
    static let accessoryBottomPadding: CGFloat = 0
}

enum PlatformChatCapabilities {
    static let supportsCameraCapture = true
}

struct PlatformConversationMenuItem: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String.appLocalized("conversation.title.chats"), systemImage: "bubble.left.and.bubble.right")
        }
    }
}

struct PlatformSettingsMenuItem: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String.appLocalized("tab.settings"), systemImage: "gearshape")
        }
    }
}

struct SendKeyboardShortcut: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        content
    }
}

struct OnboardingTabViewStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.tabViewStyle(.page(indexDisplayMode: .never))
    }
}

struct ModelBrowserCloseToolbarModifier: ViewModifier {
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .imlxTrailing) {
                Button(action: dismiss) {
                    CloseButtonLabel()
                }
                .accessibilityLabel(String.appLocalized("common.close"))
            }
        }
    }
}
