import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case modelSelection
    case memory
    case documentsAndVision
    case finish

    var title: String {
        switch self {
        case .welcome: "Welcome to iMLX"
        case .modelSelection: "Starter Models"
        case .memory: "Memory"
        case .documentsAndVision: "Documents & Vision"
        case .finish: "You’re Ready"
        }
    }
    
    var icon: String {
        switch self {
        case .welcome: "sparkles"
        case .modelSelection: "cpu"
        case .memory: "brain"
        case .documentsAndVision: "eye.fill"
        case .finish: "checkmark.circle.fill"
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
        ZStack(alignment: .bottom) {
            ChatBackgroundView()
                .ignoresSafeArea()

            TabView(selection: $step) {
                ForEach(OnboardingStep.allCases, id: \.self) { currentStep in
                    ScrollView {
                        VStack(spacing: 32) {
                            OnboardingProgressHeader(
                                step: currentStep,
                                stepIndex: currentStep.rawValue,
                                stepCount: OnboardingStep.allCases.count
                            )
                            .padding(.top, 60)

                            OnboardingStepContent(
                                step: currentStep,
                                recommendedModels: recommendedModels,
                                selectedModelID: selectedModelID,
                                pendingStarterModelID: appState.pendingStarterModelId,
                                modelDownloadSnapshots: appState.modelDownloadSnapshots,
                                isSelectedModelDownloaded: isSelectedModelDownloaded,
                                onSelectModel: selectModel,
                                onCancelDownload: cancelStarterDownload
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 220) // Give space for the footer
                    }
                    .scrollIndicators(.hidden)
                    .tag(currentStep)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: step)

            // Fixed Footer
            OnboardingFooter(
                step: step,
                isStartingDownload: isStartingDownload,
                selectedModel: selectedModel,
                modelDownloadSnapshots: appState.modelDownloadSnapshots,
                downloadButtonTitle: downloadButtonTitle,
                onDownloadSelectedModel: startSelectedModelDownload,
                onCancelDownload: cancelStarterDownload,
                onSkipModelSelection: advance,
                onContinue: continueFlow,
                onBack: goBack
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 48)
            .padding(.top, 40)
            .background(
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0.0),
                                .init(color: .black, location: 0.35),
                                .init(color: .black, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .sensoryFeedback(.selection, trigger: step)
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

    private func cancelStarterDownload() {
        Task {
            await appState.cancelStarterModelDownload()
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
    let step: OnboardingStep
    let stepIndex: Int
    let stepCount: Int

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: step.icon)
                .font(.largeTitle.weight(.light))
                .foregroundStyle(BrandPalette.primaryGradient)
                .symbolEffect(.bounce.up.byLayer, options: .nonRepeating)
                .frame(height: 60)
            
            VStack(spacing: 12) {
                Text(step.title)
                    .font(.system(.title, design: .rounded))
                    .bold()
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 8) {
                    ForEach(0..<stepCount, id: \.self) { i in
                        Capsule()
                            .fill(i == stepIndex ? BrandPalette.accent : Color.secondary.opacity(0.3))
                            .frame(width: i == stepIndex ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: stepIndex)
                    }
                }
                .padding(.top, 4)
            }
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
    let onCancelDownload: () -> Void

    var body: some View {
        switch step {
        case .welcome:
            OnboardingFeatureList(
                cards: [
                    OnboardingCardContent(
                        icon: "iphone.gen3",
                        title: "Local-first by default",
                        body: "iMLX runs your chat models on-device. Your conversations, documents, and memories stay on your Apple hardware unless you explicitly turn on a network feature."
                    ),
                    OnboardingCardContent(
                        icon: "hand.raised.fill",
                        title: "Privacy before convenience",
                        body: "Web search is opt-in per conversation, and starter model downloads happen only when you choose them."
                    ),
                    OnboardingCardContent(
                        icon: "cpu",
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
        case .memory:
            OnboardingFeatureList(
                cards: [
                    OnboardingCardContent(
                        icon: "brain",
                        title: "Memory stays local",
                        body: "iMLX can infer useful memories from your chats, but pending memories stay reviewable before they become active."
                    )
                ]
            )
        case .documentsAndVision:
            OnboardingFeatureList(
                cards: [
                    OnboardingCardContent(
                        icon: "doc.text.fill",
                        title: "Documents are grounded locally",
                        body: "Attach PDFs, CSVs, or text files to a conversation and iMLX retrieves relevant excerpts on-device before answering."
                    ),
                    OnboardingCardContent(
                        icon: "eye.fill",
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
                isSelectedModelDownloaded: isSelectedModelDownloaded,
                onCancelDownload: onCancelDownload
            )
        }
    }
}

private struct OnboardingModelSelectionStep: View {
    let recommendedModels: [ModelInfo]
    let selectedModelID: String?
    let onSelectModel: (String) -> Void
    @State private var hapticSelectionTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose one model to download now, or skip and browse models later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)

            ForEach(recommendedModels) { model in
                OnboardingStarterModelRow(
                    model: model,
                    isRecommended: recommendedModels.first?.id == model.id,
                    isSelected: selectedModelID == model.id,
                    onSelect: {
                        hapticSelectionTrigger += 1
                        onSelectModel(model.id)
                    }
                )
            }
        }
        .sensoryFeedback(.selection, trigger: hapticSelectionTrigger)
    }
}

private struct OnboardingFinishStep: View {
    let recommendedModels: [ModelInfo]
    let selectedModelID: String?
    let pendingStarterModelID: String?
    let modelDownloadSnapshots: [String: ModelDownloadSnapshot]
    let isSelectedModelDownloaded: Bool
    let onCancelDownload: () -> Void

    private var selectedModel: ModelInfo? {
        guard let selectedModelID else { return nil }
        return recommendedModels.first(where: { $0.id == selectedModelID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingFeatureCard(
                content: OnboardingCardContent(
                    icon: "sparkles",
                    title: "You’re ready",
                    body: "Start chatting as soon as your model is loaded, or keep exploring memory, documents, and assistant settings from the main app."
                )
            )

            if let pendingStarterModelID,
               let snapshot = modelDownloadSnapshots[pendingStarterModelID],
               snapshot.isActive,
               let model = recommendedModels.first(where: { $0.id == pendingStarterModelID }) {
                VStack(spacing: 12) {
                    OnboardingFeatureCard(
                        content: OnboardingCardContent(
                            icon: "arrow.down.circle.fill",
                            title: "Starter model downloading",
                            body: "\(model.displayName) is downloading in the background.\n\n\(snapshot.displayStatus)"
                        )
                    )

                    Button(action: onCancelDownload) {
                        Text(String.appLocalized("models.card.stop_download"))
                            .frame(maxWidth: .infinity)
                    }
                    .liquidGlassButtonStyle(prominent: false)
                }
            } else if let selectedModel, isSelectedModelDownloaded {
                OnboardingFeatureCard(
                    content: OnboardingCardContent(
                        icon: "checkmark.circle.fill",
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
    let modelDownloadSnapshots: [String: ModelDownloadSnapshot]
    let downloadButtonTitle: (ModelInfo) -> String
    let onDownloadSelectedModel: () -> Void
    let onCancelDownload: () -> Void
    let onSkipModelSelection: () -> Void
    let onContinue: () -> Void
    let onBack: () -> Void
    @State private var hapticLightTrigger = 0
    @State private var hapticSelectionTrigger = 0

    private func isDownloading(_ model: ModelInfo) -> Bool {
        modelDownloadSnapshots[model.id]?.isActive == true
    }

    var body: some View {
        VStack(spacing: 16) {
            if step == .modelSelection {
                if let selectedModel {
                    if isDownloading(selectedModel) {
                        Text(downloadButtonTitle(selectedModel))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)

                        Button(action: {
                            hapticLightTrigger += 1
                            onCancelDownload()
                        }) {
                            Text(String.appLocalized("models.card.stop_download"))
                                .frame(maxWidth: .infinity)
                        }
                        .liquidGlassButtonStyle(prominent: false)
                    } else {
                        Button(action: {
                            hapticLightTrigger += 1
                            onDownloadSelectedModel()
                        }) {
                            HStack {
                                if isStartingDownload {
                                    ProgressView()
                                } else {
                                    Text(downloadButtonTitle(selectedModel))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .liquidGlassButtonStyle(prominent: true, tint: BrandPalette.accent)
                        .disabled(isStartingDownload)
                    }
                }

                Button(action: {
                    hapticLightTrigger += 1
                    onSkipModelSelection()
                }) {
                    Text("Skip for now")
                        .frame(maxWidth: .infinity)
                }
                .liquidGlassButtonStyle(prominent: false)
            } else {
                Button(action: {
                    hapticLightTrigger += 1
                    onContinue()
                }) {
                    Text(step == .finish ? "Start Using iMLX" : "Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .liquidGlassButtonStyle(prominent: true, tint: BrandPalette.accent)
            }

            if step.rawValue > OnboardingStep.welcome.rawValue && step != .finish {
                Button(action: {
                    hapticSelectionTrigger += 1
                    onBack()
                }) {
                    Text("Back")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: hapticLightTrigger)
        .sensoryFeedback(.selection, trigger: hapticSelectionTrigger)
    }
}

private struct OnboardingStarterModelRow: View {
    let model: ModelInfo
    let isRecommended: Bool
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if isRecommended {
                            Text("Recommended")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(BrandPalette.primaryGradient, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }

                    Text("\(model.parameterCount) • \(String(format: "%.1f GB", model.estimatedSizeGB)) • \(model.supportsVision ? "Vision" : "Text only")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .stroke(isSelected ? BrandPalette.accent : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(BrandPalette.primaryGradient)
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .padding(20)
            .liquidGlassSurface(
                tint: isSelected ? BrandPalette.accent.opacity(0.1) : nil,
                in: RoundedRectangle(cornerRadius: 24),
                interactive: true
            )
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingCardContent: Identifiable {
    var id: String { title }
    let icon: String
    let title: String
    let body: String
}

private struct OnboardingFeatureCard: View {
    let content: OnboardingCardContent

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: content.icon)
                .font(.title2)
                .foregroundStyle(BrandPalette.primaryGradient)
                .frame(width: 32)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(content.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(content.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .liquidGlassSurface(in: RoundedRectangle(cornerRadius: 24))
    }
}

#Preview("Onboarding Card") {
    ZStack {
        ChatBackgroundView()
            .ignoresSafeArea()
        
        OnboardingFeatureCard(
            content: OnboardingCardContent(
                icon: "hand.raised.fill",
                title: "Privacy before convenience",
                body: "Web search is opt-in per conversation, and starter model downloads happen only when you choose them."
            )
        )
        .padding()
    }
}
