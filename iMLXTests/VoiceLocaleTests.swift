import XCTest
@testable import iMLX

final class VoiceLocaleTests: XCTestCase {
    func testVoiceLocaleResolution() {
        XCTAssertEqual(VoiceLocale.resolve(preferredAppLanguageCode: "en", effectiveLocale: Locale(identifier: "en-US")), .english)
        XCTAssertEqual(VoiceLocale.resolve(preferredAppLanguageCode: "es", effectiveLocale: Locale(identifier: "en-US")), .spanish)
        XCTAssertEqual(VoiceLocale.resolve(preferredAppLanguageCode: "zh-Hans", effectiveLocale: Locale(identifier: "en-US")), .simplifiedChinese)
        XCTAssertEqual(VoiceLocale.resolve(preferredAppLanguageCode: nil, effectiveLocale: Locale(identifier: "es-MX")), .spanish)
        XCTAssertEqual(VoiceLocale.resolve(preferredAppLanguageCode: nil, effectiveLocale: Locale(identifier: "zh-Hans-CN")), .simplifiedChinese)
    }

    func testVoiceLocaleProperties() {
        let english = VoiceLocale.english
        XCTAssertTrue(english.supportsLiveKokoroSynthesis)
        XCTAssertEqual(english.defaultVoiceName, "af_heart")

        let spanish = VoiceLocale.spanish
        XCTAssertTrue(spanish.supportsLiveKokoroSynthesis)
        XCTAssertEqual(spanish.defaultVoiceName, "ef_dora")

        let chinese = VoiceLocale.simplifiedChinese
        XCTAssertTrue(chinese.supportsLiveKokoroSynthesis)
        XCTAssertEqual(chinese.defaultVoiceName, "zf_xiaoxiao")
    }
}
