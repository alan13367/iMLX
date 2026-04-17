import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case modelSelection
    case personasAndMemory
    case documentsAndVision
    case finish

    var title: String {
        switch self {
        case .welcome:
            "Welcome to iMLX"
        case .modelSelection:
            "Recommended starter models"
        case .personasAndMemory:
            "Personas and memory"
        case .documentsAndVision:
            "Documents and vision"
        case .finish:
            "You’re ready"
        }
    }
}

struct OnboardingFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let appState: AppState

    @State private var step: OnboardingStep = .welcome
    @State private var selectedModelID: String?
    @State private var isStartingDownload = false

    private var recommendedModels: [ModelInfo] {
        appState.recommendedStarterModels()
    }

    private var selectedModel: ModelInfo? {
        guard let selectedModelID else { return nil }
        return recommendedModels.first(where: { $0.id == selectedModelID })
    }

    private var isSelectedModelDownloaded: Bool {
        guard let selectedModelID else { return false }
        return appState.manifestService.isDownloaded(modelId: selectedModelID)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                OnboardingProgressHeader(
                    title: step.title,
                    stepIndex: step.rawValue,
                    stepCount: OnboardingStep.allCases.count
                )

                OnboardingStepContent(
                    step: step,
                    recommendedModels: recommendedModels,
                    selectedModelID: selectedModelID,
                    pendingStarterModelID: appState.pendingStarterModelId,
                    modelDownloadSnapshots: appState.modelDownloadSnapshots,
                    isSelectedModelDownloaded: isSelectedModelDownloaded,
                    onSelectModel: selectModel
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                OnboardingFooter(
                    step: step,
                    isStartingDownload: isStartingDownload,
                    selectedModel: selectedModel,
                    downloadButtonTitle: downloadButtonTitle,
                    onDownloadSelectedModel: startSelectedModelDownload,
                    onSkipModelSelection: advance,
                    onContinue: continueFlow,
                    onBack: goBack
                )
            }
            .padding(24)
            .navigationBarBackButtonHidden(true)
        }
    }

    private func selectModel(_ modelID: String) {
        selectedModelID = modelID
    }

    private func startSelectedModelDownload() {
        guard let selectedModel else { return }
        Task {
            await startStarterDownload(selectedModel)
        }
    }

    private func continueFlow() {
        if step == .finish {
            appState.markOnboardingCompleted()
            dismiss()
        } else {
            advance()
        }
    }

    private func goBack() {
        guard let previousStep = OnboardingStep(rawValue: max(step.rawValue - 1, 0)) else { return }
        step = previousStep
    }

    private func advance() {
        guard let nextStep = OnboardingStep(rawValue: min(step.rawValue + 1, OnboardingStep.allCases.count - 1)) else { return }
        step = nextStep
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

private struct OnboardingProgressHeader: View {
    let title: String
    let stepIndex: Int
    let stepCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.largeTitle.weight(.bold))
            ProgressView(value: Double(stepIndex + 1), total: Double(stepCount))
        }
    }
}

private struct OnboardingStepContent: View {
    let step: OnboardingStep
    let recommendedModels: [ModelInfo]
    let selectedModelID: String?
    let pendingStarterModelID: String?
    let modelDownloadSnapshots: [String: ModelDownloadSnapshot]
    let isSelectedModelDownloaded: Bool
    let onSelectModel: (String) -> Void

    var body: some View {
        switch step {
        case .welcome:
            OnboardingFeatureList(
                cards: [
                    OnboardingCardContent(
                        title: "Local-first by default",
                        body: "iMLX runs your chat models on-device. Your conversations, personas, documents, and memories stay on your Apple hardware unless you explicitly turn on a network feature."
                    ),
                    OnboardingCardContent(
                        title: "Privacy before convenience",
                        body: "Web search is opt-in per conversation, and starter model downloads happen only when you choose them."
                    ),
                    OnboardingCardContent(
                        title: "Built for your device",
                        body: "We’ll recommend a small starter set of models based on this device’s memory tier so setup stays smooth."
                    )
                ]
            )
        case .modelSelection:
            OnboardingModelSelectionStep(
                recommendedModels: recommendedModels,
                selectedModelID: selectedModelID,
                onSelectModel: onSelectModel
            )
        case .personasAndMemory:
            OnboardingFeatureList(
                cards: [
                    OnboardingCardContent(
                        title: "Personas shape the assistant",
                        body: "Each conversation can use a different persona, changing tone, focus, and prompting without swapping your model automatically."
                    ),
                    OnboardingCardContent(
                        title: "Memory stays local",
                        body: "iMLX can infer useful memories from your chats, but pending memories stay reviewable before they become active."
                    )
                ]
            )
        case .documentsAndVision:
            OnboardingFeatureList(
                cards: [
                    OnboardingCardContent(
                        title: "Documents are grounded locally",
                        body: "Attach PDFs, CSVs, or text files to a conversation and iMLX retrieves relevant excerpts on-device before answering."
                    ),
                    OnboardingCardContent(
                        title: "Vision depends on the model",
                        body: "Only vision-capable models can work with photos. You can swap later if you need image understanding in a conversation."
                    )
                ]
            )
        case .finish:
            OnboardingFinishStep(
                recommendedModels: recommendedModels,
                selectedModelID: selectedModelID,
                pendingStarterModelID: pendingStarterModelID,
                modelDownloadSnapshots: modelDownloadSnapshots,
                isSelectedModelDownloaded: isSelectedModelDownloaded
            )
        }
    }
}

private struct OnboardingModelSelectionStep: View {
    let recommendedModels: [ModelInfo]
    let selectedModelID: String?
    let onSelectModel: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recommended starter models")
                .font(.title2.weight(.semibold))
            Text("Choose one model to download now, or skip and browse models later.")
                .foregroundStyle(.secondary)

            ForEach(recommendedModels) { model in
                OnboardingStarterModelRow(
                    model: model,
                    isRecommended: recommendedModels.first?.id == model.id,
                    isSelected: selectedModelID == model.id,
                    onSelect: { onSelectModel(model.id) }
                )
            }
        }
    }
}

private struct OnboardingFinishStep: View {
    let recommendedModels: [ModelInfo]
    let selectedModelID: String?
    let pendingStarterModelID: String?
    let modelDownloadSnapshots: [String: ModelDownloadSnapshot]
    let isSelectedModelDownloaded: Bool

    private var selectedModel: ModelInfo? {
        guard let selectedModelID else { return nil }
        return recommendedModels.first(where: { $0.id == selectedModelID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingFeatureCard(
                content: OnboardingCardContent(
                    title: "You’re ready",
                    body: "Start chatting as soon as your model is loaded, or keep exploring personas, memory, and documents from the main app."
                )
            )

            if let pendingStarterModelID,
               let snapshot = modelDownloadSnapshots[pendingStarterModelID],
               let model = recommendedModels.first(where: { $0.id == pendingStarterModelID }) {
                OnboardingFeatureCard(
                    content: OnboardingCardContent(
                        title: "Starter model downloading",
                        body: "\(model.displayName) is downloading in the background.\n\n\(snapshot.displayStatus)"
                    )
                )
            } else if let selectedModel, isSelectedModelDownloaded {
                OnboardingFeatureCard(
                    content: OnboardingCardContent(
                        title: "Starter model ready",
                        body: "\(selectedModel.displayName) finished downloading and is ready to load."
                    )
                )
            }
        }
    }
}

private struct OnboardingFeatureList: View {
    let cards: [OnboardingCardContent]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(cards) { card in
                OnboardingFeatureCard(content: card)
            }
        }
    }
}

private struct OnboardingFooter: View {
    let step: OnboardingStep
    let isStartingDownload: Bool
    let selectedModel: ModelInfo?
    let downloadButtonTitle: (ModelInfo) -> String
    let onDownloadSelectedModel: () -> Void
    let onSkipModelSelection: () -> Void
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if step == .modelSelection {
                if let selectedModel {
                    Button(action: onDownloadSelectedModel) {
                        if isStartingDownload {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(downloadButtonTitle(selectedModel))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isStartingDownload)
                }

                Button("Skip for now", action: onSkipModelSelection)
                    .buttonStyle(.bordered)
            } else {
                Button(step == .finish ? "Start Using iMLX" : "Continue", action: onContinue)
                    .buttonStyle(.borderedProminent)
            }

            if step.rawValue > OnboardingStep.welcome.rawValue && step != .finish {
                Button("Back", action: onBack)
                    .buttonStyle(.plain)
            }
        }
    }
}

private struct OnboardingStarterModelRow: View {
    let model: ModelInfo
    let isRecommended: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.displayName)
                            .font(.headline)
                        if isRecommended {
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

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? BrandPalette.accent : .secondary)
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingCardContent: Identifiable {
    var id: String { title }
    let title: String
    let body: String
}

private struct OnboardingFeatureCard: View {
    let content: OnboardingCardContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(content.title)
                .font(.headline)
            Text(content.body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

#Preview("Onboarding Card") {
    OnboardingFeatureCard(
        content: OnboardingCardContent(
            title: "Privacy before convenience",
            body: "Web search is opt-in per conversation, and starter model downloads happen only when you choose them."
        )
    )
    .padding()
}
