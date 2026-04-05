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
        case gemma3
        case lfm2
        case lfm25

        var displayName: String {
            switch self {
            case .qwen3: return "Qwen 3"
            case .qwen35: return "Qwen 3.5"
            case .qwen2vl: return "Qwen 2-VL"
            case .gemma3: return "Gemma 3"
            case .lfm2: return "LFM 2"
            case .lfm25: return "LFM 2.5"
            }
        }

        var logoName: String {
            switch self {
            case .qwen3, .qwen35, .qwen2vl: return "qwen_logo"
            case .gemma3: return "gemma_logo"
            case .lfm2, .lfm25: return "lfm_logo"
            }
        }

        var sortOrder: Int {
            switch self {
            case .qwen3: return 0
            case .qwen35: return 1
            case .qwen2vl: return 2
            case .gemma3: return 3
            case .lfm2: return 4
            case .lfm25: return 5
            }
        }
    }
}
