import SwiftUI

struct WebSearchPrivacyConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onEnable: () -> Void
    let onKeepLocal: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "globe.badge.chevron.backward")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(BrandPalette.cyan)
                            .frame(width: 44, height: 44)
                            .liquidGlassSurface(
                                tint: BrandPalette.cyan.opacity(0.18),
                                in: Circle(),
                                fallback: AnyShapeStyle(BrandPalette.cyan.opacity(0.10))
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(String.appLocalized("web_search.privacy.title"))
                                .font(.title3.weight(.semibold))
                            Text(String.appLocalized("web_search.privacy.subtitle"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        privacyPoint("network", String.appLocalized("web_search.privacy.point_message"))
                        privacyPoint("safari", String.appLocalized("web_search.privacy.point_pages"))
                        privacyPoint("lock.slash", String.appLocalized("web_search.privacy.point_boundary"))
                        privacyPoint("checkmark.shield", String.appLocalized("web_search.privacy.point_local"))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 18)
            }

            VStack(spacing: 10) {
                Button {
                    onEnable()
                    dismiss()
                } label: {
                    Text(String.appLocalized("web_search.privacy.enable"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .liquidGlassButtonStyle(prominent: true, tint: BrandPalette.accent)

                Button {
                    onKeepLocal()
                    dismiss()
                } label: {
                    Text(String.appLocalized("web_search.privacy.keep_local"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .liquidGlassButtonStyle(tint: BrandPalette.cyan)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
    }

    private func privacyPoint(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandPalette.accent)
                .frame(width: 24, height: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
