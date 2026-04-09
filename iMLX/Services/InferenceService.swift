import Foundation
import CoreImage
import ImageIO
import MLX
import MLXLMCommon
import MLXVLM

actor InferenceService {
    private var modelContainer: ModelContainer?
    private var loadedModelSupportsVision = false

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
                    hub: defaultHubApi,
                    configuration: .init(directory: localDirectory)
                )
            }

            return try await MLXLMCommon.loadModelContainer(
                directory: localDirectory
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

    private func withPreferredDevice<R>(_ operation: () async throws -> R) async rethrows -> R {
        return try await operation()
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
        }
    }
}
