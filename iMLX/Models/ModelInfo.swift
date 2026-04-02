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
    let supportsThinking: Bool
    let prefersThinkingEnabled: Bool

    var isDownloaded: Bool = false
    var localURL: URL?

    enum ModelFamily: String, Codable, CaseIterable {
        case qwen3
        case qwen35
        case lfm2
        case lfm25
        case gemma3
    }

    func prompt(for text: String, thinkingEnabled: Bool) -> String {
        guard supportsThinking else { return text }
        guard !text.hasPrefix("/think") && !text.hasPrefix("/no_think") else { return text }
        let directive = thinkingEnabled ? "/think" : "/no_think"
        return "\(directive)\n\n\(text)"
    }
}
