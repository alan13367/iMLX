import SwiftUI
import MLX

@main
struct iMLXApp: App {
    @State private var appState = AppState()
    @State private var isShowingLaunchScreen = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                MainTabView(appState: appState)
                    .opacity(isShowingLaunchScreen ? 0 : 1)

                if isShowingLaunchScreen {
                    BrandLoadingView(
                        title: "iMLX",
                        subtitle: "Local AI Models"
                    )
                    .transition(.opacity)
                }
            }
            .task {
                appState.loadConversations()

                try? await Task.sleep(for: .seconds(1.2))

                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.35)) {
                        isShowingLaunchScreen = false
                    }
                }
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

    var body: some View {
        NavigationStack {
            Group {
                if let conversationId = appState.activeConversationId {
                    ChatView(appState: appState, conversationId: conversationId)
                        .id(conversationId)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
