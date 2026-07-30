import Foundation
import SwiftUI

struct ChatCameraPickerPresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onImagePicked: (Data) -> Void

    func body(content: Content) -> some View {
        content
    }
}

struct ChatFileDropModifier: ViewModifier {
    let onDrop: ([URL]) -> Void

    func body(content: Content) -> some View {
        content.dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            onDrop(urls)
            return true
        }
    }
}

struct ChatUtilitySheetSizingModifier: ViewModifier {
    let sheet: ChatUtilitySheet

    func body(content: Content) -> some View {
        content.frame(
            minWidth: minimumSize.width,
            idealWidth: idealSize.width,
            maxWidth: maximumSize.width,
            minHeight: minimumSize.height,
            idealHeight: idealSize.height,
            maxHeight: maximumSize.height
        )
    }

    private var minimumSize: CGSize {
        switch sheet {
        case .models:
            CGSize(width: 720, height: 580)
        case .conversations:
            CGSize(width: 560, height: 560)
        case .memoryLibrary:
            CGSize(width: 720, height: 580)
        case .settings:
            CGSize(width: 640, height: 580)
        }
    }

    private var idealSize: CGSize {
        switch sheet {
        case .models:
            CGSize(width: 800, height: 640)
        case .conversations:
            CGSize(width: 620, height: 620)
        case .memoryLibrary:
            CGSize(width: 800, height: 640)
        case .settings:
            CGSize(width: 680, height: 640)
        }
    }

    private var maximumSize: CGSize {
        switch sheet {
        case .models, .memoryLibrary:
            CGSize(width: 1_000, height: 780)
        case .conversations:
            CGSize(width: 760, height: 780)
        case .settings:
            CGSize(width: 820, height: 780)
        }
    }
}

struct ChatUtilitySheetCloseControlModifier: ViewModifier {
    let sheet: ChatUtilitySheet
    let onClose: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if sheet == .models {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .liquidGlassSurface(
                            in: Circle(),
                            fallback: AnyShapeStyle(Color.secondary.opacity(0.10)),
                            interactive: true
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(String.appLocalized("common.close"))
                .help(String.appLocalized("common.close"))
                .padding(.trailing, 6)
                .zIndex(100)
            }
        }
    }
}

struct ChatLiveVoicePresentationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let appState: AppState
    let chatViewModel: ChatViewModel

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            LiveVoiceConversationView(appState: appState, chatViewModel: chatViewModel)
                .frame(minWidth: 680, minHeight: 620)
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
            .task(id: conversationId) {
                guard appState.consumeComposerFocusRequest() else { return }
                try? await Task.sleep(for: .milliseconds(50))
                focusComposer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .imlxOpenModelBrowser)) { _ in
                openModels()
            }
            .onReceive(NotificationCenter.default.publisher(for: .imlxFocusComposer)) { _ in
                focusComposer()
            }
    }
}
