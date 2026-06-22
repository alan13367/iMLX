import Foundation

nonisolated enum GroundingText {
    static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(in text: String, minimumLength: Int = 3) -> [String] {
        normalizeWhitespace(text)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= minimumLength }
    }

    static func lexicalSimilarity(query: String, text: String) -> Double {
        let queryTerms = Set(tokens(in: query))
        let textTerms = Set(tokens(in: text))
        guard !queryTerms.isEmpty, !textTerms.isEmpty else { return 0 }

        let overlap = queryTerms.intersection(textTerms).count
        guard overlap > 0 else { return 0 }
        return Double(overlap) / Double(queryTerms.count)
    }

    static func cosineSimilarity(_ lhs: [Double]?, _ rhs: [Double]?) -> Double {
        guard let lhs, let rhs, lhs.count == rhs.count, !lhs.isEmpty else {
            return 0
        }

        var dotProduct = 0.0
        var lhsMagnitude = 0.0
        var rhsMagnitude = 0.0
        for index in lhs.indices {
            dotProduct += lhs[index] * rhs[index]
            lhsMagnitude += lhs[index] * lhs[index]
            rhsMagnitude += rhs[index] * rhs[index]
        }

        let denominator = sqrt(lhsMagnitude) * sqrt(rhsMagnitude)
        guard denominator > 0 else { return 0 }
        return max(0, dotProduct / denominator)
    }

    static func excerpt(
        from text: String,
        maximumCharacters: Int,
        suffix: String = "...",
        normalizingWhitespace: Bool = true
    ) -> String {
        let prepared = normalizingWhitespace ? normalizeWhitespace(text) : text
        guard prepared.count > maximumCharacters else { return prepared }

        return String(prepared.prefix(maximumCharacters))
            .trimmingCharacters(in: .whitespacesAndNewlines) + suffix
    }
}
