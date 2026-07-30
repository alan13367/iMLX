import AppIntents

struct OpenLiveVoiceIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Open Live Voice"
    nonisolated static let description = IntentDescription("Open iMLX directly in a live voice conversation.")
    nonisolated static let isDiscoverable = true

    @available(iOS 26.0, macOS 26.0, *)
    nonisolated static var supportedModes: IntentModes {
        .foreground(.immediate)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppShortcutRouteStore.savePendingRoute(.openLiveVoice)
        return .result()
    }
}

@available(*, deprecated)
extension OpenLiveVoiceIntent {
    static var openAppWhenRun: Bool { true }
}

struct iMLXAppShortcuts: AppShortcutsProvider {
    nonisolated static var shortcutTileColor: ShortcutTileColor {
        .blue
    }

    nonisolated static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenLiveVoiceIntent(),
            phrases: [
                "Open live voice in \(.applicationName)",
                "Start live voice with \(.applicationName)",
                "Talk with \(.applicationName)"
            ],
            shortTitle: "Live Voice",
            systemImageName: "waveform.badge.mic"
        )
    }
}
