import AVFoundation

@MainActor
final class PlatformSpeechRecognitionSession {
    func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func prepareInputFormat(for inputNode: AVAudioInputNode) throws -> AVAudioFormat {
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechRecognitionError.invalidInputConfiguration
        }
        return format
    }

    func deactivate() {}
}
