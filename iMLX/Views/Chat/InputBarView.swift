import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isGenerating: Bool
    let isSendEnabled: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(String.appLocalized("chat.message_placeholder"), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous),
                    fallback: AnyShapeStyle(.ultraThinMaterial),
                    interactive: true
                )
                .focused(isFocused)
                .onSubmit {
                    onSend()
                }

            if isGenerating {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.white)
                        .liquidGlassSurface(
                            tint: .red.opacity(0.24),
                            in: Circle(),
                            fallback: AnyShapeStyle(Color.red),
                            interactive: true
                        )
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Stop generating")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(isSendEnabled ? Color.white : Color.secondary)
                        .liquidGlassSurface(
                            tint: isSendEnabled ? BrandPalette.accent.opacity(0.3) : nil,
                            in: Circle(),
                            fallback: isSendEnabled
                                ? AnyShapeStyle(BrandPalette.primaryGradient)
                                : AnyShapeStyle(Color.secondary.opacity(0.12)),
                            interactive: true
                        )
                }
                .disabled(!isSendEnabled)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Send message")
            }
        }
    }
}
