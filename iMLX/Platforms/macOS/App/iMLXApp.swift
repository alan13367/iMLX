import SwiftUI

@main
struct iMLXApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup(id: IMLXWindowID.main) {
            AppRootView(appState: appState)
                .environment(\.locale, appState.effectiveLocale)
                .tint(BrandPalette.accent)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1_180, height: 780)
        .backgroundTask(.urlSession(ModelDownloadService.backgroundSessionIdentifier)) {
            await appState.handleBackgroundDownloadEvents()
        }
        .commands {
            IMLXCommands(appState: appState)
        }

        Settings {
            SettingsView(appState: appState, showsCloseButton: false)
                .environment(\.locale, appState.effectiveLocale)
                .tint(BrandPalette.accent)
        }
    }
}

struct AppRootView: View {
    @Bindable var appState: AppState

    var body: some View {
        AppLifecycleRootView(appState: appState) {
            ChatRootView(appState: appState)
                .sheet(isPresented: $appState.showsOnboarding) {
                    OnboardingFlowView(appState: appState)
                        .interactiveDismissDisabled()
                        .frame(minWidth: 720, minHeight: 600)
                }
        }
    }
}

struct ChatRootView: View {
    let appState: AppState
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ConversationListView(
                appState: appState,
                presentation: .rootNavigation,
                sidebarVisibility: $columnVisibility,
                onSelect: { _ in }
            )
            .navigationSplitViewColumnWidth(min: 230, ideal: 280, max: 360)
            // The generated toggle always sorts ahead of the sidebar's own items, so
            // ConversationListView supplies its own to control the ordering.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ActiveConversationDetailView(appState: appState)
        }
    }
}
