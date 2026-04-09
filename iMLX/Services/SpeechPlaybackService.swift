import AVFoundation
import Foundation

@MainActor
final class SpeechPlaybackService {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var hasConnectedNode = false

    init() {
        audioEngine.attach(playerNode)
    }

    func play(_ speech: SynthesizedSpeech, completion: @escaping @MainActor () -> Void) throws {
        stop()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let format = AVAudioFormat(standardFormatWithSampleRate: speech.sampleRate, channels: 1)!
        if !hasConnectedNode {
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
            hasConnectedNode = true
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(speech.samples.count)
        ) else {
            throw SpeechPlaybackError.bufferCreationFailed
        }

        buffer.frameLength = buffer.frameCapacity
        guard let channels = buffer.floatChannelData else {
            throw SpeechPlaybackError.bufferCreationFailed
        }

        speech.samples.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            UnsafeMutableRawPointer(channels[0]).copyMemory(
                from: UnsafeRawPointer(baseAddress),
                byteCount: pointer.count * MemoryLayout<Float>.stride
            )
        }

        if !audioEngine.isRunning {
            try audioEngine.start()
        }

        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts) {
            Task { @MainActor in
                completion()
            }
        }
        playerNode.play()
    }

    func stop() {
        playerNode.stop()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum SpeechPlaybackError: LocalizedError {
    case bufferCreationFailed

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            "Unable to prepare audio playback."
        }
    }
}
