import SwiftUI

struct ChatToolbarMenu: View {
    let onOpenConversations: () -> Void
    let onOpenModels: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Menu {
            #if !os(macOS)
            Button(action: onOpenConversations) {
                Label(String.appLocalized("conversation.title.chats"), systemImage: "bubble.left.and.bubble.right")
            }
            #endif

            Button(action: onOpenModels) {
                Label(String.appLocalized("tab.models"), systemImage: "arrow.down.circle")
            }

            #if os(macOS)
            SettingsLink {
                Label(String.appLocalized("tab.settings"), systemImage: "gearshape")
            }
            #else
            Button(action: onOpenSettings) {
                Label(String.appLocalized("tab.settings"), systemImage: "gearshape")
            }
            #endif
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .tint(.primary)
        .accessibilityLabel("Open app menu")
    }
}
