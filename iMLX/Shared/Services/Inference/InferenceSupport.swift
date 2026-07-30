import CoreImage
import Foundation
import ImageIO
import MLXLMCommon
import MLXLMTokenizers

actor ProfilingTokenizerLoader: MLXLMCommon.TokenizerLoader {
    private let underlying = TokenizersLoader()
    private(set) var duration: TimeInterval?

    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let signpost = LLMProfiler.beginInterval("Tokenizer Loading")
        let timer = LLMProfiler.Timer()
        defer {
            duration = timer.elapsedSeconds()
            LLMProfiler.endInterval("Tokenizer Loading", signpost)
        }
        return try await underlying.load(from: directory)
    }
}

nonisolated extension ChatMessage {
    var chatMessage: Chat.Message {
        let userInputImages = userInputImages(from: attachedImages)

        switch role {
        case .user:
            return .user(content, images: userInputImages)
        case .assistant:
            return .assistant(content, images: userInputImages)
        case .system:
            return .system(content, images: userInputImages)
        }
    }

    var chatMessageStrippingImages: Chat.Message {
        switch role {
        case .user:
            return .user(content, images: [])
        case .assistant:
            return .assistant(content, images: [])
        case .system:
            return .system(content, images: [])
        }
    }
}

nonisolated func userInputImages(from images: [ChatAttachmentImage]?) -> [UserInput.Image] {
    guard let images else { return [] }

    return images.compactMap { image in
        let data = image.data
        if let ciImage = CIImage(data: data, options: [.applyOrientationProperty: true]) {
            return .ciImage(ciImage)
        }

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }

        return .ciImage(CIImage(cgImage: cgImage))
    }
}

enum InferenceError: LocalizedError {
    case noModelLoaded
    case modelLoadFailed(String)
    case outOfMemory
    case generationCancelled
    case simulatorUnsupported
    case visionUnsupportedModel
    case invalidImageData
    case speechAssetsUnavailable
    case speechTextEmpty
    case unsupportedSpeechLocale(String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            String.appLocalized("error.inference.no_model_loaded")
        case .modelLoadFailed(let reason):
            String(format: String.appLocalized("error.inference.model_load_failed"), reason)
        case .outOfMemory:
            String.appLocalized("error.inference.out_of_memory")
        case .generationCancelled:
            String.appLocalized("error.inference.generation_cancelled")
        case .simulatorUnsupported:
            String.appLocalized("error.inference.simulator")
        case .visionUnsupportedModel:
            String.appLocalized("error.inference.vision_unsupported")
        case .invalidImageData:
            String.appLocalized("error.inference.invalid_image")
        case .speechAssetsUnavailable:
            "Kokoro speech assets are not available yet."
        case .speechTextEmpty:
            "There was no reply text to speak."
        case .unsupportedSpeechLocale(let localeName):
            "Live voice is not available for \(localeName) yet."
        }
    }
}
