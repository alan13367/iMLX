import Foundation
import SwiftUI

struct ChatCameraPickerPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onImagePicked: (Data) -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            ImagePicker(isPresented: $isPresented, onImagePicked: onImagePicked)
        }
    }
}

struct ChatFileDropModifier: ViewModifier {
    let onDrop: ([URL]) -> Void

    func body(content: Content) -> some View {
        content
    }
}

struct ChatUtilitySheetSizingModifier: ViewModifier {
    let sheet: ChatUtilitySheet

    func body(content: Content) -> some View {
        content
    }
}

struct ChatUtilitySheetCloseControlModifier: ViewModifier {
    let sheet: ChatUtilitySheet
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content
    }
}

struct ChatLiveVoicePresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let appState: AppState
    let chatViewModel: ChatViewModel

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: $isPresented) {
            LiveVoiceConversationView(appState: appState, chatViewModel: chatViewModel)
        }
    }
}

struct ChatPlatformLifecycleModifier: ViewModifier {
    let conversationId: UUID
    let appState: AppState
    let openModels: () -> Void
    let focusComposer: () -> Void

    func body(content: Content) -> some View {
        content
    }
}
