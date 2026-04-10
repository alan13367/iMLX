import Foundation
import NaturalLanguage

extension MemoryService {
    nonisolated func extractionCandidates(from rawOutput: String, sourceText: String? = nil) -> [MemoryExtractionCandidate] {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isNoMemoryMarker(trimmed) else { return [] }

        for payload in jsonPayloads(in: trimmed) {
            if let candidates = extractionCandidatesFromJSON(payload) {
                return sanitizedCandidates(candidates, sourceText: sourceText)
            }
        }

        let legacyCandidates = fallbackExtractionCandidates(from: trimmed).map {
            RawMemoryExtractionCandidate(
                canonicalContent: $0,
                relation: nil,
                value: nil,
                sourceQuote: nil,
                sourceLanguageCode: nil,
                confidence: nil,
                requiresSourceQuote: false
            )
        }
        return sanitizedCandidates(legacyCandidates, sourceText: sourceText)
    }



    private nonisolated func sanitizedCandidates(
        _ candidates: [RawMemoryExtractionCandidate],
        sourceText: String? = nil
    ) -> [MemoryExtractionCandidate] {
        var seen = Set<String>()
        var latestByConflictKey: [String: MemoryExtractionCandidate] = [:]
        var orderedKeys: [String] = []

        for rawCandidate in candidates {
            let confidence = min(max(rawCandidate.confidence ?? 1, 0), 1)
            guard confidence >= MemoryScoring.minimumExtractionConfidence else { continue }
            guard var normalized = normalizedExtractionCandidate(rawCandidate.canonicalContent) else { continue }
            guard normalized.count >= Constants.Memory.minimumCandidateCharacters else { continue }
            if normalized.count > Constants.Memory.maximumCandidateCharacters {
                normalized = String(normalized.prefix(Constants.Memory.maximumCandidateCharacters))
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
                if let lastCharacter = normalized.last, !".!?".contains(lastCharacter) {
                    normalized += "."
                }
            }

            let sourceQuote = normalizedMetadataValue(rawCandidate.sourceQuote, maxLength: 320)
            guard !rawCandidate.requiresSourceQuote || sourceText == nil || sourceQuote != nil else { continue }
            guard isGroundedInUserMessage(
                normalized,
                sourceQuote: sourceQuote,
                sourceText: sourceText,
                factValue: rawCandidate.value,
                relation: rawCandidate.relation
            ) else {
                continue
            }

            let relation = MemoryFactParser.normalizedRelationRawValue(rawCandidate.relation)
                ?? MemoryFactParser.signature(for: normalized)?.relation.rawValue
            let value = normalizedMetadataValue(rawCandidate.value, maxLength: 180)
            let sourceLanguageCode = normalizedLanguageCode(rawCandidate.sourceLanguageCode)
                ?? detectedLanguageCode(in: sourceQuote ?? sourceText ?? normalized)

            let candidate = MemoryExtractionCandidate(
                canonicalContent: normalized,
                relation: relation,
                value: value,
                sourceQuote: sourceQuote,
                sourceLanguageCode: sourceLanguageCode,
                confidence: confidence
            )

            let dedupeKey = MemoryText.searchable(normalized)
            guard seen.insert(dedupeKey).inserted else { continue }

            if let signature = MemoryFactParser.signature(relation: relation, value: value)
                ?? MemoryFactParser.signature(for: normalized),
               !signature.isRetraction {
                let key = signature.conflictKey
                if latestByConflictKey[key] == nil {
                    orderedKeys.append(key)
                }
                latestByConflictKey[key] = candidate
            } else {
                let key = "raw:\(dedupeKey)"
                orderedKeys.append(key)
                latestByConflictKey[key] = candidate
            }
        }

        return orderedKeys.compactMap { latestByConflictKey[$0] }
    }

    private nonisolated func normalizedExtractionCandidate(_ candidate: String) -> String? {
        var normalized = strippedCandidate(candidate)
        guard !normalized.isEmpty, !isNoMemoryMarker(normalized) else { return nil }

        normalized = durableMemoryContent(from: normalized)
        normalized = MemoryFactParser.rewriteFirstPerson(normalized)
        normalized = normalizedUserMemorySentence(normalized)

        guard isWellFormedUserMemory(normalized) else { return nil }
        guard !isGenericRequestMemory(normalized) else { return nil }
        guard !isEphemeralConversationMemory(normalized) else { return nil }
        guard !isLowConfidenceAttributionMemory(normalized) else { return nil }

        if let signature = MemoryFactParser.signature(for: normalized), signature.isRetraction {
            return nil
        }

        if let lastCharacter = normalized.last, !".!?".contains(lastCharacter) {
            normalized += "."
        }
        return normalized
    }

    private nonisolated func isWellFormedUserMemory(_ content: String) -> Bool {
        let lowercased = content.lowercased()
        guard lowercased.hasPrefix("the user ") || lowercased.hasPrefix("the user's ") || lowercased.hasPrefix("the user’s ") else {
            return false
        }

        let wordCount = content
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .count
        return wordCount >= 4
    }

    private nonisolated func isGenericRequestMemory(_ content: String) -> Bool {
        let lowercased = content.lowercased()
        let blockedPrefixes = [
            "the user asked",
            "the user asks",
            "the user requested",
            "the user requests",
            "the user is asking",
            "the user is requesting",
            "the user needs help",
            "the user wants help",
            "the user would like help"
        ]
        if blockedPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return true
        }

        let blockedPhrases = [
            "clarification request",
            "information request",
            "recommendation request",
            "correction request",
            "comparison request"
        ]
        return blockedPhrases.contains { lowercased.contains($0) }
    }

    nonisolated func isLowValueInferredMemory(_ content: String) -> Bool {
        isGenericRequestMemory(content)
            || isEphemeralConversationMemory(content)
            || isLowConfidenceAttributionMemory(content)
    }

    private nonisolated func isEphemeralConversationMemory(_ content: String) -> Bool {
        let normalized = normalizedMemoryContent(content)
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        let blockedPrefixes = [
            "the user says hi",
            "the user says hello",
            "the user says hey",
            "the user says hola",
            "the user says good morning",
            "the user says good afternoon",
            "the user says good evening",
            "the user said hi",
            "the user said hello",
            "the user said hey",
            "the user greets",
            "the user greeted",
            "the user says thanks",
            "the user says thank you",
            "the user thanks",
            "the user thanked",
            "the user says bye",
            "the user says goodbye",
            "the user opens with a greeting",
            "the user starts with a greeting",
            "the user starts the conversation"
        ]

        if blockedPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        let speechActPrefixes = [
            "the user says ",
            "the user said ",
            "the user mentions ",
            "the user mentioned "
        ]
        let niceties: Set<String> = [
            "hi", "hello", "hey", "hola", "thanks", "thank you", "good morning", "good afternoon",
            "good evening", "bye", "goodbye"
        ]

        for prefix in speechActPrefixes where normalized.hasPrefix(prefix) {
            let remainder = normalized.dropFirst(prefix.count)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            if niceties.contains(String(remainder)) {
                return true
            }
        }

        return false
    }

    private nonisolated func isLowConfidenceAttributionMemory(_ content: String) -> Bool {
        let normalized = normalizedMemoryContent(content)
            .lowercased()
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        let blockedPrefixes = [
            "the user thinks",
            "the user believes",
            "the user guesses",
            "the user estimates",
            "the user assumes",
            "the user wonders",
            "the user is wondering",
            "the user is asking whether",
            "the user is asking how much"
        ]
        return blockedPrefixes.contains { normalized.hasPrefix($0) }
    }

    private nonisolated func isGroundedInUserMessage(
        _ candidate: String,
        sourceQuote: String?,
        sourceText: String?,
        factValue: String?,
        relation rawRelation: String?
    ) -> Bool {
        guard let sourceText else { return true }

        let normalizedSource = normalizedMemoryContent(sourceText)
        guard !normalizedSource.isEmpty else { return false }

        let candidateNumbers = numericTokens(in: candidate)
        let sourceNumbers = numericTokens(in: normalizedSource)
        guard candidateNumbers.isSubset(of: sourceNumbers) else { return false }

        let relation = MemoryRelation(externalValue: rawRelation) ?? MemoryFactParser.signature(for: candidate)?.relation

        if let sourceQuote {
            guard sourceQuoteIsSupported(sourceQuote, in: normalizedSource) else { return false }
            guard candidateNumbers.isSubset(of: numericTokens(in: sourceQuote)) else { return false }

            if let relation, !factValueIsSupportedBySourceQuote(factValue, relation: relation, sourceQuote: sourceQuote) {
                return false
            }

            switch relation {
            case .some(.likes), .some(.dislikes):
                return sourceContainsExplicitPreference(sourceQuote)
            case .some(.name), .some(.residence):
                return relation.map { sourceContainsRelationEvidence($0, in: sourceQuote) } == true
                    || sourceValueOverlapScore(factValue, sourceQuote: sourceQuote) > 0
            case .some(.goal), .some(.project), .some(.constraint):
                return relation.map { sourceContainsRelationEvidence($0, in: sourceQuote) } == true
                    || sourceValueOverlapScore(factValue, sourceQuote: sourceQuote) >= 0.25
            case .some(.pronouns), .some(.timezone), .some(.occupation), .some(.employer), .some(.education), .some(.language), .some(.allergy), .some(.diet), .some(.identity), .some(.general):
                return relation.map { sourceContainsRelationEvidence($0, in: sourceQuote) } == true
                    || sourceValueOverlapScore(factValue, sourceQuote: sourceQuote) >= 0.20
            case .none:
                return sourceValueOverlapScore(factValue, sourceQuote: sourceQuote) >= 0.20
                    || termSupportRatio(candidate: candidate, source: sourceQuote) >= 0.35
            }
        }

        let candidateTerms = Set(MemoryText.tokens(candidate))
        let sourceTerms = Set(MemoryText.tokens(normalizedSource))
        guard !candidateTerms.isEmpty, !sourceTerms.isEmpty else { return false }

        let supportedTerms = candidateTerms.intersection(sourceTerms)
        let supportRatio = Double(supportedTerms.count) / Double(candidateTerms.count)

        if let signature = MemoryFactParser.signature(for: candidate) {
            switch signature.relation {
            case .likes, .dislikes:
                return sourceContainsExplicitPreference(normalizedSource)
                    && (supportRatio >= 0.35 || sourceTerms.intersection(Set(signature.valueKey.split(separator: " ").map(String.init))).isEmpty == false)
            case .name, .pronouns, .residence, .timezone, .occupation, .employer, .education, .language, .goal, .project, .constraint, .allergy, .diet:
                return supportRatio >= 0.30
            case .identity, .general:
                return supportRatio >= 0.50
            }
        }

        return supportRatio >= 0.50
    }

    private nonisolated func sourceContainsExplicitPreference(_ sourceText: String) -> Bool {
        let normalized = MemoryText.aliasSearchable(sourceText)
        let markers = [
            "i like", "i love", "i enjoy", "i prefer", "i m a fan", "i am a fan",
            "my favorite", "i dislike", "i hate", "i don t like", "i do not like",
            "me gusta", "me encanta", "prefiero", "mi favorito", "odio", "detesto", "no me gusta",
            "j aime", "j adore", "je prefere", "je deteste", "je n aime pas",
            "ich mag", "ich liebe", "ich bevorzuge", "ich hasse",
            "mi piace", "amo", "preferisco", "odio", "non mi piace",
            "eu gosto", "eu amo", "prefiro", "odeio", "nao gosto", "não gosto",
            "喜欢", "喜歡", "讨厌", "討厭", "好き", "嫌い", "좋아", "싫어"
        ]
        return markers.contains { normalized.contains($0) }
    }

    private nonisolated func sourceQuoteIsSupported(_ sourceQuote: String, in sourceText: String) -> Bool {
        let quote = normalizedMemoryContent(sourceQuote)
        guard !quote.isEmpty else { return false }

        let normalizedQuote = MemoryText.searchable(quote)
        let normalizedSource = MemoryText.searchable(sourceText)
        if normalizedSource.contains(normalizedQuote) {
            return true
        }

        let quoteTokens = Set(MemoryText.tokens(normalizedQuote))
        let sourceTokens = Set(MemoryText.tokens(normalizedSource))
        guard !quoteTokens.isEmpty, !sourceTokens.isEmpty else { return false }

        let overlap = quoteTokens.intersection(sourceTokens).count
        return Double(overlap) / Double(quoteTokens.count) >= 0.75
    }

    private nonisolated func factValueIsSupportedBySourceQuote(
        _ factValue: String?,
        relation: MemoryRelation,
        sourceQuote: String
    ) -> Bool {
        guard let factValue = normalizedMetadataValue(factValue, maxLength: 180),
              !factValue.isEmpty else {
            return true
        }

        if !usesMostlyLatinScript(sourceQuote) {
            return true
        }

        let valueTokens = factValue
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !valueTokens.isEmpty else { return true }

        let quoteTokens = MemoryText.tokens(sourceQuote)

        switch relation {
        case .name:
            return valueTokens.allSatisfy { tokenIsSupported($0, by: quoteTokens) }
        case .residence, .employer:
            let highRiskTokens = valueTokens.filter { looksLikeNamedEntityToken($0) }
            return highRiskTokens.isEmpty || highRiskTokens.allSatisfy { tokenIsSupported($0, by: quoteTokens) }
        case .pronouns, .timezone, .occupation, .education, .language, .likes, .dislikes, .goal, .project, .constraint, .allergy, .diet, .identity, .general:
            return true
        }
    }

    private nonisolated func sourceContainsRelationEvidence(_ relation: MemoryRelation, in sourceText: String) -> Bool {
        let normalized = MemoryText.aliasSearchable(sourceText)
        switch relation {
        case .name:
            return containsAny(["my name is", "i am called", "me llamo", "mi nombre es", "je m appelle", "mein name ist", "mi chiamo", "meu nome e", "我的名字", "我叫"], in: normalized)
        case .pronouns:
            return containsAny(["my pronouns", "mis pronombres", "mes pronoms", "meine pronomen", "i miei pronomi"], in: normalized)
        case .residence:
            return containsAny(["i live", "i reside", "i am based", "i m based", "my home", "vivo", "resido", "mi casa", "j habite", "je vis", "ich wohne", "ich lebe", "vivo a", "abito", "moro", "我住", "住んで"], in: normalized)
        case .timezone:
            return containsAny(["timezone", "time zone", "zona horaria", "fuseau horaire", "zeitzone", "fuso orario"], in: normalized)
        case .occupation:
            return containsAny(["i work as", "i am a", "i m a", "my job", "trabajo como", "soy", "mon metier", "je suis", "ich bin", "lavoro come", "sou"], in: normalized)
        case .employer:
            return containsAny(["i work at", "i work for", "my employer", "trabajo en", "trabajo para", "je travaille", "ich arbeite", "lavoro per", "trabalho na"], in: normalized)
        case .education:
            return containsAny(["i study", "i am studying", "i m studying", "i learn", "estudio", "estoy estudiando", "j etudie", "ich studiere", "studio", "estudo"], in: normalized)
        case .language:
            return containsAny(["i speak", "my preferred language", "hablo", "mi idioma", "je parle", "ich spreche", "parlo", "falo"], in: normalized)
        case .likes, .dislikes:
            return sourceContainsExplicitPreference(sourceText)
        case .goal:
            return containsAny(["i want to", "i plan to", "my goal", "quiero", "planeo", "mi objetivo", "je veux", "mon objectif", "ich will", "mein ziel", "voglio", "meu objetivo"], in: normalized)
        case .project:
            return containsAny(["working on", "my project", "estoy trabajando", "mi proyecto", "mon projet", "mein projekt", "il mio progetto", "meu projeto"], in: normalized)
        case .constraint:
            return containsAny(["i need", "i cannot", "i can t", "i require", "necesito", "no puedo", "je dois", "je ne peux pas", "ich brauche", "ich kann nicht", "ho bisogno", "preciso"], in: normalized)
        case .allergy:
            return containsAny(["allergic", "allergy", "alergia", "alergico", "alérgico", "allergique", "allergisch", "allergico"], in: normalized)
        case .diet:
            return containsAny(["vegan", "vegetarian", "kosher", "halal", "vegano", "vegetariano", "vegetarien", "vegetarisch"], in: normalized)
        case .identity, .general:
            return false
        }
    }

    private nonisolated func sourceValueOverlapScore(_ factValue: String?, sourceQuote: String) -> Double {
        guard let factValue, !MemoryText.compact(factValue).isEmpty else { return 0 }

        let valueTokens = Set(MemoryText.tokens(factValue))
        let sourceTokens = Set(MemoryText.tokens(sourceQuote))
        guard !valueTokens.isEmpty, !sourceTokens.isEmpty else { return 0 }

        let overlap = valueTokens.intersection(sourceTokens).count
        if overlap > 0 {
            return Double(overlap) / Double(valueTokens.count)
        }

        let fuzzyOverlap = valueTokens.filter { valueToken in
            sourceTokens.contains { sourceToken in
                tokensAreFuzzyMatch(valueToken, sourceToken)
            }
        }.count
        return Double(fuzzyOverlap) / Double(valueTokens.count)
    }

    private nonisolated func termSupportRatio(candidate: String, source: String) -> Double {
        let candidateTerms = Set(MemoryText.tokens(candidate))
        let sourceTerms = Set(MemoryText.tokens(source))
        guard !candidateTerms.isEmpty, !sourceTerms.isEmpty else { return 0 }
        return Double(candidateTerms.intersection(sourceTerms).count) / Double(candidateTerms.count)
    }

    private nonisolated func tokenIsSupported(_ token: String, by sourceTokens: [String]) -> Bool {
        guard let normalizedToken = MemoryText.tokens(token).first else { return false }
        return sourceTokens.contains { tokensAreFuzzyMatch(normalizedToken, $0) }
    }

    private nonisolated func tokensAreFuzzyMatch(_ left: String, _ right: String) -> Bool {
        if left == right { return true }
        if left.count >= 4, right.count >= 4, (left.contains(right) || right.contains(left)) {
            return true
        }
        guard abs(left.count - right.count) <= 2, min(left.count, right.count) >= 4 else { return false }
        return editDistance(left, right, maximumDistance: 2) <= 2
    }

    private nonisolated func looksLikeNamedEntityToken(_ token: String) -> Bool {
        guard let first = token.unicodeScalars.first else { return false }
        if token.count <= 1 { return false }
        if CharacterSet.decimalDigits.contains(first) { return true }
        return CharacterSet.uppercaseLetters.contains(first)
    }

    private nonisolated func usesMostlyLatinScript(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return true }
        let latinCount = letters.filter { $0.value <= 0x024F }.count
        return Double(latinCount) / Double(letters.count) >= 0.75
    }

    private nonisolated func editDistance(_ left: String, _ right: String, maximumDistance: Int) -> Int {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)
        if abs(leftCharacters.count - rightCharacters.count) > maximumDistance {
            return maximumDistance + 1
        }

        var previous = Array(0...rightCharacters.count)
        var current = Array(repeating: 0, count: rightCharacters.count + 1)

        for leftIndex in 1...leftCharacters.count {
            current[0] = leftIndex
            var rowMinimum = current[0]
            for rightIndex in 1...rightCharacters.count {
                let cost = leftCharacters[leftIndex - 1] == rightCharacters[rightIndex - 1] ? 0 : 1
                current[rightIndex] = min(
                    previous[rightIndex] + 1,
                    current[rightIndex - 1] + 1,
                    previous[rightIndex - 1] + cost
                )
                rowMinimum = min(rowMinimum, current[rightIndex])
            }
            if rowMinimum > maximumDistance {
                return maximumDistance + 1
            }
            swap(&previous, &current)
        }

        return previous[rightCharacters.count]
    }

    private nonisolated func numericTokens(in text: String) -> Set<String> {
        guard let regex = try? NSRegularExpression(pattern: #"[$€£¥]?\d+(?:[\.,]\d+)?(?:k|m|%)?"#, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(regex.matches(in: text, range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            let token = text[matchRange]
                .lowercased()
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: CharacterSet(charactersIn: "$€£¥"))
            return token.isEmpty ? nil : token
        })
    }

    private nonisolated func extractionCandidatesFromJSON(_ text: String) -> [RawMemoryExtractionCandidate]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return memoryCandidates(fromJSON: object)
    }

    private nonisolated func memoryCandidates(fromJSON object: Any) -> [RawMemoryExtractionCandidate] {
        if let string = object as? String {
            return [
                RawMemoryExtractionCandidate(
                    canonicalContent: string,
                    relation: nil,
                    value: nil,
                    sourceQuote: nil,
                    sourceLanguageCode: nil,
                    confidence: nil,
                    requiresSourceQuote: false
                )
            ]
        }

        if let array = object as? [Any] {
            return array.flatMap(memoryCandidates(fromJSON:))
        }

        guard let dictionary = object as? [String: Any] else {
            return []
        }

        let containerKeys = ["memories", "facts", "items", "results", "candidates"]
        let contentKeys = ["canonicalContent", "canonical_content", "content", "memory", "text", "sentence"]
        var candidates: [RawMemoryExtractionCandidate] = []

        for key in containerKeys {
            if let value = value(for: key, in: dictionary) {
                candidates.append(contentsOf: memoryCandidates(fromJSON: value))
            }
        }

        if let content = stringValue(for: contentKeys, in: dictionary) {
            candidates.append(
                RawMemoryExtractionCandidate(
                    canonicalContent: content,
                    relation: stringValue(for: ["relation", "type", "category"], in: dictionary),
                    value: stringValue(for: ["value", "canonicalValue", "canonical_value", "factValue", "fact_value"], in: dictionary),
                    sourceQuote: stringValue(for: ["sourceQuote", "source_quote", "quote", "evidence", "evidenceQuote", "evidence_quote"], in: dictionary),
                    sourceLanguageCode: stringValue(for: ["sourceLanguageCode", "source_language_code", "language", "languageCode", "language_code"], in: dictionary),
                    confidence: doubleValue(for: ["confidence", "score"], in: dictionary),
                    requiresSourceQuote: structuredCandidateKeysArePresent(in: dictionary)
                )
            )
        }

        return candidates
    }

    private nonisolated func value(for lowercaseKey: String, in dictionary: [String: Any]) -> Any? {
        let normalizedLookupKey = normalizedJSONKey(lowercaseKey)
        return dictionary.first { normalizedJSONKey($0.key) == normalizedLookupKey }?.value
    }

    private nonisolated func stringValue(for keys: [String], in dictionary: [String: Any]) -> String? {
        for key in keys {
            if let string = value(for: key, in: dictionary) as? String {
                let compacted = MemoryText.compact(string)
                if !compacted.isEmpty {
                    return compacted
                }
            }
        }
        return nil
    }

    private nonisolated func doubleValue(for keys: [String], in dictionary: [String: Any]) -> Double? {
        for key in keys {
            let rawValue = value(for: key, in: dictionary)
            if let number = rawValue as? NSNumber {
                return number.doubleValue
            }
            if let string = rawValue as? String, let value = Double(MemoryText.compact(string)) {
                return value
            }
        }
        return nil
    }

    private nonisolated func structuredCandidateKeysArePresent(in dictionary: [String: Any]) -> Bool {
        let structuredKeys = [
            "canonicalContent", "canonical_content", "relation", "type", "category", "value",
            "canonicalValue", "canonical_value", "factValue", "fact_value", "sourceQuote",
            "source_quote", "quote", "evidence", "evidenceQuote", "evidence_quote",
            "sourceLanguageCode", "source_language_code", "language", "languageCode",
            "language_code", "confidence", "score"
        ]
        let dictionaryKeys = Set(dictionary.keys.map(normalizedJSONKey))
        return structuredKeys.map(normalizedJSONKey).contains { dictionaryKeys.contains($0) }
    }

    private nonisolated func normalizedJSONKey(_ key: String) -> String {
        key
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private nonisolated func jsonPayloads(in text: String) -> [String] {
        var payloads = [text]
        payloads.append(contentsOf: fencedCodePayloads(in: text))
        payloads.append(contentsOf: balancedJSONFragments(in: text))

        var seen = Set<String>()
        return payloads.compactMap { payload in
            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private nonisolated func fencedCodePayloads(in text: String) -> [String] {
        let parts = text.components(separatedBy: "```")
        guard parts.count > 2 else { return [] }

        return parts.indices.compactMap { index in
            guard index % 2 == 1 else { return nil }
            var payload = parts[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if payload.lowercased().hasPrefix("json") {
                payload = payload.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return payload
        }
    }

    private nonisolated func balancedJSONFragments(in text: String) -> [String] {
        var fragments: [String] = []
        var stack: [Character] = []
        var startIndex: String.Index?
        var isInString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]

            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                continue
            }

            if character == "\"" {
                isInString = true
                continue
            }

            if character == "[" || character == "{" {
                if stack.isEmpty {
                    startIndex = index
                }
                stack.append(character)
                continue
            }

            if character == "]" || character == "}" {
                guard let opening = stack.last,
                      (opening == "[" && character == "]") || (opening == "{" && character == "}") else {
                    stack.removeAll()
                    startIndex = nil
                    continue
                }

                stack.removeLast()
                if stack.isEmpty, let fragmentStartIndex = startIndex {
                    fragments.append(String(text[fragmentStartIndex...index]))
                    startIndex = nil
                }
            }
        }

        return fragments
    }

    private nonisolated func fallbackExtractionCandidates(from text: String) -> [String] {
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        let lineCandidates = stripped
            .components(separatedBy: .newlines)
            .flatMap(sentenceCandidates(from:))
        return lineCandidates.isEmpty ? sentenceCandidates(from: stripped) : lineCandidates
    }

    private nonisolated func sentenceCandidates(from text: String) -> [String] {
        let compacted = normalizedMemoryContent(text)
        guard !compacted.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = compacted

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: compacted.startIndex..<compacted.endIndex) { range, _ in
            sentences.append(String(compacted[range]))
            return true
        }

        if sentences.isEmpty {
            sentences = compacted.components(separatedBy: ";")
        }

        return sentences.map(strippedCandidate)
    }

    private nonisolated func strippedCandidate(_ candidate: String) -> String {
        var stripped = normalizedMemoryContent(candidate)
        let patterns = [
            #"^\s*(?:[-*]|\d+[\.\)])\s*"#,
            #"^\s*(?:(?:memory|fact|candidate|remember)\s*[:\-]\s*)"#,
            #"^\s*["']?(?:memory|fact|content|text)["']?\s*[:=]\s*"#
        ]

        for pattern in patterns {
            stripped = stripped.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }

        return stripped.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"' ,")))
    }

    private nonisolated func isNoMemoryMarker(_ text: String) -> Bool {
        let normalized = MemoryText.searchable(text)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        let markers: Set<String> = [
            "[]", "null", "none", "no memory", "no memories", "no durable memories",
            "nothing", "nothing to remember", "n/a", "na"
        ]
        return markers.contains(normalized)
    }

}
