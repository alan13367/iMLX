import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechRecognitionService {
    private var audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceWorkItem: DispatchWorkItem?
    private var onPartial: ((String) -> Void)?
    private var onFinal: ((String) -> Void)?
    private var latestTranscript = ""
    private var hasDeliveredFinal = false
    private var hasDetectedSpeech = false

    func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let microphoneAuthorized = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }

        return speechAuthorized && microphoneAuthorized
    }

    func startRecognition(
        locale: VoiceLocale,
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (String) -> Void
    ) throws {
        stopRecognition()

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale.localeIdentifier))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechRecognitionError.unavailable
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try configureAudioSession(audioSession)
        } catch {
            throw normalizedRecognitionError(error)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format = try recognitionFormat(for: inputNode, audioSession: audioSession)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw normalizedRecognitionError(error)
        }

        self.onPartial = onPartial
        self.onFinal = onFinal
        self.recognitionRequest = request
        latestTranscript = ""
        hasDeliveredFinal = false
        hasDetectedSpeech = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                self.latestTranscript = transcript
                self.onPartial?(transcript)
                if !transcript.isEmpty {
                    self.hasDetectedSpeech = true
                    self.scheduleSilenceTimeout(interval: 1.5)
                }
                if result.isFinal {
                    self.finishRecognition(deliverFinal: true)
                }
            } else if error != nil {
                self.finishRecognition(deliverFinal: true)
            }
        }

        scheduleSilenceTimeout(interval: 4.0)
    }

    func stopRecognition() {
        finishRecognition(deliverFinal: false)
    }

    private func scheduleSilenceTimeout(interval: TimeInterval) {
        silenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishRecognition(deliverFinal: true)
        }
        silenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    private func finishRecognition(deliverFinal: Bool) {
        silenceWorkItem?.cancel()
        silenceWorkItem = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if deliverFinal, !hasDeliveredFinal {
            hasDeliveredFinal = true
            let transcript = latestTranscript
            if !transcript.isEmpty || hasDetectedSpeech {
                onFinal?(transcript)
            }
        }
    }

    private func configureAudioSession(_ audioSession: AVAudioSession) throws {
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .duckOthers, .allowBluetooth]
        )
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        guard audioSession.maximumInputNumberOfChannels > 0 else {
            throw SpeechRecognitionError.invalidInputConfiguration
        }

        do {
            try audioSession.setPreferredInputNumberOfChannels(1)
        } catch {
            if !isInvalidAudioSessionParameter(error) {
                throw error
            }
        }
    }

    private func recognitionFormat(for inputNode: AVAudioInputNode, audioSession: AVAudioSession) throws -> AVAudioFormat {
        let candidateFormats = [
            inputNode.inputFormat(forBus: 0),
            inputNode.outputFormat(forBus: 0)
        ]

        if let format = candidateFormats.first(where: isValidRecognitionFormat) {
            return format
        }

        let sampleRate = audioSession.sampleRate
        let channelCount = audioSession.inputNumberOfChannels
        if sampleRate > 0,
           channelCount > 0,
           let fallbackFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channelCount),
                interleaved: false
           ) {
            return fallbackFormat
        }

        throw SpeechRecognitionError.invalidInputConfiguration
    }

    private func isValidRecognitionFormat(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }

    private func normalizedRecognitionError(_ error: Error) -> Error {
        if let recognitionError = error as? SpeechRecognitionError {
            return recognitionError
        }

        if isInvalidAudioSessionParameter(error) {
            return SpeechRecognitionError.invalidInputConfiguration
        }

        return error
    }

    private func isInvalidAudioSessionParameter(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSOSStatusErrorDomain && nsError.code == -50
    }
}

enum SpeechRecognitionError: LocalizedError {
    case unavailable
    case invalidInputConfiguration

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Speech recognition is unavailable right now."
        case .invalidInputConfiguration:
            "The microphone input is not ready yet. Please try again."
        }
    }
}
