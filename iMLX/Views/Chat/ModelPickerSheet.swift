import SwiftUI

struct ModelPickerSheet: View {
    let appState: AppState
    let chatViewModel: ChatViewModel
    @Binding var isPresented: Bool
    @State private var viewModel = ModelManagerViewModel()
    @State private var isLoadingModelId: String?

    var body: some View {
        NavigationStack {
            List {
                if viewModel.downloadedModels.isEmpty {
                    Section {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("No downloaded models")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Go to the Models tab to download one")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    if let loadedId = appState.loadedModelId {
                        Section("Currently Loaded") {
                            loadedModelRow(modelId: loadedId)
                        }
                    }

                    Section("Downloaded Models") {
                        ForEach(viewModel.downloadedModels) { model in
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
                            Label("Unload Model", systemImage: "eject")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }

    private func loadedModelRow(modelId: String) -> some View {
        let model = Constants.ModelRegistry.curatedModels.first(where: { $0.id == modelId })
        return Group {
            if let model {
                HStack {
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
            }
        }
    }

    private func modelRow(model: ModelInfo) -> some View {
        HStack {
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
        .contentShape(Rectangle())
        .onTapGesture {
            Task {
                isLoadingModelId = model.id
                await chatViewModel.loadModel(model)
                isLoadingModelId = nil
            }
        }
    }
}
