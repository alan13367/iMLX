import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit

typealias PlatformImage = UIImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}
#elseif canImport(AppKit)
import AppKit

typealias PlatformImage = NSImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}
#endif

enum PlatformClipboard {
    @MainActor
    static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

enum PlatformApplication {
    @MainActor
    static func openLanguageSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        let candidates = [
            "x-apple.systempreferences:com.apple.Localization-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.language"
        ]
        guard let url = candidates.compactMap(URL.init(string:)).first else { return }
        NSWorkspace.shared.open(url)
        #endif
    }
}

extension ToolbarItemPlacement {
    static var imlxLeading: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .topBarLeading
        #endif
    }

    static var imlxTrailing: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarTrailing
        #endif
    }

    static var imlxPrincipal: ToolbarItemPlacement {
        #if os(macOS)
        .automatic
        #else
        .principal
        #endif
    }
}

extension View {
    @ViewBuilder
    func imlxInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

enum PlatformColors {
    static var groupedBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.clear
        #endif
    }
}
