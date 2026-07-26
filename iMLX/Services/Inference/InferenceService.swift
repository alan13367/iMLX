import Foundation
import CoreGraphics
import CoreImage
import CryptoKit
import ImageIO
import MLX
import MLXFFT
import MLXLMCommon
import MLXLMTokenizers
import MLXVLM

actor InferenceService {
    private struct ConversationSessionCache {
        let key: String
        let modelId: String
        let historyFingerprint: String
        let systemPrompt: String
        let thinkingEnabled: Bool?
        let generationCacheSignature: String
        let session: ChatSession
    }

    private var modelContainer: ModelContainer?
    private var loadedModelId: String?
    private var loadedModelSupportsVision = false
    private var visionFeaturesEnabled = false
    private var wiredMemoryBudgetBytes: Int?
    private var kokoroTTS: KokoroTTS?
    private var kokoroVoiceEmbedding: MLXArray?
    private var kokoroAssets: SpeechAssetFileLocations?
    private var kokoroVoiceLocale: VoiceLocale?
    private var lastModelLoadMetrics: LLMModelLoadMetrics?
    private let profilingStore = LLMProfilingStore()
    private var latestProfile: LLMExecutionProfile?
    private var profileHistory: [LLMExecutionProfile] = []
    private var profilingSessions: [LLMProfilingSessionRecord] = []
    private var recoveredCrashReports: [LLMInferenceCrashReport] = []
    private var didLoadPersistedProfiles = false
    private var lastInProgressSnapshotPersistedAt: ContinuousClock.Instant?
    private let inProgressSnapshotMinInterval: Duration = .seconds(15)
    private var conversationSessionCache: ConversationSessionCache?

    var isModelLoaded: Bool {
        modelContainer != nil
    }

    func latestExecutionProfile() async -> LLMExecutionProfile? {
        await loadPersistedProfilesIfNeeded()
        return latestProfile
    }

    func executionProfileHistory() async -> [LLMExecutionProfile] {
        await loadPersistedProfilesIfNeeded()
        return profileHistory
    }

    func executionProfileSessions() async -> [LLMProfilingSessionRecord] {
        await loadPersistedProfilesIfNeeded()
        return profilingSessions
    }

    func recoveredInferenceCrashReports() async -> [LLMInferenceCrashReport] {
        await loadPersistedProfilesIfNeeded()
        return recoveredCrashReports
    }

    func deleteExecutionProfileSession(id: UUID) async {
        await loadPersistedProfilesIfNeeded()
        let persistedState = await profilingStore.deleteSession(id: id)
        profilingSessions = persistedState.sessions
        profileHistory = persistedState.profiles
        recoveredCrashReports = persistedState.crashReports
        latestProfile = profileHistory.max { $0.createdAt < $1.createdAt }
    }

    func load(modelId: String, modelName: String? = nil, localDirectory: URL, appRegistrySupportsVision: Bool? = nil) async throws {
        #if targetEnvironment(simulator)
        throw InferenceError.simulatorUnsupported
        #else
        if isModelLoaded {
            await unload()
        }
        lastModelLoadMetrics = nil
        MLX.Memory.cacheLimit = InferenceOptimizationPolicy.defaultCacheLimitBytes()
        MLX.Memory.memoryLimit = InferenceOptimizationPolicy.memoryLimitBytes()
        MLX.Memory.clearCache()

        let configSupportsVision = detectVisionSupport(in: localDirectory)
        let appSaysVision = appRegistrySupportsVision ?? false
        let shouldPreferVisionLoader = configSupportsVision && appSaysVision
        let displayName = modelName ?? modelId
        let memoryBeforeLoad = LLMProfiler.currentMemoryFootprintBytes()
        let loadTimer = LLMProfiler.Timer()
        let loadSignpost = LLMProfiler.beginInterval("Model Loading")
        let tokenizerLoader = ProfilingTokenizerLoader()
        let budgetBytes = InferenceWiredMemory.budgetBytes(
            weightBytes: InferenceWiredMemory.estimatedModelWeightBytes(in: localDirectory)
        )

        do {
            let container = try await InferenceWiredMemory.withBudget(bytes: budgetBytes) {
                if shouldPreferVisionLoader {
                    return try await VLMModelFactory.shared.loadContainer(
                        from: localDirectory,
                        using: tokenizerLoader
                    )
                }

                return try await MLXLMCommon.loadModelContainer(
                    from: localDirectory,
                    using: tokenizerLoader
                )
            }

            let modelLoadDuration = loadTimer.elapsedSeconds()
            let memoryAfterLoad = LLMProfiler.currentMemoryFootprintBytes()
            modelContainer = container
            loadedModelId = modelId
            loadedModelSupportsVision = shouldPreferVisionLoader
            visionFeaturesEnabled = shouldPreferVisionLoader
            wiredMemoryBudgetBytes = budgetBytes
            LLMProfiler.endInterval("Model Loading", loadSignpost)

            let warmupDuration = await warmUpLoadedModel(container)
            lastModelLoadMetrics = LLMModelLoadMetrics(
                modelName: displayName,
                modelLoadDuration: modelLoadDuration,
                tokenizerLoadDuration: await tokenizerLoader.duration,
                memoryBeforeModelLoad: memoryBeforeLoad,
                memoryAfterModelLoad: memoryAfterLoad,
                modelWarmupDuration: warmupDuration
            )
        } catch {
            LLMProfiler.endInterval("Model Loading", loadSignpost)
            MLX.Memory.clearCache()
            throw error
        }
        #endif
    }

    /// Runs a throwaway single-token generation so the user's first real message does not also pay
    /// for Metal kernel compilation and first-touch allocation.
    private func warmUpLoadedModel(_ container: ModelContainer) async -> TimeInterval? {
        let signpost = LLMProfiler.beginInterval("Model Warm-up")
        let timer = LLMProfiler.Timer()
        defer { LLMProfiler.endInterval("Model Warm-up", signpost) }

        var parameters = GenerateParameters(temperature: 0)
        parameters.maxTokens = 1
        let session = ChatSession(container, generateParameters: parameters)

        do {
            try await InferenceWiredMemory.withBudget(bytes: wiredMemoryBudgetBytes) {
                for try await _ in session.streamDetails(
                    to: "Hi",
                    role: .user,
                    images: [],
                    videos: []
                ) {
                    try Task.checkCancellation()
                }
            }
        } catch {
            return nil
        }
        return timer.elapsedSeconds()
    }

    func invalidateConversationSessionCache() {
        conversationSessionCache = nil
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
        repetitionPenalty: Float = 1.0,
        topK: Int? = nil,
        minP: Float? = nil,
        seed: UInt64? = nil,
        modelName: String? = nil,
        profileRunLabel: String = "Local LLM Inference",
        promptConstructionDuration: TimeInterval? = nil,
        profilingContext: LLMProfilingRunContext? = nil,
        conversationCacheKey: String? = nil,
        conversationCacheUserText: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let contextMessageCount = (systemPrompt.isEmpty ? 0 : 1) + history.count + 1
        var contextCharacterCount = systemPrompt.count + prompt.count
        var contextTextBytes = systemPrompt.utf8.count + prompt.utf8.count
        var contextMediaBytes = images?.reduce(0) { $0 + $1.data.count } ?? 0
        var contextMediaAttachmentCount = images?.count ?? 0

        for message in history {
            contextCharacterCount += message.content.count
            contextTextBytes += message.content.utf8.count
            if let attachedImages = message.attachedImages {
                contextMediaAttachmentCount += attachedImages.count
                contextMediaBytes += attachedImages.reduce(0) { $0 + $1.data.count }
            }
        }
        let contextTotalBytes = contextTextBytes + contextMediaBytes

        return AsyncThrowingStream<String, Error> { continuation in
            #if targetEnvironment(simulator)
            var profile = makeExecutionProfile(
                runLabel: profileRunLabel,
                modelName: modelName,
                promptCharacterCount: prompt.count,
                contextMessageCount: contextMessageCount,
                contextCharacterCount: contextCharacterCount,
                contextTextBytes: contextTextBytes,
                contextMediaAttachmentCount: contextMediaAttachmentCount,
                contextMediaBytes: contextMediaBytes,
                contextTotalBytes: contextTotalBytes,
                promptConstructionDuration: promptConstructionDuration,
                profilingContext: profilingContext
            )
            profile.errorInfo = LLMProfiler.errorInfo(from: InferenceError.simulatorUnsupported)
            recordExecutionProfileInMemory(profile)
            let profilingStore = profilingStore
            Task {
                await profilingStore.recordCompletedProfile(profile)
            }
            continuation.finish(throwing: InferenceError.simulatorUnsupported)
            return
            #else
            guard let modelContainer else {
                var profile = makeExecutionProfile(
                    runLabel: profileRunLabel,
                    modelName: modelName,
                    promptCharacterCount: prompt.count,
                    contextMessageCount: contextMessageCount,
                    contextCharacterCount: contextCharacterCount,
                    contextTextBytes: contextTextBytes,
                    contextMediaAttachmentCount: contextMediaAttachmentCount,
                    contextMediaBytes: contextMediaBytes,
                    contextTotalBytes: contextTotalBytes,
                    promptConstructionDuration: promptConstructionDuration,
                    profilingContext: profilingContext
                )
                profile.errorInfo = LLMProfiler.errorInfo(from: InferenceError.noModelLoaded)
                recordExecutionProfileInMemory(profile)
                let profilingStore = profilingStore
                Task {
                    await profilingStore.recordCompletedProfile(profile)
                }
                continuation.finish(throwing: InferenceError.noModelLoaded)
                return
            }

            let userInputImages = userInputImages(from: images)
            if let images, !images.isEmpty {
                guard !userInputImages.isEmpty else {
                    var profile = makeExecutionProfile(
                        runLabel: profileRunLabel,
                        modelName: modelName,
                        promptCharacterCount: prompt.count,
                        contextMessageCount: contextMessageCount,
                        contextCharacterCount: contextCharacterCount,
                        contextTextBytes: contextTextBytes,
                        contextMediaAttachmentCount: contextMediaAttachmentCount,
                        contextMediaBytes: contextMediaBytes,
                        contextTotalBytes: contextTotalBytes,
                        promptConstructionDuration: promptConstructionDuration,
                        profilingContext: profilingContext
                    )
                    profile.errorInfo = LLMProfiler.errorInfo(from: InferenceError.invalidImageData)
                    recordExecutionProfileInMemory(profile)
                    let profilingStore = profilingStore
                    Task {
                        await profilingStore.recordCompletedProfile(profile)
                    }
                    continuation.finish(throwing: InferenceError.invalidImageData)
                    return
                }
                guard loadedModelSupportsVision && visionFeaturesEnabled else {
                    var profile = makeExecutionProfile(
                        runLabel: profileRunLabel,
                        modelName: modelName,
                        promptCharacterCount: prompt.count,
                        contextMessageCount: contextMessageCount,
                        contextCharacterCount: contextCharacterCount,
                        contextTextBytes: contextTextBytes,
                        contextMediaAttachmentCount: contextMediaAttachmentCount,
                        contextMediaBytes: contextMediaBytes,
                        contextTotalBytes: contextTotalBytes,
                        promptConstructionDuration: promptConstructionDuration,
                        profilingContext: profilingContext
                    )
                    profile.errorInfo = LLMProfiler.errorInfo(from: InferenceError.visionUnsupportedModel)
                    recordExecutionProfileInMemory(profile)
                    let profilingStore = profilingStore
                    Task {
                        await profilingStore.recordCompletedProfile(profile)
                    }
                    continuation.finish(throwing: InferenceError.visionUnsupportedModel)
                    return
                }
            }

            let loadMetrics = lastModelLoadMetrics
            let resolvedModelName = modelName ?? loadMetrics?.modelName ?? "Unknown Model"
            let task = Task {
                await loadPersistedProfilesIfNeeded()
                lastInProgressSnapshotPersistedAt = nil
                var profile = makeExecutionProfile(
                    runLabel: profileRunLabel,
                    modelName: resolvedModelName,
                    promptCharacterCount: prompt.count,
                    contextMessageCount: contextMessageCount,
                    contextCharacterCount: contextCharacterCount,
                    contextTextBytes: contextTextBytes,
                    contextMediaAttachmentCount: contextMediaAttachmentCount,
                    contextMediaBytes: contextMediaBytes,
                    contextTotalBytes: contextTotalBytes,
                    promptConstructionDuration: promptConstructionDuration,
                    profilingContext: profilingContext
                )
                var peakFootprintBytes = LLMProfiler.currentMemoryFootprintBytes() ?? 0
                let availableMemoryAtStart = LLMProfiler.availableMemoryBytes()
                profile.memoryAvailableAtInferenceStart = availableMemoryAtStart
                profile.memoryBeforeInference = peakFootprintBytes == 0 ? nil : peakFootprintBytes
                profile.recordMemoryFootprintSample(peakFootprintBytes: &peakFootprintBytes)
                profile.thermalStateBeforeInference = LLMProfiler.thermalStateDescription()
                profile.batteryLevelBeforeInference = await LLMProfiler.coarseBatteryLevel()
                let optimizationPlan = InferenceOptimizationPolicy.plan(
                    contextTextBytes: contextTextBytes,
                    contextMediaAttachmentCount: contextMediaAttachmentCount,
                    maxTokens: maxTokens,
                    availableMemoryBytes: availableMemoryAtStart,
                    modelIdentifier: profilingContext?.modelId,
                    modelName: resolvedModelName,
                    estimatedModelSizeGB: profilingContext?.estimatedSizeGB,
                    supportsVision: loadedModelSupportsVision,
                    allowsKVQuantization: InferenceOptimizationPolicy.allowsKVQuantization(
                        modelIdentifier: profilingContext?.modelId,
                        modelName: resolvedModelName,
                        supportsVision: loadedModelSupportsVision
                    )
                )
                profile.measurementNotes.append(
                    "Generation tuning: prefillStepSize=\(optimizationPlan.prefillStepSize), " +
                    "maxKVSize=\(optimizationPlan.maxKVSize.map(String.init) ?? "none"), " +
                    "kvBits=\(optimizationPlan.kvBits.map(String.init) ?? "none"), " +
                    "kvGroupSize=\(optimizationPlan.kvGroupSize), " +
                    "quantizedKVStart=\(optimizationPlan.quantizedKVStart), " +
                    "mlxCacheLimit=\(optimizationPlan.mlxCacheLimitBytes), " +
                    "visionInputSize=\(optimizationPlan.visionInputSize)."
                )
                if let seed {
                    profile.measurementNotes.append("Sampling seed: \(seed).")
                }
                MLX.Memory.cacheLimit = optimizationPlan.mlxCacheLimitBytes
                if optimizationPlan.shouldClearCacheBeforeGeneration {
                    MLX.Memory.clearCache()
                }

                let fullTimer = LLMProfiler.Timer()
                let fullSignpost = LLMProfiler.beginInterval("Full Local LLM Inference")
                var didEndFullSignpost = false
                func endFullSignpostIfNeeded() {
                    guard !didEndFullSignpost else { return }
                    LLMProfiler.endInterval("Full Local LLM Inference", fullSignpost)
                    didEndFullSignpost = true
                }

                func finishProfile(error: Error? = nil) async {
                    profile.totalInferenceDuration = fullTimer.elapsedSeconds()
                    profile.recordMemoryFootprintSample(peakFootprintBytes: &peakFootprintBytes)
                    profile.memoryAfterInference = LLMProfiler.currentMemoryFootprintBytes()
                    if let before = profile.memoryBeforeInference,
                       let after = profile.memoryAfterInference {
                        profile.memoryDelta = Int64(after) - Int64(before)
                    }
                    if profile.timeToFirstGeneratedToken == nil,
                       let firstChunk = profile.timeToFirstOutputChunk {
                        profile.timeToFirstGeneratedToken = firstChunk
                        profile.timeToFirstGeneratedTokenSource = "first_output_chunk_fallback"
                    }
                    profile.thermalStateAfterInference = LLMProfiler.thermalStateDescription()
                    profile.batteryLevelAfterInference = await LLMProfiler.coarseBatteryLevel()
                    if let error {
                        profile.errorInfo = LLMProfiler.errorInfo(from: error)
                    }
                    await recordExecutionProfile(profile)
                    endFullSignpostIfNeeded()
                }

                do {
                    try await InferenceWiredMemory.withBudget(bytes: wiredMemoryBudgetBytes) {
                        let additionalContext: [String: any Sendable]? = thinkingEnabled.map { value in
                            ["enable_thinking": value]
                        }

                        var parameters = GenerateParameters(
                            temperature: temperature,
                            topP: topP
                        )
                        parameters.maxTokens = maxTokens
                        parameters.prefillStepSize = optimizationPlan.prefillStepSize
                        parameters.maxKVSize = optimizationPlan.maxKVSize
                        parameters.kvBits = optimizationPlan.kvBits
                        parameters.kvGroupSize = optimizationPlan.kvGroupSize
                        parameters.quantizedKVStart = optimizationPlan.quantizedKVStart
                        if repetitionPenalty != 1.0 {
                            parameters.repetitionPenalty = repetitionPenalty
                        }
                        if let topK {
                            parameters.topK = topK
                        }
                        if let minP {
                            parameters.minP = minP
                        }
                        parameters.seed = seed

                        let sessionHistory = loadedModelSupportsVision
                            ? history.map(\.chatMessage)
                            : history.map(\.chatMessageStrippingImages)
                        let historyFingerprint = Self.historyFingerprint(history)
                        let cacheSignature = Self.generationCacheSignature(
                            optimizationPlan: optimizationPlan,
                            supportsVision: loadedModelSupportsVision
                        )
                        let historyHasImages = history.contains {
                            !($0.attachedImages?.isEmpty ?? true)
                        }
                        // Prefix reuse is safe for vision-capable models on text-only turns.
                        // Any image in the live turn or prior history forces a full rebuild.
                        let canUseConversationCache = conversationCacheKey != nil
                            && userInputImages.isEmpty
                            && !historyHasImages
                        let session: ChatSession
                        if canUseConversationCache,
                           let conversationCacheKey,
                           let loadedModelId,
                           let cached = conversationSessionCache,
                           cached.key == conversationCacheKey,
                           cached.modelId == loadedModelId,
                           cached.historyFingerprint == historyFingerprint,
                           cached.systemPrompt == systemPrompt,
                           cached.thinkingEnabled == thinkingEnabled,
                           cached.generationCacheSignature == cacheSignature {
                            session = cached.session
                            session.generateParameters = parameters
                            session.additionalContext = additionalContext
                            profile.measurementNotes.append("Validated conversation prefix cache hit.")
                        } else {
                            session = ChatSession(
                                modelContainer,
                                instructions: systemPrompt.isEmpty ? nil : systemPrompt,
                                history: sessionHistory,
                                generateParameters: parameters,
                                processing: .init(
                                    resize: CGSize(
                                        width: optimizationPlan.visionInputSize,
                                        height: optimizationPlan.visionInputSize
                                    )
                                ),
                                additionalContext: additionalContext
                            )
                            if conversationCacheKey != nil {
                                profile.measurementNotes.append("Conversation prefix cache miss; rebuilt from visible history.")
                            }
                        }

                        let stream = session.streamDetails(
                            to: prompt,
                            role: .user,
                            images: userInputImages,
                            videos: []
                        )

                        do {
                            let decodeSignpost = LLMProfiler.beginInterval("Decode / Token Generation")
                            defer {
                                LLMProfiler.endInterval("Decode / Token Generation", decodeSignpost)
                            }
                            let streamSetupTimer = LLMProfiler.Timer()
                            var decodeTimer: LLMProfiler.Timer?
                            var emittedTextChunkCount = 0
                            var emittedTextCharacterCount = 0
                            var generatedText = ""
                            var receivedCompletionInfo = false
                            var lastDecodeProgressSnapshot = 0.0

                            generationLoop: for try await generation in stream {
                                try Task.checkCancellation()

                                switch generation {
                                case .chunk(let chunk):
                                    generatedText.append(chunk)
                                    if profile.tokenizationDuration == nil {
                                        profile.tokenizationDuration = streamSetupTimer.elapsedSeconds()
                                        saveInProgressProfile(
                                            &profile,
                                            peakFootprintBytes: &peakFootprintBytes,
                                            stage: "tokenized_input"
                                        )
                                    }
                                    emittedTextChunkCount += 1
                                    emittedTextCharacterCount += chunk.count
                                    profile.outputTextChunkCount = emittedTextChunkCount
                                    profile.outputCharacterCount = emittedTextCharacterCount
                                    if profile.timeToFirstOutputChunk == nil {
                                        profile.timeToFirstOutputChunk = fullTimer.elapsedSeconds()
                                        LLMProfiler.emitEvent("Detokenization")
                                        let yieldResult = continuation.yield(chunk)
                                        lastDecodeProgressSnapshot = fullTimer.elapsedSeconds()
                                        saveInProgressProfile(
                                            &profile,
                                            peakFootprintBytes: &peakFootprintBytes,
                                            stage: "first_output_chunk",
                                            emittedTextChunkCount: emittedTextChunkCount,
                                            emittedTextCharacterCount: emittedTextCharacterCount
                                        )
                                        decodeTimer = LLMProfiler.Timer()
                                        if case .terminated = yieldResult {
                                            profile.stopReason = "cancelled"
                                            break generationLoop
                                        }
                                        continue
                                    }
                                    if case .terminated = continuation.yield(chunk) {
                                        profile.stopReason = "cancelled"
                                        break generationLoop
                                    }
                                    let elapsed = fullTimer.elapsedSeconds()
                                    if elapsed - lastDecodeProgressSnapshot >= 15 {
                                        profile.decodeGenerationDuration = decodeTimer?.elapsedSeconds()
                                        profile.decodeGenerationDurationSource = "in_progress_consumer_wall_clock_decode_loop"
                                        saveInProgressProfile(
                                            &profile,
                                            peakFootprintBytes: &peakFootprintBytes,
                                            stage: "decode_progress",
                                            emittedTextChunkCount: emittedTextChunkCount,
                                            emittedTextCharacterCount: emittedTextCharacterCount,
                                            writeSessionExport: false
                                        )
                                        lastDecodeProgressSnapshot = elapsed
                                    }

                                case .info(let info):
                                    receivedCompletionInfo = true
                                    profile.inputTokenCount = info.promptTokenCount
                                    profile.outputTokenCount = info.generationTokenCount
                                    profile.prefillPromptEvaluationDuration = info.promptTime
                                    profile.prefillPromptEvaluationDurationSource = "mlx_generate_completion_info_prompt_time"
                                    profile.decodeGenerationDuration = info.generateTime
                                    profile.decodeGenerationDurationSource = "mlx_generate_completion_info_generate_time"
                                    profile.stopReason = Self.stopReasonDescription(info.stopReason)
                                    if info.generateTime > 0 {
                                        profile.tokensPerSecond = Double(info.generationTokenCount) / info.generateTime
                                        profile.tokensPerSecondMeasurement = "mlx_generate_completion_info"
                                    }
                                    if let firstOutput = profile.timeToFirstOutputChunk {
                                        profile.tokenizationDuration = max(0, firstOutput - info.promptTime)
                                        profile.timeToFirstGeneratedToken = firstOutput
                                        profile.timeToFirstGeneratedTokenSource =
                                            "first_output_chunk_correlated_with_mlx_completion_info"
                                    } else {
                                        profile.tokenizationDuration = max(
                                            0,
                                            fullTimer.elapsedSeconds() - info.promptTime - info.generateTime
                                        )
                                    }

                                case .toolCall:
                                    continue
                                }
                            }

                            if profile.stopReason == nil {
                                profile.stopReason = "stream_completed"
                                profile.decodeGenerationDuration = decodeTimer?.elapsedSeconds()
                                profile.decodeGenerationDurationSource = "consumer_wall_clock_decode_loop"
                            }

                            if canUseConversationCache,
                               receivedCompletionInfo,
                               profile.stopReason != "cancelled",
                               let conversationCacheKey,
                               let loadedModelId {
                                // ChatViewModel only enables caching when the generation prompt
                                // matches the visible user text, keeping the session and fingerprint aligned.
                                var completedHistory = history
                                completedHistory.append(
                                    .init(
                                        role: .user,
                                        content: conversationCacheUserText ?? prompt
                                    )
                                )
                                completedHistory.append(.init(role: .assistant, content: generatedText))
                                session.instructions = nil
                                conversationSessionCache = ConversationSessionCache(
                                    key: conversationCacheKey,
                                    modelId: loadedModelId,
                                    historyFingerprint: Self.historyFingerprint(completedHistory),
                                    systemPrompt: systemPrompt,
                                    thinkingEnabled: thinkingEnabled,
                                    generationCacheSignature: cacheSignature,
                                    session: session
                                )
                            } else if conversationCacheKey != nil {
                                conversationSessionCache = nil
                            }
                        }
                    }

                    await finishProfile()
                    if profile.stopReason == "cancelled"
                        || InferenceOptimizationPolicy.shouldReclaimCache(
                            availableMemoryBytes: LLMProfiler.availableMemoryBytes()
                        )
                    {
                        conversationSessionCache = nil
                        MLX.Memory.clearCache()
                    }
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        profile.stopReason = "cancelled"
                    }
                    let mappedError = Task.isCancelled
                        ? InferenceError.generationCancelled
                        : mapError(error)
                    await finishProfile(error: Task.isCancelled ? nil : mappedError)
                    MLX.Memory.clearCache()
                    if Task.isCancelled {
                        continuation.finish(throwing: InferenceError.generationCancelled)
                    } else {
                        continuation.finish(throwing: mappedError)
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
            #endif
        }
    }

    func benchmark(
        prompt: String,
        iterations: Int,
        systemPrompt: String,
        maxTokens: Int,
        temperature: Float = 0.7,
        topP: Float = 1.0,
        repetitionPenalty: Float = 1.0,
        modelName: String? = nil,
        profilingContext: LLMProfilingRunContext? = nil
    ) async throws -> LLMBenchmarkResult {
        let iterationCount = max(0, iterations)
        var profiles: [LLMExecutionProfile] = []
        profiles.reserveCapacity(iterationCount)

        for iteration in 0..<iterationCount {
            // Iterations stay distinct from each other but the run as a whole is reproducible,
            // so throughput comparisons are not muddied by different sampled outputs.
            let stream = generate(
                prompt: prompt,
                history: [],
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty,
                seed: Constants.Generation.reproducibleRunSeed &+ UInt64(iteration),
                modelName: modelName,
                profileRunLabel: "Benchmark",
                profilingContext: profilingContext
            )
            for try await _ in stream {
                try Task.checkCancellation()
            }
            if let latestProfile {
                profiles.append(latestProfile)
            }
        }

        return LLMBenchmarkResult(prompt: prompt, profiles: profiles)
    }

    func runIFBench(
        prompts: [IFBenchPrompt],
        systemPrompt: String,
        maxTokens: Int,
        temperature: Float = 0,
        topP: Float = 1.0,
        repetitionPenalty: Float = 1.0,
        modelName: String? = nil,
        profilingContext: LLMProfilingRunContext? = nil,
        progress: (@MainActor @Sendable (_ completedPrompts: Int, _ totalPrompts: Int) -> Void)? = nil
    ) async throws -> IFBenchRunResult {
        var responseRecords: [IFBenchResponseRecord] = []
        var profiles: [LLMExecutionProfile] = []
        responseRecords.reserveCapacity(prompts.count)
        profiles.reserveCapacity(prompts.count)

        for item in prompts {
            var response = ""
            let stream = generate(
                prompt: item.prompt,
                history: [],
                systemPrompt: systemPrompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty,
                seed: Constants.Generation.reproducibleRunSeed,
                modelName: modelName,
                profileRunLabel: "IFBench",
                profilingContext: profilingContext
            )

            for try await chunk in stream {
                try Task.checkCancellation()
                response += chunk
            }

            let profile = latestProfile
            if let profile {
                profiles.append(profile)
            }
            responseRecords.append(
                IFBenchResponseRecord(
                    key: item.key,
                    prompt: item.prompt,
                    response: response,
                    profileID: profile?.id
                )
            )
            if let progress {
                await progress(responseRecords.count, prompts.count)
            }
        }

        return IFBenchRunResult(
            modelName: modelName ?? lastModelLoadMetrics?.modelName ?? "Unknown Model",
            runContext: profilingContext,
            responseRecords: responseRecords,
            profiles: profiles
        )
    }

    func unload() async {
        let wasLoaded = modelContainer != nil
        modelContainer = nil
        loadedModelId = nil
        loadedModelSupportsVision = false
        visionFeaturesEnabled = false
        lastModelLoadMetrics = nil
        conversationSessionCache = nil
        wiredMemoryBudgetBytes = nil

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
        var combinedAudio: [Float] = []
        let stream = synthesizeSpeechStream(text: text, locale: locale, assets: assets)
        for try await chunk in stream {
            combinedAudio.append(contentsOf: chunk.samples)
        }
        return SynthesizedSpeech(
            samples: combinedAudio,
            sampleRate: Double(KokoroTTS.Constants.samplingRate)
        )
    }

    func synthesizeSpeechStream(
        text: String,
        locale: VoiceLocale,
        assets: SpeechAssetFileLocations
    ) -> AsyncThrowingStream<SynthesizedSpeech, Error> {
        #if targetEnvironment(simulator)
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: InferenceError.simulatorUnsupported)
        }
        #else
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard locale.supportsLiveKokoroSynthesis else {
                        throw InferenceError.unsupportedSpeechLocale(locale.displayName)
                    }

                    // Speech runs between chat turns, so dropping the buffer pool unconditionally
                    // would make every spoken reply cost the next generation a cold cache.
                    if InferenceOptimizationPolicy.shouldReclaimCache(
                        availableMemoryBytes: LLMProfiler.availableMemoryBytes()
                    ) {
                        MLX.Memory.clearCache()
                    }

                    if kokoroAssets != assets || kokoroTTS == nil || kokoroVoiceEmbedding == nil
                        || kokoroVoiceLocale != locale
                    {
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

                    let clearCacheBetweenStages = InferenceOptimizationPolicy
                        .shouldClearCacheBetweenSpeechStages(
                            availableMemoryBytes: LLMProfiler.availableMemoryBytes()
                        )
                    for index in chunks.indices {
                        try Task.checkCancellation()
                        var samples = try kokoroTTS.generateAudio(
                            voice: voiceEmbedding,
                            language: language,
                            text: chunks[index],
                            clearCacheBetweenStages: clearCacheBetweenStages
                        ).0
                        if index < chunks.index(before: chunks.endIndex) {
                            samples.append(contentsOf: repeatElement(Float.zero, count: 2_400))
                        }
                        if case .terminated = continuation.yield(
                            SynthesizedSpeech(
                                samples: samples,
                                sampleRate: Double(KokoroTTS.Constants.samplingRate)
                            )
                        ) {
                            break
                        }
                    }

                    if InferenceOptimizationPolicy.shouldReclaimCache(
                        availableMemoryBytes: LLMProfiler.availableMemoryBytes()
                    ) {
                        MLX.Memory.clearCache()
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        #endif
    }

    func unloadSpeechSynthesisResources() {
        releaseSpeechSynthesisResources()
    }

    private func speechChunks(for text: String) -> [String] {
        InferenceInputPolicy.speechChunks(
            for: text,
            maximumInputCharacters: Constants.SpeechSynthesis.maxInputCharacters,
            maximumChunks: Constants.SpeechSynthesis.maxChunks
        )
    }

    private func releaseSpeechSynthesisResources() {
        kokoroTTS = nil
        kokoroVoiceEmbedding = nil
        kokoroAssets = nil
        kokoroVoiceLocale = nil
        MLX.Memory.clearCache()
    }

    private func detectVisionSupport(in directory: URL) -> Bool {
        InferenceInputPolicy.modelConfigurationSupportsVision(in: directory)
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

    private func loadPersistedProfilesIfNeeded() async {
        guard !didLoadPersistedProfiles else { return }
        let persistedState = await profilingStore.loadPersistedState()
        profilingSessions = persistedState.sessions
        for profile in persistedState.profiles {
            recordExecutionProfileInMemory(profile)
        }
        recoveredCrashReports = persistedState.crashReports
        profileHistory.sort { $0.createdAt < $1.createdAt }
        latestProfile = profileHistory.max { $0.createdAt < $1.createdAt }
        didLoadPersistedProfiles = true
    }

    private func makeExecutionProfile(
        runLabel: String,
        modelName: String?,
        promptCharacterCount: Int,
        contextMessageCount: Int,
        contextCharacterCount: Int,
        contextTextBytes: Int,
        contextMediaAttachmentCount: Int,
        contextMediaBytes: Int,
        contextTotalBytes: Int,
        promptConstructionDuration: TimeInterval?,
        profilingContext: LLMProfilingRunContext?
    ) -> LLMExecutionProfile {
        LLMExecutionProfile(
            runLabel: runLabel,
            modelName: modelName ?? lastModelLoadMetrics?.modelName ?? "Unknown Model",
            promptCharacterCount: promptCharacterCount,
            contextMessageCount: contextMessageCount,
            contextCharacterCount: contextCharacterCount,
            contextTextBytes: contextTextBytes,
            contextMediaAttachmentCount: contextMediaAttachmentCount,
            contextMediaBytes: contextMediaBytes,
            contextTotalBytes: contextTotalBytes,
            modelLoadMetrics: lastModelLoadMetrics,
            promptConstructionDuration: promptConstructionDuration,
            profilingContext: profilingContext
        )
    }

    private func saveInProgressProfile(
        _ profile: inout LLMExecutionProfile,
        peakFootprintBytes: inout UInt64,
        stage: String,
        emittedTextChunkCount: Int? = nil,
        emittedTextCharacterCount: Int? = nil,
        writeSessionExport: Bool = true
    ) {
        profile.recordMemoryFootprintSample(peakFootprintBytes: &peakFootprintBytes)
        let profileSnapshot = profile
        let profilingStore = profilingStore
        let memoryFootprintBytes = LLMProfiler.currentMemoryFootprintBytes()
        let thermalState = LLMProfiler.thermalStateDescription()
        let persistInProgressSnapshot = shouldPersistInProgressSnapshot(for: stage)
        Task {
            await profilingStore.saveInProgressProfile(
                profileSnapshot,
                stage: stage,
                memoryFootprintBytes: memoryFootprintBytes,
                thermalState: thermalState,
                batteryLevel: nil,
                emittedTextChunkCount: emittedTextChunkCount,
                emittedTextCharacterCount: emittedTextCharacterCount,
                persistInProgressSnapshot: persistInProgressSnapshot,
                writeSessionExport: writeSessionExport
            )
        }
    }

    private func shouldPersistInProgressSnapshot(for stage: String) -> Bool {
        switch stage {
        case "tokenized_input", "first_output_chunk":
            lastInProgressSnapshotPersistedAt = ContinuousClock().now
            return true
        case "decode_progress":
            let now = ContinuousClock().now
            if let lastPersisted = lastInProgressSnapshotPersistedAt,
               lastPersisted.duration(to: now) < inProgressSnapshotMinInterval {
                return false
            }
            lastInProgressSnapshotPersistedAt = now
            return true
        default:
            return false
        }
    }

    private func recordExecutionProfile(_ profile: LLMExecutionProfile) async {
        recordExecutionProfileInMemory(profile)
        let session = await profilingStore.recordCompletedProfile(profile)
        recordProfilingSessionInMemory(session)
    }

    private func recordExecutionProfileInMemory(_ profile: LLMExecutionProfile) {
        latestProfile = profile
        if let index = profileHistory.firstIndex(where: { $0.id == profile.id }) {
            profileHistory[index] = profile
        } else {
            profileHistory.append(profile)
        }
    }

    private func recordProfilingSessionInMemory(_ session: LLMProfilingSessionRecord) {
        if let index = profilingSessions.firstIndex(where: { $0.id == session.id }) {
            profilingSessions[index] = session
        } else {
            profilingSessions.append(session)
        }
        profilingSessions.sort { $0.startedAt < $1.startedAt }
        recoveredCrashReports = profilingSessions
            .flatMap(\.crashReports)
            .sorted { $0.recoveredAt < $1.recoveredAt }
    }

    private nonisolated static func stopReasonDescription(_ stopReason: GenerateStopReason) -> String {
        switch stopReason {
        case .stop:
            return "stop"
        case .length:
            return "length"
        case .cancelled:
            return "cancelled"
        }
    }

    private nonisolated static func historyFingerprint(_ history: [ChatMessage]) -> String {
        var hasher = SHA256()
        for message in history {
            hasher.update(data: Data(message.role.rawValue.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(message.content.utf8))
            hasher.update(data: Data([0xff]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func generationCacheSignature(
        optimizationPlan: InferenceOptimizationPlan,
        supportsVision: Bool
    ) -> String {
        [
            optimizationPlan.maxKVSize.map(String.init) ?? "none",
            optimizationPlan.kvBits.map(String.init) ?? "none",
            String(optimizationPlan.kvGroupSize),
            String(optimizationPlan.quantizedKVStart),
            supportsVision ? "vision" : "text",
        ].joined(separator: ":")
    }
}
