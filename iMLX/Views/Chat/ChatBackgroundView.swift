import SwiftUI

struct ChatBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let p1 = Float(time.truncatingRemainder(dividingBy: 24) / 24) * 2 * .pi
            let p2 = Float(time.truncatingRemainder(dividingBy: 32) / 32) * 2 * .pi
            let p3 = Float(time.truncatingRemainder(dividingBy: 40) / 40) * 2 * .pi
            
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(0.0, 0.0), .init(0.5, 0.0), .init(1.0, 0.0),
                    .init(0.0, 0.5), 
                    .init(0.5 + 0.1 * cos(p1), 0.5 + 0.1 * sin(p1)),
                    .init(1.0, 0.5),
                    .init(0.0, 1.0), .init(0.5, 1.0), .init(1.0, 1.0)
                ],
                colors: colorScheme == .dark ? darkColors(p2: p2, p3: p3) : lightColors(p2: p2, p3: p3)
            )
            .ignoresSafeArea()
        }
    }
    
    private func darkColors(p2: Float, p3: Float) -> [Color] {
        [
            Color.black, Color(white: 0.02), Color.black,
            Color.black, BrandPalette.navy, BrandPalette.magenta.opacity(0.15 + 0.05 * Double(sin(p2))),
            BrandPalette.cyan.opacity(0.12 + 0.04 * Double(cos(p3))), Color.black, Color.black
        ]
    }
    
    private func lightColors(p2: Float, p3: Float) -> [Color] {
        [
            Color.white, Color(white: 0.97), Color.white,
            Color(white: 0.98), BrandPalette.cyan.opacity(0.08 + 0.03 * Double(sin(p2))), Color.white,
            Color.white, BrandPalette.magenta.opacity(0.08 + 0.03 * Double(cos(p3))), Color(white: 0.98)
        ]
    }
}
