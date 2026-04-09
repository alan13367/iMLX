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
    @State private var userBubbleWidth: CGFloat = 0

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
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                attachmentStrip

                if message.role == .assistant {
                    assistantContent
                } else if !message.content.isEmpty {
                    bubble(text: message.content, foregroundStyle: .white, measureWidth: shouldMeasureUserBubbleWidth)
                }
            }
            if message.role == .assistant { Spacer(minLength: 36) }
        }
        .overlay(copyFeedback, alignment: .bottom)
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if hasAttachments {
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if let attachedDocuments = message.attachedDocuments, !attachedDocuments.isEmpty {
                    documentAttachmentStrip(attachedDocuments)
                }
                if let attachedImages = message.attachedImages, !attachedImages.isEmpty {
                    imageAttachmentStrip(attachedImages)
                }
            }
        }
    }

    @ViewBuilder
    private func imageAttachmentStrip(_ attachedImages: [ChatAttachmentImage]) -> some View {
        if message.role == .user, attachedImages.count == 1 {
            attachmentStripContent(attachedImages)
                .frame(width: max(userBubbleWidth, 80), alignment: .center)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack {
                if message.role == .assistant {
                    attachmentStripContent(attachedImages)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    attachmentStripContent(attachedImages)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func attachmentStripContent(_ attachedImages: [ChatAttachmentImage]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachedImages) { image in
                    AttachmentImageThumbnailView(imageData: image.data, size: 80, cornerRadius: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
        .frame(maxWidth: 220)
    }

    private func documentAttachmentStrip(_ attachedDocuments: [ConversationDocumentReference]) -> some View {
        HStack {
            if message.role == .assistant {
                documentAttachmentContent(attachedDocuments)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                documentAttachmentContent(attachedDocuments)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func documentAttachmentContent(_ attachedDocuments: [ConversationDocumentReference]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachedDocuments) { document in
                    HStack(spacing: 8) {
                        Image(systemName: iconName(for: document.kind))
                            .foregroundStyle(message.role == .user ? .white : BrandPalette.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(document.kind.displayName)
                                .font(.caption2)
                                .foregroundStyle(message.role == .user ? .white.opacity(0.8) : .secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background {
                        if message.role == .user {
                            BrandPalette.primaryGradient
                        } else {
                            Color(.tertiarySystemFill)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
        .frame(maxWidth: 260)
    }

    private var assistantContent: some View {
        let parsedContent = parsedAssistantContent ?? ParsedAssistantContent(message.content, isStreaming: isStreaming)

        return VStack(alignment: .leading, spacing: 8) {
            if let thinking = parsedContent.thinking, !thinking.isEmpty {
                DisclosureGroup(isExpanded: $isThinkingExpanded) {
                    assistantText(thinking)
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
                    bubble(text: parsedContent.response, foregroundStyle: .primary)
                    if !isStreaming {
                        copyButton(copyText: parsedContent.copyableText)
                            .padding(.bottom, 4)
                    }
                }
            }

            if !isStreaming {
                VStack(alignment: .leading, spacing: 6) {
                    if let sources = message.retrievedSources, !sources.isEmpty {
                        sourcesSection(sources)
                    }
                    if let generationStats = message.generationStats {
                        StatsOverlayView(stats: generationStats, isLive: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if parsedContent.response.isEmpty {
                        HStack {
                            Spacer()
                            copyButton(copyText: parsedContent.copyableText)
                        }
                    }
                }
            }
        }
    }

    private var shouldMeasureUserBubbleWidth: Bool {
        message.role == .user && (message.attachedImages?.count == 1)
    }

    private func sourcesSection(_ sources: [MessageSource]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String.appLocalized("message.sources"), systemImage: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(sources) { source in
                Button {
                    if let url = source.url {
                        openURL(url)
                    }
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

    @ViewBuilder
    private func bubble(text: String, foregroundStyle: Color, measureWidth: Bool = false) -> some View {
        assistantText(text)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.role == .user
                    ? AnyShapeStyle(BrandPalette.primaryGradient)
                    : AnyShapeStyle(.fill.tertiary)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .background {
                if measureWidth {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                userBubbleWidth = proxy.size.width
                            }
                            .onChange(of: proxy.size.width) {
                                userBubbleWidth = proxy.size.width
                            }
                    }
                }
            }
    }

    @ViewBuilder
    private func assistantText(_ text: String) -> some View {
        if isStreaming {
            Text(text)
                .font(.body)
        } else if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(.body)
                .tint(BrandPalette.accent)
        } else {
            Text(text)
                .font(.body)
        }
    }

    private func copyButton(copyText: String) -> some View {
        Button {
            UIPasteboard.general.setValue(copyText, forPasteboardType: UTType.plainText.identifier)
            showCopyFeedback = true
            Haptics.impactLight()
            Task { @MainActor in
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
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Copy response")
    }

    private var copyFeedback: some View {
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

    private var hasAttachments: Bool {
        (message.attachedDocuments?.isEmpty == false) || (message.attachedImages?.isEmpty == false)
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

    private func sourceTitle(for source: MessageSource) -> String {
        if let location = source.location, !location.isEmpty {
            return "\(source.title) | \(location)"
        }
        return source.title
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
