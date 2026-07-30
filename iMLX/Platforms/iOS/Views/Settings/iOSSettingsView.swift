import SwiftUI

private enum SettingsNavigationDestination: String, Hashable {
    case memory
    case personalization
    case speechAssets
    case about
    #if DEBUG
    case profiling
    #endif
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var appState: AppState
    var showsCloseButton = true
    @State private var navigationDestination: SettingsNavigationDestination?
    private let deviceCapability = DeviceCapabilityService()

    init(appState: AppState, showsCloseButton: Bool = true) {
        self.appState = appState
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        SettingsViewFacade(appState: appState) { showClearModelsAlert in
            Form {
                Section {
                    Button {
                        PlatformApplication.openLanguageSettings()
                    } label: {
                        SettingsValueRow(
                            title: String.appLocalized("settings.section.language"),
                            detail: String.appLocalized("settings.language.system_settings_detail"),
                            systemImage: "globe"
                        )
                    }
                    .buttonStyle(.plain)

                    Toggle(isOn: Binding(
                        get: { appState.openKeyboardOnLaunch },
                        set: { appState.setOpenKeyboardOnLaunch($0) }
                    )) {
                        Label {
                            Text(String.appLocalized("settings.open_keyboard_on_launch"))
                        } icon: {
                            Image(systemName: "keyboard")
                                .foregroundStyle(.primary)
                        }
                    }
                } header: {
                    SettingsSectionHeader(title: String.appLocalized("settings.section.app"))
                }

                Section {
                    SettingsNavigationRow(
                        title: String.appLocalized("settings.assistant.title"),
                        detail: personalizationSettingsSummary,
                        systemImage: "person.crop.circle"
                    ) {
                        navigationDestination = .personalization
                    }

                    SettingsNavigationRow(
                        title: String.appLocalized("settings.manage_memory"),
                        detail: memoryDetailText,
                        systemImage: "brain.head.profile"
                    ) {
                        navigationDestination = .memory
                    }

                    SettingsNavigationRow(
                        title: String.appLocalized("settings.speech_assets.section"),
                        detail: speechAssetsSummary,
                        systemImage: "waveform"
                    ) {
                        navigationDestination = .speechAssets
                    }
                } header: {
                    SettingsSectionHeader(title: String.appLocalized("settings.section.system"))
                }

                #if DEBUG
                Section {
                    SettingsNavigationRow(
                        title: "LLM Profiling",
                        detail: profilingDetail,
                        systemImage: "gauge.with.dots.needle.67percent"
                    ) {
                        navigationDestination = .profiling
                    }
                } header: {
                    SettingsSectionHeader(title: "Developer")
                }
                #endif

                Section {
                    SettingsNavigationRow(
                        title: String.appLocalized("settings.section.about"),
                        detail: SettingsMetadata.appVersion,
                        systemImage: "info.circle"
                    ) {
                        navigationDestination = .about
                    }
                } header: {
                    SettingsSectionHeader(title: String.appLocalized("settings.section.about"))
                }
            }
            .navigationTitle(String.appLocalized("settings.title"))
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .imlxTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            CloseButtonLabel()
                        }
                        .accessibilityLabel(String.appLocalized("common.close"))
                    }
                }
            }
            .navigationDestination(item: $navigationDestination) { destination in
                switch destination {
                case .memory:
                    MemoryLibraryView(appState: appState)
                case .personalization:
                    AssistantSettingsView(appState: appState)
                case .speechAssets:
                    SpeechAssetsSettingsView(appState: appState)
                case .about:
                    AboutSettingsView(
                        appState: appState,
                        appVersion: SettingsMetadata.appVersion,
                        deviceCapability: deviceCapability,
                        showClearModelsAlert: showClearModelsAlert
                    )
                #if DEBUG
                case .profiling:
                    LLMProfilingView(appState: appState)
                #endif
                }
            }
        }
    }

    private var speechAssetsSummary: String {
        appState.speechAssetStatus.hasCoreModel
            ? String.appLocalized("settings.speech_assets.installed")
            : String.appLocalized("settings.speech_assets.not_installed")
    }

    private var personalizationSettingsSummary: String {
        guard appState.assistantPersonalizationEnabled else {
            return String.appLocalized("settings.assistant.personalization.off")
        }
        return appState.assistantTemperature.formatted(.number.precision(.fractionLength(1)))
    }

    private var memoryDetailText: String {
        let pendingCount = appState.memories.count(where: { $0.status == .pending })
        let activeCount = appState.memories.count(where: { $0.status == .active })
        if pendingCount > 0 {
            return String(format: String.appLocalized("settings.manage_memory_detail_pending"), activeCount, pendingCount)
        }
        return String(format: String.appLocalized("settings.manage_memory_detail"), activeCount)
    }

    #if DEBUG
    private var profilingDetail: String {
        guard let profile = appState.latestLLMExecutionProfile else {
            return "No run yet"
        }
        return [
            LLMProfileFormatters.duration(profile.totalInferenceDuration),
            LLMProfileFormatters.characterRate(profile.outputCharactersPerSecond)
        ].joined(separator: " · ")
    }
    #endif
}

let settingsDeviceSystemImage = "iphone"

extension View {
    func imlxSettingsFormStyle() -> some View {
        self
    }
}

struct SettingsSectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        Label {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer()
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsNavigationRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
