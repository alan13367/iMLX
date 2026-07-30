import AVFoundation
import Foundation
import Speech

nonisolated struct SpeechRecognitionSessionGate: Sendable {
    private(set) var activeSessionID: UUID?

    mutating func begin() -> UUID {
        let sessionID = UUID()
        activeSessionID = sessionID
        return sessionID
    }

    func accepts(_ sessionID: UUID) -> Bool {
        activeSessionID == sessionID
    }

    mutating func finish(_ sessionID: UUID) -> Bool {
        guard activeSessionID == sessionID else { return false }
        activeSessionID = nil
        return true
    }
}

@MainActor
final class SpeechRecognitionService {
    private var audioEngine = AVAudioEngine()
    private let platformSession = PlatformSpeechRecognitionSession()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceWorkItem: DispatchWorkItem?
    private var onPartial: ((String) -> Void)?
    private var onFinal: ((String) -> Void)?
    private var sessionGate = SpeechRecognitionSessionGate()
    private var latestTranscript = ""

    func requestPermissions() async -> Bool {
        let speechAuthorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        let microphoneAuthorized = await platformSession.requestMicrophonePermission()
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

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let format: AVAudioFormat
        do {
            format = try platformSession.prepareInputFormat(for: inputNode)
        } catch {
            platformSession.deactivate()
            throw normalizedRecognitionError(error)
        }

        let sessionID = sessionGate.begin()
        self.onPartial = onPartial
        self.onFinal = onFinal
        recognitionRequest = request
        latestTranscript = ""

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            finishRecognition(sessionID: sessionID, deliverFinal: false)
            throw normalizedRecognitionError(error)
        }

        scheduleSilenceTimeout(interval: 4.0, sessionID: sessionID)
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, self.sessionGate.accepts(sessionID) else { return }
            if let result {
                let transcript = result.bestTranscription.formattedString
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let transcriptChanged = transcript != self.latestTranscript
                self.latestTranscript = transcript

                if result.isFinal {
                    self.finishRecognition(sessionID: sessionID, deliverFinal: true)
                    return
                }
                if transcriptChanged {
                    self.onPartial?(transcript)
                    if !transcript.isEmpty {
                        self.scheduleSilenceTimeout(interval: 1.5, sessionID: sessionID)
                    }
                }
            }
            if error != nil {
                self.finishRecognition(sessionID: sessionID, deliverFinal: true)
            }
        }
        guard sessionGate.accepts(sessionID) else {
            task.cancel()
            return
        }
        recognitionTask = task
    }

    func stopRecognition(deliverFinal: Bool = false) {
        guard let activeSessionID = sessionGate.activeSessionID else {
            tearDownAudioSession()
            return
        }
        finishRecognition(sessionID: activeSessionID, deliverFinal: deliverFinal)
    }

    private func scheduleSilenceTimeout(interval: TimeInterval, sessionID: UUID) {
        silenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.sessionGate.accepts(sessionID) else { return }
            self.finishRecognition(sessionID: sessionID, deliverFinal: true)
        }
        silenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + interval, execute: workItem)
    }

    private func finishRecognition(sessionID: UUID, deliverFinal: Bool) {
        guard sessionGate.finish(sessionID) else { return }
        silenceWorkItem?.cancel()
        silenceWorkItem = nil

        let finalCallback = onFinal
        let finalTranscript = latestTranscript
        onPartial = nil
        onFinal = nil
        latestTranscript = ""

        tearDownAudioSession()

        if deliverFinal {
            finalCallback?(finalTranscript)
        }
    }

    private func tearDownAudioSession() {
        let request = recognitionRequest
        let task = recognitionTask
        recognitionRequest = nil
        recognitionTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        request?.endAudio()
        task?.cancel()
        platformSession.deactivate()
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
