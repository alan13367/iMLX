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

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Creativity")
                        Spacer()
                        Text("\(viewModel.temperature, specifier: "%.1f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { viewModel.temperature },
                        set: { viewModel.temperature = $0 }
                    ), in: 0.0...2.0, step: 0.1)
                    Text(viewModel.temperatureDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Focus")
                        Spacer()
                        Text("\(viewModel.topP, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { viewModel.topP },
                        set: { viewModel.topP = $0 }
                    ), in: 0.0...1.0, step: 0.05)
                    Text(viewModel.topPDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Repetition Control")
                        Spacer()
                        Text("\(viewModel.repetitionPenalty, specifier: "%.1f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { viewModel.repetitionPenalty },
                        set: { viewModel.repetitionPenalty = $0 }
                    ), in: 0.9...2.0, step: 0.1)
                    Text(viewModel.repetitionPenaltyDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Responses now stop when the model decides it is finished.")
                    Text("If you are unsure, leave these on the defaults.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button("Reset to Defaults") {
                    viewModel.resetToDefaults()
                }
                .foregroundStyle(.red)
            } header: {
                Text("Response Style")
            } footer: {
                Text("Creativity changes how adventurous the wording is. Focus narrows or widens the set of candidate words. Repetition Control helps prevent loops and repeated phrasing.")
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
                    Text(String(format: "%.2f GB", appState.manifestService.totalStorageUsedGB))
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
        let downloadedEntries = appState.manifestService.getDownloadedModels()

        Task {
            await appState.inferenceService.unload()
            await MainActor.run {
                appState.clearModel()
            }

            for entry in downloadedEntries {
                let model = ModelInfo(
                    id: entry.id,
                    displayName: entry.displayName,
                    huggingFaceId: entry.huggingFaceId,
                    parameterCount: "",
                    quantization: "",
                    estimatedSizeGB: 0,
                    minDeviceRAM: 8,
                    family: .qwen3,
                    logoName: "",
                    supportsThinking: false,
                    supportsVision: false,
                    prefersThinkingEnabled: false
                )
                try? await appState.downloadService.deleteModel(model)
                await MainActor.run {
                    appState.manifestService.removeDownloaded(modelId: entry.id)
                }
            }
            await MainActor.run {
                Haptics.notificationWarning()
            }
        }
    }
}
