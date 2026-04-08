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
        case mistral3
        case lfm2
        case lfm25

        var displayName: String {
            switch self {
            case .qwen3: return "Qwen 3"
            case .qwen35: return "Qwen 3.5"
            case .qwen2vl: return "Qwen 2-VL"
            case .gemma3: return "Gemma 3"
            case .mistral3: return "Mistral 3"
            case .lfm2: return "LFM 2"
            case .lfm25: return "LFM 2.5"
            }
        }

        var familyDescription: String {
            switch self {
            case .qwen3:
                return "Qwen 3 focuses on efficient reasoning and strong instruction following in compact local models."
            case .qwen35:
                return "Qwen3.5 represents a significant leap forward, integrating breakthroughs in multimodal learning, architectural efficiency, reinforcement learning scale, and global accessibility to empower developers and enterprises with unprecedented capability and efficiency."
            case .qwen2vl:
                return "Qwen2-VL is optimized for vision-language understanding, combining image perception and grounded text generation for multimodal tasks."
            case .gemma3:
                return "Gemma 3 brings lightweight multimodal models with strong everyday quality and practical local-device efficiency."
            case .mistral3:
                return "Mistral 3 emphasizes fast instruction following and scalable reasoning across compact and larger local deployments."
            case .lfm2:
                return "LFM 2 is a compact Liquid model family tuned for efficient everyday chat and low-footprint on-device use."
            case .lfm25:
                return "LFM 2.5 pushes Liquid's small-model efficiency further, adding stronger reasoning behavior while staying lightweight for local use."
            }
        }

        var logoName: String {
            switch self {
            case .qwen3, .qwen35, .qwen2vl: return "qwen_logo"
            case .gemma3: return "gemma_logo"
            case .mistral3: return "mistral_logo"
            case .lfm2, .lfm25: return "lfm_logo"
            }
        }

        var sortOrder: Int {
            switch self {
            case .qwen3: return 0
            case .qwen35: return 1
            case .qwen2vl: return 2
            case .gemma3: return 3
            case .mistral3: return 4
            case .lfm2: return 5
            case .lfm25: return 6
            }
        }
    }
}
