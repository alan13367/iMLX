import Foundation

nonisolated struct LLMExecutionErrorInfo: Codable, Hashable, Sendable {
    let message: String
    let domain: String?
    let code: Int?
}

nonisolated struct LLMProfilingRunContext: Codable, Hashable, Sendable {
    let modelId: String?
    let parameterCount: String?
    let quantization: String?
    let estimatedSizeGB: Double?
    let maxTokens: Int
    let temperature: Float
    let topP: Float
    let repetitionPenalty: Float
    let thinkingEnabled: Bool?
    let devicePhysicalMemoryGB: Int

    init(
        model: ModelInfo?,
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        repetitionPenalty: Float,
        thinkingEnabled: Bool?
    ) {
        self.modelId = model?.id
        self.parameterCount = model?.parameterCount
        self.quantization = model?.quantization
        self.estimatedSizeGB = model?.estimatedSizeGB
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
        self.thinkingEnabled = thinkingEnabled
        self.devicePhysicalMemoryGB = LLMProfiler.devicePhysicalMemoryGB()
    }

    init(
        maxTokens: Int,
        temperature: Float,
        topP: Float,
        repetitionPenalty: Float,
        thinkingEnabled: Bool? = nil
    ) {
        self.modelId = nil
        self.parameterCount = nil
        self.quantization = nil
        self.estimatedSizeGB = nil
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
        self.thinkingEnabled = thinkingEnabled
        self.devicePhysicalMemoryGB = LLMProfiler.devicePhysicalMemoryGB()
    }
}

nonisolated struct LLMModelLoadMetrics: Codable, Hashable, Sendable {
    let modelName: String
    let modelLoadDuration: TimeInterval
    let tokenizerLoadDuration: TimeInterval?
    let memoryBeforeModelLoad: UInt64?
    let memoryAfterModelLoad: UInt64?
}

nonisolated struct LLMExecutionProfile: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let runLabel: String
    let modelName: String
    let deviceModel: String?
    let iOSVersion: String?
    let promptCharacterCount: Int
    let contextMessageCount: Int?
    let contextCharacterCount: Int?
    let contextTextBytes: Int?
    let contextMediaAttachmentCount: Int?
    let contextMediaBytes: Int?
    let contextTotalBytes: Int?
    var inputTokenCount: Int?
    var outputTokenCount: Int
    var outputTextChunkCount: Int?
    var outputCharacterCount: Int?
    var modelLoadDuration: TimeInterval?
    var tokenizerLoadDuration: TimeInterval?
    var promptConstructionDuration: TimeInterval?
    var tokenizationDuration: TimeInterval?
    var prefillPromptEvaluationDuration: TimeInterval?
    var prefillPromptEvaluationDurationSource: String
    var timeToFirstGeneratedToken: TimeInterval?
    var timeToFirstGeneratedTokenSource: String
    var timeToFirstOutputChunk: TimeInterval?
    var decodeGenerationDuration: TimeInterval?
    var decodeGenerationDurationSource: String
    var totalInferenceDuration: TimeInterval?
    var totalInferenceDurationScope: String
    var tokensPerSecond: Double?
    var tokensPerSecondMeasurement: String
    var memoryBeforeModelLoad: UInt64?
    var memoryAfterModelLoad: UInt64?
    var memoryBeforeInference: UInt64?
    var memoryAfterInference: UInt64?
    var memoryPeakDuringInference: UInt64?
    var memoryAvailableAtInferenceStart: UInt64?
    var memoryDelta: Int64?
    var memoryMeasurementKind: String
    var modelId: String?
    var parameterCount: String?
    var quantization: String?
    var estimatedSizeGB: Double?
    var maxTokens: Int?
    var temperature: Float?
    var topP: Float?
    var repetitionPenalty: Float?
    var thinkingEnabled: Bool?
    var devicePhysicalMemoryGB: Int?
    var thermalStateBeforeInference: String?
    var thermalStateAfterInference: String?
    var batteryLevelBeforeInference: Double?
    var batteryLevelAfterInference: Double?
    var isBatteryLevelCoarse: Bool
    var batteryMeasurementKind: String
    var energyMeasurementKind: String
    var stopReason: String?
    var errorInfo: LLMExecutionErrorInfo?
    var measurementNotes: [String]

    init(
        runLabel: String,
        modelName: String,
        promptCharacterCount: Int,
        contextMessageCount: Int = 1,
        contextCharacterCount: Int? = nil,
        contextTextBytes: Int? = nil,
        contextMediaAttachmentCount: Int = 0,
        contextMediaBytes: Int = 0,
        contextTotalBytes: Int? = nil,
        modelLoadMetrics: LLMModelLoadMetrics?,
        promptConstructionDuration: TimeInterval?,
        profilingContext: LLMProfilingRunContext? = nil
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.runLabel = runLabel
        self.modelName = modelName
        self.deviceModel = LLMProfiler.deviceModelIdentifier()
        self.iOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        self.promptCharacterCount = promptCharacterCount
        self.contextMessageCount = contextMessageCount
        self.contextCharacterCount = contextCharacterCount ?? promptCharacterCount
        self.contextTextBytes = contextTextBytes
        self.contextMediaAttachmentCount = contextMediaAttachmentCount
        self.contextMediaBytes = contextMediaBytes
        self.contextTotalBytes = contextTotalBytes ?? contextTextBytes.map { $0 + contextMediaBytes }
        self.inputTokenCount = nil
        self.outputTokenCount = 0
        self.outputTextChunkCount = 0
        self.outputCharacterCount = 0
        self.modelLoadDuration = modelLoadMetrics?.modelLoadDuration
        self.tokenizerLoadDuration = modelLoadMetrics?.tokenizerLoadDuration
        self.promptConstructionDuration = promptConstructionDuration
        self.tokenizationDuration = nil
        self.prefillPromptEvaluationDuration = nil
        self.prefillPromptEvaluationDurationSource = "unavailable_stream_response_no_generate_completion_info"
        self.timeToFirstGeneratedToken = nil
        self.timeToFirstGeneratedTokenSource = "not_recorded_until_first_output_chunk"
        self.timeToFirstOutputChunk = nil
        self.decodeGenerationDuration = nil
        self.decodeGenerationDurationSource = "consumer_wall_clock_decode_loop"
        self.totalInferenceDuration = nil
        self.totalInferenceDurationScope = "inference_service_tokenization_prefill_decode_excludes_chat_orchestration"
        self.tokensPerSecond = nil
        self.tokensPerSecondMeasurement = "unavailable_stream_response_no_token_count"
        self.memoryBeforeModelLoad = modelLoadMetrics?.memoryBeforeModelLoad
        self.memoryAfterModelLoad = modelLoadMetrics?.memoryAfterModelLoad
        self.memoryBeforeInference = nil
        self.memoryAfterInference = nil
        self.memoryPeakDuringInference = nil
        self.memoryAvailableAtInferenceStart = nil
        self.memoryDelta = nil
        self.memoryMeasurementKind = "task_vm_info_phys_footprint_bytes"
        self.modelId = profilingContext?.modelId
        self.parameterCount = profilingContext?.parameterCount
        self.quantization = profilingContext?.quantization
        self.estimatedSizeGB = profilingContext?.estimatedSizeGB
        self.maxTokens = profilingContext?.maxTokens
        self.temperature = profilingContext?.temperature
        self.topP = profilingContext?.topP
        self.repetitionPenalty = profilingContext?.repetitionPenalty
        self.thinkingEnabled = profilingContext?.thinkingEnabled
        self.devicePhysicalMemoryGB = profilingContext?.devicePhysicalMemoryGB
        self.thermalStateBeforeInference = nil
        self.thermalStateAfterInference = nil
        self.batteryLevelBeforeInference = nil
        self.batteryLevelAfterInference = nil
        self.isBatteryLevelCoarse = true
        self.batteryMeasurementKind = "UIDevice_batteryLevel_coarse_fraction"
        self.energyMeasurementKind = "indirect_only_no_public_joule_measurement"
        self.stopReason = nil
        self.errorInfo = nil
        self.measurementNotes = []
    }

    mutating func recordMemoryFootprintSample(peakFootprintBytes: inout UInt64) {
        guard let footprint = LLMProfiler.currentMemoryFootprintBytes() else { return }
        peakFootprintBytes = max(peakFootprintBytes, footprint)
        memoryPeakDuringInference = peakFootprintBytes
    }

    static let sessionMeasurementNotes = [
        "Memory uses Mach task_vm_info phys_footprint when available, falling back to resident_size; treat it as process footprint, not total system pressure.",
        "Battery level comes from UIDevice and is too coarse for single-inference energy measurement.",
        "Normal public iOS APIs do not expose exact joule-level energy consumption for one local LLM run.",
        "Use latency, memory, thermal state, sustained throughput, repeated-run battery drain, and Xcode Instruments Power profiling as indirect energy indicators.",
        "Total inference duration starts inside InferenceService and excludes chat orchestration, tool execution, memory retrieval, and separately measured prompt construction.",
        "Tokenization duration includes MLXLMCommon user-input preparation, which may include chat templating and media preprocessing.",
        "MLXLMCommon GenerateCompletionInfo supplies prompt/output token counts, prompt/decode timing, throughput, and stop reason when generation completes normally.",
        "Time to first output chunk is recorded separately because streamed text chunks can lag the first raw token when detokenization buffers partial text.",
        "Detokenization is performed inside MLXLMCommon's generation stream; this app records emitted text chunk and character counts from stream output.",
        "memoryPeakDuringInference is the maximum sampled process phys_footprint during the run (including periodic samples while decoding).",
        "memoryAvailableAtInferenceStart uses os_proc_available_memory and reflects jetsam headroom, not total device RAM."
    ]

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    static var csvHeader: String {
        [
            "id",
            "createdAt",
            "runLabel",
            "modelName",
            "deviceModel",
            "iOSVersion",
            "promptCharacterCount",
            "contextMessageCount",
            "contextCharacterCount",
            "contextTextBytes",
            "contextMediaAttachmentCount",
            "contextMediaBytes",
            "contextTotalBytes",
            "inputTokenCount",
            "outputTokenCount",
            "outputTextChunkCount",
            "outputCharacterCount",
            "modelLoadDuration",
            "tokenizerLoadDuration",
            "promptConstructionDuration",
            "tokenizationDuration",
            "prefillPromptEvaluationDuration",
            "prefillPromptEvaluationDurationSource",
            "timeToFirstGeneratedToken",
            "timeToFirstGeneratedTokenSource",
            "timeToFirstOutputChunk",
            "decodeGenerationDuration",
            "decodeGenerationDurationSource",
            "totalInferenceDuration",
            "totalInferenceDurationScope",
            "tokensPerSecond",
            "tokensPerSecondMeasurement",
            "memoryBeforeModelLoad",
            "memoryAfterModelLoad",
            "memoryBeforeInference",
            "memoryAfterInference",
            "memoryPeakDuringInference",
            "memoryAvailableAtInferenceStart",
            "memoryDelta",
            "memoryMeasurementKind",
            "modelId",
            "parameterCount",
            "quantization",
            "estimatedSizeGB",
            "maxTokens",
            "temperature",
            "topP",
            "repetitionPenalty",
            "thinkingEnabled",
            "devicePhysicalMemoryGB",
            "thermalStateBeforeInference",
            "thermalStateAfterInference",
            "batteryLevelBeforeInference",
            "batteryLevelAfterInference",
            "isBatteryLevelCoarse",
            "batteryMeasurementKind",
            "energyMeasurementKind",
            "stopReason",
            "errorMessage"
        ].joined(separator: ",")
    }

    var csvRow: String {
        var fields: [String] = []
        fields.reserveCapacity(40)
        fields.append(id.uuidString)
        fields.append(ISO8601DateFormatter().string(from: createdAt))
        fields.append(runLabel)
        fields.append(modelName)
        fields.append(deviceModel ?? "")
        fields.append(iOSVersion ?? "")
        fields.append(String(promptCharacterCount))
        fields.append(contextMessageCount.map(String.init) ?? "")
        fields.append(contextCharacterCount.map(String.init) ?? "")
        fields.append(contextTextBytes.map(String.init) ?? "")
        fields.append(contextMediaAttachmentCount.map(String.init) ?? "")
        fields.append(contextMediaBytes.map(String.init) ?? "")
        fields.append(contextTotalBytes.map(String.init) ?? "")
        fields.append(inputTokenCount.map(String.init) ?? "")
        fields.append(measuredOutputTokenCount.map(String.init) ?? "")
        fields.append(outputTextChunkCount.map(String.init) ?? "")
        fields.append(outputCharacterCount.map(String.init) ?? "")
        fields.append(Self.string(modelLoadDuration))
        fields.append(Self.string(tokenizerLoadDuration))
        fields.append(Self.string(promptConstructionDuration))
        fields.append(Self.string(tokenizationDuration))
        fields.append(Self.string(prefillPromptEvaluationDuration))
        fields.append(prefillPromptEvaluationDurationSource)
        fields.append(Self.string(timeToFirstGeneratedToken))
        fields.append(timeToFirstGeneratedTokenSource)
        fields.append(Self.string(timeToFirstOutputChunk))
        fields.append(Self.string(decodeGenerationDuration))
        fields.append(decodeGenerationDurationSource)
        fields.append(Self.string(totalInferenceDuration))
        fields.append(totalInferenceDurationScope)
        fields.append(Self.string(tokensPerSecond))
        fields.append(tokensPerSecondMeasurement)
        fields.append(memoryBeforeModelLoad.map(String.init) ?? "")
        fields.append(memoryAfterModelLoad.map(String.init) ?? "")
        fields.append(memoryBeforeInference.map(String.init) ?? "")
        fields.append(memoryAfterInference.map(String.init) ?? "")
        fields.append(memoryPeakDuringInference.map(String.init) ?? "")
        fields.append(memoryAvailableAtInferenceStart.map(String.init) ?? "")
        fields.append(memoryDelta.map(String.init) ?? "")
        fields.append(memoryMeasurementKind)
        fields.append(modelId ?? "")
        fields.append(parameterCount ?? "")
        fields.append(quantization ?? "")
        fields.append(Self.string(estimatedSizeGB))
        fields.append(maxTokens.map(String.init) ?? "")
        fields.append(Self.string(temperature))
        fields.append(Self.string(topP))
        fields.append(Self.string(repetitionPenalty))
        fields.append(thinkingEnabled.map(String.init) ?? "")
        fields.append(devicePhysicalMemoryGB.map(String.init) ?? "")
        fields.append(thermalStateBeforeInference ?? "")
        fields.append(thermalStateAfterInference ?? "")
        fields.append(Self.string(batteryLevelBeforeInference))
        fields.append(Self.string(batteryLevelAfterInference))
        fields.append(String(isBatteryLevelCoarse))
        fields.append(batteryMeasurementKind)
        fields.append(energyMeasurementKind)
        fields.append(stopReason ?? "")
        fields.append(errorInfo?.message ?? "")
        return fields.map(Self.csvEscaped).joined(separator: ",")
    }

    private static func csvEscaped(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func string(_ value: Double?) -> String {
        guard let value else { return "" }
        return String(value)
    }

    private static func string(_ value: Float?) -> String {
        guard let value else { return "" }
        return String(value)
    }
}

nonisolated extension LLMExecutionProfile {
    var measuredOutputTokenCount: Int? {
        outputTokenCount > 0 ? outputTokenCount : nil
    }

    var outputCharactersPerSecond: Double? {
        guard let outputCharacterCount,
              outputCharacterCount > 0,
              let decodeGenerationDuration,
              decodeGenerationDuration > 0 else {
            return nil
        }
        return Double(outputCharacterCount) / decodeGenerationDuration
    }

    var qualityFlags: [String] {
        var flags: [String] = []
        if errorInfo != nil {
            flags.append("error_recorded")
        }
        if stopReason == "cancelled" {
            flags.append("cancelled")
        }
        if stopReason == nil {
            flags.append("stop_reason_missing")
        }
        if measuredOutputTokenCount == nil {
            flags.append("output_token_count_unavailable")
        }
        if tokensPerSecond == nil {
            flags.append("tokens_per_second_unavailable")
        }
        if prefillPromptEvaluationDuration == nil {
            flags.append("prefill_duration_unavailable")
        }
        if timeToFirstGeneratedTokenSource == "first_output_chunk_fallback" {
            flags.append("ttft_from_first_output_chunk_fallback")
        }
        if decodeGenerationDurationSource == "consumer_wall_clock_decode_loop" {
            flags.append("decode_duration_from_consumer_wall_clock")
        }
        if decodeGenerationDurationSource == "in_progress_consumer_wall_clock_decode_loop" {
            flags.append("decode_duration_from_in_progress_snapshot")
        }
        return flags
    }
}

nonisolated struct LLMProfileModelExport: Codable, Hashable, Sendable {
    let displayName: String
    let modelId: String?
    let parameterCount: String?
    let quantization: String?
    let estimatedSizeGB: Double?

    init(_ profile: LLMExecutionProfile) {
        self.displayName = profile.modelName
        self.modelId = profile.modelId
        self.parameterCount = profile.parameterCount
        self.quantization = profile.quantization
        self.estimatedSizeGB = profile.estimatedSizeGB
    }
}

nonisolated struct LLMProfileGenerationExport: Codable, Hashable, Sendable {
    let maxTokens: Int?
    let temperature: Float?
    let topP: Float?
    let repetitionPenalty: Float?
    let thinkingEnabled: Bool?

    init(_ profile: LLMExecutionProfile) {
        self.maxTokens = profile.maxTokens
        self.temperature = profile.temperature
        self.topP = profile.topP
        self.repetitionPenalty = profile.repetitionPenalty
        self.thinkingEnabled = profile.thinkingEnabled
    }
}

nonisolated struct LLMExecutionProfileExport: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let runLabel: String
    let model: LLMProfileModelExport
    let generation: LLMProfileGenerationExport
    let prompt: LLMProfilePromptExport
    let output: LLMProfileOutputExport
    let durations: LLMProfileDurationsExport
    let memory: LLMProfileMemoryExport
    let thermal: LLMProfileThermalExport
    let battery: LLMProfileBatteryExport?
    let stopReason: String?
    let errorInfo: LLMExecutionErrorInfo?
    let qualityFlags: [String]
    let durationSourceOverrides: [String: String]

    init(_ profile: LLMExecutionProfile) {
        self.id = profile.id
        self.createdAt = profile.createdAt
        self.runLabel = profile.runLabel
        self.model = LLMProfileModelExport(profile)
        self.generation = LLMProfileGenerationExport(profile)
        self.prompt = LLMProfilePromptExport(profile)
        self.output = LLMProfileOutputExport(profile)
        self.durations = LLMProfileDurationsExport(profile)
        self.memory = LLMProfileMemoryExport(profile)
        self.thermal = LLMProfileThermalExport(profile)
        self.battery = LLMProfileBatteryExport(profile)
        self.stopReason = profile.stopReason
        self.errorInfo = profile.errorInfo
        self.qualityFlags = profile.qualityFlags
        self.durationSourceOverrides = Self.durationSourceOverrides(for: profile)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case createdAt
        case runLabel
        case model
        case generation
        case prompt
        case output
        case durations
        case memory
        case thermal
        case battery
        case stopReason
        case errorInfo
        case qualityFlags
        case durationSourceOverrides
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(runLabel, forKey: .runLabel)
        try container.encode(model, forKey: .model)
        try container.encode(generation, forKey: .generation)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(output, forKey: .output)
        try container.encode(durations, forKey: .durations)
        try container.encode(memory, forKey: .memory)
        try container.encode(thermal, forKey: .thermal)
        try container.encodeIfPresent(battery, forKey: .battery)
        try container.encodeIfPresent(stopReason, forKey: .stopReason)
        try container.encodeIfPresent(errorInfo, forKey: .errorInfo)
        if !qualityFlags.isEmpty {
            try container.encode(qualityFlags, forKey: .qualityFlags)
        }
        if !durationSourceOverrides.isEmpty {
            try container.encode(durationSourceOverrides, forKey: .durationSourceOverrides)
        }
    }

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func durationSourceOverrides(for profile: LLMExecutionProfile) -> [String: String] {
        var overrides: [String: String] = [:]
        if profile.prefillPromptEvaluationDurationSource != "unavailable_stream_response_no_generate_completion_info" {
            overrides["prefillPromptEvaluationDuration"] = profile.prefillPromptEvaluationDurationSource
        }
        if profile.timeToFirstGeneratedTokenSource != "first_output_chunk_fallback" {
            overrides["timeToFirstGeneratedToken"] = profile.timeToFirstGeneratedTokenSource
        }
        if profile.decodeGenerationDurationSource != "consumer_wall_clock_decode_loop" {
            overrides["decodeGenerationDuration"] = profile.decodeGenerationDurationSource
        }
        return overrides
    }
}

nonisolated struct LLMProfilePromptExport: Codable, Hashable, Sendable {
    let latestUserCharacterCount: Int
    let contextMessageCount: Int?
    let contextCharacterCount: Int?
    let contextTextBytes: Int?
    let contextMediaAttachmentCount: Int?
    let contextMediaBytes: Int?
    let contextTotalBytes: Int?
    let contextTokenCount: Int?

    init(_ profile: LLMExecutionProfile) {
        self.latestUserCharacterCount = profile.promptCharacterCount
        self.contextMessageCount = profile.contextMessageCount
        self.contextCharacterCount = profile.contextCharacterCount
        self.contextTextBytes = profile.contextTextBytes
        self.contextMediaAttachmentCount = profile.contextMediaAttachmentCount
        self.contextMediaBytes = profile.contextMediaBytes
        self.contextTotalBytes = profile.contextTotalBytes
        self.contextTokenCount = profile.inputTokenCount
    }
}

nonisolated struct LLMProfileOutputExport: Codable, Hashable, Sendable {
    let tokenCount: Int?
    let tokensPerSecond: Double?
    let textChunkCount: Int?
    let characterCount: Int?
    let charactersPerSecond: Double?

    init(_ profile: LLMExecutionProfile) {
        self.tokenCount = profile.measuredOutputTokenCount
        self.tokensPerSecond = profile.tokensPerSecond
        self.textChunkCount = profile.outputTextChunkCount
        self.characterCount = profile.outputCharacterCount
        self.charactersPerSecond = profile.outputCharactersPerSecond
    }
}

nonisolated struct LLMProfileDurationsExport: Codable, Hashable, Sendable {
    let promptConstruction: TimeInterval?
    let tokenization: TimeInterval?
    let prefillPromptEvaluation: TimeInterval?
    let timeToFirstGeneratedToken: TimeInterval?
    let timeToFirstOutputChunk: TimeInterval?
    let decodeGeneration: TimeInterval?
    let totalInference: TimeInterval?

    init(_ profile: LLMExecutionProfile) {
        self.promptConstruction = profile.promptConstructionDuration
        self.tokenization = profile.tokenizationDuration
        self.prefillPromptEvaluation = profile.prefillPromptEvaluationDuration
        self.timeToFirstGeneratedToken = profile.timeToFirstGeneratedToken
        self.timeToFirstOutputChunk = profile.timeToFirstOutputChunk
        self.decodeGeneration = profile.decodeGenerationDuration
        self.totalInference = profile.totalInferenceDuration
    }
}

nonisolated struct LLMProfileMemoryExport: Codable, Hashable, Sendable {
    let beforeInference: UInt64?
    let afterInference: UInt64?
    let peakDuringInference: UInt64?
    let availableAtInferenceStart: UInt64?
    let delta: Int64?

    init(_ profile: LLMExecutionProfile) {
        self.beforeInference = profile.memoryBeforeInference
        self.afterInference = profile.memoryAfterInference
        self.peakDuringInference = profile.memoryPeakDuringInference
        self.availableAtInferenceStart = profile.memoryAvailableAtInferenceStart
        self.delta = profile.memoryDelta
    }
}

nonisolated struct LLMProfileThermalExport: Codable, Hashable, Sendable {
    let beforeInference: String?
    let afterInference: String?

    init(_ profile: LLMExecutionProfile) {
        self.beforeInference = profile.thermalStateBeforeInference
        self.afterInference = profile.thermalStateAfterInference
    }
}

nonisolated struct LLMProfileBatteryExport: Codable, Hashable, Sendable {
    let beforeInference: Double?
    let afterInference: Double?

    init?(_ profile: LLMExecutionProfile) {
        guard profile.batteryLevelBeforeInference != nil || profile.batteryLevelAfterInference != nil else {
            return nil
        }
        self.beforeInference = profile.batteryLevelBeforeInference
        self.afterInference = profile.batteryLevelAfterInference
    }
}

nonisolated struct LLMBenchmarkMetricSummary: Codable, Hashable, Sendable {
    let mean: Double
    let median: Double
    let min: Double
    let max: Double

    init?(_ values: [Double]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        mean = values.reduce(0, +) / Double(values.count)
        if sorted.count.isMultiple(of: 2) {
            let upper = sorted.count / 2
            median = (sorted[upper - 1] + sorted[upper]) / 2
        } else {
            median = sorted[sorted.count / 2]
        }
        min = sorted.first ?? 0
        max = sorted.last ?? 0
    }
}

nonisolated struct LLMBenchmarkResult: Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let prompt: String
    let iterations: Int
    let profiles: [LLMExecutionProfile]
    let totalInferenceTime: LLMBenchmarkMetricSummary?
    let timeToFirstToken: LLMBenchmarkMetricSummary?
    let tokensPerSecond: LLMBenchmarkMetricSummary?
    let charactersPerSecond: LLMBenchmarkMetricSummary?
    let memoryDelta: LLMBenchmarkMetricSummary?

    init(prompt: String, profiles: [LLMExecutionProfile]) {
        self.id = UUID()
        self.createdAt = Date()
        self.prompt = prompt
        self.iterations = profiles.count
        self.profiles = profiles
        self.totalInferenceTime = LLMBenchmarkMetricSummary(profiles.compactMap(\.totalInferenceDuration))
        self.timeToFirstToken = LLMBenchmarkMetricSummary(profiles.compactMap(\.timeToFirstGeneratedToken))
        self.tokensPerSecond = LLMBenchmarkMetricSummary(profiles.compactMap(\.tokensPerSecond))
        self.charactersPerSecond = LLMBenchmarkMetricSummary(profiles.compactMap(\.outputCharactersPerSecond))
        self.memoryDelta = LLMBenchmarkMetricSummary(profiles.compactMap { profile in
            profile.memoryDelta.map(Double.init)
        })
    }

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

nonisolated struct LLMBenchmarkResultExport: Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let promptCharacterCount: Int
    let iterations: Int
    let profiles: [LLMExecutionProfile]
    let totalInferenceTime: LLMBenchmarkMetricSummary?
    let timeToFirstToken: LLMBenchmarkMetricSummary?
    let tokensPerSecond: LLMBenchmarkMetricSummary?
    let charactersPerSecond: LLMBenchmarkMetricSummary?
    let memoryDelta: LLMBenchmarkMetricSummary?

    init(_ result: LLMBenchmarkResult) {
        self.id = result.id
        self.createdAt = result.createdAt
        self.promptCharacterCount = result.prompt.count
        self.iterations = result.iterations
        self.profiles = result.profiles
        self.totalInferenceTime = result.totalInferenceTime
        self.timeToFirstToken = result.timeToFirstToken
        self.tokensPerSecond = result.tokensPerSecond
        self.charactersPerSecond = result.charactersPerSecond
        self.memoryDelta = result.memoryDelta
    }

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

nonisolated struct LLMInferenceInProgressSnapshot: Identifiable, Codable, Hashable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let sessionID: UUID
    let sessionStartedAt: Date
    let createdAt: Date
    var updatedAt: Date
    var stage: String
    var profile: LLMExecutionProfile
    var memoryFootprintBytes: UInt64?
    var thermalState: String?
    var batteryLevel: Double?
    var isBatteryLevelCoarse: Bool
    var emittedTextChunkCount: Int?
    var emittedTextCharacterCount: Int?
    var notes: [String]

    init(
        sessionID: UUID,
        sessionStartedAt: Date,
        profile: LLMExecutionProfile,
        stage: String,
        memoryFootprintBytes: UInt64?,
        thermalState: String?,
        batteryLevel: Double?,
        emittedTextChunkCount: Int? = nil,
        emittedTextCharacterCount: Int? = nil
    ) {
        self.schemaVersion = 1
        self.id = profile.id
        self.sessionID = sessionID
        self.sessionStartedAt = sessionStartedAt
        self.createdAt = profile.createdAt
        self.updatedAt = Date()
        self.stage = stage
        self.profile = profile
        self.memoryFootprintBytes = memoryFootprintBytes
        self.thermalState = thermalState
        self.batteryLevel = batteryLevel
        self.isBatteryLevelCoarse = true
        self.emittedTextChunkCount = emittedTextChunkCount
        self.emittedTextCharacterCount = emittedTextCharacterCount
        self.notes = [
            "This is a best-effort in-progress inference snapshot written before completion.",
            "If recovered after launch, the previous process exited before normal inference cleanup completed; causes can include a crash, jetsam, force quit, debugger stop, or power loss.",
            "Recovery data is not a native iOS crash report and does not include exact joule-level energy consumption."
        ]
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case sessionID
        case sessionStartedAt
        case createdAt
        case updatedAt
        case stage
        case profile
        case memoryFootprintBytes
        case thermalState
        case batteryLevel
        case isBatteryLevelCoarse
        case emittedTextChunkCount
        case emittedTextCharacterCount
        case notes
    }

    init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let profile = try container.decode(LLMExecutionProfile.self, forKey: .profile)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? profile.id
        self.sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID) ?? self.id
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? profile.createdAt
        self.sessionStartedAt = try container.decodeIfPresent(Date.self, forKey: .sessionStartedAt) ?? self.createdAt
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        self.stage = try container.decodeIfPresent(String.self, forKey: .stage) ?? "unknown"
        self.profile = profile
        self.memoryFootprintBytes = try container.decodeIfPresent(UInt64.self, forKey: .memoryFootprintBytes)
        self.thermalState = try container.decodeIfPresent(String.self, forKey: .thermalState)
        self.batteryLevel = try container.decodeIfPresent(Double.self, forKey: .batteryLevel)
        self.isBatteryLevelCoarse = try container.decodeIfPresent(Bool.self, forKey: .isBatteryLevelCoarse) ?? true
        self.emittedTextChunkCount = try container.decodeIfPresent(Int.self, forKey: .emittedTextChunkCount)
        self.emittedTextCharacterCount = try container.decodeIfPresent(Int.self, forKey: .emittedTextCharacterCount)
        self.notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

nonisolated struct LLMInferenceCrashReport: Identifiable, Codable, Hashable, Sendable {
    let schemaVersion: Int
    let id: UUID
    let recoveredAt: Date
    let inferredReason: String
    let snapshot: LLMInferenceInProgressSnapshot
    let recoveredProfile: LLMExecutionProfile
    let recoveryProcessMemoryFootprintBytes: UInt64?
    let recoveryThermalState: String?
    let notes: [String]

    init(
        snapshot: LLMInferenceInProgressSnapshot,
        recoveryProcessMemoryFootprintBytes: UInt64?,
        recoveryThermalState: String?
    ) {
        var profile = snapshot.profile
        profile.stopReason = profile.stopReason ?? "interrupted"
        profile.errorInfo = profile.errorInfo ?? LLMExecutionErrorInfo(
            message: "The app exited before inference completion was recorded. This may indicate a crash, jetsam termination, force quit, debugger stop, or power loss.",
            domain: "iMLX.LLMProfiling",
            code: nil
        )
        if !profile.measurementNotes.contains(Self.recoveredProfileNote) {
            profile.measurementNotes.append(Self.recoveredProfileNote)
        }

        self.schemaVersion = 1
        self.id = UUID()
        self.recoveredAt = Date()
        self.inferredReason = "in_progress_snapshot_found_on_next_launch"
        self.snapshot = snapshot
        self.recoveredProfile = profile
        self.recoveryProcessMemoryFootprintBytes = recoveryProcessMemoryFootprintBytes
        self.recoveryThermalState = recoveryThermalState
        self.notes = [
            "Recovered from an in-progress inference snapshot left on disk.",
            "This is a best-effort crash/interruption report, not a symbolicated Apple crash log.",
            "Metrics captured after recovery describe the new process, not the terminated process.",
            "Exact joule-level energy consumption is not available from normal public iOS APIs."
        ]
    }

    private static let recoveredProfileNote = "This profile was recovered from an in-progress snapshot; after-inference metrics may be missing because the process exited before normal completion."
}

nonisolated struct LLMInferenceInProgressSnapshotExport: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let updatedAt: Date
    let stage: String
    let profile: LLMExecutionProfileExport
    let memoryFootprintBytes: UInt64?
    let thermalState: String?
    let batteryLevel: Double?
    let isBatteryLevelCoarse: Bool
    let emittedTextChunkCount: Int?
    let emittedTextCharacterCount: Int?

    init(_ snapshot: LLMInferenceInProgressSnapshot) {
        self.id = snapshot.id
        self.createdAt = snapshot.createdAt
        self.updatedAt = snapshot.updatedAt
        self.stage = snapshot.stage
        self.profile = LLMExecutionProfileExport(snapshot.profile)
        self.memoryFootprintBytes = snapshot.memoryFootprintBytes
        self.thermalState = snapshot.thermalState
        self.batteryLevel = snapshot.batteryLevel
        self.isBatteryLevelCoarse = snapshot.isBatteryLevelCoarse
        self.emittedTextChunkCount = snapshot.emittedTextChunkCount
        self.emittedTextCharacterCount = snapshot.emittedTextCharacterCount
    }
}

nonisolated struct LLMInferenceCrashReportExport: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let recoveredAt: Date
    let inferredReason: String
    let interruptedStage: String
    let snapshotUpdatedAt: Date
    let profile: LLMExecutionProfileExport
    let recoveryProcessMemoryFootprintBytes: UInt64?
    let recoveryThermalState: String?

    init(_ report: LLMInferenceCrashReport) {
        self.id = report.id
        self.recoveredAt = report.recoveredAt
        self.inferredReason = report.inferredReason
        self.interruptedStage = report.snapshot.stage
        self.snapshotUpdatedAt = report.snapshot.updatedAt
        self.profile = LLMExecutionProfileExport(report.recoveredProfile)
        self.recoveryProcessMemoryFootprintBytes = report.recoveryProcessMemoryFootprintBytes
        self.recoveryThermalState = report.recoveryThermalState
    }
}

nonisolated struct LLMProfilingSessionRecord: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    var updatedAt: Date
    var label: String
    var profiles: [LLMExecutionProfile]
    var crashReports: [LLMInferenceCrashReport]
    var activeSnapshot: LLMInferenceInProgressSnapshot?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        updatedAt: Date = Date(),
        label: String = "Debug Session",
        profiles: [LLMExecutionProfile] = [],
        crashReports: [LLMInferenceCrashReport] = [],
        activeSnapshot: LLMInferenceInProgressSnapshot? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.label = label
        self.profiles = profiles.sorted { $0.createdAt < $1.createdAt }
        self.crashReports = crashReports.sorted { $0.recoveredAt < $1.recoveredAt }
        self.activeSnapshot = activeSnapshot
    }

    mutating func upsertProfile(_ profile: LLMExecutionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        profiles.sort { $0.createdAt < $1.createdAt }
        activeSnapshot = activeSnapshot?.id == profile.id ? nil : activeSnapshot
        updatedAt = Date()
    }

    mutating func saveActiveSnapshot(_ snapshot: LLMInferenceInProgressSnapshot) {
        activeSnapshot = snapshot
        updatedAt = snapshot.updatedAt
    }

    mutating func addCrashReport(_ report: LLMInferenceCrashReport) {
        if !crashReports.contains(where: { $0.snapshot.id == report.snapshot.id }) {
            crashReports.append(report)
            crashReports.sort { $0.recoveredAt < $1.recoveredAt }
        }
        upsertProfile(report.recoveredProfile)
        if activeSnapshot?.id == report.snapshot.id {
            activeSnapshot = nil
        }
        updatedAt = report.recoveredAt
    }
}

nonisolated struct LLMProfilingHistoryArchive: Codable, Hashable, Sendable {
    let schemaVersion: Int
    var updatedAt: Date
    var sessions: [LLMProfilingSessionRecord]
    var profiles: [LLMExecutionProfile]
    var crashReports: [LLMInferenceCrashReport]

    init(
        sessions: [LLMProfilingSessionRecord] = [],
        profiles: [LLMExecutionProfile] = [],
        crashReports: [LLMInferenceCrashReport] = []
    ) {
        self.schemaVersion = 1
        self.updatedAt = Date()
        self.sessions = sessions
        self.profiles = profiles
        self.crashReports = crashReports
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case updatedAt
        case sessions
        case profiles
        case crashReports
    }

    init(from decoder: Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        let decodedProfiles = try container.decodeIfPresent([LLMExecutionProfile].self, forKey: .profiles) ?? []
        let decodedCrashReports = try container.decodeIfPresent([LLMInferenceCrashReport].self, forKey: .crashReports) ?? []
        let decodedSessions = try container.decodeIfPresent([LLMProfilingSessionRecord].self, forKey: .sessions) ?? []
        if decodedSessions.isEmpty, !decodedProfiles.isEmpty || !decodedCrashReports.isEmpty {
            let startedAt = decodedProfiles.map { $0.createdAt }.min() ?? decodedCrashReports.map { $0.recoveredAt }.min() ?? Date()
            let updatedAt = decodedProfiles.map { $0.createdAt }.max() ?? decodedCrashReports.map { $0.recoveredAt }.max() ?? Date()
            self.sessions = [
                LLMProfilingSessionRecord(
                    startedAt: startedAt,
                    updatedAt: updatedAt,
                    label: "Imported Profiling Session",
                    profiles: decodedProfiles,
                    crashReports: decodedCrashReports
                )
            ]
        } else {
            self.sessions = decodedSessions
        }
        self.profiles = decodedProfiles
        self.crashReports = decodedCrashReports
    }
}

nonisolated struct LLMProfilingSessionMetadataExport: Codable, Hashable, Sendable {
    let id: UUID
    let label: String
    let startedAt: Date
    let updatedAt: Date

    init(_ session: LLMProfilingSessionRecord) {
        self.id = session.id
        self.label = session.label
        self.startedAt = session.startedAt
        self.updatedAt = session.updatedAt
    }
}

nonisolated struct LLMProfilingEnvironmentExport: Codable, Hashable, Sendable {
    let deviceModel: String?
    let iOSVersion: String?
    let devicePhysicalMemoryGB: Int?

    init(_ profile: LLMExecutionProfile) {
        self.deviceModel = profile.deviceModel
        self.iOSVersion = profile.iOSVersion
        self.devicePhysicalMemoryGB = profile.devicePhysicalMemoryGB
    }
}

nonisolated struct LLMProfilingModelLoadExport: Codable, Hashable, Sendable {
    let modelName: String
    let modelLoadDuration: TimeInterval?
    let tokenizerLoadDuration: TimeInterval?
    let memoryBeforeModelLoad: UInt64?
    let memoryAfterModelLoad: UInt64?

    init(_ profile: LLMExecutionProfile) {
        self.modelName = profile.modelName
        self.modelLoadDuration = profile.modelLoadDuration
        self.tokenizerLoadDuration = profile.tokenizerLoadDuration
        self.memoryBeforeModelLoad = profile.memoryBeforeModelLoad
        self.memoryAfterModelLoad = profile.memoryAfterModelLoad
    }
}

nonisolated struct LLMProfilingMeasurementMetadataExport: Codable, Hashable, Sendable {
    let memoryMeasurementKind: String
    let batteryMeasurementKind: String
    let energyMeasurementKind: String
    let totalInferenceDurationScope: String
    let tokensPerSecondMeasurement: String
    let defaultPrefillPromptEvaluationDurationSource: String
    let defaultTimeToFirstGeneratedTokenSource: String
    let defaultDecodeGenerationDurationSource: String

    init(_ profile: LLMExecutionProfile?) {
        self.memoryMeasurementKind = profile?.memoryMeasurementKind ?? "task_vm_info_phys_footprint_bytes"
        self.batteryMeasurementKind = profile?.batteryMeasurementKind ?? "UIDevice_batteryLevel_coarse_fraction"
        self.energyMeasurementKind = profile?.energyMeasurementKind ?? "indirect_only_no_public_joule_measurement"
        self.totalInferenceDurationScope = profile?.totalInferenceDurationScope ?? "inference_service_tokenization_prefill_decode_excludes_chat_orchestration"
        self.tokensPerSecondMeasurement = profile?.tokensPerSecondMeasurement ?? "unavailable_stream_response_no_token_count"
        self.defaultPrefillPromptEvaluationDurationSource = "unavailable_stream_response_no_generate_completion_info"
        self.defaultTimeToFirstGeneratedTokenSource = "first_output_chunk_fallback"
        self.defaultDecodeGenerationDurationSource = "consumer_wall_clock_decode_loop"
    }
}

nonisolated struct LLMProfilingSessionExport: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let exportedAt: Date
    let session: LLMProfilingSessionMetadataExport
    let environment: LLMProfilingEnvironmentExport?
    let modelLoads: [LLMProfilingModelLoadExport]
    let measurementMetadata: LLMProfilingMeasurementMetadataExport
    let profileOrder: String
    let profileCount: Int
    let profiles: [LLMExecutionProfileExport]
    let crashReportCount: Int
    let crashReports: [LLMInferenceCrashReportExport]
    let activeSnapshot: LLMInferenceInProgressSnapshotExport?
    let measurementLimitations: [String]

    init(
        session: LLMProfilingSessionRecord
    ) {
        let orderedProfiles = session.profiles.sorted { left, right in
            left.createdAt < right.createdAt
        }
        let orderedCrashReports = session.crashReports.sorted { left, right in
            left.recoveredAt < right.recoveredAt
        }
        let referenceProfile = orderedProfiles.first
            ?? session.activeSnapshot?.profile
            ?? orderedCrashReports.first?.recoveredProfile
        let profilesWithActiveSnapshot = orderedProfiles + [session.activeSnapshot?.profile].compactMap { $0 }
        self.schemaVersion = 3
        self.exportedAt = Date()
        self.session = LLMProfilingSessionMetadataExport(session)
        self.environment = referenceProfile.map(LLMProfilingEnvironmentExport.init)
        self.modelLoads = Self.modelLoads(from: profilesWithActiveSnapshot)
        self.measurementMetadata = LLMProfilingMeasurementMetadataExport(referenceProfile)
        self.profileOrder = "oldest_to_newest"
        self.profileCount = orderedProfiles.count
        self.profiles = orderedProfiles.map(LLMExecutionProfileExport.init)
        self.crashReportCount = orderedCrashReports.count
        self.crashReports = orderedCrashReports.map(LLMInferenceCrashReportExport.init)
        self.activeSnapshot = session.activeSnapshot.map(LLMInferenceInProgressSnapshotExport.init)
        self.measurementLimitations = LLMExecutionProfile.sessionMeasurementNotes
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case session
        case environment
        case modelLoads
        case measurementMetadata
        case profileOrder
        case profileCount
        case profiles
        case crashReportCount
        case crashReports
        case activeSnapshot
        case measurementLimitations
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(session, forKey: .session)
        try container.encodeIfPresent(environment, forKey: .environment)
        if !modelLoads.isEmpty {
            try container.encode(modelLoads, forKey: .modelLoads)
        }
        try container.encode(measurementMetadata, forKey: .measurementMetadata)
        try container.encode(profileOrder, forKey: .profileOrder)
        try container.encode(profileCount, forKey: .profileCount)
        try container.encode(profiles, forKey: .profiles)
        try container.encode(crashReportCount, forKey: .crashReportCount)
        if !crashReports.isEmpty {
            try container.encode(crashReports, forKey: .crashReports)
        }
        try container.encodeIfPresent(activeSnapshot, forKey: .activeSnapshot)
        try container.encode(measurementLimitations, forKey: .measurementLimitations)
    }

    private static func modelLoads(from profiles: [LLMExecutionProfile]) -> [LLMProfilingModelLoadExport] {
        var seen: Set<LLMProfilingModelLoadExport> = []
        var values: [LLMProfilingModelLoadExport] = []
        for profile in profiles {
            let value = LLMProfilingModelLoadExport(profile)
            guard !seen.contains(value) else { continue }
            seen.insert(value)
            values.append(value)
        }
        return values
    }

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

nonisolated enum LLMProfileFormatters {
    static func duration(_ duration: TimeInterval?) -> String {
        guard let duration else { return "n/a" }
        return "\(duration.formatted(.number.precision(.fractionLength(3)))) s"
    }

    static func rate(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return "\(value.formatted(.number.precision(.fractionLength(2)))) tok/s"
    }

    static func characterRate(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        return "\(value.formatted(.number.precision(.fractionLength(2)))) chars/s"
    }

    static func integer(_ value: Int?) -> String {
        guard let value else { return "n/a" }
        return value.formatted()
    }

    static func memory(_ bytes: UInt64?) -> String {
        guard let bytes else { return "n/a" }
        let megabytes = Double(bytes) / 1_048_576
        return "\(megabytes.formatted(.number.precision(.fractionLength(1)))) MB"
    }

    static func memoryDelta(_ bytes: Int64?) -> String {
        guard let bytes else { return "n/a" }
        let sign = bytes > 0 ? "+" : ""
        let megabytes = Double(bytes) / 1_048_576
        return "\(sign)\(megabytes.formatted(.number.precision(.fractionLength(1)))) MB"
    }

    static func battery(_ level: Double?) -> String {
        guard let level else { return "n/a" }
        return level.formatted(.percent.precision(.fractionLength(0)))
    }
}
