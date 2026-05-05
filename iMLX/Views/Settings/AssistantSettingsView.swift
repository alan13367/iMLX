import SwiftUI

struct AssistantSettingsView: View {
    @Bindable var appState: AppState

    private struct TemperatureOption: Hashable {
        let value: Double
        let label: String
    }

    private let temperatureOptions: [TemperatureOption] = [
        TemperatureOption(value: 0.0, label: String.appLocalized("settings.assistant.temperature.label.0_0")),
        TemperatureOption(value: 0.3, label: String.appLocalized("settings.assistant.temperature.label.0_3")),
        TemperatureOption(value: 0.5, label: String.appLocalized("settings.assistant.temperature.label.0_5")),
        TemperatureOption(value: 0.8, label: String.appLocalized("settings.assistant.temperature.label.0_8")),
        TemperatureOption(value: 1.0, label: String.appLocalized("settings.assistant.temperature.label.1_0"))
    ]

    var body: some View {
        Form {
            Section {
                Toggle(
                    String.appLocalized("settings.assistant.personalization.enabled"),
                    isOn: Binding(
                        get: { appState.assistantPersonalizationEnabled },
                        set: { appState.setAssistantPersonalizationEnabled($0) }
                    )
                )

                if appState.assistantPersonalizationEnabled {
                    TextField(
                        String.appLocalized("settings.assistant.prompt"),
                        text: Binding(
                            get: { displayedAssistantPrompt },
                            set: { appState.setAssistantSystemPrompt($0) }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(4...10)

                    Picker(
                        String.appLocalized("settings.assistant.temperature"),
                        selection: Binding(
                            get: { appState.assistantTemperature },
                            set: { appState.setAssistantTemperature($0) }
                        )
                    ) {
                        ForEach(temperatureOptions, id: \.value) { option in
                            Text("\(option.value, format: .number.precision(.fractionLength(1))) - \(option.label)")
                                .tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text(String.appLocalized("settings.assistant.personalization"))
            } footer: {
                Text(String.appLocalized("settings.assistant.personalization_description"))
            }

            Section {
                Button(String.appLocalized("settings.assistant.reset")) {
                    appState.resetAssistantGenerationSettings()
                }
            }
        }
        .navigationTitle(String.appLocalized("settings.assistant.title"))
    }

    private var displayedAssistantPrompt: String {
        let stored = appState.assistantSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultPrompt = Constants.Generation.defaultSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return stored == defaultPrompt ? "" : appState.assistantSystemPrompt
    }
}
