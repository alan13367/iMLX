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
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text(document.displayName)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            onRemoveDocument(document)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Remove document")
                    }
                    .padding(.leading, 10)
                    .padding(.trailing, 2)
                    .padding(.vertical, 4)
                    .background(
                        Color.secondary.opacity(ChatMetrics.inlineFillOpacity),
                        in: Capsule()
                    )
                }
            }
            .padding(.horizontal, 4)
        }
        .scrollIndicators(.hidden)
    }
}
