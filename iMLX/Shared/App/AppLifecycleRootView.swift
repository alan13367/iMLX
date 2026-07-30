import SwiftUI

struct AppLifecycleRootView<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var appState: AppState
    let content: Content

    init(appState: AppState, @ViewBuilder content: () -> Content) {
        self.appState = appState
        self.content = content()
    }

    var body: some View {
        content
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
