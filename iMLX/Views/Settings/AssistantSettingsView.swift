import SwiftUI

struct AssistantSettingsView: View {
    @Bindable var appState: AppState

    private let temperatureOptions: [Double] = [0.0, 0.3, 0.5, 0.7, 1.0]

    var body: some View {
        Form {
            Section {
                TextField(
                    String.appLocalized("settings.assistant.system_prompt"),
                    text: Binding(
                        get: { appState.assistantSystemPrompt },
                        set: { appState.setAssistantSystemPrompt($0) }
                    ),
                    axis: .vertical
                )
                .lineLimit(4...10)
            } header: {
                Text(String.appLocalized("settings.assistant.system_prompt"))
            }

            Section {
                Picker(
                    String.appLocalized("settings.assistant.temperature"),
                    selection: Binding(
                        get: { appState.assistantTemperature },
                        set: { appState.setAssistantTemperature($0) }
                    )
                ) {
                    ForEach(temperatureOptions, id: \.self) { value in
                        Text(value, format: .number.precision(.fractionLength(1)))
                            .tag(value)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text(String.appLocalized("settings.assistant.temperature"))
            } footer: {
                Text(String.appLocalized("settings.assistant.temperature_description"))
            }

            Section {
                Button(String.appLocalized("settings.assistant.reset")) {
                    appState.resetAssistantGenerationSettings()
                }
            }
        }
        .navigationTitle(String.appLocalized("settings.assistant.title"))
    }
}
