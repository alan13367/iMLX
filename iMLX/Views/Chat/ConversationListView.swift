import SwiftUI

enum ConversationListPresentation {
    case rootNavigation
    case modalSheet
}

struct ConversationListView: View {
    let appState: AppState
    var presentation: ConversationListPresentation = .rootNavigation
    var onClose: (() -> Void)?
    var onSelect: (UUID) -> Void

    @State private var conversationPendingDeletion: Conversation?
    @State private var isShowingDeleteSelectedAlert = false
    @State private var isSelectionMode = false
    @State private var selectedConversationIDs: Set<UUID> = []

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

    private var canClearAllConversations: Bool {
        !appState.conversations.isEmpty
    }

    private var allConversationIDs: Set<UUID> {
        Set(appState.conversations.map(\.id))
    }

    private var hasSelectedConversations: Bool {
        !selectedConversationIDs.isEmpty
    }

    private var hasSelectedAllConversations: Bool {
        canClearAllConversations && selectedConversationIDs == allConversationIDs
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
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedConversationIDs.contains(conversation.id),
                        onOpen: { selectConversation(conversation.id) },
                        onToggleSelection: { toggleSelection(for: conversation.id) }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !isSelectionMode {
                            Button(role: .destructive) {
                                confirmDeletion(for: conversation)
                            } label: {
                                Label(String.appLocalized("common.delete"), systemImage: "trash")
                            }
                        }
                    }
                    .contextMenu {
                        if isSelectionMode {
                            Button {
                                toggleSelection(for: conversation.id)
                            } label: {
                                Label(
                                    selectedConversationIDs.contains(conversation.id)
                                        ? String.appLocalized("conversation.deselect")
                                        : String.appLocalized("common.select"),
                                    systemImage: selectedConversationIDs.contains(conversation.id)
                                        ? "checkmark.circle.fill"
                                        : "circle"
                                )
                            }
                        } else {
                            Button(role: .destructive) {
                                confirmDeletion(for: conversation)
                            } label: {
                                Label(String.appLocalized("common.delete"), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(navigationTitle)
        .toolbar {
            if presentation == .modalSheet {
                if isSelectionMode {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button(hasSelectedAllConversations ? String.appLocalized("conversation.deselect_all") : String.appLocalized("conversation.select_all")) {
                            toggleSelectAll()
                        }
                        .disabled(!canClearAllConversations)
                        Button(role: .destructive) {
                            isShowingDeleteSelectedAlert = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(!hasSelectedConversations)
                        .accessibilityLabel(String.appLocalized("conversation.delete_selected"))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String.appLocalized("common.cancel")) {
                            stopSelecting()
                        }
                    }
                } else {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        if canClearAllConversations {
                            Button(String.appLocalized("common.select")) {
                                startSelecting()
                            }
                        }
                        Button(action: createConversation) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New conversation")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onClose?()
                        } label: {
                            CloseButtonLabel()
                        }
                        .accessibilityLabel(String.appLocalized("common.close"))
                    }
                }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    if isSelectionMode {
                        Button(String.appLocalized("common.cancel")) {
                            stopSelecting()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelectionMode {
                        Button(String.appLocalized("common.cancel")) {
                            stopSelecting()
                        }
                    } else if canClearAllConversations {
                        Button(String.appLocalized("common.select")) {
                            startSelecting()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelectionMode {
                        Button(hasSelectedAllConversations ? String.appLocalized("conversation.deselect_all") : String.appLocalized("conversation.select_all")) {
                            toggleSelectAll()
                        }
                        .disabled(!canClearAllConversations)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSelectionMode {
                        Button(role: .destructive) {
                            isShowingDeleteSelectedAlert = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(!hasSelectedConversations)
                        .accessibilityLabel(String.appLocalized("conversation.delete_selected"))
                    } else {
                        Button(action: createConversation) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("New conversation")
                    }
                }
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
        .alert(String.appLocalized("conversation.delete_selected_title"), isPresented: $isShowingDeleteSelectedAlert) {
            Button(String.appLocalized("common.delete"), role: .destructive) {
                deleteSelectedConversations()
            }
            Button(String.appLocalized("common.cancel"), role: .cancel) {
                isShowingDeleteSelectedAlert = false
            }
        } message: {
            Text(String(format: String.appLocalized("conversation.delete_selected_message"), selectedConversationIDs.count))
        }
    }

    private func deleteConversation(_ conversation: Conversation) {
        appState.deleteConversation(conversation.id)
        if conversationPendingDeletion?.id == conversation.id {
            conversationPendingDeletion = nil
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

    private func startSelecting() {
        isSelectionMode = true
        selectedConversationIDs = []
    }

    private func stopSelecting() {
        isSelectionMode = false
        selectedConversationIDs = []
    }

    private func toggleSelection(for id: UUID) {
        if selectedConversationIDs.contains(id) {
            selectedConversationIDs.remove(id)
        } else {
            selectedConversationIDs.insert(id)
        }
    }

    private func toggleSelectAll() {
        selectedConversationIDs = hasSelectedAllConversations ? [] : allConversationIDs
    }

    private func deleteSelectedConversations() {
        let ids = selectedConversationIDs
        for id in ids {
            appState.deleteConversation(id)
        }
        isShowingDeleteSelectedAlert = false
        conversationPendingDeletion = nil
        stopSelecting()
        if let id = appState.activeConversationId {
            onSelect(id)
        }
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
    let isSelectionMode: Bool
    let isSelected: Bool
    let onOpen: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isSelectionMode {
                Button(action: onToggleSelection) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? .blue : .secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    isSelected
                        ? String.appLocalized("conversation.deselect")
                        : String.appLocalized("common.select")
                )
            }

            Button(action: isSelectionMode ? onToggleSelection : onOpen) {
                ConversationRow(
                    conversation: conversation,
                    isActive: isActive,
                    showsDeleteControl: false,
                    onDelete: {}
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(conversation.displayTitle)
            .accessibilityHint(isSelectionMode ? String.appLocalized("common.select") : "Open conversation")
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
