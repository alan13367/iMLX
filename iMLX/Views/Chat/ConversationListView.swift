import SwiftUI

enum ConversationListPresentation {
    case rootNavigation
    case modalSheet
}

struct ConversationListView: View {
    let appState: AppState
    var presentation: ConversationListPresentation = .rootNavigation
    var onSelect: (UUID) -> Void

    private var navigationTitle: String {
        presentation == .modalSheet ? "Chats" : "Conversations"
    }

    var body: some View {
        List {
            if appState.conversations.isEmpty {
                emptyContent
            } else {
                ForEach(appState.conversations) { conversation in
                    ConversationRow(conversation: conversation, isActive: appState.activeConversationId == conversation.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.selectConversation(conversation.id)
                            onSelect(conversation.id)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                appState.deleteConversation(conversation.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .navigationTitle(navigationTitle)
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

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.displayTitle)
                    .font(.subheadline)
                    .fontWeight(isActive ? .semibold : .regular)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let modelId = conversation.modelId {
                        Text(modelId)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(conversation.formattedDate)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text("\(conversation.messages.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.fill.tertiary)
                .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}
