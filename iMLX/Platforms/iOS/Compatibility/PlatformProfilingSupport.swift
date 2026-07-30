import UIKit

nonisolated enum PlatformProfilingSupport {
    static let isBatteryLevelCoarse = true
    static let batteryMeasurementKind = "UIDevice_batteryLevel_coarse_fraction"

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

    @MainActor
    static func coarseBatteryLevel() -> Double? {
        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        if !wasMonitoring {
            device.isBatteryMonitoringEnabled = true
        }
        defer {
            if !wasMonitoring {
                device.isBatteryMonitoringEnabled = false
            }
        }

        let level = device.batteryLevel
        guard level >= 0 else { return nil }
        return Double(level)
    }
}
