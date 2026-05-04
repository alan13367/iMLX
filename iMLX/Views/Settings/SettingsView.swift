import SwiftUI

private enum SettingsNavigationDestination: String, Hashable {
    case memory
    case assistant
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var appState: AppState
    @State private var showClearModelsAlert = false
    @State private var navigationDestination: SettingsNavigationDestination?
    @State private var hapticWarningTrigger = 0
    private let deviceCapability = DeviceCapabilityService()

    var body: some View {
        Form {
            Section(String.appLocalized("settings.section.language")) {
                Picker(String.appLocalized("settings.section.language"), selection: $appState.preferredAppLanguageOption) {
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

            Section(String.appLocalized("settings.section.assistant")) {
                Button {
                    navigationDestination = .assistant
                } label: {
                    HStack {
                        Text(String.appLocalized("settings.assistant.title"))
                        Spacer()
                        Text(appState.assistantTemperature, format: .number.precision(.fractionLength(1)))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(String.appLocalized("settings.section.memory")) {
                Button {
                    navigationDestination = .memory
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String.appLocalized("settings.manage_memory"))
                        Text(memoryDetailText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section(String.appLocalized("settings.section.onboarding")) {
                Button(String.appLocalized("settings.replay_onboarding")) {
                    appState.resetOnboarding()
                }
            }

            Section(String.appLocalized("settings.speech_assets.section")) {
                LabeledContent(String.appLocalized("settings.speech_assets.resolved_locale")) {
                    Text(appState.resolvedVoiceLocale.displayName)
                }
                LabeledContent(String.appLocalized("settings.speech_assets.core_model")) {
                    Text(appState.speechAssetStatus.hasCoreModel ? String.appLocalized("settings.speech_assets.installed") : String.appLocalized("settings.speech_assets.not_installed"))
                }
                LabeledContent(String.appLocalized("settings.speech_assets.cached_locales")) {
                    Text(
                        appState.speechAssetStatus.activatedLocales.isEmpty
                            ? String.appLocalized("settings.speech_assets.none")
                            : appState.speechAssetStatus.activatedLocales
                                .sorted { $0.displayName < $1.displayName }
                                .map(\.displayName)
                                .joined(separator: ", ")
                    )
                }
                Button(String.appLocalized("settings.speech_assets.clear"), role: .destructive) {
                    Task {
                        await appState.clearSpeechAssets()
                    }
                }
            }

            Section(String.appLocalized("settings.section.storage")) {
                LabeledContent(String.appLocalized("settings.models_storage")) {
                    Text("\(appState.manifestService.totalStorageUsedGB, format: .number.precision(.fractionLength(2))) GB")
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    CloseButtonLabel()
                }
                .accessibilityLabel(String.appLocalized("common.close"))
            }
        }
        .navigationDestination(item: $navigationDestination) { destination in
            switch destination {
            case .memory:
                MemoryLibraryView(appState: appState)
            case .assistant:
                AssistantSettingsView(appState: appState)
            }
        }
        .alert(String.appLocalized("settings.clear_alert_title"), isPresented: $showClearModelsAlert) {
            Button(String.appLocalized("common.cancel"), role: .cancel) {}
            Button(String.appLocalized("settings.clear_confirm"), role: .destructive) {
                clearAllModels()
            }
        } message: {
            Text(String.appLocalized("settings.clear_alert_message"))
        }
        .sensoryFeedback(.warning, trigger: hapticWarningTrigger)
    }

    private func clearAllModels() {
        Task {
            await appState.clearAllDownloadedModels()
            hapticWarningTrigger += 1
        }
    }

    private var memoryDetailText: String {
        let pendingCount = appState.memories.count(where: { $0.status == .pending })
        let activeCount = appState.memories.count(where: { $0.status == .active })
        if pendingCount > 0 {
            return String(format: String.appLocalized("settings.manage_memory_detail_pending"), activeCount, pendingCount)
        }
        return String(format: String.appLocalized("settings.manage_memory_detail"), activeCount)
    }
}
