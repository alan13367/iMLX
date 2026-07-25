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
    var statusText = String.appLocalized("voice.status.ready")
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
    private var turnTask: Task<Void, Never>?
    private var activeSpeakSession: UUID?

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

    var canStartListening: Bool {
        !isPreparingAssets
            && !isRestoringConversationModel
            && !isListening
            && !isSpeaking
            && !isGeneratingReply
            && !needsAssetDownload
            && (appState.loadedModelId != nil || suspendedModelForPlayback != nil)
            && !isRunningOnSimulator
    }

    var canStopSpeaking: Bool {
        isSpeaking && !isGeneratingReply
    }

    var unavailableReason: String? {
        if isRunningOnSimulator {
            return String.appLocalized("voice.status.device_only")
        }
        if appState.loadedModelId == nil && suspendedModelForPlayback == nil && !isRestoringConversationModel {
            return String.appLocalized("voice.status.load_model")
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
            statusText = String(format: String.appLocalized("voice.status.download_needed"), voiceLocale.displayName)
        } else if isGeneratingReply {
            statusText = String.appLocalized("voice.status.generating")
        } else if isRestoringConversationModel {
            statusText = String.appLocalized("voice.status.reloading_model")
        } else if !isListening && !isSpeaking {
            statusText = String.appLocalized("voice.status.tap_mic")
        }
    }

    func downloadAssets() async {
        errorMessage = nil
        isPreparingAssets = true
        statusText = String.appLocalized("voice.status.downloading_assets")

        do {
            _ = try await appState.speechAssetService.prepareAssets(for: voiceLocale)
            needsAssetDownload = false
            statusText = String.appLocalized("voice.status.assets_ready")
        } catch {
            errorMessage = error.localizedDescription
            statusText = String.appLocalized("voice.status.asset_download_failed")
        }

        isPreparingAssets = false
    }

    func toggleListening() async {
        if isListening {
            recognitionService.stopRecognition()
            isListening = false
            statusText = String.appLocalized("voice.status.listening_stopped")
            return
        }
        await startListeningCycle()
    }

    func stopSpeaking() async {
        guard canStopSpeaking else { return }
        activeSpeakSession = nil
        playbackService.stop()
        isSpeaking = false
        statusText = String.appLocalized("voice.status.tap_mic")
        await resumeConversationModelIfNeeded()
    }

    func invalidateForLanguageChange() async {
        await close()
        errorMessage = String.appLocalized("voice.status.language_changed")
        await refresh()
    }

    func close() async {
        isSessionActive = false
        activeSpeakSession = nil
        turnTask?.cancel()
        turnTask = nil
        chatViewModel.stopGeneration(discardPartialResponse: true)
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
            statusText = String.appLocalized("voice.status.memory_low")
            return
        }
        guard !needsAssetDownload else {
            statusText = String.appLocalized("voice.status.download_to_continue")
            return
        }

        let hasPermissions = await recognitionService.requestPermissions()
        guard hasPermissions else {
            errorMessage = String.appLocalized("voice.status.permissions_required_detail")
            statusText = String.appLocalized("voice.status.permissions_required")
            return
        }

        partialTranscript = ""
        errorMessage = nil
        statusText = String.appLocalized("voice.status.listening")

        do {
            try recognitionService.startRecognition(
                locale: voiceLocale,
                onPartial: { [weak self] transcript in
                    guard let self else { return }
                    guard self.isSessionActive else { return }
                    self.partialTranscript = transcript
                },
                onFinal: { [weak self] transcript in
                    guard let self else { return }
                    guard self.isSessionActive else { return }
                    self.turnTask?.cancel()
                    self.turnTask = Task { @MainActor in
                        await self.handleRecognizedTranscript(transcript)
                    }
                }
            )
            isListening = true
        } catch {
            errorMessage = error.localizedDescription
            statusText = String.appLocalized("voice.status.listening_failed")
        }
    }

    private func handleRecognizedTranscript(_ transcript: String) async {
        guard isSessionActive, !Task.isCancelled else { return }
        isListening = false
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusText = String.appLocalized("voice.status.no_speech")
            return
        }

        partialTranscript = ""
        lastUserTranscript = trimmed
        isGeneratingReply = true
        statusText = String.appLocalized("voice.status.generating")

        guard let assistantMessage = await chatViewModel.sendMessageAndWait(
            trimmed,
            allowPostReplyTasks: false,
            isLiveVoiceReply: true
        ) else {
            isGeneratingReply = false
            guard isSessionActive, !Task.isCancelled else { return }
            statusText = String.appLocalized("voice.status.no_reply")
            return
        }
        guard isSessionActive, !Task.isCancelled else {
            isGeneratingReply = false
            return
        }

        await suspendConversationModelForPlaybackIfNeeded()
        guard isSessionActive, !Task.isCancelled else {
            isGeneratingReply = false
            await resumeConversationModelIfNeeded()
            return
        }
        isGeneratingReply = false
        await speak(assistantMessage.content)
    }

    private func speak(_ text: String) async {
        guard isSessionActive, !Task.isCancelled else { return }
        guard let assetLocations = await appState.speechAssetService.fileLocations(for: voiceLocale) else {
            guard isSessionActive, !Task.isCancelled else { return }
            needsAssetDownload = true
            statusText = String.appLocalized("voice.status.download_to_continue")
            return
        }

        refreshMemoryWarning(for: .speechSynthesis)
        if let memoryWarningMessage {
            await resumeConversationModelIfNeeded()
            errorMessage = memoryWarningMessage
            statusText = String.appLocalized("voice.status.speech_memory_low")
            return
        }

        let session = UUID()
        activeSpeakSession = session
        isSpeaking = true
        statusText = String.appLocalized("voice.status.preparing_speech")

        do {
            let speechStream = await appState.inferenceService.synthesizeSpeechStream(
                text: text,
                locale: voiceLocale,
                assets: assetLocations
            )
            var didStartPlayback = false
            for try await speechChunk in speechStream {
                guard isSessionActive, !Task.isCancelled, activeSpeakSession == session else {
                    playbackService.stop()
                    isSpeaking = false
                    activeSpeakSession = nil
                    await resumeConversationModelIfNeeded()
                    return
                }
                if !didStartPlayback {
                    try playbackService.startStreaming(sampleRate: speechChunk.sampleRate) { [weak self] in
                        guard let self else { return }
                        Task { @MainActor in
                            guard self.isSessionActive, self.activeSpeakSession == session else { return }
                            self.activeSpeakSession = nil
                            self.isSpeaking = false
                            self.statusText = String.appLocalized("voice.status.preparing_next_turn")
                            await self.resumeConversationModelIfNeeded()
                            self.statusText = String.appLocalized("voice.status.listening")
                            if self.isSessionActive {
                                await self.startListeningCycle()
                            }
                        }
                    }
                    didStartPlayback = true
                    statusText = String.appLocalized("voice.status.preparing_speech")
                }
                try playbackService.enqueue(speechChunk)
            }
            guard didStartPlayback else {
                throw InferenceError.speechTextEmpty
            }
            playbackService.finishStreaming()
        } catch {
            playbackService.stop()
            activeSpeakSession = nil
            guard isSessionActive, !Task.isCancelled else { return }
            isSpeaking = false
            await resumeConversationModelIfNeeded()
            errorMessage = speechErrorMessage(for: error)
            statusText = String.appLocalized("voice.status.speech_failed")
        }
    }

    private func speechErrorMessage(for error: Error) -> String {
        if let g2pError = error as? G2PProcessorError {
            switch g2pError {
            case .invalidPhonemeOutput:
                return String.appLocalized("voice.status.speech_text_unsupported")
            case .processorNotInitialized, .unsupportedLanguage:
                return String.appLocalized("voice.status.speech_failed")
            }
        }
        return error.localizedDescription
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
        if model != nil {
            await appState.inferenceService.unloadSpeechSynthesisResources()
        }
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
            memoryWarningMessage = String(format: String.appLocalized("voice.status.memory_warning_start"), availableMemoryMB)
        case .speechSynthesis:
            memoryWarningMessage = String(format: String.appLocalized("voice.status.memory_warning_speech"), availableMemoryMB)
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
