import ImageIO
import SwiftUI

/// Tint colors for the document attachment cards. Resolved from a small
/// curated palette so the card looks correct in light *and* dark mode without
/// hardcoded RGB.
enum DocumentAttachmentPalette {
    case pdf, csv, text

    init(kind: ConversationDocumentKind) {
        switch kind {
        case .pdf: self = .pdf
        case .csv: self = .csv
        case .text: self = .text
        }
    }

    var tint: Color {
        switch self {
        case .pdf: .red
        case .csv: .green
        case .text: BrandPalette.accent
        }
    }

    var iconName: String {
        switch self {
        case .pdf: "doc.richtext.fill"
        case .csv: "tablecells.fill"
        case .text: "doc.text.fill"
        }
    }
}

/// Combined image + document attachment strip for a message.
struct MessageAttachments: View {
    let role: ChatMessage.Role
    let attachedDocuments: [ConversationDocumentReference]
    let attachedImages: [ChatAttachmentImage]

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            if !attachedDocuments.isEmpty {
                MessageDocumentAttachmentStrip(
                    role: role,
                    attachedDocuments: attachedDocuments
                )
            }

            if !attachedImages.isEmpty {
                MessageImageAttachmentStrip(
                    role: role,
                    attachedImages: attachedImages
                )
            }
        }
    }

    private var alignment: HorizontalAlignment {
        role == .user ? .trailing : .leading
    }
}

private struct MessageDocumentAttachmentStrip: View {
    let role: ChatMessage.Role
    let attachedDocuments: [ConversationDocumentReference]

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
            AttachmentDocumentCard(document: document)
                .frame(maxWidth: 320, alignment: role == .user ? .trailing : .leading)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(attachedDocuments) { document in
                        AttachmentDocumentCard(document: document)
                    }
                }
                .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: 320, alignment: role == .user ? .trailing : .leading)
        }
    }
}

private struct MessageImageAttachmentStrip: View {
    let role: ChatMessage.Role
    let attachedImages: [ChatAttachmentImage]

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
        let imageSize: CGFloat = isSingle ? 180 : 96

        return ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachedImages) { image in
                    AttachmentImageThumbnailView(
                        imageId: image.id,
                        imageData: image.data,
                        size: imageSize,
                        cornerRadius: ChatMetrics.chipCornerRadius
                    )
                        .accessibilityLabel("Attached image")
                }
            }
            .frame(maxWidth: .infinity, alignment: role == .user ? .trailing : .leading)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: isSingle ? imageSize : 240)
    }
}

/// Single-document attachment row. A flat fill with a tinted document glyph;
/// the kind is carried by the icon rather than a rail, stroke, and badge.
struct AttachmentDocumentCard: View {
    let document: ConversationDocumentReference

    private var palette: DocumentAttachmentPalette {
        DocumentAttachmentPalette(kind: document.kind)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: palette.iconName)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(palette.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(document.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(document.kind.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(width: 280, alignment: .leading)
        .background(
            Color.secondary.opacity(ChatMetrics.inlineFillOpacity),
            in: RoundedRectangle(cornerRadius: ChatMetrics.chipCornerRadius, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(document.displayName), \(document.kind.displayName)")
    }
}

/// Decoded thumbnail view backed by a shared `NSCache`.
struct AttachmentImageThumbnailView: View {
    @Environment(\.displayScale) private var displayScale

    let imageId: UUID
    let imageData: Data
    let size: CGFloat
    let cornerRadius: CGFloat

    @State private var image: PlatformImage?

    private var maxPixelSize: CGFloat {
        size * displayScale
    }

    private var cacheKey: String {
        AttachmentImageThumbnailCache.cacheKey(for: imageId, maxPixelSize: maxPixelSize)
    }

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.secondary.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: cacheKey) {
            image = nil
            image = await AttachmentImageThumbnailCache.shared.image(
                for: imageData,
                cacheKey: cacheKey,
                maxPixelSize: maxPixelSize
            )
        }
    }
}

nonisolated final class AttachmentImageThumbnailCache {
    static let shared = AttachmentImageThumbnailCache()
    private let cache = NSCache<NSString, PlatformImage>()

    private init() {
        cache.countLimit = 96
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    static func cacheKey(for id: UUID, maxPixelSize: CGFloat) -> String {
        "\(id.uuidString)-\(Int(maxPixelSize.rounded(.up)))"
    }

    func image(for data: Data, cacheKey: String, maxPixelSize: CGFloat) async -> PlatformImage? {
        await image(for: data, cacheKey: cacheKey as NSString, maxPixelSize: maxPixelSize)
    }

    private func image(for data: Data, cacheKey key: NSString, maxPixelSize: CGFloat) async -> PlatformImage? {
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let decoded = await Task.detached(priority: .utility) {
            Self.downsampledImage(from: data, maxPixelSize: maxPixelSize)
        }.value

        if let decoded {
            cache.setObject(decoded, forKey: key, cost: data.count)
        }

        return decoded
    }

    private static func downsampledImage(from data: Data, maxPixelSize: CGFloat) -> PlatformImage? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, imageSourceOptions) else {
            return PlatformImageFactory.image(data: data)
        }

        let downsampleOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize.rounded(.up)))
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return PlatformImage(data: data)
        }

        return PlatformImageFactory.image(cgImage: cgImage)
    }
}

#Preview("Document card — PDF") {
    AttachmentDocumentCard(
        document: ConversationDocumentReference(
            id: "1",
            displayName: "MANDATO GESTORIA.pdf",
            kind: .pdf,
            importedAt: .now
        )
    )
    .padding()
}
