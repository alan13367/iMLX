import SwiftUI
import UIKit
import ImageIO

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
                        cornerRadius: 14
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

/// Single-document attachment card. Uses semantic backgrounds so it adapts
/// correctly to light and dark mode. The tint is *only* applied to the icon
/// background and an accent rail; the card body uses `.regularMaterial`.
struct AttachmentDocumentCard: View {
    let document: ConversationDocumentReference

    private var palette: DocumentAttachmentPalette {
        DocumentAttachmentPalette(kind: document.kind)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(palette.tint.opacity(0.14))
                    .frame(width: 40, height: 48)

                Image(systemName: palette.iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(palette.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(document.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(document.kind.displayName.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(palette.tint)
                    .lineLimit(1)
                    .accessibilityLabel(document.kind.displayName)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 280, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(palette.tint)
            .frame(width: 3)
            .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.tint.opacity(0.32), lineWidth: 0.8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(document.displayName), \(document.kind.displayName)")
    }
}

/// Decoded thumbnail view backed by a shared `NSCache`. Identical behavior
/// to the previous implementation in `MessageBubbleView.swift` but moved here
/// so attachment-related code lives in one file.
struct AttachmentImageThumbnailView: View {
    @Environment(\.displayScale) private var displayScale

    let imageId: UUID
    let imageData: Data
    let size: CGFloat
    let cornerRadius: CGFloat

    @State private var image: UIImage?

    private var maxPixelSize: CGFloat {
        size * displayScale
    }

    private var cacheKey: String {
        AttachmentImageThumbnailCache.cacheKey(for: imageId, maxPixelSize: maxPixelSize)
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
                cacheKey: cacheKey,
                maxPixelSize: maxPixelSize
            )
        }
    }
}

nonisolated final class AttachmentImageThumbnailCache {
    static let shared = AttachmentImageThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 96
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    static func cacheKey(for id: UUID, maxPixelSize: CGFloat) -> String {
        "\(id.uuidString)-\(Int(maxPixelSize.rounded(.up)))"
    }

    func image(for data: Data, cacheKey: String, maxPixelSize: CGFloat) async -> UIImage? {
        await image(for: data, cacheKey: cacheKey as NSString, maxPixelSize: maxPixelSize)
    }

    private func image(for data: Data, cacheKey key: NSString, maxPixelSize: CGFloat) async -> UIImage? {
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let decoded = await Task.detached(priority: .utility) {
            Self.downsampledImage(from: data, maxPixelSize: maxPixelSize)
        }.value

        if let decoded {
            let cost = decoded.cgImage.map { $0.bytesPerRow * $0.height } ?? data.count
            cache.setObject(decoded, forKey: key, cost: cost)
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
