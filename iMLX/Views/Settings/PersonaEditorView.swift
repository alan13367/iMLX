import SwiftUI

private struct PersonaDraft {
    let id: String
    let createdAt: Date
    var name: String
    var summary: String
    var goal: String
    var tone: PersonaTone
    var suggestedOpening: String
    var defaultModelId: String?
    var temperature: Double
    var topP: Double
    var repetitionPenalty: Double
    var systemPrompt: String
    var usesCustomSystemPrompt: Bool
    var symbolName: String
    var isBuiltIn: Bool

    init(persona: Persona? = nil) {
        if let persona {
            id = persona.id
            createdAt = persona.createdAt
            name = persona.name
            summary = persona.summary
            goal = persona.goal
            tone = persona.tone
            suggestedOpening = persona.suggestedOpening
            defaultModelId = persona.defaultModelId
            temperature = persona.temperature
            topP = persona.topP
            repetitionPenalty = persona.repetitionPenalty
            systemPrompt = persona.systemPrompt
            usesCustomSystemPrompt = persona.usesCustomSystemPrompt
            symbolName = persona.symbolName
            isBuiltIn = persona.isBuiltIn
        } else {
            id = "persona-\(UUID().uuidString.lowercased())"
            createdAt = Date()
            name = ""
            summary = ""
            goal = ""
            tone = .balanced
            suggestedOpening = ""
            defaultModelId = nil
            temperature = Double(Constants.Generation.defaultTemperature)
            topP = Double(Constants.Generation.defaultTopP)
            repetitionPenalty = Double(Constants.Generation.defaultRepetitionPenalty)
            systemPrompt = ""
            usesCustomSystemPrompt = false
            symbolName = "person.crop.circle"
            isBuiltIn = false
        }
    }

    var generatedPromptPreview: String {
        Persona.generatedSystemPrompt(
            name: trimmedName.isEmpty ? "Helpful Assistant" : trimmedName,
            summary: summary,
            goal: goal,
            tone: tone
        )
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedGoal: String {
        goal.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isValid: Bool {
        !trimmedName.isEmpty && !trimmedGoal.isEmpty
    }

    func persona() -> Persona {
        Persona(
            id: id,
            name: trimmedName,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            goal: trimmedGoal,
            tone: tone,
            suggestedOpening: suggestedOpening.trimmingCharacters(in: .whitespacesAndNewlines),
            defaultModelId: defaultModelId,
            temperature: temperature,
            topP: topP,
            repetitionPenalty: repetitionPenalty,
            systemPrompt: usesCustomSystemPrompt ? systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines) : generatedPromptPreview,
            usesCustomSystemPrompt: usesCustomSystemPrompt,
            symbolName: symbolName,
            isBuiltIn: isBuiltIn,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

struct PersonaEditorView: View {
    let appState: AppState
    let existingPersona: Persona?
    var onSave: ((Persona) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var draft: PersonaDraft

    init(appState: AppState, persona: Persona? = nil, onSave: ((Persona) -> Void)? = nil) {
        self.appState = appState
        self.existingPersona = persona
        self.onSave = onSave
        _draft = State(initialValue: PersonaDraft(persona: persona))
    }

    var body: some View {
        Form {
            Section(String.appLocalized("persona.editor.section.basics")) {
                TextField(String.appLocalized("persona.editor.name"), text: $draft.name)
                TextField(String.appLocalized("persona.editor.summary"), text: $draft.summary)
                TextField(String.appLocalized("persona.editor.example_request"), text: $draft.suggestedOpening, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section(String.appLocalized("persona.editor.section.goal")) {
                TextField(
                    String.appLocalized("persona.editor.goal_placeholder"),
                    text: $draft.goal,
                    axis: .vertical
                )
                .lineLimit(4...8)
            }

            Section(String.appLocalized("persona.editor.section.style")) {
                Picker(String.appLocalized("persona.editor.tone"), selection: $draft.tone) {
                    ForEach(PersonaTone.allCases) { tone in
                        Text(tone.displayName).tag(tone)
                    }
                }
            }

            Section {
                Toggle(String.appLocalized("persona.editor.toggle_custom_prompt"), isOn: $draft.usesCustomSystemPrompt)

                if draft.usesCustomSystemPrompt {
                    TextField(String.appLocalized("persona.editor.system_prompt"), text: $draft.systemPrompt, axis: .vertical)
                        .lineLimit(6...14)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String.appLocalized("persona.editor.prompt_preview"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(draft.generatedPromptPreview)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(String.appLocalized("persona.editor.creativity"))
                        Spacer()
                        Text("\(draft.temperature, specifier: "%.1f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $draft.temperature, in: 0.0...2.0, step: 0.1)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(String.appLocalized("persona.editor.focus"))
                        Spacer()
                        Text("\(draft.topP, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $draft.topP, in: 0.0...1.0, step: 0.05)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(String.appLocalized("persona.editor.repetition"))
                        Spacer()
                        Text("\(draft.repetitionPenalty, specifier: "%.1f")")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $draft.repetitionPenalty, in: 0.9...2.0, step: 0.1)
                }
            } header: {
                Text(String.appLocalized("persona.editor.advanced"))
            } footer: {
                Text(String.appLocalized("persona.editor.advanced_footer"))
            }
        }
        .navigationTitle(existingPersona == nil
            ? String.appLocalized("persona.editor.new_title")
            : String.appLocalized("persona.editor.edit_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String.appLocalized("common.cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String.appLocalized("common.save")) {
                    savePersona()
                }
                .disabled(!draft.isValid)
            }
        }
    }

    private func savePersona() {
        let persona = draft.persona()
        appState.savePersona(persona)
        onSave?(persona)
        dismiss()
    }
}
