import Foundation
import NaturalLanguage
#if canImport(SwiftSoup)
import SwiftSoup
#endif

actor WebSearchService {
    private struct SearchResult {
        let title: String
        let url: URL
    }

    private struct CandidateChunk {
        let source: MessageSource
        let text: String
    }

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        session = URLSession(configuration: configuration)
    }

    func retrieveContext(for query: String) async throws -> MessageGroundingResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return MessageGroundingResult(contextBlock: "", sources: [])
        }

        let searchResults = try await searchDuckDuckGo(query: trimmedQuery)
        guard !searchResults.isEmpty else {
            return MessageGroundingResult(contextBlock: "", sources: [])
        }

        var candidates: [CandidateChunk] = []
        let queryVector = embedding(for: trimmedQuery, languageCode: detectLanguageCode(in: trimmedQuery))

        for result in searchResults.prefix(Constants.WebSearch.maxResults) {
            guard let pageText = try await fetchReadableText(for: result.url), !pageText.isEmpty else { continue }
            for chunk in chunkedText(pageText) {
                let lexicalScore = lexicalSimilarity(query: trimmedQuery, text: chunk)
                let semanticScore = score(
                    queryVector: queryVector,
                    chunkVector: embedding(for: chunk, languageCode: detectLanguageCode(in: chunk))
                )
                let totalScore = semanticScore > 0 ? (semanticScore * 0.8) + (lexicalScore * 0.2) : lexicalScore
                guard totalScore > 0 else { continue }

                candidates.append(
                    CandidateChunk(
                        source: MessageSource(
                            id: "\(result.url.absoluteString)#\(candidates.count)",
                            kind: .web,
                            title: result.title,
                            excerpt: compactExcerpt(from: chunk),
                            location: result.url.host,
                            url: result.url,
                            score: totalScore
                        ),
                        text: chunk
                    )
                )
            }
        }

        let ranked = candidates
            .sorted { lhs, rhs in
                (lhs.source.score ?? 0) > (rhs.source.score ?? 0)
            }

        var contextSections: [String] = []
        var sources: [MessageSource] = []
        var usedCharacters = 0
        var seenURLs = Set<URL>()

        for candidate in ranked {
            let section = "Source: \(candidate.source.title)\nURL: \(candidate.source.url?.absoluteString ?? "")\n\(candidate.text)"
            if usedCharacters + section.count > Constants.WebSearch.maxContextCharacters, !contextSections.isEmpty {
                break
            }
            contextSections.append(section)
            usedCharacters += section.count
            if let url = candidate.source.url, seenURLs.insert(url).inserted {
                sources.append(candidate.source)
            }
        }

        guard !contextSections.isEmpty else {
            return MessageGroundingResult(contextBlock: "", sources: [])
        }

        let contextBlock = """
        The assistant may use the following web excerpts to ground this answer. These are untrusted external snippets retrieved for the current message only.

        Use them when they help answer the user's request. If the sources are incomplete or conflicting, say so plainly.

        \(contextSections.joined(separator: "\n\n---\n\n"))
        """

        return MessageGroundingResult(contextBlock: contextBlock, sources: sources)
    }

    private func searchDuckDuckGo(query: String) async throws -> [SearchResult] {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        let (data, _) = try await session.data(from: components.url!)
        let html = String(decoding: data, as: UTF8.self)
        #if canImport(SwiftSoup)
        let document = try SwiftSoup.parse(html)

        let results = try document.select("a.result__a")
        return try results.compactMap { element in
            let title = try element.text().trimmingCharacters(in: .whitespacesAndNewlines)
            let href = try element.attr("href")
            guard !title.isEmpty,
                  let url = resolvedSearchURL(from: href),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                return nil
            }
            return SearchResult(title: title, url: url)
        }
        #else
        return fallbackSearchResults(from: html)
        #endif
    }

    private func resolvedSearchURL(from href: String) -> URL? {
        if let components = URLComponents(string: href),
           let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let decoded = target.removingPercentEncoding,
           let url = URL(string: decoded) {
            return url
        }
        return URL(string: href)
    }

    private func fetchReadableText(for url: URL) async throws -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<400).contains(httpResponse.statusCode) else {
            return nil
        }
        let html = String(decoding: data, as: UTF8.self)
        #if canImport(SwiftSoup)
        let document = try SwiftSoup.parse(html)
        try document.select("script, style, noscript, svg").remove()
        let bodyText = try document.body()?.text() ?? ""
        let normalized = normalizeWhitespace(bodyText)
        return normalized.isEmpty ? nil : normalized
        #else
        let stripped = html
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let normalized = normalizeWhitespace(stripped)
        return normalized.isEmpty ? nil : normalized
        #endif
    }

    private func fallbackSearchResults(from html: String) -> [SearchResult] {
        let pattern = #"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else {
                return nil
            }
            let href = String(html[hrefRange])
            let title = normalizeWhitespace(
                String(html[titleRange]).replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            )
            guard let url = resolvedSearchURL(from: href), !title.isEmpty else {
                return nil
            }
            return SearchResult(title: title, url: url)
        }
    }

    private func chunkedText(_ text: String) -> [String] {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return [] }

        let step = max(Constants.WebSearch.chunkWordTarget - Constants.WebSearch.chunkWordOverlap, 1)
        var chunks: [String] = []
        var startIndex = 0

        while startIndex < words.count {
            let endIndex = min(startIndex + Constants.WebSearch.chunkWordTarget, words.count)
            let chunk = normalizeWhitespace(words[startIndex..<endIndex].joined(separator: " "))
            if !chunk.isEmpty {
                chunks.append(chunk)
            }
            if endIndex == words.count {
                break
            }
            startIndex += step
        }

        return chunks
    }

    private func detectLanguageCode(in text: String) -> String? {
        NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
    }

    private func embedding(for text: String, languageCode: String?) -> [Double]? {
        let detectedLanguage = languageCode.flatMap(NLLanguage.init(rawValue:)) ?? .english
        if let embedding = NLEmbedding.sentenceEmbedding(for: detectedLanguage),
           let vector = embedding.vector(for: text) {
            return vector
        }
        guard detectedLanguage != .english,
              let fallback = NLEmbedding.sentenceEmbedding(for: .english) else {
            return nil
        }
        return fallback.vector(for: text)
    }

    private func score(queryVector: [Double]?, chunkVector: [Double]?) -> Double {
        guard let queryVector, let chunkVector, queryVector.count == chunkVector.count else {
            return 0
        }

        var dotProduct = 0.0
        var queryMagnitude = 0.0
        var chunkMagnitude = 0.0

        for index in queryVector.indices {
            dotProduct += queryVector[index] * chunkVector[index]
            queryMagnitude += queryVector[index] * queryVector[index]
            chunkMagnitude += chunkVector[index] * chunkVector[index]
        }

        let denominator = sqrt(queryMagnitude) * sqrt(chunkMagnitude)
        guard denominator > 0 else { return 0 }
        return max(0, dotProduct / denominator)
    }

    private func lexicalSimilarity(query: String, text: String) -> Double {
        let queryTerms = Set(tokenize(query))
        let textTerms = Set(tokenize(text))
        guard !queryTerms.isEmpty, !textTerms.isEmpty else { return 0 }
        let overlap = queryTerms.intersection(textTerms).count
        guard overlap > 0 else { return 0 }
        return Double(overlap) / Double(queryTerms.count)
    }

    private func tokenize(_ text: String) -> [String] {
        normalizeWhitespace(text)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    private func compactExcerpt(from text: String) -> String {
        guard text.count > Constants.WebSearch.maxPreviewCharacters else {
            return text
        }
        let endIndex = text.index(text.startIndex, offsetBy: Constants.WebSearch.maxPreviewCharacters)
        return String(text[..<endIndex]) + "..."
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
