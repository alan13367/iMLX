import Foundation

struct ModelInfo: Identifiable, Codable {
    let id: String
    let displayName: String
    let huggingFaceId: String
    let parameterCount: String
    let quantization: String
    let estimatedSizeGB: Double
    let minDeviceRAM: Int
    let family: ModelFamily
    let logoName: String
    let supportsThinking: Bool
    let supportsVision: Bool
    let prefersThinkingEnabled: Bool

    var isDownloaded: Bool = false
    var localURL: URL?

    enum ModelFamily: String, Codable, CaseIterable {
        case qwen3
        case qwen35
        case qwen2vl
        case lfm2
        case lfm25
        case gemma3
    }
}
