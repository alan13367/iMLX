import AVFoundation

@MainActor
final class PlatformSpeechRecognitionSession {
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func prepareInputFormat(for inputNode: AVAudioInputNode) throws -> AVAudioFormat {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .duckOthers, .allowBluetoothHFP]
        )
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        guard audioSession.maximumInputNumberOfChannels > 0 else {
            throw SpeechRecognitionError.invalidInputConfiguration
        }

        do {
            try audioSession.setPreferredInputNumberOfChannels(1)
        } catch {
            let nsError = error as NSError
            if nsError.domain != NSOSStatusErrorDomain || nsError.code != -50 {
                throw error
            }
        }

        let candidateFormats = [
            inputNode.inputFormat(forBus: 0),
            inputNode.outputFormat(forBus: 0)
        ]
        if let format = candidateFormats.first(where: Self.isValid) {
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

    func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func isValid(_ format: AVAudioFormat) -> Bool {
        format.sampleRate > 0 && format.channelCount > 0
    }
}
