import SwiftUI

struct SettingsView: View {
    let appState: AppState
    @State private var showClearModelsAlert = false

    private var viewModel: SettingsViewModel {
        appState.settingsViewModel
    }

    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("Physical RAM") {
                    Text("\(viewModel.deviceCapability.physicalMemoryGB) GB")
                }
                LabeledContent("Device Tier") {
                    Text(viewModel.deviceCapability.tier.displayName)
                }
                if let modelId = appState.loadedModelId {
                    LabeledContent("Active Model") {
                        Text(modelId)
                            .foregroundStyle(.green)
                    }
                }
            }

            Section("Generation Parameters") {
                Stepper("Max Tokens: \(viewModel.maxTokens)", value: Binding(
                    get: { viewModel.maxTokens },
                    set: { viewModel.maxTokens = $0 }
                ), in: 64...4096, step: 64)

                Slider(value: Binding(
                    get: { viewModel.temperature },
                    set: { viewModel.temperature = $0 }
                ), in: 0.0...2.0, step: 0.1) {
                    Text("Temperature: \(viewModel.temperature, specifier: "%.1f")")
                }

                Slider(value: Binding(
                    get: { viewModel.topP },
                    set: { viewModel.topP = $0 }
                ), in: 0.0...1.0, step: 0.05) {
                    Text("Top P: \(viewModel.topP, specifier: "%.2f")")
                }

                Slider(value: Binding(
                    get: { viewModel.repetitionPenalty },
                    set: { viewModel.repetitionPenalty = $0 }
                ), in: 0.9...2.0, step: 0.1) {
                    Text("Repetition Penalty: \(viewModel.repetitionPenalty, specifier: "%.1f")")
                }

                Button("Reset to Defaults") {
                    viewModel.resetToDefaults()
                }
                .foregroundStyle(.red)
            }

            Section("System Prompt") {
                TextField("Enter system prompt...", text: Binding(
                    get: { viewModel.systemPrompt },
                    set: { viewModel.systemPrompt = $0 }
                ), axis: .vertical)
                .lineLimit(3...8)
            }

            Section("Storage") {
                LabeledContent("Models Storage") {
                    Text(String(format: "%.2f GB", viewModel.totalStorageUsedGB))
                }
                Button("Clear All Downloaded Models", role: .destructive) {
                    showClearModelsAlert = true
                }
            }

            Section("About") {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
        }
        .navigationTitle("Settings")
        .alert("Clear All Models?", isPresented: $showClearModelsAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clearAllModels()
            }
        } message: {
            Text("This will delete all downloaded models. This cannot be undone.")
        }
    }

    private func clearAllModels() {
        let manifestService = ManifestService()
        let downloadService = ModelDownloadService()
        for entry in manifestService.getDownloadedModels() {
            Task {
                let model = ModelInfo(
                    id: entry.id,
                    displayName: entry.displayName,
                    huggingFaceId: entry.huggingFaceId,
                    parameterCount: "",
                    quantization: "",
                    estimatedSizeGB: 0,
                    minDeviceRAM: 8,
                    family: .qwen3
                )
                try? await downloadService.deleteModel(model)
                manifestService.removeDownloaded(modelId: entry.id)
            }
        }
        Haptics.notificationWarning()
    }
}
