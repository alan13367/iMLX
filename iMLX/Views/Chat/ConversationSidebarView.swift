import SwiftUI

struct ConversationSidebarView: View {
    let appState: AppState
    var onSelect: (UUID) -> Void

    var body: some View {
        List(selection: Binding(
            get: { appState.activeConversationId },
            set: { newId in
                if let id = newId {
                    appState.selectConversation(id)
                    onSelect(id)
                }
            }
        )) {
            Section {
                Button {
                    let id = appState.createNewConversation()
                    onSelect(id)
                } label: {
                    Label("New Conversation", systemImage: "plus.circle")
                        .font(.subheadline)
                }
            }

            Section("Recent") {
                ForEach(appState.conversations) { conversation in
                    ConversationRow(conversation: conversation, isActive: appState.activeConversationId == conversation.id)
                        .tag(conversation.id)
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
        .listStyle(.sidebar)
        .navigationTitle("Conversations")
    }
}
