import SwiftUI

struct ModelPickerSheet: View {
    let appState: AppState
    let chatViewModel: ChatViewModel
    @Binding var isPresented: Bool
    @State private var downloadedModels: [ModelInfo] = []
    @State private var isLoadingModelId: String?

    var body: some View {
        NavigationStack {
            List {
                #if targetEnvironment(simulator)
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String.appLocalized("models.picker.simulator_title"))
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(String.appLocalized("models.picker.simulator_detail"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                #endif

                if downloadedModels.isEmpty {
                    Section {
                        ContentUnavailableView(
                            String.appLocalized("models.picker.none"),
                            systemImage: "arrow.down.circle",
                            description: Text(String.appLocalized("models.picker.hint_download"))
                        )
                        .padding(.vertical, 20)
                    }
                } else {
                    if let loadedId = appState.loadedModelId {
                        Section(String.appLocalized("models.picker.currently_loaded")) {
                            loadedModelRow(modelId: loadedId)
                        }
                    }

                    Section(String.appLocalized("models.picker.downloaded")) {
                        ForEach(downloadedModels) { model in
                            if model.id != appState.loadedModelId {
                                modelRow(model: model)
                            }
                        }
                    }
                }

                if appState.loadedModelId != nil {
                    Section {
                        Button(role: .destructive) {
                            Task {
                                await chatViewModel.unloadModel()
                            }
                        } label: {
                            Label(String.appLocalized("models.picker.unload"), systemImage: "eject")
                                .frame(maxWidth: .infinity)
                        }
                        .accessibilityLabel("Unload model from memory")
                    }
                }
            }
            .navigationTitle(String.appLocalized("models.picker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String.appLocalized("common.done")) {
                        isPresented = false
                    }
                }
            }
            .task {
                await refreshDownloadedModels()
            }
        }
    }

    private func refreshDownloadedModels() async {
        let refreshed = await appState.reconcileModelCatalogState()
        downloadedModels = refreshed
    }

    private func loadedModelRow(modelId: String) -> some View {
        let model = Constants.ModelRegistry.curatedModels.first(where: { $0.id == modelId })
        return Group {
            if let model {
                HStack(spacing: 12) {
                    modelLogo(for: model)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.displayName)
                            .font(.headline)
                        Text("\(model.parameterCount) · \(model.quantization)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if chatViewModel.isModelLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            } else {
                Text(modelId)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func modelRow(model: ModelInfo) -> some View {
        Button {
            #if targetEnvironment(simulator)
            Task { @MainActor in
                await chatViewModel.unloadModel()
                chatViewModel.errorMessage = InferenceError.simulatorUnsupported.localizedDescription
            }
            #else
            Task { @MainActor in
                isLoadingModelId = model.id
                await chatViewModel.loadModel(model)
                isLoadingModelId = nil
            }
            #endif
        } label: {
            HStack(spacing: 12) {
                modelLogo(for: model)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(.headline)
                    Text("\(model.parameterCount) · \(model.quantization)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoadingModelId == model.id {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if targetEnvironment(simulator)
        .opacity(0.6)
        #endif
        .accessibilityLabel("Load \(model.displayName)")
        .accessibilityHint("Loads this model for chat")
    }

    private func modelLogo(for model: ModelInfo) -> some View {
        ModelLogoView(family: model.family)
    }
}
