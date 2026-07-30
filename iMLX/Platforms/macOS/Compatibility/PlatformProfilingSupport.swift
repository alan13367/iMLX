nonisolated enum PlatformProfilingSupport {
    static let isBatteryLevelCoarse = false
    static let batteryMeasurementKind = "unavailable_on_macOS"

    static let sessionMeasurementNotes = [
        "Memory uses Mach task_vm_info phys_footprint when available, falling back to resident_size; treat it as process footprint, not total system pressure.",
        "Battery level is unavailable on macOS; battery fields remain nil.",
        "Normal public macOS APIs do not expose exact joule-level energy consumption for one local LLM run.",
        "Use latency, memory, thermal state, sustained throughput, and Xcode Instruments Power profiling as indirect energy indicators.",
        "Total inference duration starts inside InferenceService and excludes chat orchestration, tool execution, memory retrieval, and separately measured prompt construction.",
        "Tokenization duration includes MLXLMCommon user-input preparation, which may include chat templating and media preprocessing.",
        "MLXLMCommon GenerateCompletionInfo supplies prompt/output token counts, prompt/decode timing, throughput, and stop reason when generation completes normally.",
        "Time to first output chunk is recorded separately because streamed text chunks can lag the first raw token when detokenization buffers partial text.",
        "Detokenization is performed inside MLXLMCommon's generation stream; this app records emitted text chunk and character counts from stream output.",
        "memoryPeakDuringInference is the maximum sampled process phys_footprint during the run (including periodic samples while decoding).",
        "memoryAvailableAtInferenceStart uses Mach host_statistics64 to subtract app, wired, and compressed memory from physical RAM, mirroring Activity Monitor's memory-used accounting rather than process jetsam headroom."
    ]

    @MainActor
    static func coarseBatteryLevel() -> Double? {
        nil
    }
}
