import SwiftUI

struct PersonaLibraryView: View {
    let appState: AppState

    @State private var editingPersona: Persona?
    @State private var isCreatingPersona = false

    private var starterPersonas: [Persona] {
        appState.personas.filter(\.isBuiltIn)
    }

    private var customPersonas: [Persona] {
        appState.personas.filter { !$0.isBuiltIn }
    }

    var body: some View {
        List {
            Section {
                Text(String.appLocalized("persona.library.intro"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !starterPersonas.isEmpty {
                Section(String.appLocalized("persona.section.starters")) {
                    ForEach(starterPersonas) { persona in
                        personaRow(persona)
                    }
                }
            }

            Section(String.appLocalized("persona.section.custom")) {
                if customPersonas.isEmpty {
                    Text(String.appLocalized("persona.no_custom"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(customPersonas) { persona in
                        personaRow(persona)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.deletePersona(persona.id)
                                } label: {
                                    Label(String.appLocalized("common.delete"), systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(String.appLocalized("persona.library.title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isCreatingPersona = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingPersona) { persona in
            NavigationStack {
                PersonaEditorView(appState: appState, persona: persona)
            }
        }
        .sheet(isPresented: $isCreatingPersona) {
            NavigationStack {
                PersonaEditorView(appState: appState)
            }
        }
    }

    private func personaRow(_ persona: Persona) -> some View {
        Button {
            editingPersona = persona
        } label: {
            HStack(spacing: 12) {
                Image(systemName: persona.symbolName)
                    .font(.title3)
                    .foregroundStyle(BrandPalette.primaryGradient)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(persona.localizedName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if persona.isBuiltIn {
                            Text(String.appLocalized("persona.starter_badge"))
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .liquidGlassSurface(in: Capsule(), fallback: AnyShapeStyle(.fill.tertiary))
                        }
                    }

                    Text(persona.localizedDisplaySummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    if let modelId = persona.defaultModelId,
                       let model = Constants.ModelRegistry.curatedModels.first(where: { $0.id == modelId }) {
                        Text(String(format: String.appLocalized("persona.prefers_model"), model.displayName))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
