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
                        subtitle: String.appLocalized("brand.subtitle")
                    )
                    .transition(.opacity)
                }
            }
            .environment(\.locale, appState.effectiveLocale)
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
        let _ = appState.preferredAppLanguageCode
        TabView {
            Tab(String.appLocalized("tab.chat"), systemImage: "bubble.left.and.bubble.right") {
                ChatRootView(appState: appState)
            }
            Tab(String.appLocalized("tab.models"), systemImage: "arrow.down.circle") {
                NavigationStack {
                    ModelBrowserView(appState: appState)
                }
            }
            Tab(String.appLocalized("tab.settings"), systemImage: "gearshape") {
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
