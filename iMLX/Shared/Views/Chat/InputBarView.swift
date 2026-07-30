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
        HStack(alignment: .bottom, spacing: 8) {
            TextField(String.appLocalized("chat.message_placeholder"), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.vertical, 11)
                .frame(minHeight: 44)
                .focused(isFocused)
                .onSubmit {
                    onSend()
                }

            if isGenerating {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.red, in: Circle())
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Stop generating")
            } else {
                Button(action: primaryAction) {
                    Image(systemName: primarySymbolName)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(primaryActionEnabled ? Color.white : Color.secondary)
                        .frame(width: 30, height: 30)
                        .background(primaryActionFill, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!primaryActionEnabled)
                .modifier(SendKeyboardShortcut(isEnabled: !isTextEmpty))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
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

    private var primaryActionFill: Color {
        primaryActionEnabled
            ? BrandPalette.accent
            : Color.secondary.opacity(ChatMetrics.inlineFillOpacity)
    }

    private func primaryAction() {
        if isTextEmpty {
            onVoiceTap()
        } else {
            onSend()
        }
    }
}
