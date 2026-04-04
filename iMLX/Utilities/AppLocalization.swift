import Foundation

enum AppLocalization {
    static let preferredLanguageUserDefaultsKey = "preferredAppLanguage"

    static var effectiveLocale: Locale {
        if let code = UserDefaults.standard.string(forKey: preferredLanguageUserDefaultsKey), !code.isEmpty {
            return Locale(identifier: code)
        }
        return Locale.current
    }
}

enum AppLanguageOption: String, CaseIterable, Identifiable {
    case system = "system"
    case english = "en"
    case spanish = "es"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var storageCode: String? {
        switch self {
        case .system:
            nil
        case .english:
            "en"
        case .spanish:
            "es"
        case .simplifiedChinese:
            "zh-Hans"
        }
    }

    static func from(storageCode: String?) -> AppLanguageOption {
        guard let code = storageCode, !code.isEmpty else { return .system }
        switch code {
        case "en": return .english
        case "es": return .spanish
        case "zh-Hans": return .simplifiedChinese
        default: return .system
        }
    }

    var titleLocalizationKey: String {
        switch self {
        case .system: return "settings.language.system"
        case .english: return "settings.language.english"
        case .spanish: return "settings.language.spanish"
        case .simplifiedChinese: return "settings.language.simplified_chinese"
        }
    }
}

extension String {
    static func appLocalized(_ key: String) -> String {
        if let code = UserDefaults.standard.string(forKey: AppLocalization.preferredLanguageUserDefaultsKey), !code.isEmpty {
            var resource = LocalizedStringResource(String.LocalizationValue(stringLiteral: key))
            resource.locale = Locale(identifier: code)
            return String(localized: resource)
        }
        return String(localized: String.LocalizationValue(stringLiteral: key))
    }
}
