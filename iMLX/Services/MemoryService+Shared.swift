import Foundation
import NaturalLanguage

extension MemoryService {
    nonisolated func containsAny(_ terms: [String], in text: String) -> Bool {
        terms.contains { text.contains($0) }
    }


    nonisolated func embedding(for text: String) -> [Double]? {
        let normalizedText = normalizedMemoryContent(text)
        guard !normalizedText.isEmpty else { return nil }
        let language = NLLanguageRecognizer.dominantLanguage(for: normalizedText) ?? .english

        if let embedding = NLEmbedding.sentenceEmbedding(for: language),
           let vector = embedding.vector(for: normalizedText) {
            return vector
        }

        guard language != .english,
              let fallbackEmbedding = NLEmbedding.sentenceEmbedding(for: .english),
              let vector = fallbackEmbedding.vector(for: normalizedText) else {
            return nil
        }

        return vector
    }

    nonisolated func normalizedMemoryContent(_ content: String) -> String {
        MemoryText.compact(content)
    }

    nonisolated func normalizedStoredMemoryContent(_ content: String) -> String {
        var normalized = normalizedMemoryContent(content)
        normalized = durableMemoryContent(from: normalized)
        normalized = MemoryFactParser.rewriteFirstPerson(normalized)
        normalized = normalizedUserMemorySentence(normalized)

        if let lastCharacter = normalized.last, !".!?".contains(lastCharacter) {
            normalized += "."
        }

        return normalized
    }


    nonisolated func normalizedUserMemorySentence(_ content: String) -> String {
        let lowercased = content.lowercased()
        if lowercased.hasPrefix("the user:") {
            let detail = content.dropFirst("the user:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            return "The user \(detail)"
        }
        if lowercased.hasPrefix("user's ") {
            return "The user's \(content.dropFirst(7))"
        }
        if lowercased.hasPrefix("user’s ") {
            return "The user’s \(content.dropFirst(7))"
        }
        if lowercased.hasPrefix("user ") {
            return "The user \(content.dropFirst(5))"
        }
        if lowercased.hasPrefix("likes ") || lowercased.hasPrefix("loves ") || lowercased.hasPrefix("enjoys ") {
            return "The user \(content)"
        }
        if lowercased.hasPrefix("dislikes ") || lowercased.hasPrefix("hates ") {
            return "The user \(content)"
        }
        if lowercased.hasPrefix("name is ") {
            return "The user's \(content)"
        }
        return content
    }


    nonisolated func durableMemoryContent(from content: String) -> String {
        let lowercased = content.lowercased()
        let markers = [
            " and i would like ",
            " and i'd like ",
            " and i’d like ",
            " and i want ",
            " and i need ",
            " and would like ",
            " and want ",
            " and need ",
            ", i would like ",
            ", i'd like ",
            ", i’d like ",
            ", i want ",
            ", i need ",
            ", would like ",
            ", want ",
            ", need ",
            " but i would like ",
            " but i'd like ",
            " but i’d like ",
            " but i want ",
            " but i need ",
            " but would like ",
            " but want ",
            " but need ",
            " so i would like ",
            " so i'd like ",
            " so i’d like ",
            " so i want ",
            " so i need ",
            " so would like ",
            " so want ",
            " so need "
        ]

        let firstMarkerRange = markers
            .compactMap { marker in lowercased.range(of: marker) }
            .min { left, right in left.lowerBound < right.lowerBound }

        guard let firstMarkerRange else { return content }

        let trimmed = content[..<firstMarkerRange.lowerBound]
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?,;:")))
        guard !trimmed.isEmpty else { return content }
        return "\(trimmed)."
    }


    nonisolated func normalizedMetadataValue(_ value: String?, maxLength: Int) -> String? {
        guard let value else { return nil }
        var normalized = MemoryText.compact(value)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
        guard !normalized.isEmpty else { return nil }
        if normalized.count > maxLength {
            normalized = String(normalized.prefix(maxLength))
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return normalized.isEmpty ? nil : normalized
    }

    nonisolated func normalizedLanguageCode(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = MemoryText.compact(value)
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()
            .filter { character in
                character.isLetter || character.isNumber || character == "-"
            }
        guard !normalized.isEmpty, normalized.count <= 24 else { return nil }
        return normalized
    }

    nonisolated func detectedLanguageCode(in text: String) -> String? {
        let normalized = MemoryText.compact(text)
        guard !normalized.isEmpty,
              let language = NLLanguageRecognizer.dominantLanguage(for: normalized) else {
            return nil
        }
        return language.rawValue
    }

}
