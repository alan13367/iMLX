import SwiftUI

struct ChatModelStatusMenu: View {
    let isModelLoading: Bool
    let selectedModelDisplayName: String?
    let loadedModelId: String?
    let loadedModelDisplayName: String?
    let downloadedModels: [ModelInfo]
    let onSelectModel: (ModelInfo) -> Void
    let onUnload: () -> Void
    let onManageModels: () -> Void

    var body: some View {
        Menu {
            if downloadedModels.isEmpty {
                Section {
                    Text(String.appLocalized("chat.model_menu.no_downloads"))
                }
            } else {
                Section {
                    ForEach(downloadedModels) { model in
                        Button {
                            onSelectModel(model)
                        } label: {
                            if model.id == loadedModelId {
                                Label(model.displayName, systemImage: "checkmark")
                            } else {
                                Text(model.displayName)
                            }
                        }
                    }
                }
            }

            if loadedModelId != nil {
                Section {
                    Button(role: .destructive, action: onUnload) {
                        Label(
                            String.appLocalized("models.picker.unload"),
                            systemImage: "eject"
                        )
                    }
                }
            }

            Section {
                Button(action: onManageModels) {
                    Label(
                        String.appLocalized("chat.model_menu.manage"),
                        systemImage: "square.and.arrow.down"
                    )
                }
            }
        } label: {
            ChatModelStatusLabel(
                isModelLoading: isModelLoading,
                selectedModelDisplayName: selectedModelDisplayName,
                loadedModelDisplayName: loadedModelDisplayName
            )
        }
        .tint(.primary)
        .menuOrder(.fixed)
        .accessibilityLabel(
            loadedModelDisplayName == nil
                ? String.appLocalized("chat.select_model")
                : String.appLocalized("chat.change_model_a11y")
        )
        .accessibilityHint(String.appLocalized("chat.model_picker_hint"))
    }
}
