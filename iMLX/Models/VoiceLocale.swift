import Foundation

nonisolated enum VoiceLocale: String, CaseIterable, Codable, Identifiable {
    case english = "en"
    case spanish = "es"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english:
            "en-US"
        case .spanish:
            "es-ES"
        case .simplifiedChinese:
            "zh-CN"
        }
    }

    var displayName: String {
        switch self {
        case .english:
            "English"
        case .spanish:
            "Spanish"
        case .simplifiedChinese:
            "Simplified Chinese"
        }
    }

    var supportsLiveKokoroSynthesis: Bool {
        switch self {
        case .english, .spanish, .simplifiedChinese:
            true
        }
    }

    var defaultVoiceName: String {
        switch self {
        case .english:
            "af_heart"
        case .spanish:
            "ef_dora"
        case .simplifiedChinese:
            "zf_xiaoxiao"
        }
    }

    static func resolve(preferredAppLanguageCode: String?, effectiveLocale: Locale) -> VoiceLocale {
        let sourceCode = preferredAppLanguageCode?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCode = {
            if let sourceCode, !sourceCode.isEmpty {
                return sourceCode
            }
            return effectiveLocale.identifier
        }()
        let rawCode = resolvedCode.lowercased()

        if rawCode.hasPrefix("es") {
            return .spanish
        }
        if rawCode.hasPrefix("zh-hans") || rawCode.hasPrefix("zh_cn") || rawCode.hasPrefix("zh-cn") {
            return .simplifiedChinese
        }
        return .english
    }
}
