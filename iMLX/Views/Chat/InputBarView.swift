import SwiftUI

struct InputBarView: View {
    @Binding var text: String
    let isGenerating: Bool
    let isSendEnabled: Bool
    var isFocused: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(String.appLocalized("chat.message_placeholder"), text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.fill.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused(isFocused)
                .onSubmit {
                    onSend()
                }

            if isGenerating {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.title2.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Stop generating")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.title2.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(isSendEnabled ? Color.blue : Color.secondary.opacity(0.12))
                        .foregroundStyle(isSendEnabled ? Color.white : Color.secondary)
                        .clipShape(Circle())
                }
                .disabled(!isSendEnabled)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Send message")
            }
        }
    }
}
