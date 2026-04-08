import SwiftUI

struct PersonaPickerSheet: View {
    let appState: AppState
    let chatViewModel: ChatViewModel
    @Binding var isPresented: Bool

    @State private var isCreatingPersona = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(String.appLocalized("persona.picker.intro"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(String.appLocalized("persona.section.available")) {
                    ForEach(appState.personas) { persona in
                        Button {
                            chatViewModel.selectPersona(persona)
                            isPresented = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: persona.symbolName)
                                    .font(.title3)
                                    .foregroundStyle(BrandPalette.primaryGradient)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(persona.localizedName)
                                        .foregroundStyle(.primary)
                                    Text(persona.localizedDisplaySummary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(2)
                                }

                                Spacer()

                                if chatViewModel.activePersona.id == persona.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(String.appLocalized("persona.picker.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String.appLocalized("common.done")) {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreatingPersona = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isCreatingPersona) {
            NavigationStack {
                PersonaEditorView(appState: appState) { persona in
                    chatViewModel.selectPersona(persona)
                }
            }
        }
    }
}
