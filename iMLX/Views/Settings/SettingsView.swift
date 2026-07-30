import SwiftUI
import UniformTypeIdentifiers

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
    @State private var showClearModelsAlert = false
    @State private var navigationDestination: SettingsNavigationDestination?
    @State private var hapticWarningTrigger = 0
    private let deviceCapability = DeviceCapabilityService()

    var body: some View {
        Group {
            #if os(macOS)
            MacSettingsRootView(
                appState: appState,
                deviceCapability: deviceCapability,
                showClearModelsAlert: $showClearModelsAlert
            )
            #else
            mobileSettingsContent
            #endif
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

    private var mobileSettingsContent: some View {
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
                    detail: appVersion,
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
                    appVersion: appVersion,
                    deviceCapability: deviceCapability,
                    showClearModelsAlert: $showClearModelsAlert
                )
            #if DEBUG
            case .profiling:
                LLMProfilingView(appState: appState)
            #endif
            }
        }
    }

    private func clearAllModels() {
        Task {
            await appState.clearAllDownloadedModels()
            hapticWarningTrigger += 1
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
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

#if os(macOS)
private enum MacSettingsTab: String, Hashable {
    case general
    case assistant
    case memory
    case speech
    #if DEBUG
    case profiling
    #endif
    case about
}

private struct MacSettingsRootView: View {
    @Bindable var appState: AppState
    let deviceCapability: DeviceCapabilityService
    @Binding var showClearModelsAlert: Bool
    @State private var selection: MacSettingsTab = .general

    var body: some View {
        TabView(selection: $selection) {
            Tab(String.appLocalized("settings.section.general"), systemImage: "gearshape", value: MacSettingsTab.general) {
                MacSettingsPane {
                    MacGeneralSettingsView(appState: appState)
                }
            }

            Tab(String.appLocalized("settings.assistant.title"), systemImage: "person.crop.circle", value: MacSettingsTab.assistant) {
                MacSettingsPane {
                    AssistantSettingsView(appState: appState)
                }
            }

            Tab(String.appLocalized("settings.manage_memory"), systemImage: "brain.head.profile", value: MacSettingsTab.memory) {
                MacSettingsPane(idealHeight: 560) {
                    MemoryLibraryView(appState: appState)
                }
            }

            Tab(String.appLocalized("settings.speech_assets.section"), systemImage: "waveform", value: MacSettingsTab.speech) {
                MacSettingsPane {
                    SpeechAssetsSettingsView(appState: appState)
                }
            }

            #if DEBUG
            Tab("LLM Profiling", systemImage: "gauge.with.dots.needle.67percent", value: MacSettingsTab.profiling) {
                MacSettingsPane(idealWidth: 640, idealHeight: 620) {
                    LLMProfilingView(appState: appState)
                }
            }
            #endif

            Tab(String.appLocalized("settings.section.about"), systemImage: "info.circle", value: MacSettingsTab.about) {
                MacSettingsPane {
                    AboutSettingsView(
                        appState: appState,
                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
                        deviceCapability: deviceCapability,
                        showClearModelsAlert: $showClearModelsAlert
                    )
                }
            }
        }
    }
}

/// Wraps a macOS settings pane so every tab gets its own navigation stack and a
/// consistent, resizable preferences-window footprint.
private struct MacSettingsPane<Content: View>: View {
    var idealWidth: CGFloat = 560
    var idealHeight: CGFloat = 480
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
        }
        .frame(
            minWidth: 500,
            idealWidth: idealWidth,
            maxWidth: .infinity,
            minHeight: 360,
            idealHeight: idealHeight,
            maxHeight: .infinity
        )
    }
}

private struct MacGeneralSettingsView: View {
    @Bindable var appState: AppState
    @State private var isChoosingModelsFolder = false
    @State private var modelsFolderError: String?

    var body: some View {
        Form {
            Section {
                Toggle(String.appLocalized("settings.focus_composer_on_launch"), isOn: Binding(
                    get: { appState.openKeyboardOnLaunch },
                    set: { appState.setOpenKeyboardOnLaunch($0) }
                ))

                LabeledContent(String.appLocalized("settings.section.language")) {
                    Button(String.appLocalized("settings.language.mac_system_settings_detail")) {
                        PlatformApplication.openLanguageSettings()
                    }
                }
            }

            Section {
                LabeledContent(String.appLocalized("settings.models.additional_folder")) {
                    Text(additionalModelsFolderDisplayPath)
                        .foregroundStyle(appState.additionalModelsFolderURL == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300, alignment: .trailing)
                }

                HStack {
                    Button(String.appLocalized("settings.models.choose_folder")) {
                        modelsFolderError = nil
                        isChoosingModelsFolder = true
                    }

                    if appState.additionalModelsFolderURL != nil {
                        Button(String.appLocalized("settings.models.rescan")) {
                            rescanAdditionalModels()
                        }

                        Button(
                            String.appLocalized("settings.models.remove_folder"),
                            role: .destructive
                        ) {
                            clearAdditionalModelsFolder()
                        }
                    }
                }

                if appState.additionalModelsFolderURL != nil {
                    Text(
                        String(
                            format: String.appLocalized("settings.models.detected_count"),
                            appState.additionalModelsCount
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let modelsFolderError {
                    Text(modelsFolderError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text(String.appLocalized("settings.models.section"))
            } footer: {
                Text(String.appLocalized("settings.models.additional_folder_help"))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String.appLocalized("settings.section.general"))
        .fileImporter(
            isPresented: $isChoosingModelsFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            chooseAdditionalModelsFolder(result)
        }
    }

    private var additionalModelsFolderDisplayPath: String {
        appState.additionalModelsFolderURL?.path
            ?? String.appLocalized("settings.models.no_folder")
    }

    private func chooseAdditionalModelsFolder(_ result: Result<[URL], Error>) {
        do {
            guard let folderURL = try result.get().first else { return }
            Task {
                do {
                    try await appState.setAdditionalModelsFolder(folderURL)
                    modelsFolderError = nil
                } catch {
                    modelsFolderError = error.localizedDescription
                }
            }
        } catch {
            modelsFolderError = error.localizedDescription
        }
    }

    private func rescanAdditionalModels() {
        Task {
            await appState.rescanAdditionalModelsFolder()
            modelsFolderError = nil
        }
    }

    private func clearAdditionalModelsFolder() {
        Task {
            await appState.clearAdditionalModelsFolder()
            modelsFolderError = nil
        }
    }
}
#endif

private struct SpeechAssetsSettingsView: View {
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

private struct AboutSettingsView: View {
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

private var settingsDeviceSystemImage: String {
    #if os(macOS)
    "laptopcomputer"
    #else
    "iphone"
    #endif
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

extension View {
    @ViewBuilder
    func imlxSettingsFormStyle() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }
}

private struct SettingsSectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        #if os(macOS)
        Text(title)
        #else
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
        #endif
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
