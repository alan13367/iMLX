import SwiftUI

@main
struct iMLXApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        #if os(macOS)
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
        #else
        WindowGroup {
            AppRootView(appState: appState)
                .environment(\.locale, appState.effectiveLocale)
                .tint(BrandPalette.accent)
        }
        .backgroundTask(.urlSession(ModelDownloadService.backgroundSessionIdentifier)) {
            await appState.handleBackgroundDownloadEvents()
        }
        #endif
    }
}

struct AppRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var appState: AppState

    var body: some View {
        onboardingContent
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

    @ViewBuilder
    private var onboardingContent: some View {
        #if os(macOS)
        ChatRootView(appState: appState)
            .sheet(isPresented: $appState.showsOnboarding) {
                OnboardingFlowView(appState: appState)
                    .interactiveDismissDisabled()
                    .frame(minWidth: 720, minHeight: 600)
            }
        #else
        ChatRootView(appState: appState)
            .fullScreenCover(isPresented: $appState.showsOnboarding) {
                OnboardingFlowView(appState: appState)
                    .interactiveDismissDisabled()
            }
        #endif
    }
}

struct ChatRootView: View {
    let appState: AppState

    #if os(macOS)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #endif

    var body: some View {
        #if os(macOS)
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
            chatDetail
        }
        #else
        NavigationStack {
            chatDetail
        }
        #endif
    }

    @ViewBuilder
    private var chatDetail: some View {
        if let conversationId = appState.activeConversationId {
            ChatView(appState: appState, conversationId: conversationId)
                .id(conversationId)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
