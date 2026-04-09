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
    let appState: AppState

    var body: some View {
        let _ = appState.preferredAppLanguageCode
        ChatRootView(appState: appState)
            .fullScreenCover(isPresented: Binding(
                get: { !appState.hasCompletedOnboarding },
                set: { _ in }
            )) {
                OnboardingFlowView(appState: appState)
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
