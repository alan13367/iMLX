import Foundation

nonisolated enum Constants {
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
                supportsThinking: false,
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
                supportsVision: false,
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
                id: "gemma4-e2b-it-4bit",
                displayName: "Gemma 4 E2B",
                huggingFaceId: "mlx-community/gemma-4-e2b-it-4bit",
                parameterCount: "E2B",
                quantization: "4-bit",
                estimatedSizeGB: 3.6,
                minDeviceRAM: 12,
                family: .gemma4,
                logoName: "gemma_logo",
                supportsThinking: true,
                supportsVision: true,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "gemma4-e4b-it-4bit",
                displayName: "Gemma 4 E4B",
                huggingFaceId: "mlx-community/gemma-4-e4b-it-4bit",
                parameterCount: "E4B",
                quantization: "4-bit",
                estimatedSizeGB: 5.2,
                minDeviceRAM: 16,
                family: .gemma4,
                logoName: "gemma_logo",
                supportsThinking: true,
                supportsVision: true,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "ministral-3-3b-instruct-4bit",
                displayName: "Ministral 3 3B Instruct",
                huggingFaceId: "mlx-community/Ministral-3-3B-Instruct-2512-4bit",
                parameterCount: "3B",
                quantization: "4-bit",
                estimatedSizeGB: 1.9,
                minDeviceRAM: 12,
                family: .mistral3,
                logoName: "mistral_logo",
                supportsThinking: false,
                supportsVision: false,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "ministral-3-3b-reasoning-4bit",
                displayName: "Ministral 3 3B Reasoning",
                huggingFaceId: "mlx-community/Ministral-3-3B-Reasoning-2512-4bit",
                parameterCount: "3B",
                quantization: "4-bit",
                estimatedSizeGB: 1.9,
                minDeviceRAM: 12,
                family: .mistral3,
                logoName: "mistral_logo",
                supportsThinking: false,
                supportsVision: false,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "ministral-3-8b-instruct-4bit",
                displayName: "Ministral 3 8B Instruct",
                huggingFaceId: "mlx-community/Ministral-3-8B-Instruct-2512-4bit",
                parameterCount: "8B",
                quantization: "4-bit",
                estimatedSizeGB: 4.8,
                minDeviceRAM: 16,
                family: .mistral3,
                logoName: "mistral_logo",
                supportsThinking: false,
                supportsVision: false,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "ministral-3-8b-reasoning-4bit",
                displayName: "Ministral 3 8B Reasoning",
                huggingFaceId: "mlx-community/Ministral-3-8B-Reasoning-2512-4bit",
                parameterCount: "8B",
                quantization: "4-bit",
                estimatedSizeGB: 4.8,
                minDeviceRAM: 16,
                family: .mistral3,
                logoName: "mistral_logo",
                supportsThinking: false,
                supportsVision: false,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "ministral-3-14b-instruct-4bit",
                displayName: "Ministral 3 14B Instruct",
                huggingFaceId: "mlx-community/Ministral-3-14B-Instruct-2512-4bit",
                parameterCount: "14B",
                quantization: "4-bit",
                estimatedSizeGB: 8.3,
                minDeviceRAM: 24,
                family: .mistral3,
                logoName: "mistral_logo",
                supportsThinking: false,
                supportsVision: false,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "ministral-3-14b-reasoning-4bit",
                displayName: "Ministral 3 14B Reasoning",
                huggingFaceId: "mlx-community/Ministral-3-14B-Reasoning-2512-4bit",
                parameterCount: "14B",
                quantization: "4-bit",
                estimatedSizeGB: 8.3,
                minDeviceRAM: 24,
                family: .mistral3,
                logoName: "mistral_logo",
                supportsThinking: false,
                supportsVision: false,
                prefersThinkingEnabled: false
            ),
            ModelInfo(
                id: "lfm2-1.2b-4bit",
                displayName: "LFM2 1.2B",
                huggingFaceId: "mlx-community/LFM2-1.2B-4bit",
                parameterCount: "1.2B",
                quantization: "4-bit",
                estimatedSizeGB: 0.7,
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
                huggingFaceId: "LiquidAI/LFM2.5-350M-MLX-4bit",
                parameterCount: "350M",
                quantization: "4-bit",
                estimatedSizeGB: 0.3,
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
                estimatedSizeGB: 0.7,
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
        static let memoriesDirectory = "Memories"
        static let memoriesFilename = "user_memories.json"
        static let documentsDirectory = "Documents"
        static let documentMetadataDirectory = "DocumentMetadata"
        static let documentIndexesDirectory = "DocumentIndexes"
        static let downloadedModelsManifest = "downloaded_models.json"
        static let modelDownloadJobsManifest = "model_download_jobs.json"
        static let modelDownloadStagingDirectory = "ModelDownloadStaging"
        static let speechAssetsDirectory = "SpeechAssets"
        static let speechAssetsStateFilename = "speech_assets.json"
    }

    enum Generation {
        static let defaultTemperature: Float = 0.7
        static let defaultTopP: Float = 1.0
        static let defaultRepetitionPenalty: Float = 1.0
        static let standardMaxTokens = 4096
        static let memoryConstrainedStandardMaxTokens = 1024
        static let memoryConstrainedVisionMaxTokens = 1024
        static let lowHeadroomVisionMaxTokens = 256
        static let mediumHeadroomVisionMaxTokens = 512
        static let compactThinkingMaxSizeGB = 1.0
        static let mediumThinkingMaxSizeGB = 3.0
        static let largeThinkingMaxSizeGB = 5.5
        static let compactModelHiddenThinkingMaxTokens = 3072
        static let mediumModelHiddenThinkingMaxTokens = 2048
        static let largeModelHiddenThinkingMaxTokens = 1536
        static let extraLargeModelHiddenThinkingMaxTokens = 1024
        static let minimumFinalAnswerMaxTokens = 256
        static let minimumHiddenThinkingMaxTokens = 128
        static let memoryConstrainedHistoryMessageLimit = 8
        static let memoryConstrainedDocumentContextCharacters = 2_000
        static let mediumMemoryHeadroomMB: UInt64 = 1_200
        static let highMemoryHeadroomMB: UInt64 = 2_000
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

    enum Memory {
        static let maxRetrievedMemories = 4
        static let maxContextCharacters = 1_200
        static let memoryConstrainedContextCharacters = 600
        static let extractionMaxTokens = 256
        static let minimumCandidateCharacters = 8
        static let maximumCandidateCharacters = 220
        static let minimumBaseRetrievalScore = 0.12
        static let topicalAffinityScore = 0.24
        static let coreIdentityRetrievalScore = 0.14
        static let duplicateScoreThreshold = 0.82
        static let forgetMatchThreshold = 0.35
        static let personaMatchBoost = 0.12
        static let globalMemoryBoost = 0.04
        static let substringMatchBoost = 0.25
    }

    enum UI {
        static let streamingResponseFlushInterval: TimeInterval = 1.0 / 30.0
    }

    enum WebSearch {
        static let maxResults = 3
        static let maxContextCharacters = 6_000
        static let maxPreviewCharacters = 240
        static let chunkWordTarget = 140
        static let chunkWordOverlap = 24
    }
}
