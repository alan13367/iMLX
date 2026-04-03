import SwiftUI

enum ConversationListPresentation {
    case rootNavigation
    case modalSheet
}

struct ConversationListView: View {
    let appState: AppState
    var presentation: ConversationListPresentation = .rootNavigation
    var onSelect: (UUID) -> Void
    @State private var conversationPendingDeletion: Conversation?

    private var navigationTitle: String {
        presentation == .modalSheet ? "Chats" : "Conversations"
    }

    var body: some View {
        List {
            if appState.conversations.isEmpty {
                emptyContent
            } else {
                ForEach(appState.conversations) { conversation in
                    ConversationRow(
                        conversation: conversation,
                        isActive: appState.activeConversationId == conversation.id,
                        showsDeleteControl: true,
                        onDelete: {
                            conversationPendingDeletion = conversation
                        }
                    )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.selectConversation(conversation.id)
                            onSelect(conversation.id)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                conversationPendingDeletion = conversation
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                conversationPendingDeletion = conversation
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .confirmationDialog(
            "Delete Chat?",
            isPresented: Binding(
                get: { conversationPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        conversationPendingDeletion = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let conversation = conversationPendingDeletion else { return }
                appState.deleteConversation(conversation.id)
                conversationPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                conversationPendingDeletion = nil
            }
        } message: {
            if let conversationPendingDeletion {
                Text("Delete \"\(conversationPendingDeletion.displayTitle)\"?")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let id = appState.createNewConversation()
                    onSelect(id)
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
            Text("No conversations yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .listRowBackground(Color.clear)
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let isActive: Bool
    let showsDeleteControl: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.displayTitle)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)

                Text(conversation.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text("\(conversation.messages.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.fill.tertiary)
                .clipShape(Capsule())

            if showsDeleteControl {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.fill.tertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
