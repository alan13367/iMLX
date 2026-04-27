import SwiftUI

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
            Haptics.selectionChanged()
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
    }

    @ViewBuilder
    private func bodyContent(text: String) -> some View {
        MessageMarkdownText(text: text, isStreaming: isStreaming, linkTint: BrandPalette.accent)
            .font(.callout)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
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

/// Markdown-aware text renderer used by message bubbles and panels.
///
/// During streaming we render the raw plain text (markdown parsing is expensive
/// and unstable mid-stream); once the message is finalized we render inline
/// markdown so bold/links/inline code render correctly.
///
/// SwiftUI's `Text(AttributedString)` only renders inline markdown — block
/// elements like bullet/numbered lists pass through as literal `*`/`-`/`1.`.
/// Before parsing we normalize common list prefixes to a real bullet glyph so
/// chat answers don't look like raw markdown.
struct MessageMarkdownText: View {
    let text: String
    let isStreaming: Bool
    let linkTint: Color

    var body: some View {
        if isStreaming {
            Text(text)
        } else {
            let normalized = MessageMarkdownText.normalizeListPrefixes(text)
            if let attributed = try? AttributedString(
                markdown: normalized,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .tint(linkTint)
            } else {
                Text(normalized)
            }
        }
    }

    /// Replaces leading `* `, `- `, `+ ` markers with `•  ` and renders
    /// `<n>. ` numbered markers as `n.  ` with consistent spacing. Preserves
    /// indentation so nested lists keep their visual depth.
    static func normalizeListPrefixes(_ source: String) -> String {
        var result = ""
        result.reserveCapacity(source.count)
        var isFirstLine = true
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if !isFirstLine { result.append("\n") }
            isFirstLine = false
            result.append(transformedLine(String(line)))
        }
        return result
    }

    private static func transformedLine(_ line: String) -> String {
        let leadingWhitespace = line.prefix(while: { $0 == " " || $0 == "\t" })
        let body = line.dropFirst(leadingWhitespace.count)

        if body.hasPrefix("* ") || body.hasPrefix("- ") || body.hasPrefix("+ ") {
            return "\(leadingWhitespace)•  \(body.dropFirst(2))"
        }

        var digits = ""
        var index = body.startIndex
        while index < body.endIndex, body[index].isNumber {
            digits.append(body[index])
            index = body.index(after: index)
        }
        if !digits.isEmpty,
           index < body.endIndex,
           body[index] == ".",
           body.index(after: index) < body.endIndex,
           body[body.index(after: index)] == " " {
            let rest = body[body.index(index, offsetBy: 2)...]
            return "\(leadingWhitespace)\(digits).  \(rest)"
        }

        return line
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
