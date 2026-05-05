import SwiftUI

@main
struct iMLXApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            AppRootView(appState: appState)
                .environment(\.locale, appState.effectiveLocale)
                .tint(BrandPalette.accent)
        }
        .backgroundTask(.urlSession(ModelDownloadService.backgroundSessionIdentifier)) {
            await appState.handleBackgroundDownloadEvents()
        }
    }
}

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var appState: AppState

    var body: some View {
        ChatRootView(appState: appState)
            .fullScreenCover(isPresented: $appState.showsOnboarding) {
                OnboardingFlowView(appState: appState)
                    .interactiveDismissDisabled()
            }
            .onAppear {
                appState.refreshPendingShortcutRoute()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                appState.refreshPendingShortcutRoute()
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                appState.refreshPendingShortcutRoute()
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
