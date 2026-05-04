import SwiftUI

// MARK: - User bubble

/// Refined user message bubble. Uses `regularMaterial` with a brand-tinted
/// stroke and a subtle gradient lining instead of a full magenta→cyan fill —
/// puts the message *content* first and reserves the brand identity for the
/// app chrome.
struct UserMessageBubble: View {
    let text: String
    let deliveryState: MessageDeliveryState
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !text.isEmpty {
                UserMessageInlineMarkdownText(text: text, linkTint: BrandPalette.accent)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.regularMaterial)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        BrandPalette.magenta.opacity(0.40),
                                        BrandPalette.accent.opacity(0.32),
                                        BrandPalette.cyan.opacity(0.26)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }

            MessageDeliveryStatusView(state: deliveryState, onRetry: onRetry)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        switch deliveryState {
        case .sending:
            return Text("\(text). \(String.appLocalized("message.sending"))")
        case .failed:
            return Text("\(text). \(String.appLocalized("message.failed"))")
        case .sent:
            return Text(text)
        }
    }
}

/// Compact delivery status indicator displayed under the user bubble.
struct MessageDeliveryStatusView: View {
    let state: MessageDeliveryState
    let onRetry: (() -> Void)?
    @State private var hapticLightTrigger = 0

    var body: some View {
        Group {
            switch state {
            case .sent:
                EmptyView()
            case .sending:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.secondary)
                    Text(String.appLocalized("message.sending"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            case .failed:
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                            .symbolRenderingMode(.hierarchical)
                        Text(String.appLocalized("message.failed"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    if let onRetry {
                        Button {
                            hapticLightTrigger += 1
                            onRetry()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2.weight(.bold))
                                Text(String.appLocalized("message.retry"))
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(BrandPalette.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(BrandPalette.accent.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String.appLocalized("message.retry"))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticLightTrigger)
    }
}

// MARK: - Assistant text

/// Bubble-less assistant text. Renders flowing markdown text directly on the
/// chat background and appends an animated streaming caret while generating.
struct AssistantMessageText: View {
    let text: String
    let isStreaming: Bool
    var linkPhoneNumbers: Bool = false

    var body: some View {
        if isStreaming {
            // Streaming layout: render the text then an inline caret right
            // after the last glyph. Using a `Group` of `Text` doesn't allow
            // a custom caret view, so we use HStack with `lastTextBaseline`.
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                MessageStreamingCaret()
                    .alignmentGuide(.lastTextBaseline) { d in d[VerticalAlignment.center] + 6 }
            }
        } else {
            MessageMarkdownText(
                text: text,
                isStreaming: false,
                linkTint: BrandPalette.accent,
                linkPhoneNumbers: linkPhoneNumbers
            )
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct UserMessageInlineMarkdownText: View {
    let text: String
    let linkTint: Color

    var body: some View {
        let sanitized = MarkdownSanitizer.removingRemoteImages(from: text)
        if let attributed = try? AttributedString(
            markdown: sanitized,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .tint(linkTint)
        } else {
            Text(sanitized)
        }
    }
}

#Preview("User bubble — sent") {
    UserMessageBubble(text: "Summarize the document", deliveryState: .sent, onRetry: nil)
        .padding()
}

#Preview("User bubble — sending") {
    UserMessageBubble(text: "Summarize the document", deliveryState: .sending, onRetry: nil)
        .padding()
}

#Preview("User bubble — failed") {
    UserMessageBubble(text: "Summarize the document", deliveryState: .failed) {}
        .padding()
}

#Preview("Assistant markdown") {
    ScrollView {
        AssistantMessageText(
            text: """
            ## Study Plan

            - Review the parser
              - Confirm fallback behavior
              - Keep streaming cheap
            1. Build the app
            2. Run the tests

            > Sources can explain the answer without taking over the layout.

            ```swift
            struct Renderer {
                let streamsPlainText: Bool = true
            }
            ```

            | Case | Expected |
            | --- | --- |
            | Final answer | Textual |
            | Streaming | Plain Text |

            See [Textual](https://github.com/gonzalezreal/textual).
            """,
            isStreaming: false
        )
        .padding()
    }
}
