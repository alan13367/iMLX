import SwiftUI

struct ChatPendingDocumentStrip: View {
    let pendingDocuments: [ConversationDocumentReference]
    let onRemoveDocument: (ConversationDocumentReference) -> Void
    let iconName: (ConversationDocumentKind) -> String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(pendingDocuments) { document in
                    HStack(spacing: 6) {
                        Image(systemName: iconName(document.kind))
                            .foregroundStyle(BrandPalette.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(document.kind.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            onRemoveDocument(document)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Remove document")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .liquidGlassSurface(
                        tint: BrandPalette.cyan.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                        fallback: AnyShapeStyle(BrandPalette.cyan.opacity(0.1))
                    )
                }
            }
            .liquidGlassContainer(spacing: 10)
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
    }
}
