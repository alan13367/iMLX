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
    @Bindable var appState: AppState

    var body: some View {
        AppLifecycleRootView(appState: appState) {
            ChatRootView(appState: appState)
                .fullScreenCover(isPresented: $appState.showsOnboarding) {
                    OnboardingFlowView(appState: appState)
                        .interactiveDismissDisabled()
                }
        }
    }
}

struct ChatRootView: View {
    let appState: AppState

    var body: some View {
        NavigationStack {
            ActiveConversationDetailView(appState: appState)
        }
    }
}
