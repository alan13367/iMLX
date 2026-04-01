import SwiftUI

@main
struct MLX_AIApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainTabView(appState: appState)
                .task {
                    appState.loadConversations()
                }
        }
    }
}

struct MainTabView: View {
    let appState: AppState

    var body: some View {
        TabView {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right") {
                ChatRootView(appState: appState)
            }
            Tab("Models", systemImage: "arrow.down.circle") {
                NavigationStack {
                    ModelBrowserView(appState: appState)
                }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView(appState: appState)
                }
            }
        }
    }
}

struct ChatRootView: View {
    let appState: AppState
    @State private var navigationPath = NavigationPath()

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            ipadLayout
        } else {
            iphoneLayout
        }
    }

    private var iphoneLayout: some View {
        NavigationStack(path: $navigationPath) {
            ConversationListView(appState: appState) { conversationId in
                navigationPath.append(conversationId)
            }
            .navigationDestination(for: UUID.self) { conversationId in
                ChatView(appState: appState, conversationId: conversationId)
            }
        }
    }

    private var ipadLayout: some View {
        NavigationSplitView {
            ConversationSidebarView(appState: appState) { _ in }
        } detail: {
            if let conversationId = appState.activeConversationId {
                ChatView(appState: appState, conversationId: conversationId)
                    .id(conversationId)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text("Select or create a conversation")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
