import SwiftUI

extension View {
    @ViewBuilder
    func liquidGlassSurface<S: Shape>(
        tint: Color? = nil,
        in shape: S,
        fallback: AnyShapeStyle = AnyShapeStyle(.thinMaterial),
        fallbackStroke: Color = Color.secondary.opacity(0.14),
        interactive: Bool = false
    ) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(Self.liquidGlass(tint: tint, interactive: interactive), in: shape)
        } else {
            self
                .background(fallback, in: shape)
                .overlay {
                    shape.stroke(fallbackStroke, lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    func liquidGlassButtonStyle(
        prominent: Bool = false,
        tint: Color? = nil
    ) -> some View {
        if #available(iOS 26, *) {
            if prominent {
                self
                    .tint(tint)
                    .buttonStyle(.glassProminent)
            } else {
                self
                    .tint(tint)
                    .buttonStyle(.glass)
            }
        } else {
            if prominent {
                self
                    .tint(tint)
                    .buttonStyle(.borderedProminent)
            } else {
                self
                    .tint(tint)
                    .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    func liquidGlassContainer(spacing: CGFloat? = nil) -> some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
    }

    @available(iOS 26, *)
    private static func liquidGlass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}
