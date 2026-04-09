import SwiftUI

struct OnboardingFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var selectedModelID: String?
    @State private var isStartingDownload = false

    let appState: AppState

    private let steps = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                progressHeader

                Group {
                    switch step {
                    case 0:
                        welcomeStep
                    case 1:
                        modelSelectionStep
                    case 2:
                        personasAndMemoryStep
                    case 3:
                        documentsAndVisionStep
                    default:
                        finishStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                footer
            }
            .padding(24)
            .navigationBarBackButtonHidden(true)
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Welcome to iMLX")
                .font(.largeTitle.weight(.bold))
            ProgressView(value: Double(step + 1), total: Double(steps))
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingCard(
                title: "Local-first by default",
                body: "iMLX runs your chat models on-device. Your conversations, personas, documents, and memories stay on your Apple hardware unless you explicitly turn on a network feature."
            )
            onboardingCard(
                title: "Privacy before convenience",
                body: "Web search is opt-in per conversation, and starter model downloads happen only when you choose them."
            )
            onboardingCard(
                title: "Built for your device",
                body: "We’ll recommend a small starter set of models based on this device’s memory tier so setup stays smooth."
            )
        }
    }

    private var modelSelectionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recommended starter models")
                .font(.title2.weight(.semibold))
            Text("Choose one model to download now, or skip and browse models later.")
                .foregroundStyle(.secondary)

            ForEach(appState.recommendedStarterModels()) { model in
                Button {
                    selectedModelID = model.id
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(model.displayName)
                                    .font(.headline)
                                if appState.recommendedStarterModels().first?.id == model.id {
                                    Text("Recommended")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(BrandPalette.accent.opacity(0.15), in: Capsule())
                                }
                            }
                            Text("\(model.parameterCount) • \(String(format: "%.1f GB", model.estimatedSizeGB)) • \(model.supportsVision ? "Vision" : "Text only")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: selectedModelID == model.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedModelID == model.id ? BrandPalette.accent : .secondary)
                    }
                    .padding(16)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var personasAndMemoryStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingCard(
                title: "Personas shape the assistant",
                body: "Each conversation can use a different persona, changing tone, focus, and prompting without swapping your model automatically."
            )
            onboardingCard(
                title: "Memory stays local",
                body: "iMLX can infer useful memories from your chats, but pending memories stay reviewable before they become active."
            )
        }
    }

    private var documentsAndVisionStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingCard(
                title: "Documents are grounded locally",
                body: "Attach PDFs, CSVs, or text files to a conversation and iMLX retrieves relevant excerpts on-device before answering."
            )
            onboardingCard(
                title: "Vision depends on the model",
                body: "Only vision-capable models can work with photos. You can swap later if you need image understanding in a conversation."
            )
        }
    }

    private var finishStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            onboardingCard(
                title: "You’re ready",
                body: "Start chatting as soon as your model is loaded, or keep exploring personas, memory, and documents from the main app."
            )

            if let pendingModelID = appState.pendingStarterModelId,
               let snapshot = appState.modelDownloadSnapshots[pendingModelID],
               let model = appState.recommendedStarterModels().first(where: { $0.id == pendingModelID }) {
                onboardingCard(
                    title: "Starter model downloading",
                    body: "\(model.displayName) is downloading in the background.\n\n\(snapshot.displayStatus)"
                )
            } else if let selectedModelID,
                      appState.manifestService.isDownloaded(modelId: selectedModelID),
                      let model = appState.recommendedStarterModels().first(where: { $0.id == selectedModelID }) {
                onboardingCard(
                    title: "Starter model ready",
                    body: "\(model.displayName) finished downloading and is ready to load."
                )
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if step == 1 {
                if let selectedModel {
                    Button {
                        Task {
                            await startStarterDownload(selectedModel)
                        }
                    } label: {
                        if isStartingDownload {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(downloadButtonTitle(for: selectedModel))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStartingDownload)
                }

                Button("Skip for now") {
                    advance()
                }
                .buttonStyle(.bordered)
            } else {
                Button(step == steps - 1 ? "Start Using iMLX" : "Continue") {
                    if step == steps - 1 {
                        appState.markOnboardingCompleted()
                        dismiss()
                    } else {
                        advance()
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            if step > 0 && step < steps - 1 {
                Button("Back") {
                    step = max(step - 1, 0)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedModel: ModelInfo? {
        guard let selectedModelID else { return nil }
        return appState.recommendedStarterModels().first(where: { $0.id == selectedModelID })
    }

    private func onboardingCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func advance() {
        step = min(step + 1, steps - 1)
    }

    private func startStarterDownload(_ model: ModelInfo) async {
        isStartingDownload = true
        defer { isStartingDownload = false }
        do {
            try await appState.startStarterModelDownload(model)
            advance()
        } catch {
        }
    }

    private func downloadButtonTitle(for model: ModelInfo) -> String {
        if let snapshot = appState.modelDownloadSnapshots[model.id] {
            return snapshot.displayStatus
        }
        return "Download \(model.displayName)"
    }
}
