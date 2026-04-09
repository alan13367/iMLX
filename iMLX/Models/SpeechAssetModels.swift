import Foundation

nonisolated struct SpeechAssetStatus: Codable, Equatable {
    var hasCoreModel: Bool
    var hasVoiceAssets: Bool
    var activatedLocales: Set<VoiceLocale>
    var activeDownload: SpeechAssetDownloadState?

    static let empty = SpeechAssetStatus(
        hasCoreModel: false,
        hasVoiceAssets: false,
        activatedLocales: [],
        activeDownload: nil
    )

    func isReady(for locale: VoiceLocale) -> Bool {
        hasCoreModel && hasVoiceAssets && activatedLocales.contains(locale)
    }
}

nonisolated struct SpeechAssetDownloadState: Codable, Equatable {
    let locale: VoiceLocale
    let phase: String
    let progress: Double?
}

nonisolated struct SpeechAssetFileLocations: Equatable {
    let modelURL: URL
    let voiceURL: URL
}

nonisolated struct SynthesizedSpeech: Equatable {
    let samples: [Float]
    let sampleRate: Double
}
