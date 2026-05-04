import SwiftUI
import Textual

/// Single canonical disclosure for assistant "thinking" reasoning.
///
/// Used in three places:
///  - As an inline panel inside the assistant message (`mode = .inline`).
///  - As a pinned header above the streaming bubble (`mode = .pinnedHeader`).
///  - As a header-only label rendered above an externally-rendered body
///    (`mode = .headerOnly`) — used by the streaming bubble when the pinned
///    header sits above and the panel renders only the expanded body inline.
struct MessageThinkingPanel: View {
    enum Mode: Equatable {
        /// Header + body in a single rounded surface.
        case inline
        /// Header only; intended to be rendered as a pinned section header.
        case pinnedHeader
        /// Body only; the disclosure header is rendered elsewhere.
        case bodyOnly
    }

    let text: String?
    let isStreaming: Bool
    let isWaitingForAnswer: Bool
    let mode: Mode
    @Binding var isExpanded: Bool
    var onToggle: (() -> Void)? = nil
    @State private var hapticSelectionTrigger = 0

    var body: some View {
        switch mode {
        case .inline:
            VStack(alignment: .leading, spacing: 10) {
                disclosureButton
                if isExpanded, let text, !text.isEmpty {
                    bodyContent(text: text)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .leading) { gradientRail }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        case .pinnedHeader:
            disclosureButton
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(panelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .leading) { gradientRail }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .bodyOnly:
            if isExpanded, let text, !text.isEmpty {
                bodyContent(text: text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .leading) { gradientRail }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var disclosureButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
            hapticSelectionTrigger += 1
            onToggle?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandPalette.cyan)
                    .symbolRenderingMode(.hierarchical)

                Text(String.appLocalized("message.thinking"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                if isStreaming, isWaitingForAnswer {
                    ThinkingActivityIndicator()
                        .padding(.leading, 2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(.easeInOut(duration: 0.18), value: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String.appLocalized("message.thinking"))
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityHint(Text(isExpanded ? "Hide reasoning" : "Show reasoning"))
        .accessibilityAddTraits(.isButton)
        .sensoryFeedback(.selection, trigger: hapticSelectionTrigger)
    }

    @ViewBuilder
    private func bodyContent(text: String) -> some View {
        MessageMarkdownText(text: text, isStreaming: isStreaming, linkTint: BrandPalette.accent)
            .font(.callout)
            .foregroundStyle(.secondary)
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var panelBackground: some ShapeStyle {
        AnyShapeStyle(.regularMaterial)
    }

    private var gradientRail: some View {
        Rectangle()
            .fill(BrandPalette.primaryGradient)
            .frame(width: 2)
            .accessibilityHidden(true)
    }
}

/// Markdown-aware text renderer used by assistant messages and thinking panels.
///
/// During streaming we render the raw plain text (markdown parsing is expensive
/// and unstable mid-stream); once the message is finalized Textual renders
/// block-level Markdown such as lists, code fences, blockquotes, and tables.
struct MessageMarkdownText: View {
    let text: String
    let isStreaming: Bool
    let linkTint: Color
    var linkPhoneNumbers: Bool = false

    var body: some View {
        if isStreaming {
            Text(text)
        } else {
            StructuredText(markdown: sanitizedMarkdown)
                .textual.structuredTextStyle(.gitHub)
                .textual.inlineStyle(chatInlineStyle)
                .textual.headingStyle(IMLXChatHeadingStyle())
                .textual.paragraphStyle(IMLXChatParagraphStyle())
                .textual.codeBlockStyle(IMLXChatCodeBlockStyle())
                .textual.overflowMode(.scroll)
                .tint(linkTint)
        }
    }

    private var sanitizedMarkdown: String {
        let withoutRemoteImages = MarkdownSanitizer.removingRemoteImages(from: text)
        guard linkPhoneNumbers else { return withoutRemoteImages }
        return MarkdownSanitizer.linkingPhoneNumbers(from: withoutRemoteImages)
    }

    private var chatInlineStyle: InlineStyle {
        InlineStyle()
            .code(
                .monospaced,
                .fontScale(0.88),
                .backgroundColor(BrandPalette.accent.opacity(0.12))
            )
            .strong(.fontWeight(.semibold))
            .link(.foregroundColor(linkTint))
    }
}

private struct IMLXChatHeadingStyle: StructuredText.HeadingStyle {
    private static let fontScales: [CGFloat] = [1.28, 1.18, 1.1, 1.0, 0.95, 0.92]

    func makeBody(configuration: Configuration) -> some View {
        let headingLevel = min(configuration.headingLevel, Self.fontScales.count)

        configuration.label
            .textual.fontScale(Self.fontScales[headingLevel - 1])
            .textual.lineSpacing(.fontScaled(0.15))
            .textual.blockSpacing(.init(top: headingLevel <= 2 ? 14 : 10, bottom: 6))
            .fontWeight(.semibold)
    }
}

private struct IMLXChatParagraphStyle: StructuredText.ParagraphStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(0.22))
            .textual.blockSpacing(.init(top: 0, bottom: 10))
    }
}

private struct IMLXChatCodeBlockStyle: StructuredText.CodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        Overflow {
            configuration.label
                .textual.lineSpacing(.fontScaled(0.2))
                .textual.fontScale(0.86)
                .monospaced()
                .padding(12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .background(BrandPalette.accent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(BrandPalette.accent.opacity(0.16), lineWidth: 0.8)
        }
        .textual.blockSpacing(.init(top: 2, bottom: 12))
    }
}

#Preview("Thinking — inline") {
    StatefulPreviewWrapper(true) { binding in
        MessageThinkingPanel(
            text: "Let me think step-by-step.\n1. Look at the document\n2. Summarize the key fields",
            isStreaming: false,
            isWaitingForAnswer: false,
            mode: .inline,
            isExpanded: binding
        )
        .padding()
    }
}

#Preview("Thinking — streaming pinned header") {
    StatefulPreviewWrapper(true) { binding in
        MessageThinkingPanel(
            text: nil,
            isStreaming: true,
            isWaitingForAnswer: true,
            mode: .pinnedHeader,
            isExpanded: binding
        )
        .padding()
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ value: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: value)
        self.content = content
    }

    var body: some View { content($value) }
}
