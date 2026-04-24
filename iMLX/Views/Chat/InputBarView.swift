import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isGenerating: Bool
    let isSendEnabled: Bool
    let isVoiceEnabled: Bool
    var isFocused: FocusState<Bool>.Binding
    let onVoiceTap: () -> Void
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
                Button(action: primaryAction) {
                    Image(systemName: primarySymbolName)
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(primaryActionEnabled ? Color.white : Color.secondary)
                        .liquidGlassSurface(
                            tint: primaryActionTint,
                            in: Circle(),
                            fallback: primaryActionFallback,
                            interactive: true
                        )
                }
                .disabled(!primaryActionEnabled)
                .frame(width: 44, height: 44)
                .accessibilityLabel(primaryAccessibilityLabel)
            }
        }
    }

    private var isTextEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var primaryActionEnabled: Bool {
        isTextEmpty ? isVoiceEnabled : isSendEnabled
    }

    private var primarySymbolName: String {
        isTextEmpty ? "waveform" : "arrow.up"
    }

    private var primaryAccessibilityLabel: String {
        isTextEmpty ? "Open live voice" : "Send message"
    }

    private var primaryActionTint: Color? {
        guard primaryActionEnabled else { return nil }
        return isTextEmpty ? BrandPalette.cyan.opacity(0.22) : BrandPalette.accent.opacity(0.3)
    }

    private var primaryActionFallback: AnyShapeStyle {
        if !primaryActionEnabled {
            return AnyShapeStyle(Color.secondary.opacity(0.12))
        }
        if isTextEmpty {
            return AnyShapeStyle(BrandPalette.cyan.opacity(0.9))
        }
        return AnyShapeStyle(BrandPalette.primaryGradient)
    }

    private func primaryAction() {
        if isTextEmpty {
            onVoiceTap()
        } else {
            onSend()
        }
    }
}
