import Foundation

@Observable
@MainActor
final class LiveVoiceSessionViewModel {
    var partialTranscript = ""
    var lastUserTranscript = ""
    var statusText = "Voice mode is ready."
    var errorMessage: String?
    var isListening = false
    var isSpeaking = false
    var isPreparingAssets = false
    var isRestoringConversationModel = false
    var needsAssetDownload = false

    private let appState: AppState
    private let chatViewModel: ChatViewModel
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

    var localeSupportMessage: String? {
        guard !voiceLocale.supportsLiveKokoroSynthesis else { return nil }
        return "Kokoro live voice is currently available only in English in this build."
    }

    var canStartListening: Bool {
        !isPreparingAssets
            && !isRestoringConversationModel
            && !isListening
            && !isSpeaking
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
        if let unavailableReason {
            statusText = unavailableReason
        } else if needsAssetDownload {
            statusText = "Local voice needs a one-time Kokoro download for \(voiceLocale.displayName)."
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
    }

    private func startListeningCycle() async {
        guard isSessionActive else { return }
        guard unavailableReason == nil else {
            statusText = unavailableReason ?? statusText
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
        statusText = "Generating..."

        guard let assistantMessage = await chatViewModel.sendMessageAndWait(trimmed) else {
            statusText = "No reply was generated."
            return
        }

        await suspendConversationModelForPlaybackIfNeeded()
        await speak(assistantMessage.content)
    }

    private func speak(_ text: String) async {
        guard let assetLocations = await appState.speechAssetService.fileLocations(for: voiceLocale) else {
            needsAssetDownload = true
            statusText = "Download the local voice assets to continue."
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
        suspendedModelForPlayback = await chatViewModel.suspendLoadedModelForVoicePlayback()
    }

    private func resumeConversationModelIfNeeded() async {
        let model = suspendedModelForPlayback
        suspendedModelForPlayback = nil
        isRestoringConversationModel = true
        await chatViewModel.resumeModelAfterVoicePlayback(model)
        isRestoringConversationModel = false
    }

    private var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
