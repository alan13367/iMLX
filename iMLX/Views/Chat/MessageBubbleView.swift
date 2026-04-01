import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var showCopyFeedback = false

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                messageContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.role == .user
                            ? AnyShapeStyle(.blue)
                            : AnyShapeStyle(.fill.tertiary)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                if message.role == .assistant {
                    copyButton
                }
            }
            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .overlay(copyFeedback, alignment: .bottom)
    }

    @ViewBuilder
    private var messageContent: some View {
        if message.role == .assistant {
            if let attributed = try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attributed)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .tint(.blue)
            } else {
                Text(message.content)
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        } else {
            Text(message.content)
                .font(.body)
                .foregroundStyle(.white)
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.setValue(message.content, forPasteboardType: UTType.plainText.identifier)
            showCopyFeedback = true
            Haptics.impactLight()
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCopyFeedback = false
            }
        } label: {
            Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var copyFeedback: some View {
        Group {
            if showCopyFeedback {
                Text("Copied")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
    }
}
