import SwiftUI

struct ChatComposerPersonaRow: View {
    let persona: Persona
    let onChangePersona: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: persona.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandPalette.primaryGradient)
                .frame(width: 30, height: 30)
                .liquidGlassSurface(
                    tint: BrandPalette.accent.opacity(0.14),
                    in: Circle(),
                    fallback: AnyShapeStyle(BrandPalette.accent.opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(persona.localizedName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !persona.localizedDisplaySummary.isEmpty {
                    Text(persona.localizedDisplaySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(String.appLocalized("common.change"), action: onChangePersona)
                .font(.caption.weight(.semibold))
                .liquidGlassButtonStyle(tint: BrandPalette.accent)
                .controlSize(.small)
                .frame(minHeight: 36)
        }
    }
}
