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
/// Streaming callers such as the reasoning panel stay plain text; completed
/// content uses Textual for Markdown and LaTeX attachments. The visible answer
/// uses `IncrementalStreamingMarkdownText` while generation is active.
struct MessageMarkdownText: View {
    let text: String
    let isStreaming: Bool
    let linkTint: Color
    var linkPhoneNumbers: Bool = false

    var body: some View {
        if isStreaming {
            Text(text)
        } else {
            ChatStructuredMarkdownText(
                markdown: sanitizedMarkdown,
                linkTint: linkTint
            )
        }
    }

    private var sanitizedMarkdown: String {
        MarkdownSanitizer.preparingForRendering(
            text,
            linkPhoneNumbers: linkPhoneNumbers
        )
    }
}

struct IncrementalStreamingMarkdownText: View {
    let text: String
    let streamID: UUID
    let linkTint: Color

    @State private var model = IncrementalStreamingMarkdownModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.snapshot.completedSegments) { segment in
                StableMarkdownSegmentView(
                    segment: segment,
                    linkTint: linkTint
                )
                .equatable()
            }

            ActiveStreamingMarkdownTail(
                text: model.snapshot.activeTail,
                kind: model.snapshot.activeTailKind,
                linkTint: linkTint
            )
        }
        .onChange(
            of: IncrementalStreamingMarkdownInput(streamID: streamID, text: text),
            initial: true
        ) { _, input in
            model.consume(snapshot: input.text, streamID: input.streamID)
        }
        .onDisappear {
            model.cancelScheduledPublication()
        }
    }
}

private struct IncrementalStreamingMarkdownInput: Equatable {
    let streamID: UUID
    let text: String
}

@MainActor
@Observable
private final class IncrementalStreamingMarkdownModel {
    private(set) var snapshot = StreamingMarkdownSnapshot.empty

    @ObservationIgnored private var accumulator = StreamingMarkdownAccumulator()
    @ObservationIgnored private var currentStreamID: UUID?
    @ObservationIgnored private var pendingSnapshot: StreamingMarkdownSnapshot?
    @ObservationIgnored private var publicationTask: Task<Void, Never>?
    @ObservationIgnored private var lastTailPublication = Date.distantPast
    @ObservationIgnored private var sourceCursor = StreamingSourceCursor()

    func consume(snapshot source: String, streamID: UUID) {
        if currentStreamID != streamID {
            currentStreamID = streamID
            accumulator = StreamingMarkdownAccumulator()
            pendingSnapshot = nil
            publicationTask?.cancel()
            publicationTask = nil
            snapshot = .empty
            lastTailPublication = .distantPast
            sourceCursor = StreamingSourceCursor()
        }

        let nextSnapshot: StreamingMarkdownSnapshot
        if let appendedText = sourceCursor.consume(source) {
            nextSnapshot = accumulator.consume(appending: appendedText)
        } else {
            nextSnapshot = accumulator.reset(with: source)
            sourceCursor = StreamingSourceCursor(source: source)
        }
        let committedStableBlock =
            nextSnapshot.completedSegments.count != snapshot.completedSegments.count
            || nextSnapshot.resetGeneration != snapshot.resetGeneration
        let changedTailRenderingMode =
            nextSnapshot.activeTailKind != snapshot.activeTailKind

        if committedStableBlock || changedTailRenderingMode {
            publishImmediately(nextSnapshot)
            return
        }

        pendingSnapshot = nextSnapshot
        let elapsed = Date().timeIntervalSince(lastTailPublication)
        let interval = Constants.UI.streamingMarkdownTailPublishInterval
        if elapsed >= interval {
            publishPendingSnapshot()
        } else if publicationTask == nil {
            let delayMilliseconds = Int(((interval - elapsed) * 1_000).rounded(.up))
            publicationTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(delayMilliseconds))
                guard !Task.isCancelled else { return }
                self?.publishPendingSnapshot()
            }
        }
    }

    func cancelScheduledPublication() {
        publicationTask?.cancel()
        publicationTask = nil
    }

    private func publishImmediately(_ nextSnapshot: StreamingMarkdownSnapshot) {
        publicationTask?.cancel()
        publicationTask = nil
        pendingSnapshot = nil
        snapshot = nextSnapshot
        lastTailPublication = Date()
    }

    private func publishPendingSnapshot() {
        publicationTask = nil
        guard let pendingSnapshot else { return }
        self.pendingSnapshot = nil
        snapshot = pendingSnapshot
        lastTailPublication = Date()
    }
}

private struct StableMarkdownSegmentView: View, Equatable {
    let segment: StreamingMarkdownSegment
    let linkTint: Color

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.segment == rhs.segment
    }

    var body: some View {
        ChatStructuredMarkdownText(
            markdown: MarkdownSanitizer.preparingForRendering(segment.source),
            linkTint: linkTint
        )
    }
}

private struct ActiveStreamingMarkdownTail: View {
    let text: String
    let kind: StreamingMarkdownTailKind
    let linkTint: Color

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            if shouldRenderInlineMarkdown {
                InlineText(
                    markdown: sanitizedText,
                    syntaxExtensions: [.math]
                )
                    .textual.inlineStyle(chatInlineStyle(linkTint: linkTint))
                    .tint(linkTint)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(sanitizedText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MessageStreamingCaret()
                .alignmentGuide(.lastTextBaseline) { dimensions in
                    dimensions[VerticalAlignment.center] + 6
                }
        }
    }

    private var sanitizedText: String {
        MarkdownSanitizer.preparingForRendering(text)
    }

    private var shouldRenderInlineMarkdown: Bool {
        kind.supportsInlineRendering
            && text.count <= Constants.UI.streamingMarkdownInlineTailCharacterLimit
    }
}

private struct ChatStructuredMarkdownText: View {
    let markdown: String
    let linkTint: Color

    var body: some View {
        StructuredText(
            markdown: markdown,
            syntaxExtensions: [.math]
        )
            .textual.structuredTextStyle(.gitHub)
            .textual.inlineStyle(chatInlineStyle(linkTint: linkTint))
            .textual.headingStyle(IMLXChatHeadingStyle())
            .textual.paragraphStyle(IMLXChatParagraphStyle())
            .textual.codeBlockStyle(IMLXChatCodeBlockStyle())
            .textual.overflowMode(.scroll)
            .tint(linkTint)
    }
}

private func chatInlineStyle(linkTint: Color) -> InlineStyle {
    InlineStyle()
        .code(
            .monospaced,
            .fontScale(0.88),
            .backgroundColor(BrandPalette.accent.opacity(0.12))
        )
        .strong(.fontWeight(.semibold))
        .link(.foregroundColor(linkTint))
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
        .background {
            BrandPalette.accent.opacity(0.10)
        }
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
