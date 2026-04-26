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
    private let thinkingExpansion: Binding<Bool>?
    private let showsThinkingHeader: Bool

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

    init(
        message: ChatMessage,
        isStreaming: Bool = false,
        parsedAssistantContent: ParsedAssistantContent? = nil,
        thinkingExpansion: Binding<Bool>? = nil,
        showsThinkingHeader: Bool = true
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.parsedAssistantContent = parsedAssistantContent
        self.thinkingExpansion = thinkingExpansion
        self.showsThinkingHeader = showsThinkingHeader
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
                        isThinkingExpanded: thinkingExpansion ?? $isThinkingExpanded,
                        isToolTraceExpanded: $isToolTraceExpanded,
                        showsThinkingHeader: showsThinkingHeader,
                        openSourceURL: openSourceURL,
                        onCopy: { copy(text: $0) }
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
                    .contextMenu {
                        Button {
                            copy(text: message.content)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
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

    private func copy(text: String) {
        UIPasteboard.general.setValue(text, forPasteboardType: UTType.plainText.identifier)
        showCopyFeedback = true
        Haptics.impactLight()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            showCopyFeedback = false
        }
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

    @ViewBuilder
    private var content: some View {
        if attachedDocuments.count == 1, let document = attachedDocuments.first {
            MessageDocumentAttachmentCard(
                document: document,
                iconName: iconName(document.kind),
                showsShadow: role == .user
            )
            .frame(maxWidth: 310, alignment: role == .user ? .trailing : .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachedDocuments) { document in
                        MessageDocumentAttachmentCard(
                            document: document,
                            iconName: iconName(document.kind),
                            showsShadow: role == .user
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
            }
            .frame(maxWidth: 320, alignment: role == .user ? .trailing : .leading)
        }
    }
}

private struct MessageDocumentAttachmentCard: View {
    let document: ConversationDocumentReference
    let iconName: String
    let showsShadow: Bool

    private var theme: DocumentAttachmentTheme {
        DocumentAttachmentTheme(kind: document.kind)
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(theme.iconFill)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(theme.accent)
                            .frame(width: 4)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(theme.accent.opacity(0.72), lineWidth: 1.2)
                    }

                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.accent)

                FoldedDocumentCorner(color: theme.accent)
                    .frame(width: 13, height: 13)
            }
            .frame(width: 42, height: 48)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(document.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(document.kind.displayName.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .frame(width: 280, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.fill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.border, lineWidth: 1.4)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.accent)
                .frame(width: 5)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8))
        }
        .shadow(color: showsShadow ? theme.accent.opacity(0.20) : .clear, radius: 10, x: 0, y: 4)
    }
}

private struct DocumentAttachmentTheme {
    let accent: Color
    let fill: Color
    let border: Color
    let iconFill: Color
    let title: Color

    init(kind: ConversationDocumentKind) {
        switch kind {
        case .pdf:
            accent = Color(red: 0.94, green: 0.18, blue: 0.22)
            fill = Color(red: 1.00, green: 0.96, blue: 0.95).opacity(0.95)
            border = accent.opacity(0.78)
            iconFill = Color.white.opacity(0.92)
            title = Color(red: 0.28, green: 0.04, blue: 0.05)
        case .csv:
            accent = Color(red: 0.07, green: 0.58, blue: 0.29)
            fill = Color(red: 0.93, green: 0.99, blue: 0.95).opacity(0.95)
            border = accent.opacity(0.78)
            iconFill = Color.white.opacity(0.92)
            title = Color(red: 0.04, green: 0.24, blue: 0.13)
        case .text:
            accent = Color(red: 0.15, green: 0.42, blue: 0.92)
            fill = Color(red: 0.94, green: 0.97, blue: 1.00).opacity(0.95)
            border = accent.opacity(0.76)
            iconFill = Color.white.opacity(0.92)
            title = Color(red: 0.05, green: 0.14, blue: 0.34)
        }
    }
}

private struct FoldedDocumentCorner: View {
    let color: Color

    var body: some View {
        UnevenRoundedRectangle(bottomLeadingRadius: 3, topTrailingRadius: 7)
            .fill(color.opacity(0.18))
            .overlay(
                UnevenRoundedRectangle(bottomLeadingRadius: 3, topTrailingRadius: 7)
                    .stroke(color.opacity(0.42), lineWidth: 0.8)
            )
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
    let showsThinkingHeader: Bool
    let openSourceURL: (URL?) -> Void
    let onCopy: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !isStreaming, let toolTrace {
                ToolTraceChainView(
                    trace: toolTrace,
                    isExpanded: $isToolTraceExpanded
                )
            }
            if let thinking = parsedContent.thinking, !thinking.isEmpty {
                if showsThinkingHeader {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) {
                                isThinkingExpanded.toggle()
                            }
                        } label: {
                            ThinkingDisclosureLabel(
                                isExpanded: isThinkingExpanded,
                                isStreaming: isStreaming,
                                isWaitingForAnswer: parsedContent.response.isEmpty
                            )
                        }
                        .buttonStyle(.plain)

                        ThinkingTextContent(
                            text: thinking,
                            isStreaming: isStreaming,
                            isExpanded: isThinkingExpanded
                        )
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .contextMenu {
                        if !isStreaming {
                            Button {
                                onCopy(parsedContent.copyableText)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
                } else {
                    ThinkingTextContent(
                        text: thinking,
                        isStreaming: isStreaming,
                        isExpanded: isThinkingExpanded
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }

            if !parsedContent.response.isEmpty {
                MessageTextBubble(
                    text: parsedContent.response,
                    role: .assistant,
                    isStreaming: isStreaming,
                    foregroundStyle: .primary
                )
                .contextMenu {
                    if !isStreaming {
                        Button {
                            onCopy(parsedContent.copyableText)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
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

                }
            }
        }
    }
}

struct ThinkingDisclosureLabel: View {
    let isExpanded: Bool
    let isStreaming: Bool
    let isWaitingForAnswer: Bool

    var body: some View {
        HStack(spacing: 8) {
            Label(String.appLocalized("message.thinking"), systemImage: "brain.head.profile")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if isStreaming && isWaitingForAnswer {
                Text(String.appLocalized("message.waiting_final"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

private struct ThinkingTextContent: View {
    let text: String
    let isStreaming: Bool
    let isExpanded: Bool

    var body: some View {
        if isExpanded {
            MessageTextBody(
                text: text,
                isStreaming: isStreaming,
                linkTint: BrandPalette.accent
            )
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
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
                    .background(.regularMaterial)
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
                    : AnyShapeStyle(.regularMaterial)
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
