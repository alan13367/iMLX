import Foundation

enum Constants {
    enum ModelRegistry {
        static let curatedModels: [ModelInfo] = [
            ModelInfo(
                id: "qwen3-1.7b-4bit",
                displayName: "Qwen3 1.7B",
                huggingFaceId: "mlx-community/Qwen3-1.7B-4bit",
                parameterCount: "1.7B",
                quantization: "4-bit",
                estimatedSizeGB: 1.1,
                minDeviceRAM: 8,
                family: .qwen3,
                logoName: "qwen_logo",
                supportsThinking: true,
                supportsVision: false,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "qwen3-4b-4bit",
                displayName: "Qwen3 4B",
                huggingFaceId: "mlx-community/Qwen3-4B-4bit",
                parameterCount: "4B",
                quantization: "4-bit",
                estimatedSizeGB: 2.5,
                minDeviceRAM: 12,
                family: .qwen3,
                logoName: "qwen_logo",
                supportsThinking: true,
                supportsVision: false,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "qwen3.5-0.8b-4bit",
                displayName: "Qwen3.5 0.8B",
                huggingFaceId: "mlx-community/Qwen3.5-0.8B-MLX-4bit",
                parameterCount: "0.8B",
                quantization: "4-bit",
                estimatedSizeGB: 0.5,
                minDeviceRAM: 8,
                family: .qwen35,
                logoName: "qwen_logo",
                supportsThinking: true,
                supportsVision: true,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "qwen2-vl-2b-it-4bit",
                displayName: "Qwen2-VL 2B",
                huggingFaceId: "mlx-community/Qwen2-VL-2B-Instruct-4bit",
                parameterCount: "2B",
                quantization: "4-bit",
                estimatedSizeGB: 1.5,
                minDeviceRAM: 8,
                family: .qwen2vl,
                logoName: "qwen_logo",
                supportsThinking: false,
                supportsVision: true,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "qwen3.5-2b-4bit",
                displayName: "Qwen3.5 2B",
                huggingFaceId: "mlx-community/Qwen3.5-2B-MLX-4bit",
                parameterCount: "2B",
                quantization: "4-bit",
                estimatedSizeGB: 1.3,
                minDeviceRAM: 8,
                family: .qwen35,
                logoName: "qwen_logo",
                supportsThinking: true,
                supportsVision: true,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "qwen3.5-4b-4bit",
                displayName: "Qwen3.5 4B",
                huggingFaceId: "mlx-community/Qwen3.5-4B-MLX-4bit",
                parameterCount: "4B",
                quantization: "4-bit",
                estimatedSizeGB: 2.6,
                minDeviceRAM: 12,
                family: .qwen35,
                logoName: "qwen_logo",
                supportsThinking: true,
                supportsVision: true,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "gemma3-1b-4bit",
                displayName: "Gemma 3 1B",
                huggingFaceId: "mlx-community/gemma-3-1b-it-4bit",
                parameterCount: "1B",
                quantization: "4-bit",
                estimatedSizeGB: 0.8,
                minDeviceRAM: 8,
                family: .gemma3,
                logoName: "gemma_logo",
                supportsThinking: false,
                supportsVision: true,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "gemma3-4b-4bit",
                displayName: "Gemma 3 4B",
                huggingFaceId: "mlx-community/gemma-3-4b-it-4bit",
                parameterCount: "4B",
                quantization: "4-bit",
                estimatedSizeGB: 2.8,
                minDeviceRAM: 12,
                family: .gemma3,
                logoName: "gemma_logo",
                supportsThinking: false,
                supportsVision: true,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "lfm2-1.5b-4bit",
                displayName: "LFM2 1.5B",
                huggingFaceId: "mlx-community/LFM2-1.5B-4bit",
                parameterCount: "1.5B",
                quantization: "4-bit",
                estimatedSizeGB: 1.0,
                minDeviceRAM: 8,
                family: .lfm2,
                logoName: "lfm_logo",
                supportsThinking: false,
                supportsVision: false,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "lfm2.5-350m-4bit",
                displayName: "LFM2.5 350M",
                huggingFaceId: "mlx-community/LFM2.5-350M-4bit",
                parameterCount: "350M",
                quantization: "4-bit",
                estimatedSizeGB: 0.2,
                minDeviceRAM: 8,
                family: .lfm25,
                logoName: "lfm_logo",
                supportsThinking: false,
                supportsVision: false,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "lfm2.5-1.2b-thinking-4bit",
                displayName: "LFM2.5 1.2B Thinking",
                huggingFaceId: "mlx-community/LFM2.5-1.2B-Thinking-4bit",
                parameterCount: "1.2B",
                quantization: "4-bit",
                estimatedSizeGB: 0.8,
                minDeviceRAM: 8,
                family: .lfm25,
                logoName: "lfm_logo",
                supportsThinking: true,
                supportsVision: false,
                prefersThinkingEnabled: true
            ),
        ]
    }

    enum Storage {
        static let modelsDirectory = "Models"
        static let conversationsDirectory = "Conversations"
        static let personasDirectory = "Personas"
        static let documentsDirectory = "Documents"
        static let documentMetadataDirectory = "DocumentMetadata"
        static let documentIndexesDirectory = "DocumentIndexes"
        static let downloadedModelsManifest = "downloaded_models.json"
    }

    enum Generation {
        static let defaultTemperature: Float = 0.7
        static let defaultTopP: Float = 1.0
        static let defaultRepetitionPenalty: Float = 1.0
        static let standardMaxTokens = 4096
        static let compactModelThinkingMaxTokens = 8192
        static let thinkingMaxTokens = 4096
        static let memoryConstrainedThinkingMaxTokens = 2048
        static let finalAnswerMaxTokens = 256
        static let lowMemoryAbortThresholdMB: UInt64 = 350
        static let lowMemoryCheckInterval = 32
        static let repetitiveThinkingCheckStartTokens = 160
        static let repetitiveThinkingDuplicateLineThreshold = 3
        static let conciseThinkingInstruction = """
        When thinking is enabled, keep the hidden reasoning brief and efficient. Use a short plan only, avoid repeated self-corrections, do not repeat the same outline or numbered list, and move to the final answer quickly.
        """
        static let finalAnswerOnlyInstruction = """
        Provide only the final answer to the user's last request. Do not include reasoning, planning, hidden thoughts, or meta commentary.
        """
    }

    enum RAG {
        static let chunkWordTarget = 220
        static let chunkWordOverlap = 50
        static let maxRetrievedChunks = 4
        static let maxContextCharacters = 4_000
        static let maxPreviewCharacters = 220
    }
}
