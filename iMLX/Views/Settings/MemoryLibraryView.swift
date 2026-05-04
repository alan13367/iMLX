import SwiftUI

struct MemoryLibraryView: View {
    let appState: AppState
    var onClose: (() -> Void)?

    @State private var editingMemory: UserMemory?
    @State private var selectedMemoryDetail: MemoryDetail?
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
                    ContentUnavailableView(
                        String.appLocalized("memory.pending.empty"),
                        systemImage: "brain.head.profile"
                    )
                } else {
                    ForEach(pendingMemories) { memory in
                        MemorySummaryRow(
                            memory: memory,
                            onEdit: { edit(memory) },
                            onTap: { showDetail(for: memory) },
                            onAccept: { appState.acceptMemory(id: memory.id) },
                            onReject: { appState.rejectMemory(id: memory.id) }
                        )
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
                    ContentUnavailableView(
                        String.appLocalized("memory.saved.empty"),
                        systemImage: "checkmark.circle"
                    )
                } else {
                    ForEach(activeMemories) { memory in
                        MemorySummaryRow(
                            memory: memory,
                            onEdit: { edit(memory) },
                            onTap: { showDetail(for: memory) },
                            onAccept: {},
                            onReject: {}
                        )
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
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        CloseButtonLabel()
                    }
                    .accessibilityLabel(String.appLocalized("common.close"))
                }
            }
        }
        .sheet(item: $editingMemory) { memory in
            NavigationStack {
                MemoryEditorView(appState: appState, memory: memory)
            }
        }
        .sheet(item: $selectedMemoryDetail) { detail in
            NavigationStack {
                MemoryDetailView(
                    appState: appState,
                    detail: detail,
                    onEdit: { editingMemory = detail.summary }
                )
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

    private func edit(_ memory: UserMemory) {
        editingMemory = memory
    }

    private func showDetail(for memory: UserMemory) {
        selectedMemoryDetail = appState.memoryDetail(id: memory.id)
    }
}

private struct MemorySummaryRow: View {
    let memory: UserMemory
    let onEdit: () -> Void
    let onTap: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(memory.content)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            MemoryMetaRow(memory: memory, onEdit: onEdit)

            if memory.status == .pending {
                MemoryPendingActions(onAccept: onAccept, onReject: onReject)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private struct MemoryMetaRow: View {
    let memory: UserMemory
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Label(
                    memory.captureType.displayName,
                    systemImage: memory.captureType == .explicit ? "pin.fill" : "sparkles"
                )
                Text(memory.displayCategory)
                Text(memory.updatedRelativeDate)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Button(String.appLocalized("memory.edit"), action: onEdit)
                .font(.caption.weight(.semibold))
        }
    }
}

private struct MemoryPendingActions: View {
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(String.appLocalized("memory.accept"), action: onAccept)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            Button(String.appLocalized("memory.reject"), role: .destructive, action: onReject)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

private struct MemoryEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    let memory: UserMemory

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
            MemoryEditorMemorySection(content: $content)
            MemoryEditorDetailsSection(
                appState: appState,
                category: $category,
                status: $status,
                personaScope: $personaScope
            )
            MemoryEditorMetadataSection(memory: memory)
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
        updated.category = trimmedCategory
        updated.status = status
        updated.personaId = personaScope.isEmpty ? nil : personaScope
        appState.updateMemory(updated)
        dismiss()
    }

    private var trimmedCategory: String? {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct MemoryEditorMemorySection: View {
    @Binding var content: String

    var body: some View {
        Section(String.appLocalized("memory.editor.section.memory")) {
            TextField(String.appLocalized("memory.editor.content"), text: $content, axis: .vertical)
                .lineLimit(3...8)
        }
    }
}

private struct MemoryEditorDetailsSection: View {
    let appState: AppState
    @Binding var category: String
    @Binding var status: UserMemoryStatus
    @Binding var personaScope: String

    var body: some View {
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
    }
}

private struct MemoryEditorMetadataSection: View {
    let memory: UserMemory

    var body: some View {
        Section {
            LabeledContent(String.appLocalized("memory.capture.type")) {
                Text(memory.captureType.displayName)
            }
            LabeledContent(String.appLocalized("memory.usage_count")) {
                Text("\(memory.usageCount)")
            }
        }
    }
}

private struct MemoryDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState
    let detail: MemoryDetail
    let onEdit: () -> Void

    var body: some View {
        List {
            MemoryDetailSummarySection(detail: detail)
            MemoryDetailMetadataSection(detail: detail)

            if !detail.evidence.isEmpty {
                MemoryEvidenceSection(evidence: detail.evidence)
            }

            if !detail.recentRetrievalExplanations.isEmpty {
                MemoryRetrievalExplanationSection(explanations: detail.recentRetrievalExplanations)
            }

            if let trace = detail.latestRetrievalTrace {
                MemoryRetrievalDiagnosticsSection(trace: trace, detailID: detail.id)
            }

            MemoryDetailActionsSection(
                detail: detail,
                appState: appState,
                onDismiss: dismiss.callAsFunction,
                onEdit: {
                    dismiss()
                    onEdit()
                }
            )
        }
        .navigationTitle("Memory Detail")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String.appLocalized("common.done")) {
                    dismiss()
                }
            }
        }
    }
}

private struct MemoryDetailSummarySection: View {
    let detail: MemoryDetail

    var body: some View {
        Section {
            Text(detail.summary.content)
                .font(.body)

            if let relation = detail.summary.factRelation, !relation.isEmpty {
                LabeledContent("Relation") {
                    Text(relation)
                }
            }
            if let value = detail.summary.factValue, !value.isEmpty {
                LabeledContent("Value") {
                    Text(value)
                }
            }
        }
    }
}

private struct MemoryDetailMetadataSection: View {
    let detail: MemoryDetail

    var body: some View {
        Section("Details") {
            LabeledContent(String.appLocalized("memory.capture.type")) {
                Text(detail.summary.captureType.displayName)
            }
            LabeledContent(String.appLocalized("memory.editor.status")) {
                Text(detail.summary.status.displayName)
            }
            LabeledContent(String.appLocalized("memory.editor.scope")) {
                Text(detail.scopeType.displayName)
            }
            LabeledContent("Confidence") {
                Text(detail.confidence.formatted(.percent.precision(.fractionLength(0))))
            }
            LabeledContent("Salience") {
                Text(detail.salience.formatted(.number.precision(.fractionLength(2))))
            }
            LabeledContent(String.appLocalized("memory.usage_count")) {
                Text("\(detail.summary.usageCount)")
            }
        }
    }
}

private struct MemoryEvidenceSection: View {
    let evidence: [MemoryEvidence]

    var body: some View {
        Section("Evidence") {
            ForEach(evidence) { evidence in
                VStack(alignment: .leading, spacing: 6) {
                    Text(evidence.sourceQuote)
                        .font(.body)
                    HStack(spacing: 8) {
                        if let language = evidence.sourceLanguageCode {
                            Text(language.uppercased())
                        }
                        if let conversationID = evidence.sourceConversationId {
                            Text(conversationID.uuidString.prefix(8))
                        }
                        Text(evidence.createdAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct MemoryRetrievalExplanationSection: View {
    let explanations: [MemoryRetrievalExplanation]

    var body: some View {
        Section("Why it was retrieved") {
            ForEach(explanations) { explanation in
                VStack(alignment: .leading, spacing: 4) {
                    Text(explanation.message)
                    Text(explanation.kind.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct MemoryRetrievalDiagnosticsSection: View {
    let trace: MemoryRetrievalTrace
    let detailID: UUID

    var body: some View {
        Section("Retrieval diagnostics") {
            LabeledContent("Candidate count") {
                Text("\(trace.candidateCount)")
            }
            LabeledContent("Selected IDs") {
                Text(trace.selectedMemoryIDs.map { $0.uuidString.prefix(6) }.joined(separator: ", "))
            }
            if let breakdown = trace.scoreBreakdown[detailID] {
                ForEach(breakdown.keys.sorted(), id: \.self) { key in
                    LabeledContent(key.capitalized) {
                        Text((breakdown[key] ?? 0).formatted(.number.precision(.fractionLength(2))))
                    }
                }
            }
        }
    }
}

private struct MemoryDetailActionsSection: View {
    let detail: MemoryDetail
    let appState: AppState
    let onDismiss: () -> Void
    let onEdit: () -> Void

    var body: some View {
        Section("Actions") {
            Button(String.appLocalized("memory.edit"), action: onEdit)

            if detail.summary.status == .pending {
                Button("Keep") {
                    appState.acceptMemory(id: detail.id)
                    onDismiss()
                }
            }

            Button(
                detail.summary.status == .archived ? "Keep Archived" : "Archive",
                role: detail.summary.status == .archived ? nil : .destructive
            ) {
                appState.rejectMemory(id: detail.id)
                onDismiss()
            }

            Button("Forget") {
                _ = appState.forgetMemory(matching: detail.summary.content)
                onDismiss()
            }

            if appState.canBlockMemoryRelation(detail.summary.factRelation),
               let relation = detail.summary.factRelation {
                let isBlocked = appState.isMemoryRelationBlocked(relation)
                Button(isBlocked ? "Allow this memory type" : "Never remember this type") {
                    appState.setMemoryRelationBlocked(relation, blocked: !isBlocked)
                }
            }
        }
    }
}

#Preview("Memory Row") {
    List {
        MemorySummaryRow(
            memory: UserMemory(
                content: "User prefers deep-dive architecture explanations.",
                status: .pending,
                captureType: .inferred,
                category: "Preferences"
            ),
            onEdit: {},
            onTap: {},
            onAccept: {},
            onReject: {}
        )
    }
}
