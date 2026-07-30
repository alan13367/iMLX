import Foundation

struct ModelInfo: Identifiable, Codable, Sendable {
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

    enum ModelFamily: String, Codable, CaseIterable, Sendable {
        case custom
        case imlx
        case qwen3
        case qwen35
        case qwen2vl
        case minicpm
        case gemma3
        case gemma4
        case mistral3
        case lfm2
        case lfm25
        case bonsai

        nonisolated var displayName: String {
            switch self {
            case .custom: return "Imported"
            case .imlx: return "iMLX"
            case .qwen3: return "Qwen 3"
            case .qwen35: return "Qwen 3.5"
            case .qwen2vl: return "Qwen 2-VL"
            case .minicpm: return "MiniCPM"
            case .gemma3: return "Gemma 3"
            case .gemma4: return "Gemma 4"
            case .mistral3: return "Mistral 3"
            case .lfm2: return "LFM 2"
            case .lfm25: return "LFM 2.5"
            case .bonsai: return "Bonsai"
            }
        }

        nonisolated var familyDescription: String {
            switch self {
            case .custom:
                return "Compatible MLX models discovered in the additional models folder."
            case .imlx:
                return "iMLX custom models, specifically fine-tuned for the iMLX app to enable perfect tool-calling and system awareness."
            case .qwen3:
                return "Qwen 3 focuses on efficient reasoning and strong instruction following in compact local models."
            case .qwen35:
                return "Qwen3.5 represents a significant leap forward, integrating breakthroughs in multimodal learning, architectural efficiency, reinforcement learning scale, and global accessibility to empower developers and enterprises with unprecedented capability and efficiency."
            case .qwen2vl:
                return "Qwen2-VL is optimized for vision-language understanding, combining image perception and grounded text generation for multimodal tasks."
            case .minicpm:
                return "MiniCPM is built for compact on-device assistants, reasoning, coding, and tool-use workflows with a small local footprint."
            case .gemma3:
                return "Gemma 3 brings lightweight multimodal models with strong everyday quality and practical local-device efficiency."
            case .gemma4:
                return "Gemma 4 adds newer multimodal instruction models with stronger vision understanding while staying practical for local-device use."
            case .mistral3:
                return "Mistral 3 emphasizes fast instruction following and scalable reasoning across compact and larger local deployments."
            case .lfm2:
                return "LFM 2 is a compact Liquid model family tuned for efficient everyday chat and low-footprint on-device use."
            case .lfm25:
                return "LFM 2.5 pushes Liquid's small-model efficiency further, adding stronger reasoning behavior while staying lightweight for local use."
            case .bonsai:
                return "Bonsai is Prism ML's end-to-end 1-bit model family for Apple Silicon — dense Qwen3-class quality at a fraction of the usual on-device footprint."
            }
        }

        nonisolated var logoName: String {
            switch self {
            case .custom: return "externaldrive.fill"
            case .imlx: return "BrandLogo"
            case .minicpm: return "openbmb_logo"
            case .qwen3, .qwen35, .qwen2vl: return "qwen_logo"
            case .gemma3, .gemma4: return "gemma_logo"
            case .mistral3: return "mistral_logo"
            case .lfm2, .lfm25: return "lfm_logo"
            case .bonsai: return "bonsai_logo"
            }
        }

        nonisolated var sortOrder: Int {
            switch self {
            case .imlx: return 0
            case .qwen3: return 1
            case .qwen35: return 2
            case .qwen2vl: return 3
            case .minicpm: return 4
            case .gemma3: return 5
            case .gemma4: return 6
            case .mistral3: return 7
            case .lfm2: return 8
            case .lfm25: return 9
            case .bonsai: return 10
            case .custom: return 11
            }
        }
    }
}
