import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechRecognitionService {
    private let audioEngine = AVAudioEngine()
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
        try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

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
}

enum SpeechRecognitionError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Speech recognition is unavailable right now."
        }
    }
}
