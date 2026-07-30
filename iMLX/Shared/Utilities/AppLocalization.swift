import Foundation

nonisolated enum AppLocalization {
    static var effectiveLocale: Locale {
        return Locale.current
    }
}

extension String {
    nonisolated static func appLocalized(_ key: String) -> String {
        return String(localized: String.LocalizationValue(stringLiteral: key))
    }
}
