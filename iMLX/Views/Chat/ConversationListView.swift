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
        let conversations = appState.conversations
        let conversationIDs = conversations.map(\.id)

        List {
            if conversations.isEmpty {
                emptyContent
            } else {
                ForEach(conversations) { conversation in
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
        .id(conversationIDs)
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
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: createConversation) {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("New conversation")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        if canClearAllConversations {
                            Button(String.appLocalized("common.select")) {
                                startSelecting()
                            }
                        }
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
                if isSelectionMode {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String.appLocalized("common.cancel")) {
                            stopSelecting()
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
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
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: createConversation) {
                            Image(systemName: "square.and.pencil")
                        }
                        .accessibilityLabel("New conversation")
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        if canClearAllConversations {
                            Button(String.appLocalized("common.select")) {
                                startSelecting()
                            }
                        }
                    }
                }
            }
        }
        .modifier(
            ConversationDeletionAlert(
                conversation: $conversationPendingDeletion,
                onDelete: deleteConversation
            )
        )
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
        .onChange(of: conversationIDs) { _, ids in
            selectedConversationIDs.formIntersection(Set(ids))
        }
    }

    private func deleteConversation(_ conversation: Conversation) {
        let id = conversation.id
        if conversationPendingDeletion?.id == conversation.id {
            conversationPendingDeletion = nil
        }
        selectedConversationIDs.remove(id)
        performDeferredConversationMutation {
            appState.deleteConversation(id)
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
        isShowingDeleteSelectedAlert = false
        conversationPendingDeletion = nil
        stopSelecting()
        performDeferredConversationMutation {
            let activeConversationId = appState.deleteConversations(ids)
            if let activeConversationId {
                onSelect(activeConversationId)
            }
        }
    }

    private func performDeferredConversationMutation(_ mutation: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            await Task.yield()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                mutation()
            }
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView(
            String.appLocalized("conversation.empty"),
            systemImage: "bubble.left.and.bubble.right"
        )
        .listRowBackground(Color.clear)
    }
}

private struct ConversationDeletionAlert: ViewModifier {
    @Binding var conversation: Conversation?
    let onDelete: (Conversation) -> Void

    func body(content: Content) -> some View {
        content.alert(
            String.appLocalized("conversation.delete_title"),
            isPresented: isPresented,
            presenting: conversation
        ) { conversation in
            deleteActions(for: conversation)
        } message: { conversation in
            deleteMessage(for: conversation)
        }
    }

    @ViewBuilder
    private func deleteActions(for conversation: Conversation) -> some View {
        Button(String.appLocalized("common.delete"), role: .destructive) {
            onDelete(conversation)
        }
        Button(String.appLocalized("common.cancel"), role: .cancel) {
            self.conversation = nil
        }
    }

    private func deleteMessage(for conversation: Conversation) -> some View {
        Text(
            String(
                format: String.appLocalized("conversation.delete_message"),
                conversation.displayTitle
            )
        )
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { conversation != nil },
            set: { isPresented in
                if !isPresented {
                    conversation = nil
                }
            }
        )
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
