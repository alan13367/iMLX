import SwiftUI

struct SettingsView: View {
    let appState: AppState
    @State private var showClearModelsAlert = false
    private let deviceCapability = DeviceCapabilityService()

    var body: some View {
        Form {
            Section(String.appLocalized("settings.section.language")) {
                Picker(String.appLocalized("settings.section.language"), selection: Binding(
                    get: { AppLanguageOption.from(storageCode: appState.preferredAppLanguageCode) },
                    set: { appState.setPreferredAppLanguage($0.storageCode) }
                )) {
                    ForEach(AppLanguageOption.allCases) { option in
                        Text(String.appLocalized(option.titleLocalizationKey)).tag(option)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(String.appLocalized("settings.section.device")) {
                LabeledContent(String.appLocalized("settings.physical_ram")) {
                    Text("\(deviceCapability.physicalMemoryGB) GB")
                }
                LabeledContent(String.appLocalized("settings.device_tier")) {
                    Text(deviceCapability.tier.displayName)
                }
                if let modelId = appState.loadedModelId {
                    LabeledContent(String.appLocalized("settings.active_model")) {
                        Text(modelId)
                            .foregroundStyle(.green)
                    }
                }
            }

            Section(String.appLocalized("settings.section.personas")) {
                NavigationLink {
                    PersonaLibraryView(appState: appState)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String.appLocalized("settings.manage_personas"))
                        Text(String.appLocalized("settings.manage_personas_detail"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(String.appLocalized("settings.section.storage")) {
                LabeledContent(String.appLocalized("settings.models_storage")) {
                    Text(String(format: "%.2f GB", appState.manifestService.totalStorageUsedGB))
                }
                Button(String.appLocalized("settings.clear_models"), role: .destructive) {
                    showClearModelsAlert = true
                }
            }

            Section(String.appLocalized("settings.section.about")) {
                LabeledContent(String.appLocalized("common.version")) {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
        }
        .navigationTitle(String.appLocalized("settings.title"))
        .alert(String.appLocalized("settings.clear_alert_title"), isPresented: $showClearModelsAlert) {
            Button(String.appLocalized("common.cancel"), role: .cancel) {}
            Button(String.appLocalized("settings.clear_confirm"), role: .destructive) {
                clearAllModels()
            }
        } message: {
            Text(String.appLocalized("settings.clear_alert_message"))
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
