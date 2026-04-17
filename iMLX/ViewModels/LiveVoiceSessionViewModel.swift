import Foundation

@Observable
@MainActor
final class LiveVoiceSessionViewModel {
    private enum VoiceMemoryStage {
        case startListening
        case speechSynthesis
    }

    var partialTranscript = ""
    var lastUserTranscript = ""
    var statusText = "Voice mode is ready."
    var errorMessage: String?
    var memoryWarningMessage: String?
    var isListening = false
    var isSpeaking = false
    var isGeneratingReply = false
    var isPreparingAssets = false
    var isRestoringConversationModel = false
    var needsAssetDownload = false

    private let appState: AppState
    private let chatViewModel: ChatViewModel
    private let deviceCapabilityService = DeviceCapabilityService()
    private let recognitionService = SpeechRecognitionService()
    private let playbackService = SpeechPlaybackService()
    private var isSessionActive = true
    private var suspendedModelForPlayback: ModelInfo?

    init(appState: AppState, chatViewModel: ChatViewModel) {
        self.appState = appState
        self.chatViewModel = chatViewModel
    }

    var voiceLocale: VoiceLocale {
        appState.resolvedVoiceLocale
    }

    var orbState: VoiceOrbState {
        if isSpeaking { return .speaking }
        if isGeneratingReply { return .generating }
        if isListening { return .listening }
        return .idle
    }

    var localeSupportMessage: String? {
        guard !voiceLocale.supportsLiveKokoroSynthesis else { return nil }
        return "Kokoro live voice is currently available only in English in this build."
    }

    var canStartListening: Bool {
        !isPreparingAssets
            && !isRestoringConversationModel
            && !isListening
            && !isSpeaking
            && !isGeneratingReply
            && !needsAssetDownload
            && localeSupportMessage == nil
            && (appState.loadedModelId != nil || suspendedModelForPlayback != nil)
            && !isRunningOnSimulator
    }

    var unavailableReason: String? {
        if isRunningOnSimulator {
            return "Live voice is available only on a physical device."
        }
        if appState.loadedModelId == nil && suspendedModelForPlayback == nil && !isRestoringConversationModel {
            return "Load a chat model before starting live voice."
        }
        if let localeSupportMessage {
            return localeSupportMessage
        }
        return nil
    }

    func refresh() async {
        let status = await appState.speechAssetService.status()
        needsAssetDownload = !status.isReady(for: voiceLocale)
        refreshMemoryWarning(for: .startListening)
        if let unavailableReason {
            statusText = unavailableReason
        } else if let memoryWarningMessage {
            statusText = memoryWarningMessage
        } else if needsAssetDownload {
            statusText = "Local voice needs a one-time Kokoro download for \(voiceLocale.displayName)."
        } else if isGeneratingReply {
            statusText = "Generating..."
        } else if isRestoringConversationModel {
            statusText = "Reloading the chat model for the next turn."
        } else if !isListening && !isSpeaking {
            statusText = "Tap the mic to start a live voice conversation."
        }
    }

    func downloadAssets() async {
        errorMessage = nil
        isPreparingAssets = true
        statusText = "Downloading local voice assets..."

        do {
            _ = try await appState.speechAssetService.prepareAssets(for: voiceLocale)
            needsAssetDownload = false
            statusText = "Voice assets are ready."
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Voice asset download failed."
        }

        isPreparingAssets = false
    }

    func toggleListening() async {
        if isListening {
            recognitionService.stopRecognition()
            isListening = false
            statusText = "Listening stopped."
            return
        }
        await startListeningCycle()
    }

    func invalidateForLanguageChange() async {
        await close()
        errorMessage = "Voice mode closed because the app language changed."
        await refresh()
    }

    func close() async {
        isSessionActive = false
        recognitionService.stopRecognition()
        playbackService.stop()
        await appState.inferenceService.unloadSpeechSynthesisResources()
        await resumeConversationModelIfNeeded()
        isListening = false
        isSpeaking = false
        isGeneratingReply = false
    }

    private func startListeningCycle() async {
        guard isSessionActive else { return }
        guard unavailableReason == nil else {
            statusText = unavailableReason ?? statusText
            return
        }
        refreshMemoryWarning(for: .startListening)
        guard memoryWarningMessage == nil else {
            errorMessage = memoryWarningMessage
            statusText = "Not enough free memory for live voice."
            return
        }
        guard !needsAssetDownload else {
            statusText = "Download the local voice assets to continue."
            return
        }

        let hasPermissions = await recognitionService.requestPermissions()
        guard hasPermissions else {
            errorMessage = "Microphone and speech recognition permissions are required for live voice."
            statusText = "Permissions are required."
            return
        }

        partialTranscript = ""
        errorMessage = nil
        statusText = "Listening..."

        do {
            try recognitionService.startRecognition(
                locale: voiceLocale,
                onPartial: { [weak self] transcript in
                    guard let self else { return }
                    self.partialTranscript = transcript
                },
                onFinal: { [weak self] transcript in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.handleRecognizedTranscript(transcript)
                    }
                }
            )
            isListening = true
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Unable to start listening."
        }
    }

    private func handleRecognizedTranscript(_ transcript: String) async {
        isListening = false
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = "I didn't catch that. Tap the mic to try again."
            return
        }

        partialTranscript = ""
        lastUserTranscript = trimmed
        isGeneratingReply = true
        statusText = "Generating..."

        guard let assistantMessage = await chatViewModel.sendMessageAndWait(
            trimmed,
            allowPostReplyTasks: false
        ) else {
            isGeneratingReply = false
            statusText = "No reply was generated."
            return
        }

        await suspendConversationModelForPlaybackIfNeeded()
        isGeneratingReply = false
        await speak(assistantMessage.content)
    }

    private func speak(_ text: String) async {
        guard let assetLocations = await appState.speechAssetService.fileLocations(for: voiceLocale) else {
            needsAssetDownload = true
            statusText = "Download the local voice assets to continue."
            return
        }

        refreshMemoryWarning(for: .speechSynthesis)
        if let memoryWarningMessage {
            await resumeConversationModelIfNeeded()
            errorMessage = memoryWarningMessage
            statusText = "Not enough free memory to speak the reply."
            return
        }

        isSpeaking = true
        statusText = "Preparing speech..."

        do {
            let speech = try await appState.inferenceService.synthesizeSpeech(
                text: text,
                locale: voiceLocale,
                assets: assetLocations
            )
            try playbackService.play(speech) { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.isSpeaking = false
                    self.statusText = "Preparing next turn..."
                    await self.resumeConversationModelIfNeeded()
                    self.statusText = "Listening..."
                    if self.isSessionActive {
                        await self.startListeningCycle()
                    }
                }
            }
        } catch {
            isSpeaking = false
            await resumeConversationModelIfNeeded()
            errorMessage = error.localizedDescription
            statusText = "Unable to speak the reply."
        }
    }

    private func suspendConversationModelForPlaybackIfNeeded() async {
        guard shouldSuspendConversationModelForVoicePlayback else {
            suspendedModelForPlayback = nil
            return
        }
        suspendedModelForPlayback = await chatViewModel.suspendLoadedModelForVoicePlayback()
    }

    private func resumeConversationModelIfNeeded() async {
        let model = suspendedModelForPlayback
        suspendedModelForPlayback = nil
        isRestoringConversationModel = true
        await chatViewModel.resumeModelAfterVoicePlayback(model)
        isRestoringConversationModel = false
    }

    private var resolvedConversationModel: ModelInfo? {
        guard let loadedModelId = appState.loadedModelId ?? suspendedModelForPlayback?.id else {
            return appState.selectedModel
        }
        return Constants.ModelRegistry.curatedModels.first(where: { $0.id == loadedModelId }) ?? appState.selectedModel
    }

    private var shouldSuspendConversationModelForVoicePlayback: Bool {
        guard let model = resolvedConversationModel else { return false }

        if model.estimatedSizeGB <= 0.5 {
            return false
        }

        let availableMemoryMB = deviceCapabilityService.availableMemoryMB
        if model.estimatedSizeGB <= 1.2 && availableMemoryMB >= 1_500 {
            return false
        }

        return true
    }

    private func refreshMemoryWarning(for stage: VoiceMemoryStage) {
        let availableMemoryMB = deviceCapabilityService.availableMemoryMB
        guard availableMemoryMB > 0 else {
            memoryWarningMessage = nil
            return
        }

        let requiredMemoryMB = recommendedAvailableMemoryMB(for: stage)
        guard availableMemoryMB < requiredMemoryMB else {
            memoryWarningMessage = nil
            return
        }

        switch stage {
        case .startListening:
            memoryWarningMessage = "Live voice needs more free memory before it starts. Close background apps and try again. Available now: \(availableMemoryMB) MB."
        case .speechSynthesis:
            memoryWarningMessage = "Live voice is too close to the memory limit to synthesize speech safely. Close background apps and try again. Available now: \(availableMemoryMB) MB."
        }
    }

    private func recommendedAvailableMemoryMB(for stage: VoiceMemoryStage) -> UInt64 {
        let modelSizeMB = UInt64((resolvedConversationModel?.estimatedSizeGB ?? 0) * 1024)

        switch stage {
        case .startListening:
            let threshold = 400 + (modelSizeMB / 4)
            return min(max(threshold, 500), 1_400)
        case .speechSynthesis:
            let threshold = 300 + (modelSizeMB / 8)
            return min(max(threshold, 350), 900)
        }
    }

    private var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
