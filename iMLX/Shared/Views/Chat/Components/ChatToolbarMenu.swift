import SwiftUI

struct ChatToolbarMenu: View {
    let onOpenConversations: () -> Void
    let onOpenModels: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Menu {
            PlatformConversationMenuItem(action: onOpenConversations)

            Button(action: onOpenModels) {
                Label(String.appLocalized("tab.models"), systemImage: "arrow.down.circle")
            }

            PlatformSettingsMenuItem(action: onOpenSettings)
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .tint(.primary)
        .accessibilityLabel("Open app menu")
    }
}
