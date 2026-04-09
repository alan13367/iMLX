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

            Section(String.appLocalized("settings.section.memory")) {
                NavigationLink {
                    MemoryLibraryView(appState: appState)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String.appLocalized("settings.manage_memory"))
                        Text(memoryDetailText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Onboarding") {
                Button("Replay onboarding") {
                    appState.resetOnboarding()
                }
            }

            Section("Speech Assets") {
                LabeledContent("Resolved voice locale") {
                    Text(appState.resolvedVoiceLocale.displayName)
                }
                LabeledContent("Core model") {
                    Text(appState.speechAssetStatus.hasCoreModel ? "Installed" : "Not installed")
                }
                LabeledContent("Voice locales") {
                    Text(
                        appState.speechAssetStatus.activatedLocales.isEmpty
                            ? "None"
                            : appState.speechAssetStatus.activatedLocales
                                .sorted { $0.displayName < $1.displayName }
                                .map(\.displayName)
                                .joined(separator: ", ")
                    )
                }
                Button("Clear speech assets", role: .destructive) {
                    Task {
                        await appState.clearSpeechAssets()
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
        Task {
            await appState.clearAllDownloadedModels()
            await MainActor.run {
                Haptics.notificationWarning()
            }
        }
    }

    private var memoryDetailText: String {
        let pendingCount = appState.memories.filter { $0.status == .pending }.count
        let activeCount = appState.memories.filter { $0.status == .active }.count
        if pendingCount > 0 {
            return String(format: String.appLocalized("settings.manage_memory_detail_pending"), activeCount, pendingCount)
        }
        return String(format: String.appLocalized("settings.manage_memory_detail"), activeCount)
    }
}
