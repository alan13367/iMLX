import Foundation
import MLX
import MLXLMCommon

actor InferenceService {
    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?

    var isModelLoaded: Bool {
        modelContainer != nil
    }

    func load(modelId: String, localDirectory: URL) async throws {
        if isModelLoaded {
            await unload()
        }

        let container = try await MLXLMCommon.loadModelContainer(
            directory: localDirectory
        )

        modelContainer = container
        chatSession = ChatSession(container)
    }

    func generate(
        prompt: String,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float = 1.0
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            guard let chatSession = chatSession else {
                continuation.finish(throwing: InferenceError.noModelLoaded)
                return
            }

            let task = Task {
                do {
                    let parameters = GenerateParameters(
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP
                    )

                    chatSession.generateParameters = parameters

                    let stream = chatSession.streamResponse(to: prompt)

                    for try await chunk in stream {
                        guard !Task.isCancelled else {
                            break
                        }
                        continuation.yield(chunk)
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
        }
    }

    func unload() async {
        modelContainer = nil
        chatSession = nil

        MLX.Memory.clearCache()
    }

    private func mapError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == "MLX" || nsError.localizedDescription.contains("memory") {
            return InferenceError.outOfMemory
        }
        return InferenceError.modelLoadFailed(error.localizedDescription)
    }
}

enum InferenceError: LocalizedError {
    case noModelLoaded
    case modelLoadFailed(String)
    case outOfMemory
    case generationCancelled

    var errorDescription: String? {
        switch self {
        case .noModelLoaded: "No model is currently loaded"
        case .modelLoadFailed(let reason): "Failed to load model: \(reason)"
        case .outOfMemory: "Not enough memory to run this model"
        case .generationCancelled: "Generation was cancelled"
        }
    }
}
