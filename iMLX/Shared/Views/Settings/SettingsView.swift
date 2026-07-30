import SwiftUI

struct SettingsViewFacade<Content: View>: View {
    let appState: AppState
    private let content: (Binding<Bool>) -> Content

    @State private var showClearModelsAlert = false
    @State private var hapticWarningTrigger = 0

    init(
        appState: AppState,
        @ViewBuilder content: @escaping (Binding<Bool>) -> Content
    ) {
        self.appState = appState
        self.content = content
    }

    var body: some View {
        content($showClearModelsAlert)
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
}

enum SettingsMetadata {
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

struct SpeechAssetsSettingsView: View {
    @Bindable var appState: AppState

    var body: some View {
        Form {
            Section {
                LabeledContent(String.appLocalized("settings.speech_assets.resolved_locale")) {
                    Text(appState.resolvedVoiceLocale.displayName)
                }
                LabeledContent(String.appLocalized("settings.speech_assets.core_model")) {
                    Text(appState.speechAssetStatus.hasCoreModel ? String.appLocalized("settings.speech_assets.installed") : String.appLocalized("settings.speech_assets.not_installed"))
                }
                LabeledContent(String.appLocalized("settings.speech_assets.cached_locales")) {
                    Text(cachedLocalesText)
                }
            } header: {
                SettingsSectionHeader(
                    title: String.appLocalized("settings.speech_assets.section"),
                    systemImage: "waveform"
                )
            }

            Section {
                Button(String.appLocalized("settings.speech_assets.clear"), role: .destructive) {
                    Task {
                        await appState.clearSpeechAssets()
                    }
                }
            }
        }
        .imlxSettingsFormStyle()
        .navigationTitle(String.appLocalized("settings.speech_assets.section"))
    }

    private var cachedLocalesText: String {
        appState.speechAssetStatus.activatedLocales.isEmpty
            ? String.appLocalized("settings.speech_assets.none")
            : appState.speechAssetStatus.activatedLocales
                .sorted { $0.displayName < $1.displayName }
                .map(\.displayName)
                .joined(separator: ", ")
    }
}

struct AboutSettingsView: View {
    @Bindable var appState: AppState
    let appVersion: String
    let deviceCapability: DeviceCapabilityService
    @Binding var showClearModelsAlert: Bool

    var body: some View {
        Form {
            Section {
                LabeledContent(String.appLocalized("common.version")) {
                    Text(appVersion)
                }
            } header: {
                SettingsSectionHeader(
                    title: String.appLocalized("settings.section.about"),
                    systemImage: "info.circle"
                )
            }

            Section {
                NavigationLink {
                    DeviceSettingsView(
                        appState: appState,
                        deviceCapability: deviceCapability,
                        showClearModelsAlert: $showClearModelsAlert
                    )
                } label: {
                    Label(String.appLocalized("settings.section.device"), systemImage: settingsDeviceSystemImage)
                }

                NavigationLink {
                    LegalTextView(
                        title: String.appLocalized("settings.about.terms"),
                        bodyText: String.appLocalized("settings.about.terms_body")
                    )
                } label: {
                    Label(String.appLocalized("settings.about.terms"), systemImage: "doc.text")
                }

                NavigationLink {
                    LegalTextView(
                        title: String.appLocalized("settings.about.privacy"),
                        bodyText: String.appLocalized("settings.about.privacy_body")
                    )
                } label: {
                    Label(String.appLocalized("settings.about.privacy"), systemImage: "hand.raised")
                }

                NavigationLink {
                    LicensesSettingsView()
                } label: {
                    Label(String.appLocalized("settings.about.licenses"), systemImage: "scroll")
                }
            }

            Section {
                Button(String.appLocalized("settings.replay_onboarding")) {
                    appState.resetOnboarding()
                }
            }
        }
        .imlxSettingsFormStyle()
        .navigationTitle(String.appLocalized("settings.section.about"))
    }
}

private struct DeviceSettingsView: View {
    @Bindable var appState: AppState
    let deviceCapability: DeviceCapabilityService
    @Binding var showClearModelsAlert: Bool

    var body: some View {
        Form {
            Section {
                LabeledContent(String.appLocalized("settings.physical_ram")) {
                    Text("\(deviceCapability.physicalMemoryGB) GB")
                }
                LabeledContent(String.appLocalized("settings.device_tier")) {
                    Text(deviceCapability.tier.displayName)
                }
                LabeledContent(String.appLocalized("settings.models_storage")) {
                    Text("\(appState.manifestService.totalStorageUsedGB, format: .number.precision(.fractionLength(2))) GB")
                }
            } header: {
                SettingsSectionHeader(
                    title: String.appLocalized("settings.section.device"),
                    systemImage: settingsDeviceSystemImage
                )
            }

            Section {
                Button(String.appLocalized("settings.clear_models"), role: .destructive) {
                    showClearModelsAlert = true
                }
            }
        }
        .imlxSettingsFormStyle()
        .navigationTitle(String.appLocalized("settings.section.device"))
    }
}

private struct LegalTextView: View {
    let title: String
    let bodyText: String

    var body: some View {
        ScrollView {
            Text(bodyText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
    }
}

private struct LicensesSettingsView: View {
    private let packages = [
        "GRDB.swift",
        "MLX Swift",
        "MLX Swift LM",
        "Swift Collections",
        "Swift Concurrency Extras",
        "Swift Jinja",
        "Swift Numerics",
        "Swift Syntax",
        "Swift Tokenizers",
        "Swift Tokenizers MLX",
        "SwiftUI Math",
        "Textual",
        "yyjson",
        "ZIPFoundation"
    ]

    var body: some View {
        List {
            Section {
                Text(String.appLocalized("settings.about.licenses_body"))
            }
            Section(String.appLocalized("settings.about.open_source_packages")) {
                ForEach(packages, id: \.self) { package in
                    Text(package)
                }
            }
        }
        .navigationTitle(String.appLocalized("settings.about.licenses"))
    }
}
