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
    @State private var isShowingClearAllAlert = false

    private var isShowingDeleteAlert: Binding<Bool> {
        Binding(
            get: { conversationPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    conversationPendingDeletion = nil
                }
            }
        )
    }

    private var showsInlineDeleteButton: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private var canClearAllConversations: Bool {
        !appState.conversations.isEmpty
    }

    private var navigationTitle: String {
        presentation == .modalSheet
            ? String.appLocalized("conversation.title.chats")
            : String.appLocalized("conversation.title.list")
    }

    var body: some View {
        List {
            if appState.conversations.isEmpty {
                emptyContent
            } else {
                ForEach(appState.conversations) { conversation in
                    ConversationListItem(
                        conversation: conversation,
                        isActive: appState.activeConversationId == conversation.id,
                        showsInlineDeleteButton: showsInlineDeleteButton,
                        onOpen: { selectConversation(conversation.id) },
                        onDelete: { confirmDeletion(for: conversation) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            confirmDeletion(for: conversation)
                        } label: {
                            Label(String.appLocalized("common.delete"), systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            confirmDeletion(for: conversation)
                        } label: {
                            Label(String.appLocalized("common.delete"), systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if canClearAllConversations {
                    Button(role: .destructive) {
                        isShowingClearAllAlert = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(String.appLocalized("conversation.clear_all"))
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: createConversation) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New conversation")
            }
        }
        .alert(
            String.appLocalized("conversation.delete_title"),
            isPresented: isShowingDeleteAlert,
            presenting: conversationPendingDeletion
        ) { conversation in
            Button(String.appLocalized("common.delete"), role: .destructive) {
                deleteConversation(conversation)
            }
            Button(String.appLocalized("common.cancel"), role: .cancel) {
                conversationPendingDeletion = nil
            }
        } message: { conversation in
            Text(String(format: String.appLocalized("conversation.delete_message"), conversation.displayTitle))
        }
        .alert(String.appLocalized("conversation.clear_alert_title"), isPresented: $isShowingClearAllAlert) {
            Button(String.appLocalized("conversation.clear_confirm"), role: .destructive) {
                clearAllConversations()
            }
            Button(String.appLocalized("common.cancel"), role: .cancel) {
                isShowingClearAllAlert = false
            }
        } message: {
            Text(String.appLocalized("conversation.clear_alert_message"))
        }
    }

    private func deleteConversation(_ conversation: Conversation) {
        appState.deleteConversation(conversation.id)
        if conversationPendingDeletion?.id == conversation.id {
            conversationPendingDeletion = nil
        }
    }

    private func clearAllConversations() {
        appState.clearAllConversations()
        isShowingClearAllAlert = false
        conversationPendingDeletion = nil
        if let id = appState.activeConversationId {
            onSelect(id)
        }
    }

    private func selectConversation(_ id: UUID) {
        appState.selectConversation(id)
        onSelect(id)
    }

    private func createConversation() {
        let id = appState.createNewConversation()
        onSelect(id)
    }

    private func confirmDeletion(for conversation: Conversation) {
        conversationPendingDeletion = conversation
    }

    private var emptyContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.4))
            Text(String.appLocalized("conversation.empty"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .listRowBackground(Color.clear)
    }
}

private struct ConversationListItem: View {
    let conversation: Conversation
    let isActive: Bool
    let showsInlineDeleteButton: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                ConversationRow(
                    conversation: conversation,
                    isActive: isActive,
                    showsDeleteControl: false,
                    onDelete: {}
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(conversation.displayTitle)
            .accessibilityHint("Open conversation")

            if showsInlineDeleteButton {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .liquidGlassSurface(
                            tint: .red.opacity(0.14),
                            in: Circle(),
                            fallback: AnyShapeStyle(.fill.tertiary),
                            interactive: true
                        )
                }
                .buttonStyle(.borderless)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Delete conversation")
            }
        }
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
                .liquidGlassSurface(in: Capsule(), fallback: AnyShapeStyle(.fill.tertiary))

            if showsDeleteControl {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .liquidGlassSurface(
                            tint: .red.opacity(0.14),
                            in: Circle(),
                            fallback: AnyShapeStyle(.fill.tertiary),
                            interactive: true
                        )
                }
                .buttonStyle(.borderless)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Delete conversation")
            }
        }
        .padding(.vertical, 6)
    }
}
