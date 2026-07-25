import AVFoundation
import Foundation

@MainActor
final class SpeechPlaybackService {
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var hasConnectedNode = false
    private var streamingSessionID: UUID?
    private var pendingBufferCount = 0
    private var didFinishEnqueuing = false
    private var streamingCompletion: (@MainActor () -> Void)?

    init() {
        audioEngine.attach(playerNode)
    }

    func play(_ speech: SynthesizedSpeech, completion: @escaping @MainActor () -> Void) throws {
        try startStreaming(sampleRate: speech.sampleRate, completion: completion)
        try enqueue(speech)
        finishStreaming()
    }

    func startStreaming(
        sampleRate: Double,
        completion: @escaping @MainActor () -> Void
    ) throws {
        stop()

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        if !hasConnectedNode {
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
            hasConnectedNode = true
        }

        if !audioEngine.isRunning {
            try audioEngine.start()
        }

        streamingSessionID = UUID()
        pendingBufferCount = 0
        didFinishEnqueuing = false
        streamingCompletion = completion
        playerNode.play()
    }

    func enqueue(_ speech: SynthesizedSpeech) throws {
        guard let sessionID = streamingSessionID else {
            throw SpeechPlaybackError.streamingSessionUnavailable
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: speech.sampleRate, channels: 1)!

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

        pendingBufferCount += 1
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.streamingSessionID == sessionID else { return }
                self.pendingBufferCount = max(0, self.pendingBufferCount - 1)
                self.completeStreamingIfReady()
            }
        }
    }

    func finishStreaming() {
        didFinishEnqueuing = true
        completeStreamingIfReady()
    }

    func stop() {
        streamingSessionID = nil
        pendingBufferCount = 0
        didFinishEnqueuing = false
        streamingCompletion = nil
        playerNode.stop()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func completeStreamingIfReady() {
        guard didFinishEnqueuing, pendingBufferCount == 0 else { return }
        let completion = streamingCompletion
        streamingSessionID = nil
        streamingCompletion = nil
        didFinishEnqueuing = false
        completion?()
    }
}

enum SpeechPlaybackError: LocalizedError {
    case bufferCreationFailed
    case streamingSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            "Unable to prepare audio playback."
        case .streamingSessionUnavailable:
            "Unable to start streaming audio playback."
        }
    }
}
