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

    private struct ReadablePage {
        let title: String
        let url: URL
        let bodyText: String
    }

    private struct CandidateChunk {
        let source: MessageSource
        let text: String
    }

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            // Web search should fail fast when the device is offline so chat can
            // continue locally instead of appearing stalled while URLSession waits
            // for connectivity to come back.
            configuration.waitsForConnectivity = false
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 45
            self.session = URLSession(configuration: configuration)
        }
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
            let page: ReadablePage?
            do {
                page = try await fetchReadablePage(for: result.url)
            } catch {
                if error.isAppTransportSecurityFailure {
                    continue
                }
                throw error
            }
            guard let page, !page.bodyText.isEmpty else { continue }
            let chunks = chunkedText(page.bodyText)
            for chunk in chunks.prefix(Constants.WebSearch.maxChunksScoredPerPage) {
                let lexicalScore = lexicalSimilarity(query: trimmedQuery, text: chunk)
                let semanticScore = score(
                    queryVector: queryVector,
                    chunkVector: embedding(for: chunk, languageCode: detectLanguageCode(in: chunk))
                )
                let totalScore = semanticScore > 0 ? (semanticScore * 0.8) + (lexicalScore * 0.2) : lexicalScore
                guard totalScore > 0 else { continue }

                let excerptLimit = Constants.WebSearch.maxExcerptCharactersPerSection
                let clippedText = chunk.count > excerptLimit
                    ? String(chunk.prefix(excerptLimit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                    : chunk

                candidates.append(
                    CandidateChunk(
                        source: MessageSource(
                            id: "\(result.url.absoluteString)#\(candidates.count)",
                            kind: .web,
                            title: page.title.isEmpty ? result.title : page.title,
                            excerpt: compactExcerpt(from: clippedText),
                            location: page.url.host,
                            url: page.url,
                            score: totalScore
                        ),
                        text: clippedText
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

        let headerBudget = Constants.WebSearch.maxContextCharacters
        for candidate in ranked {
            var section = "Source: \(candidate.source.title)\nURL: \(candidate.source.url?.absoluteString ?? "")\n\(candidate.text)"
            if section.count > headerBudget {
                let header = "Source: \(candidate.source.title)\nURL: \(candidate.source.url?.absoluteString ?? "")\n"
                let textBudget = max(0, headerBudget - header.count)
                let clippedBody = candidate.text.count > textBudget
                    ? String(candidate.text.prefix(textBudget)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                    : candidate.text
                section = header + clippedBody
            }
            if section.count > headerBudget {
                section = String(section.prefix(headerBudget)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            }
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

    func retrieveContext(forDirectURL url: URL, userQuery: String) async throws -> MessageGroundingResult {
        guard let readablePage = try await fetchReadablePage(for: url) else {
            return MessageGroundingResult(contextBlock: "", sources: [])
        }

        let normalizedQuery = normalizedReadURLQuery(userQuery, url: url)
        let queryVector = normalizedQuery.isEmpty
            ? nil
            : embedding(for: normalizedQuery, languageCode: detectLanguageCode(in: normalizedQuery))

        var candidates: [CandidateChunk] = []
        let chunks = chunkedText(readablePage.bodyText)

        for chunk in chunks.prefix(Constants.WebSearch.maxChunksScoredPerPage) {
            let lexicalScore = normalizedQuery.isEmpty ? 0 : lexicalSimilarity(query: normalizedQuery, text: chunk)
            let semanticScore = normalizedQuery.isEmpty ? 0 : score(
                queryVector: queryVector,
                chunkVector: embedding(for: chunk, languageCode: detectLanguageCode(in: chunk))
            )
            let totalScore = semanticScore > 0 ? (semanticScore * 0.8) + (lexicalScore * 0.2) : lexicalScore

            let excerptLimit = Constants.WebSearch.maxExcerptCharactersPerSection
            let clippedText = chunk.count > excerptLimit
                ? String(chunk.prefix(excerptLimit)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
                : chunk

            candidates.append(
                CandidateChunk(
                    source: MessageSource(
                        id: "\(readablePage.url.absoluteString)#\(candidates.count)",
                        kind: .web,
                        title: readablePage.title,
                        excerpt: compactExcerpt(from: clippedText),
                        location: readablePage.url.host,
                        url: readablePage.url,
                        score: totalScore
                    ),
                    text: clippedText
                )
            )
        }

        let rankedCandidates: [CandidateChunk]
        let scoredCandidates = candidates.filter { ($0.source.score ?? 0) > 0 }
        if !scoredCandidates.isEmpty {
            rankedCandidates = scoredCandidates.sorted { ($0.source.score ?? 0) > ($1.source.score ?? 0) }
        } else {
            rankedCandidates = Array(candidates.prefix(3))
        }

        guard !rankedCandidates.isEmpty else {
            return MessageGroundingResult(contextBlock: "", sources: [])
        }

        var contextSections: [String] = []
        var sources: [MessageSource] = []
        var usedCharacters = 0

        for candidate in rankedCandidates {
            var section = "Source: \(candidate.source.title)\nURL: \(candidate.source.url?.absoluteString ?? "")\n\(candidate.text)"
            if usedCharacters + section.count > Constants.WebSearch.maxContextCharacters, !contextSections.isEmpty {
                break
            }
            if section.count > Constants.WebSearch.maxContextCharacters {
                section = String(section.prefix(Constants.WebSearch.maxContextCharacters)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            }
            contextSections.append(section)
            usedCharacters += section.count
        }

        guard !contextSections.isEmpty else {
            return MessageGroundingResult(contextBlock: "", sources: [])
        }

        sources.append(
            MessageSource(
                id: readablePage.url.absoluteString,
                kind: .web,
                title: readablePage.title,
                excerpt: rankedCandidates.first?.source.excerpt ?? compactExcerpt(from: readablePage.bodyText),
                location: readablePage.url.host,
                url: readablePage.url,
                score: rankedCandidates.first?.source.score
            )
        )

        let contextBlock = """
        The assistant may use the following excerpts from the user-provided link to answer this message.

        These excerpts come from the exact URL the user shared. If the page content seems incomplete, inaccessible, or ambiguous, say so plainly.

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
        let url: URL?
        if let components = URLComponents(string: href),
           let target = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let decoded = target.removingPercentEncoding,
           let decodedURL = URL(string: decoded) {
            url = decodedURL
        } else {
            url = URL(string: href)
        }

        guard let url else { return nil }

        // Upgrade http to https to comply with ATS policy
        if url.scheme?.lowercased() == "http" {
            let httpsString = url.absoluteString.replacingOccurrences(of: "http://", with: "https://", options: .caseInsensitive)
            return URL(string: httpsString) ?? url
        }

        return url
    }

    private func fetchReadablePage(for url: URL) async throws -> ReadablePage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<400).contains(httpResponse.statusCode) else {
            return nil
        }

        if let mimeType = httpResponse.mimeType?.lowercased() {
            let supportedTypes = ["text/html", "application/xhtml+xml", "text/plain"]
            guard supportedTypes.contains(mimeType) else {
                return nil
            }
        }

        let html = String(decoding: data, as: UTF8.self)
        #if canImport(SwiftSoup)
        let document = try SwiftSoup.parse(html)
        try document.select("script, style, noscript, svg").remove()
        let bodyText = try document.body()?.text() ?? ""
        let title = normalizeWhitespace((try? document.title()) ?? url.host ?? url.absoluteString)
        let normalized = normalizeWhitespace(bodyText)
        guard !normalized.isEmpty else { return nil }
        let boundedBodyText = String(normalized.prefix(Constants.WebSearch.maxFetchedBodyCharacters))
        return ReadablePage(title: title, url: url, bodyText: boundedBodyText)
        #else
        let stripped = html
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        let normalized = normalizeWhitespace(stripped)
        guard !normalized.isEmpty else { return nil }
        let title = normalizeWhitespace(extractedHTMLTitle(from: html) ?? url.host ?? url.absoluteString)
        let boundedBodyText = String(normalized.prefix(Constants.WebSearch.maxFetchedBodyCharacters))
        return ReadablePage(title: title, url: url, bodyText: boundedBodyText)
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

        // Web ranking should stay quiet in the console when NaturalLanguage lacks a local
        // embedding asset for a detected page language. We only use sentence embeddings for
        // English here and rely on lexical similarity for other languages.
        guard detectedLanguage == .english,
              let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
            return nil
        }
        return embedding.vector(for: text)
    }

    private func score(queryVector: [Double]?, chunkVector: [Double]?) -> Double {
        GroundingText.cosineSimilarity(queryVector, chunkVector)
    }

    private func lexicalSimilarity(query: String, text: String) -> Double {
        GroundingText.lexicalSimilarity(query: query, text: text)
    }

    private func tokenize(_ text: String) -> [String] {
        GroundingText.tokens(in: text)
    }

    private func compactExcerpt(from text: String) -> String {
        GroundingText.excerpt(
            from: text,
            maximumCharacters: Constants.WebSearch.maxPreviewCharacters,
            normalizingWhitespace: false
        )
    }

    private func normalizeWhitespace(_ text: String) -> String {
        GroundingText.normalizeWhitespace(text)
    }

    private func normalizedReadURLQuery(_ query: String, url: URL) -> String {
        let withoutURL = query
            .replacingOccurrences(of: url.absoluteString, with: " ")
            .replacingOccurrences(of: url.absoluteString.removingPercentEncoding ?? url.absoluteString, with: " ")
        return normalizeWhitespace(withoutURL)
    }

    private func extractedHTMLTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<title[^>]*>(.*?)</title>"#) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              match.numberOfRanges > 1,
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return normalizeWhitespace(String(html[titleRange]))
    }
}

private extension Error {
    nonisolated var isAppTransportSecurityFailure: Bool {
        let urlError: URLError?
        if let error = self as? URLError {
            urlError = error
        } else {
            let nsError = self as NSError
            if nsError.domain == NSURLErrorDomain {
                urlError = URLError(.init(rawValue: nsError.code))
            } else {
                urlError = nil
            }
        }

        return urlError?.code == .appTransportSecurityRequiresSecureConnection
    }
}
