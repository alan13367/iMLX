import SwiftUI

struct MemoryLibraryView: View {
    let appState: AppState

    @State private var editingMemory: UserMemory?
    @State private var showClearAlert = false

    private var pendingMemories: [UserMemory] {
        appState.memories.filter { $0.status == .pending }
    }

    private var activeMemories: [UserMemory] {
        appState.memories.filter { $0.status == .active }
    }

    var body: some View {
        List {
            Section {
                Text(String.appLocalized("memory.library.intro"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(String.appLocalized("memory.section.pending")) {
                if pendingMemories.isEmpty {
                    Text(String.appLocalized("memory.pending.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pendingMemories) { memory in
                        memoryRow(memory)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.rejectMemory(id: memory.id)
                                } label: {
                                    Label(String.appLocalized("memory.reject"), systemImage: "xmark")
                                }
                                Button {
                                    appState.acceptMemory(id: memory.id)
                                } label: {
                                    Label(String.appLocalized("memory.accept"), systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                    }
                }
            }

            Section(String.appLocalized("memory.section.saved")) {
                if activeMemories.isEmpty {
                    Text(String.appLocalized("memory.saved.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeMemories) { memory in
                        memoryRow(memory)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.deleteMemory(id: memory.id)
                                } label: {
                                    Label(String.appLocalized("common.delete"), systemImage: "trash")
                                }
                            }
                    }
                }
            }

            if !appState.memories.isEmpty {
                Section {
                    Button(String.appLocalized("memory.clear_all"), role: .destructive) {
                        showClearAlert = true
                    }
                }
            }
        }
        .navigationTitle(String.appLocalized("memory.library.title"))
        .sheet(item: $editingMemory) { memory in
            NavigationStack {
                MemoryEditorView(appState: appState, memory: memory)
            }
        }
        .alert(String.appLocalized("memory.clear_alert_title"), isPresented: $showClearAlert) {
            Button(String.appLocalized("common.cancel"), role: .cancel) {}
            Button(String.appLocalized("memory.clear_all"), role: .destructive) {
                appState.clearAllMemories()
            }
        } message: {
            Text(String.appLocalized("memory.clear_alert_message"))
        }
    }

    private func memoryRow(_ memory: UserMemory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(memory.content)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Label(memory.captureType.displayName, systemImage: memory.captureType == .explicit ? "pin.fill" : "sparkles")
                    Text(memory.displayCategory)
                    Text(memory.updatedRelativeDate)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Button(String.appLocalized("memory.edit")) {
                    editingMemory = memory
                }
                .font(.caption.weight(.semibold))
            }

            if memory.status == .pending {
                HStack(spacing: 12) {
                    Button(String.appLocalized("memory.accept")) {
                        appState.acceptMemory(id: memory.id)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(String.appLocalized("memory.reject"), role: .destructive) {
                        appState.rejectMemory(id: memory.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MemoryEditorView: View {
    let appState: AppState
    let memory: UserMemory

    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var category: String
    @State private var status: UserMemoryStatus
    @State private var personaScope: String

    init(appState: AppState, memory: UserMemory) {
        self.appState = appState
        self.memory = memory
        _content = State(initialValue: memory.content)
        _category = State(initialValue: memory.category ?? "")
        _status = State(initialValue: memory.status)
        _personaScope = State(initialValue: memory.personaId ?? "")
    }

    var body: some View {
        Form {
            Section(String.appLocalized("memory.editor.section.memory")) {
                TextField(String.appLocalized("memory.editor.content"), text: $content, axis: .vertical)
                    .lineLimit(3...8)
            }

            Section(String.appLocalized("memory.editor.section.details")) {
                TextField(String.appLocalized("memory.editor.category"), text: $category)

                Picker(String.appLocalized("memory.editor.status"), selection: $status) {
                    ForEach(UserMemoryStatus.allCases, id: \.self) { status in
                        Text(status.displayName).tag(status)
                    }
                }

                Picker(String.appLocalized("memory.editor.scope"), selection: $personaScope) {
                    Text(String.appLocalized("memory.scope.global")).tag("")
                    ForEach(appState.personas) { persona in
                        Text(persona.localizedName).tag(persona.id)
                    }
                }
            }

            Section {
                LabeledContent(String.appLocalized("memory.capture.type")) {
                    Text(memory.captureType.displayName)
                }
                LabeledContent(String.appLocalized("memory.usage_count")) {
                    Text("\(memory.usageCount)")
                }
            }
        }
        .navigationTitle(String.appLocalized("memory.editor.title"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String.appLocalized("common.cancel")) {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String.appLocalized("common.save")) {
                    save()
                }
                .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        var updated = memory
        updated.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.category = category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : category.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.status = status
        updated.personaId = personaScope.isEmpty ? nil : personaScope
        appState.updateMemory(updated)
        dismiss()
    }
}
