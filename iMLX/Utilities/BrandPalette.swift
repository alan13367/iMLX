import SwiftUI

enum BrandPalette {
    static let accent = Color(red: 0.08, green: 0.58, blue: 1.0)
    static let cyan = Color(red: 0.18, green: 0.86, blue: 1.0)
    static let magenta = Color(red: 0.86, green: 0.28, blue: 1.0)
    static let navy = Color(red: 0.06, green: 0.06, blue: 0.18)

    static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [magenta, accent, cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
