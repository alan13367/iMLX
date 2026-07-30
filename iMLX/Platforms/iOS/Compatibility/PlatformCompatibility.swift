import SwiftUI
import UIKit

typealias PlatformImage = UIImage

extension Image {
    init(platformImage: PlatformImage) {
        self.init(uiImage: platformImage)
    }
}

nonisolated enum PlatformImageFactory {
    static func image(data: Data) -> PlatformImage? {
        PlatformImage(data: data)
    }

    static func image(cgImage: CGImage) -> PlatformImage {
        PlatformImage(cgImage: cgImage)
    }
}

enum PlatformClipboard {
    @MainActor
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}

enum PlatformApplication {
    @MainActor
    static func openLanguageSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

extension ToolbarItemPlacement {
    static var imlxLeading: ToolbarItemPlacement { .topBarLeading }
    static var imlxTrailing: ToolbarItemPlacement { .topBarTrailing }
    static var imlxPrincipal: ToolbarItemPlacement { .principal }
}

extension View {
    func imlxInlineNavigationTitle() -> some View {
        navigationBarTitleDisplayMode(.inline)
    }
}

enum PlatformColors {
    static var groupedBackground: Color { Color(uiColor: .systemGroupedBackground) }
    static var chatBackground: Color { Color(uiColor: .systemBackground) }
    static var separator: Color { Color(uiColor: .separator) }
}
