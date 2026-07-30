import SwiftUI
import UniformTypeIdentifiers

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

struct SettingsView: View {
    @Bindable var appState: AppState
    var showsCloseButton = true
    @State private var selection: MacSettingsTab = .general
    private let deviceCapability = DeviceCapabilityService()

    init(appState: AppState, showsCloseButton: Bool = true) {
        self.appState = appState
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        SettingsViewFacade(appState: appState) { showClearModelsAlert in
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
                            appVersion: SettingsMetadata.appVersion,
                            deviceCapability: deviceCapability,
                            showClearModelsAlert: showClearModelsAlert
                        )
                    }
                }
            }
        }
    }
}

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

let settingsDeviceSystemImage = "laptopcomputer"

extension View {
    func imlxSettingsFormStyle() -> some View {
        formStyle(.grouped)
    }
}

struct SettingsSectionHeader: View {
    let title: String
    var systemImage: String?

    var body: some View {
        Text(title)
    }
}
