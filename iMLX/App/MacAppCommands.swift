#if os(macOS)
import AppKit
import SwiftUI

extension Notification.Name {
    static let imlxOpenModelBrowser = Notification.Name("iMLX.openModelBrowser")
    static let imlxFocusComposer = Notification.Name("iMLX.focusComposer")
}

enum IMLXWindowID {
    static let main = "main"
}

struct IMLXCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Conversation") {
                _ = appState.createNewConversation()
                appState.requestComposerFocus()
                presentMainWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Window") {
                openWindow(id: IMLXWindowID.main)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandMenu("Model") {
            Button("Choose Model…") {
                NotificationCenter.default.post(name: .imlxOpenModelBrowser, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
        }

        CommandMenu("Conversation") {
            Button("Focus Message Composer") {
                NotificationCenter.default.post(name: .imlxFocusComposer, object: nil)
            }
            .keyboardShortcut("l", modifiers: .command)
        }
    }

    private func presentMainWindow() {
        if let existing = NSApp.windows.first(where: Self.isMainChatWindow) {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }
        openWindow(id: IMLXWindowID.main)
    }

    private static func isMainChatWindow(_ window: NSWindow) -> Bool {
        guard window.isVisible, window.canBecomeMain, window.styleMask.contains(.titled) else {
            return false
        }
        // Chat WindowGroup uses a wider shell than the Settings scene.
        return window.frame.width >= 900
    }
}
#endif
