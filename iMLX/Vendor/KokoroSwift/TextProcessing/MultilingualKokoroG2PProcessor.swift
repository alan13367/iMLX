//
//  Kokoro-tts-lib
//
import Foundation

/// A Swift-native G2P processor for Spanish and Mandarin Chinese.
nonisolated final class MultilingualKokoroG2PProcessor: G2PProcessor {
    var currentLanguage: Language?

    private let spanishSourceScalars = CharacterSet.letters
        .union(.whitespacesAndNewlines)
        .union(CharacterSet(charactersIn: ".,?!;:¿¡"))
    private let chineseSourceScalars = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "，。？！；：,.?!;:"))
    private let spanishPhonemeScalars = Set(" abcdefiklmnoprstuwx.,?!;:ʧʎɲɡχʝ")
    private let chinesePhonemeScalars = Set(" abcdefhijklmnoprstuwy.,?!;:ɑəɕɡɤɥɨɪɯŋɻʂʈʊʐʰ")

    func setLanguage(_ language: Language) throws {
        switch language {
        case .spanish, .mandarinChinese:
            currentLanguage = language
        default:
            throw G2PProcessorError.unsupportedLanguage
        }
    }

    func process(input: String) throws -> (String, [MToken]?) {
        guard let language = currentLanguage else {
            throw G2PProcessorError.processorNotInitialized
        }

        let phonemes: String
        switch language {
        case .spanish:
            let sanitized = sanitizeSpanishInput(input)
            guard !sanitized.isEmpty else {
                throw G2PProcessorError.invalidPhonemeOutput
            }
            try validateSpanishSource(sanitized)
            phonemes = processSpanish(sanitized)
        case .mandarinChinese:
            let sanitized = sanitizeChineseInput(input)
            guard !sanitized.isEmpty else {
                throw G2PProcessorError.invalidPhonemeOutput
            }
            try validateChineseSource(sanitized)
            phonemes = processChinese(sanitized)
        default:
            throw G2PProcessorError.unsupportedLanguage
        }

        return (try validateKokoroPhonemes(phonemes, language: language), nil)
    }

    /// Reduces free-form text to characters the Spanish G2P path accepts (letters, allowed punctuation, whitespace).
    private func sanitizeSpanishInput(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        var out = String()
        out.reserveCapacity(nfc.count)
        for ch in nfc {
            if ch.unicodeScalars.allSatisfy({ spanishSourceScalars.contains($0) }) {
                out.append(ch)
            } else {
                // Digits, markdown, emojis, hyphens, etc. → word boundary; `collapseWhitespace` cleans up.
                out.append(" ")
            }
        }
        return collapseWhitespace(in: out)
    }

    /// Reduces free-form text to Han characters, Chinese/ASCII punctuation, and whitespace (drops or replaces the rest).
    private func sanitizeChineseInput(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        var out = String()
        out.reserveCapacity(nfc.count)
        for ch in nfc {
            if ch.unicodeScalars.allSatisfy({ scalar in
                chineseSourceScalars.contains(scalar) || isCJKUnifiedIdeograph(scalar)
            }) {
                out.append(ch)
            } else {
                out.append(" ")
            }
        }
        return collapseWhitespace(in: out)
    }

    private func processSpanish(_ text: String) -> String {
        var result = text.lowercased()

        let replacements: [(String, String)] = [
            ("¿", ""),
            ("¡", ""),
            ("ch", "ʧ"),
            ("ll", "ʎ"),
            ("ñ", "ɲ"),
            ("gue", "ɡe"),
            ("gui", "ɡi"),
            ("gü", "ɡw"),
            ("qu", "k"),
            ("ge", "χe"),
            ("gi", "χi"),
            ("j", "χ"),
            ("v", "b"),
            ("h", ""),
            ("z", "s"),
            ("ce", "se"),
            ("ci", "si"),
            ("y", "ʝ"),
            ("c", "k")
        ]

        for (target, replacement) in replacements {
            result = result.replacingOccurrences(of: target, with: replacement)
        }

        result = result.folding(options: .diacriticInsensitive, locale: Locale(identifier: "es"))
        result = result.replacingOccurrences(of: "g", with: "ɡ")

        return result
    }

    private func processChinese(_ text: String) -> String {
        let mutableString = NSMutableString(string: text)
        
        // Transliterate to Mandarin Latin (Pinyin with tone diacritics)
        CFStringTransform(mutableString, nil, kCFStringTransformMandarinLatin, false)
        
        // Strip diacritics to get basic pinyin
        CFStringTransform(mutableString, nil, kCFStringTransformStripDiacritics, false)
        
        var result = mutableString as String
        result = result.lowercased()
        result = normalizeChinesePunctuation(in: result)

        let replacements: [(String, String)] = [
            ("zh", "ʈʂ"),
            ("ch", "ʈʂʰ"),
            ("sh", "ʂ"),
            ("z", "ts"),
            ("c", "tsʰ"),
            ("x", "ɕ"),
            ("q", "tɕʰ"),
            ("j", "tɕ"),
            ("r", "ʐ"),
            ("ü", "y"),
            ("ang", "ɑŋ"),
            ("eng", "ɤŋ"),
            ("ing", "iŋ"),
            ("ong", "ʊŋ"),
            ("ai", "aɪ"),
            ("ei", "eɪ"),
            ("ao", "ɑʊ"),
            ("ou", "oʊ"),
            ("an", "an"),
            ("en", "ən"),
            ("er", "ɑɻ")
        ]

        for (target, replacement) in replacements {
            result = result.replacingOccurrences(of: target, with: replacement)
        }
        result = result.replacingOccurrences(of: "g", with: "ɡ")

        return result
    }

    private func validateKokoroPhonemes(_ phonemes: String, language: Language) throws -> String {
        let normalized = collapseWhitespace(in: phonemes)
        guard !normalized.isEmpty else {
            throw G2PProcessorError.invalidPhonemeOutput
        }

        let allowedScalars: Set<Character>
        switch language {
        case .spanish:
            allowedScalars = spanishPhonemeScalars
        case .mandarinChinese:
            allowedScalars = chinesePhonemeScalars
        default:
            throw G2PProcessorError.unsupportedLanguage
        }
        guard normalized.allSatisfy({ allowedScalars.contains($0) }) else {
            throw G2PProcessorError.invalidPhonemeOutput
        }

        if KokoroConfig.config == nil {
            _ = KokoroConfig.loadConfig()
        }

        let tokenIDs = Tokenizer.tokenize(phonemizedText: normalized)
        guard tokenIDs.count == normalized.count else {
            throw G2PProcessorError.invalidPhonemeOutput
        }

        return normalized
    }

    private func validateSpanishSource(_ text: String) throws {
        let normalized = text.precomposedStringWithCanonicalMapping
        guard normalized.unicodeScalars.allSatisfy({ spanishSourceScalars.contains($0) }) else {
            throw G2PProcessorError.invalidPhonemeOutput
        }
    }

    private func validateChineseSource(_ text: String) throws {
        let normalized = text.precomposedStringWithCanonicalMapping
        guard normalized.unicodeScalars.allSatisfy({ scalar in
            chineseSourceScalars.contains(scalar) || isCJKUnifiedIdeograph(scalar)
        }) else {
            throw G2PProcessorError.invalidPhonemeOutput
        }
    }

    private func normalizeChinesePunctuation(in text: String) -> String {
        text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "？", with: "?")
            .replacingOccurrences(of: "！", with: "!")
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "：", with: ":")
    }

    private func isCJKUnifiedIdeograph(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F, 0x2B820...0x2CEAF:
            true
        default:
            false
        }
    }

    private func collapseWhitespace(in text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
