import Foundation
import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct MessageBubbleView: View, Equatable {
    @Environment(\.openURL) private var openURL

    let message: ChatMessage
    let isStreaming: Bool
    let parsedAssistantContent: ParsedAssistantContent?

    @State private var showCopyFeedback = false
    @State private var isThinkingExpanded = false
    @State private var isToolTraceExpanded = false
    @State private var userBubbleWidth: CGFloat = 0

    private var resolvedParsedContent: ParsedAssistantContent {
        parsedAssistantContent ?? ParsedAssistantContent(message.content, isStreaming: isStreaming)
    }

    private var hasAttachments: Bool {
        (message.attachedDocuments?.isEmpty == false) || (message.attachedImages?.isEmpty == false)
    }

    private var shouldMeasureUserBubbleWidth: Bool {
        message.role == .user && (message.attachedImages?.count == 1)
    }

    init(message: ChatMessage, isStreaming: Bool = false, parsedAssistantContent: ParsedAssistantContent? = nil) {
        self.message = message
        self.isStreaming = isStreaming
        self.parsedAssistantContent = parsedAssistantContent
    }

    static func == (lhs: MessageBubbleView, rhs: MessageBubbleView) -> Bool {
        lhs.message == rhs.message
            && lhs.isStreaming == rhs.isStreaming
            && lhs.parsedAssistantContent == rhs.parsedAssistantContent
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if hasAttachments {
                    MessageAttachmentStrip(
                        role: message.role,
                        attachedDocuments: message.attachedDocuments ?? [],
                        attachedImages: message.attachedImages ?? [],
                        userBubbleWidth: userBubbleWidth,
                        iconName: iconName(for:)
                    )
                }

                if message.role == .assistant {
                    AssistantMessageContent(
                        parsedContent: resolvedParsedContent,
                        isStreaming: isStreaming,
                        toolTrace: message.toolTrace,
                        retrievedSources: message.retrievedSources ?? [],
                        generationStats: message.generationStats,
                        isThinkingExpanded: $isThinkingExpanded,
                        isToolTraceExpanded: $isToolTraceExpanded,
                        showCopyFeedback: $showCopyFeedback,
                        openSourceURL: openSourceURL
                    )
                } else if !message.content.isEmpty {
                    MessageTextBubble(
                        text: message.content,
                        role: message.role,
                        isStreaming: isStreaming,
                        foregroundStyle: .white,
                        measureWidth: shouldMeasureUserBubbleWidth,
                        measuredWidth: $userBubbleWidth
                    )
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 36)
            }
        }
        .overlay(alignment: .bottom) {
            MessageCopyFeedbackView(showCopyFeedback: showCopyFeedback)
        }
    }

    private func openSourceURL(_ url: URL?) {
        guard let url else { return }
        openURL(url)
    }

    private func iconName(for kind: ConversationDocumentKind) -> String {
        switch kind {
        case .pdf:
            "doc.richtext"
        case .csv:
            "tablecells"
        case .text:
            "doc.text"
        }
    }
}

private struct MessageAttachmentStrip: View {
    let role: ChatMessage.Role
    let attachedDocuments: [ConversationDocumentReference]
    let attachedImages: [ChatAttachmentImage]
    let userBubbleWidth: CGFloat
    let iconName: (ConversationDocumentKind) -> String

    var body: some View {
        VStack(alignment: role == .user ? .trailing : .leading, spacing: 8) {
            if !attachedDocuments.isEmpty {
                MessageDocumentAttachmentStrip(
                    role: role,
                    attachedDocuments: attachedDocuments,
                    iconName: iconName
                )
            }

            if !attachedImages.isEmpty {
                MessageImageAttachmentStrip(
                    role: role,
                    attachedImages: attachedImages,
                    userBubbleWidth: userBubbleWidth
                )
            }
        }
    }
}

private struct MessageImageAttachmentStrip: View {
    let role: ChatMessage.Role
    let attachedImages: [ChatAttachmentImage]
    let userBubbleWidth: CGFloat

    var body: some View {
        HStack {
            if role == .assistant {
                attachmentStripContent
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                attachmentStripContent
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var attachmentStripContent: some View {
        let isSingle = attachedImages.count == 1
        let imageSize: CGFloat = isSingle ? 160 : 80

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachedImages) { image in
                    AttachmentImageThumbnailView(imageData: image.data, size: imageSize, cornerRadius: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
        }
        .frame(maxWidth: isSingle ? imageSize : 220)
    }
}

private struct MessageDocumentAttachmentStrip: View {
    let role: ChatMessage.Role
    let attachedDocuments: [ConversationDocumentReference]
    let iconName: (ConversationDocumentKind) -> String

    var body: some View {
        HStack {
            if role == .assistant {
                content
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                content
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var content: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachedDocuments) { document in
                    HStack(spacing: 8) {
                        Image(systemName: iconName(document.kind))
                            .foregroundStyle(role == .user ? .white : BrandPalette.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(document.kind.displayName)
                                .font(.caption2)
                                .foregroundStyle(role == .user ? .white.opacity(0.8) : .secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        if role == .user {
                            BrandPalette.primaryGradient
                        } else {
                            Color(.tertiarySystemFill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
        }
        .frame(maxWidth: 260)
    }
}

private struct AssistantMessageContent: View {
    let parsedContent: ParsedAssistantContent
    let isStreaming: Bool
    let toolTrace: ToolCallTrace?
    let retrievedSources: [MessageSource]
    let generationStats: GenerationStats?
    @Binding var isThinkingExpanded: Bool
    @Binding var isToolTraceExpanded: Bool
    @Binding var showCopyFeedback: Bool
    let openSourceURL: (URL?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isStreaming, let toolTrace {
                ToolTraceChainView(
                    trace: toolTrace,
                    isExpanded: $isToolTraceExpanded
                )
            }
            if let thinking = parsedContent.thinking, !thinking.isEmpty {
                DisclosureGroup(isExpanded: $isThinkingExpanded) {
                    MessageTextBody(
                        text: thinking,
                        isStreaming: isStreaming,
                        linkTint: BrandPalette.accent
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } label: {
                    HStack(spacing: 8) {
                        Label(String.appLocalized("message.thinking"), systemImage: "brain.head.profile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if isStreaming && parsedContent.response.isEmpty {
                            Text(String.appLocalized("message.waiting_final"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.fill.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if !parsedContent.response.isEmpty {
                HStack(alignment: .bottom, spacing: 8) {
                    MessageTextBubble(
                        text: parsedContent.response,
                        role: .assistant,
                        isStreaming: isStreaming,
                        foregroundStyle: .primary
                    )
                    if !isStreaming {
                        MessageCopyButton(
                            copyText: parsedContent.copyableText,
                            showCopyFeedback: $showCopyFeedback
                        )
                        .padding(.bottom, 4)
                    }
                }
            }

            if !isStreaming {
                VStack(alignment: .leading, spacing: 6) {
                    if !retrievedSources.isEmpty {
                        MessageSourcesSection(
                            sources: retrievedSources,
                            openSourceURL: openSourceURL
                        )
                    }
                    if let generationStats {
                        StatsOverlayView(stats: generationStats, isLive: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if parsedContent.response.isEmpty {
                        HStack {
                            Spacer()
                            MessageCopyButton(
                                copyText: parsedContent.copyableText,
                                showCopyFeedback: $showCopyFeedback
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct MessageSourcesSection: View {
    let sources: [MessageSource]
    let openSourceURL: (URL?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String.appLocalized("message.sources"), systemImage: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(sources) { source in
                Button {
                    openSourceURL(source.url)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sourceTitle(for: source))
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Text(source.excerpt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.fill.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(source.url == nil)
            }
        }
    }

    private func sourceTitle(for source: MessageSource) -> String {
        if let location = source.location, !location.isEmpty {
            return "\(source.title) | \(location)"
        }
        return source.title
    }
}

private struct MessageTextBubble: View {
    let text: String
    let role: ChatMessage.Role
    let isStreaming: Bool
    let foregroundStyle: Color
    var measureWidth: Bool = false
    @Binding var measuredWidth: CGFloat

    init(
        text: String,
        role: ChatMessage.Role,
        isStreaming: Bool,
        foregroundStyle: Color,
        measureWidth: Bool = false,
        measuredWidth: Binding<CGFloat> = .constant(0)
    ) {
        self.text = text
        self.role = role
        self.isStreaming = isStreaming
        self.foregroundStyle = foregroundStyle
        self.measureWidth = measureWidth
        self._measuredWidth = measuredWidth
    }

    var body: some View {
        MessageTextBody(
            text: text,
            isStreaming: isStreaming,
            linkTint: role == .user ? foregroundStyle : BrandPalette.accent
        )
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                role == .user
                    ? AnyShapeStyle(BrandPalette.primaryGradient)
                    : AnyShapeStyle(.fill.tertiary)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .background {
                if measureWidth {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                measuredWidth = proxy.size.width
                            }
                            .onChange(of: proxy.size.width) { _, width in
                                measuredWidth = width
                            }
                    }
                }
            }
    }
}

private struct MessageTextBody: View {
    let text: String
    let isStreaming: Bool
    let linkTint: Color

    var body: some View {
        if isStreaming {
            Text(text)
                .font(.body)
        } else if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.body)
                .tint(linkTint)
        } else {
            Text(text)
                .font(.body)
        }
    }
}

private struct MessageCopyButton: View {
    let copyText: String
    @Binding var showCopyFeedback: Bool

    var body: some View {
        Button(action: copy) {
            Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Copy response")
    }

    private func copy() {
        UIPasteboard.general.setValue(copyText, forPasteboardType: UTType.plainText.identifier)
        showCopyFeedback = true
        Haptics.impactLight()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            showCopyFeedback = false
        }
    }
}

private struct MessageCopyFeedbackView: View {
    let showCopyFeedback: Bool

    var body: some View {
        Group {
            if showCopyFeedback {
                Text(String.appLocalized("message.copied"))
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

struct AttachmentImageThumbnailView: View {
    let imageData: Data
    let size: CGFloat
    let cornerRadius: CGFloat

    @State private var image: UIImage?

    private var maxPixelSize: CGFloat {
        size * UIScreen.main.scale
    }

    private var cacheKey: String {
        AttachmentImageThumbnailCache.cacheKey(for: imageData, maxPixelSize: maxPixelSize)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(.tertiarySystemFill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: cacheKey) {
            image = nil
            image = await AttachmentImageThumbnailCache.shared.image(
                for: imageData,
                maxPixelSize: maxPixelSize
            )
        }
    }
}

nonisolated private final class AttachmentImageThumbnailCache {
    static let shared = AttachmentImageThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    static func cacheKey(for data: Data, maxPixelSize: CGFloat) -> String {
        "\(data.count)-\(data.hashValue)-\(Int(maxPixelSize.rounded(.up)))"
    }

    func image(for data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        let key = Self.cacheKey(for: data, maxPixelSize: maxPixelSize) as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let decoded = await Task.detached(priority: .utility) {
            Self.downsampledImage(from: data, maxPixelSize: maxPixelSize)
        }.value

        if let decoded {
            cache.setObject(decoded, forKey: key)
        }

        return decoded
    }

    private static func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return UIImage(data: data)
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded(.up)))
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return UIImage(data: data)
        }

        return UIImage(cgImage: cgImage)
    }
}

#Preview("Assistant Message") {
    MessageBubbleView(
        message: ChatMessage(
            role: .assistant,
            content: "Here is a **formatted** answer with a source-backed summary."
        )
    )
    .padding()
}

#Preview("User Message") {
    MessageBubbleView(
        message: ChatMessage(
            role: .user,
            content: "Summarize my notes from today."
        )
    )
    .padding()
}
