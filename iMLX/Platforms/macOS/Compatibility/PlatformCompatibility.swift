import AppKit
import SwiftUI

typealias PlatformImage = NSImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(nsImage: platformImage)
    }
}

nonisolated enum PlatformImageFactory {
    static func image(data: Data) -> PlatformImage? {
        PlatformImage(data: data)
    }

    static func image(cgImage: CGImage) -> PlatformImage {
        PlatformImage(cgImage: cgImage, size: .zero)
    }
}

enum PlatformClipboard {
    @MainActor
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum PlatformApplication {
    @MainActor
    static func openLanguageSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Localization-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.language"
        ]
        guard let url = candidates.compactMap(URL.init(string:)).first else { return }
        NSWorkspace.shared.open(url)
    }
}

extension ToolbarItemPlacement {
    static var imlxLeading: ToolbarItemPlacement { .navigation }
    static var imlxTrailing: ToolbarItemPlacement { .primaryAction }
    static var imlxPrincipal: ToolbarItemPlacement { .automatic }
}

extension View {
    func imlxInlineNavigationTitle() -> some View { self }
}

enum PlatformColors {
    static var groupedBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var chatBackground: Color { Color(nsColor: .textBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }
}
