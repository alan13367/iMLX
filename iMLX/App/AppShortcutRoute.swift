import Foundation

nonisolated enum AppShortcutRoute: String {
    case openLiveVoice
}

nonisolated enum AppShortcutRouteStore {
    private static let pendingRouteKey = "pendingAppShortcutRoute"

    static func loadPendingRoute(userDefaults: UserDefaults = .standard) -> AppShortcutRoute? {
        guard let rawValue = userDefaults.string(forKey: pendingRouteKey) else {
            return nil
        }
        return AppShortcutRoute(rawValue: rawValue)
    }

    static func savePendingRoute(_ route: AppShortcutRoute, userDefaults: UserDefaults = .standard) {
        userDefaults.set(route.rawValue, forKey: pendingRouteKey)
    }

    static func clearPendingRoute(userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: pendingRouteKey)
    }
}
