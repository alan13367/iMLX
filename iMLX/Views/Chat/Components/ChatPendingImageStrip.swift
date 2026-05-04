import SwiftUI

struct ChatPendingImageStrip: View {
    let pendingImages: [ChatAttachmentImage]
    let onRemoveImage: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { image in
                    ZStack(alignment: .topTrailing) {
                        AttachmentImageThumbnailView(
                            imageId: image.id,
                            imageData: image.data,
                            size: 60,
                            cornerRadius: 8
                        )

                        Button {
                            onRemoveImage(image.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .black.opacity(0.6))
                                .font(.caption)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Remove image")
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
    }
}
