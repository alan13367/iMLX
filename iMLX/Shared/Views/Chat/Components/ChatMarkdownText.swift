import SwiftUI
import Textual

/// Markdown-aware text renderer used by assistant messages and reasoning bodies.
///
/// Streaming callers such as the reasoning body stay plain text; completed
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
            .backgroundColor(Color.secondary.opacity(0.14))
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
            Color.secondary.opacity(0.10)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .textual.blockSpacing(.init(top: 2, bottom: 12))
    }
}
