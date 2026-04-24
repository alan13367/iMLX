import Foundation
import CoreImage
import ImageIO
import MLX
import MLXFFT
import MLXLMCommon
import MLXLMTokenizers
import MLXVLM

actor InferenceService {
    private var modelContainer: ModelContainer?
    private var loadedModelSupportsVision = false
    private var kokoroTTS: KokoroTTS?
    private var kokoroVoiceEmbedding: MLXArray?
    private var kokoroAssets: SpeechAssetFileLocations?
    private var kokoroVoiceLocale: VoiceLocale?

    var isModelLoaded: Bool {
        modelContainer != nil
    }

    func load(modelId: String, localDirectory: URL) async throws {
        #if targetEnvironment(simulator)
        throw InferenceError.simulatorUnsupported
        #else
        if isModelLoaded {
            await unload()
        }

        let shouldPreferVisionLoader = detectVisionSupport(in: localDirectory)

        let container = try await withPreferredDevice {
            if shouldPreferVisionLoader {
                return try await VLMModelFactory.shared.loadContainer(
                    from: localDirectory,
                    using: TokenizersLoader()
                )
            }

            return try await MLXLMCommon.loadModelContainer(
                from: localDirectory,
                using: TokenizersLoader()
            )
        }

        modelContainer = container
        loadedModelSupportsVision = shouldPreferVisionLoader
        #endif
    }

    func generate(
        prompt: String,
        images: [ChatAttachmentImage]? = nil,
        thinkingEnabled: Bool? = nil,
        history: [ChatMessage],
        systemPrompt: String,
        maxTokens: Int,
        temperature: Float = 0.7,
        topP: Float = 1.0,
        repetitionPenalty: Float = 1.0
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            #if targetEnvironment(simulator)
            continuation.finish(throwing: InferenceError.simulatorUnsupported)
            return
            #else
            guard let modelContainer else {
                continuation.finish(throwing: InferenceError.noModelLoaded)
                return
            }

            let userInputImages = userInputImages(from: images)
            if let images, !images.isEmpty {
                guard !userInputImages.isEmpty else {
                    continuation.finish(throwing: InferenceError.invalidImageData)
                    return
                }
                guard loadedModelSupportsVision else {
                    continuation.finish(throwing: InferenceError.visionUnsupportedModel)
                    return
                }
            }

            let task = Task {
                defer {
                    MLX.Memory.clearCache()
                }
                do {
                    try await withPreferredDevice {
                        let additionalContext: [String: any Sendable]? = thinkingEnabled.map { value in
                            ["enable_thinking": value]
                        }

                        let session = ChatSession(
                            modelContainer,
                            instructions: systemPrompt.isEmpty ? nil : systemPrompt,
                            history: history.map(\.chatMessage),
                            additionalContext: additionalContext
                        )
                        var parameters = GenerateParameters(
                            temperature: temperature,
                            topP: topP,
                            //repetitionPenalty: repetitionPenalty == 1 ? nil : repetitionPenalty
                        )
                        parameters.maxTokens = maxTokens

                        session.generateParameters = parameters

                        let stream = session.streamResponse(to: prompt, role: .user, images: userInputImages, videos: [])

                        for try await chunk in stream {
                            guard !Task.isCancelled else {
                                break
                            }
                            continuation.yield(chunk)
                        }
                    }

                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish(throwing: InferenceError.generationCancelled)
                    } else {
                        continuation.finish(throwing: mapError(error))
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
            #endif
        }
    }

    func unload() async {
        let wasLoaded = modelContainer != nil
        modelContainer = nil
        loadedModelSupportsVision = false

        if wasLoaded {
            await Task.yield()
            MLX.Memory.clearCache()
        }
    }

    func synthesizeSpeech(
        text: String,
        locale: VoiceLocale,
        assets: SpeechAssetFileLocations
    ) async throws -> SynthesizedSpeech {
        #if targetEnvironment(simulator)
        throw InferenceError.simulatorUnsupported
        #else
        defer {
            releaseSpeechSynthesisResources()
        }

        guard locale.supportsLiveKokoroSynthesis else {
            throw InferenceError.unsupportedSpeechLocale(locale.displayName)
        }

        MLX.Memory.clearCache()

        if kokoroAssets != assets || kokoroTTS == nil || kokoroVoiceEmbedding == nil || kokoroVoiceLocale != locale {
            let g2p: G2P = {
                switch locale {
                case .english: return .misaki
                case .spanish, .simplifiedChinese: return .multilingual
                }
            }()
            kokoroTTS = KokoroTTS(modelPath: assets.modelURL, g2p: g2p)
            let voiceWeights = try MLX.loadArrays(url: assets.voiceURL)
            guard let firstKey = voiceWeights.keys.sorted().first,
                  let voiceEmbedding = voiceWeights[firstKey] else {
                throw InferenceError.speechAssetsUnavailable
            }
            kokoroVoiceEmbedding = voiceEmbedding
            kokoroAssets = assets
            kokoroVoiceLocale = locale
        }

        guard let kokoroTTS,
              let voiceEmbedding = kokoroVoiceEmbedding else {
            throw InferenceError.speechAssetsUnavailable
        }

        let language: Language = {
            switch locale {
            case .english: return .enUS
            case .spanish: return .spanish
            case .simplifiedChinese: return .mandarinChinese
            }
        }()
        let chunks = speechChunks(for: text)
        guard !chunks.isEmpty else {
            throw InferenceError.speechTextEmpty
        }
        let audio = try await withPreferredDevice {
            var combinedAudio: [Float] = []
            combinedAudio.reserveCapacity(chunks.count * 24_000)

            for index in chunks.indices {
                let chunkAudio = try kokoroTTS.generateAudio(
                    voice: voiceEmbedding,
                    language: language,
                    text: chunks[index]
                ).0
                combinedAudio.append(contentsOf: chunkAudio)
                if index < chunks.index(before: chunks.endIndex) {
                    combinedAudio.append(contentsOf: Array(repeating: 0, count: 2_400))
                }
            }

            return combinedAudio
        }
        MLX.Memory.clearCache()
        return SynthesizedSpeech(
            samples: audio,
            sampleRate: Double(KokoroTTS.Constants.samplingRate)
        )
        #endif
    }

    func unloadSpeechSynthesisResources() {
        releaseSpeechSynthesisResources()
    }

    private func withPreferredDevice<R>(_ operation: () async throws -> R) async rethrows -> R {
        return try await operation()
    }

    private func speechChunks(for text: String) -> [String] {
        let normalizedText = String(
            text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Constants.SpeechSynthesis.maxInputCharacters)
        )
        guard !normalizedText.isEmpty else {
            return []
        }

        let sentenceFragments = normalizedText
            .components(separatedBy: CharacterSet(charactersIn: ".!?;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let baseFragments = sentenceFragments.isEmpty ? [normalizedText] : sentenceFragments
        var chunks: [String] = []
        var currentChunk = ""

        for fragment in baseFragments {
            for wordChunk in splitIntoWordChunks(fragment, maxCharacters: 180) {
                let candidate = currentChunk.isEmpty ? wordChunk : "\(currentChunk). \(wordChunk)"
                if candidate.count <= 220 {
                    currentChunk = candidate
                } else {
                    if !currentChunk.isEmpty {
                        chunks.append(currentChunk)
                    }
                    currentChunk = wordChunk
                }
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return Array(chunks.prefix(Constants.SpeechSynthesis.maxChunks))
    }

    private func splitIntoWordChunks(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else {
            return [text]
        }

        var chunks: [String] = []
        var currentChunk = ""

        for word in text.split(separator: " ") {
            let wordString = String(word)
            if currentChunk.isEmpty {
                currentChunk = wordString
                continue
            }

            let candidate = "\(currentChunk) \(wordString)"
            if candidate.count <= maxCharacters {
                currentChunk = candidate
            } else {
                chunks.append(currentChunk)
                currentChunk = wordString
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    private func releaseSpeechSynthesisResources() {
        kokoroTTS = nil
        kokoroVoiceEmbedding = nil
        kokoroAssets = nil
        kokoroVoiceLocale = nil
        MLX.Memory.clearCache()
    }

    private func detectVisionSupport(in directory: URL) -> Bool {
        let configURL = directory.appendingPathComponent("config.json")
        guard let configData = try? Data(contentsOf: configURL),
              let configObject = try? JSONSerialization.jsonObject(with: configData),
              let config = configObject as? [String: Any] else {
            return false
        }

        if config["vision_config"] != nil {
            return true
        }

        if let modelType = config["model_type"] as? String {
            let normalizedType = modelType.lowercased()
            if normalizedType.contains("_vl") || normalizedType == "qwen3_5" {
                return true
            }
        }

        return false
    }

    private func mapError(_ error: Error) -> Error {
        if let inferenceError = error as? InferenceError {
            return inferenceError
        }

        let nsError = error as NSError
        if nsError.domain == "MLX" || nsError.localizedDescription.contains("memory") {
            return InferenceError.outOfMemory
        }
        return InferenceError.modelLoadFailed(error.localizedDescription)
    }
}

nonisolated private extension ChatMessage {
    var chatMessage: Chat.Message {
        let userInputImages = userInputImages(from: attachedImages)
        
        switch role {
        case .user:
            return .user(content, images: userInputImages)
        case .assistant:
            return .assistant(content, images: userInputImages)
        case .system:
            return .system(content, images: userInputImages)
        }
    }
}

nonisolated private func userInputImages(from images: [ChatAttachmentImage]?) -> [UserInput.Image] {
    guard let images else { return [] }

    return images.compactMap { image in
        let data = image.data
        if let ciImage = CIImage(data: data, options: [.applyOrientationProperty: true]) {
            return .ciImage(ciImage)
        }

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        return .ciImage(CIImage(cgImage: cgImage))
    }
}

enum InferenceError: LocalizedError {
    case noModelLoaded
    case modelLoadFailed(String)
    case outOfMemory
    case generationCancelled
    case simulatorUnsupported
    case visionUnsupportedModel
    case invalidImageData
    case speechAssetsUnavailable
    case speechTextEmpty
    case unsupportedSpeechLocale(String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            String.appLocalized("error.inference.no_model_loaded")
        case .modelLoadFailed(let reason):
            String(format: String.appLocalized("error.inference.model_load_failed"), reason)
        case .outOfMemory:
            String.appLocalized("error.inference.out_of_memory")
        case .generationCancelled:
            String.appLocalized("error.inference.generation_cancelled")
        case .simulatorUnsupported:
            String.appLocalized("error.inference.simulator")
        case .visionUnsupportedModel:
            String.appLocalized("error.inference.vision_unsupported")
        case .invalidImageData:
            String.appLocalized("error.inference.invalid_image")
        case .speechAssetsUnavailable:
            "Kokoro speech assets are not available yet."
        case .speechTextEmpty:
            "There was no reply text to speak."
        case .unsupportedSpeechLocale(let localeName):
            "Live voice is not available for \(localeName) yet."
        }
    }
}
