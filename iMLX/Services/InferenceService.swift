import Foundation
import MLX
import MLXLMCommon

actor InferenceService {
    private var modelContainer: ModelContainer?

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

        let container = try await withPreferredDevice {
            try await MLXLMCommon.loadModelContainer(
                directory: localDirectory
            )
        }

        modelContainer = container
        #endif
    }

    func generate(
        prompt: String,
        history: [ChatMessage],
        systemPrompt: String,
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

            let task = Task {
                do {
                    try await withPreferredDevice {
                        let session = ChatSession(
                            modelContainer,
                            instructions: systemPrompt.isEmpty ? nil : systemPrompt,
                            history: history.map(\.chatMessage)
                        )
                        let parameters = GenerateParameters(
                            temperature: temperature,
                            topP: topP,
                            repetitionPenalty: repetitionPenalty == 1 ? nil : repetitionPenalty
                        )

                        session.generateParameters = parameters

                        let stream = session.streamResponse(to: prompt)

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

        if wasLoaded {
            await Task.yield()
            MLX.Memory.clearCache()
        }
    }

    private func withPreferredDevice<R>(_ operation: () async throws -> R) async rethrows -> R {
        return try await operation()
    }

    private func mapError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == "MLX" || nsError.localizedDescription.contains("memory") {
            return InferenceError.outOfMemory
        }
        return InferenceError.modelLoadFailed(error.localizedDescription)
    }
}

private extension ChatMessage {
    var chatMessage: Chat.Message {
        switch role {
        case .user:
            .user(content)
        case .assistant:
            .assistant(content)
        case .system:
            .system(content)
        }
    }
}

enum InferenceError: LocalizedError {
    case noModelLoaded
    case modelLoadFailed(String)
    case outOfMemory
    case generationCancelled
    case simulatorUnsupported

    var errorDescription: String? {
        switch self {
        case .noModelLoaded: "No model is currently loaded"
        case .modelLoadFailed(let reason): "Failed to load model: \(reason)"
        case .outOfMemory: "Not enough memory to run this model"
        case .generationCancelled: "Generation was cancelled"
        case .simulatorUnsupported: "MLX model loading is unavailable in the iOS Simulator. Run the app on a physical device or use Mac Designed for iPad."
        }
    }
}
