import SwiftUI

struct ActiveConversationDetailView: View {
    let appState: AppState

    @ViewBuilder
    var body: some View {
        if let conversationId = appState.activeConversationId {
            ChatView(appState: appState, conversationId: conversationId)
                .id(conversationId)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
