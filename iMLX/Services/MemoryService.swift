import Accelerate
import Foundation
import NaturalLanguage

private nonisolated struct MemoryRetrievalCandidate {
    let memory: UserMemory
    let score: Double
}

private nonisolated enum MemoryRelation: String, Hashable {
    case name
    case pronouns
    case residence
    case timezone
    case occupation
    case employer
    case education
    case language
    case likes
    case dislikes
    case goal
    case project
    case constraint
    case allergy
    case diet
    case identity
    case general

    var isSingleValued: Bool {
        switch self {
        case .name, .pronouns, .residence, .timezone, .employer:
            true
        case .occupation, .education, .language, .likes, .dislikes, .goal, .project, .constraint, .allergy, .diet, .identity, .general:
            false
        }
    }
}

private nonisolated struct MemoryFactSignature: Hashable {
    let relation: MemoryRelation
    let valueKey: String
    let isRetraction: Bool

    var conflictKey: String {
        switch relation {
        case .likes, .dislikes:
            "preference:\(valueKey)"
        case .general:
            "general:\(valueKey)"
        default:
            relation.rawValue
        }
    }

    func isDuplicate(of other: MemoryFactSignature) -> Bool {
        guard relation == other.relation, isRetraction == other.isRetraction else {
            return false
        }
        return MemoryText.valuesCompatible(valueKey, other.valueKey)
    }

    func conflicts(with other: MemoryFactSignature) -> Bool {
        guard !isRetraction, !other.isRetraction else { return false }

        if relation.isSingleValued, relation == other.relation {
            return !MemoryText.valuesCompatible(valueKey, other.valueKey)
        }

        if (relation == .likes && other.relation == .dislikes) || (relation == .dislikes && other.relation == .likes) {
            return MemoryText.valuesCompatible(valueKey, other.valueKey)
        }

        return false
    }

    func matchesForgetTarget(_ other: MemoryFactSignature) -> Bool {
        if relation == other.relation {
            return valueKey.isEmpty || MemoryText.valuesCompatible(valueKey, other.valueKey)
        }

        if relation == .likes, other.relation == .dislikes {
            return false
        }

        if relation == .dislikes, other.relation == .likes {
            return false
        }

        if conflictKey == other.conflictKey {
            return valueKey.isEmpty || MemoryText.valuesCompatible(valueKey, other.valueKey)
        }

        return false
    }
}

private nonisolated enum MemoryScoring {
    static let exactScanLimit = 256
    static let sparseCandidateLimit = 120
    static let semanticCandidateLimit = 160
    static let fallbackRecentCandidateLimit = 32
    static let bm25K1 = 1.2
    static let bm25B = 0.72
    static let bm25Saturation = 4.0
    static let semanticWeight = 0.62
    static let sparseWeight = 0.28
    static let coverageWeight = 0.10
}

private nonisolated enum MemoryText {
    private static let stopWords: Set<String> = [
        "a", "about", "all", "also", "am", "an", "and", "are", "as", "at", "be", "because", "but",
        "by", "can", "do", "does", "for", "from", "had", "has", "have", "i", "if", "in", "into",
        "is", "it", "its", "me", "my", "of", "on", "or", "our", "so", "that", "the", "their",
        "them", "they", "this", "to", "user", "users", "was", "we", "were", "with", "would", "you",
        "your"
    ]

    static func compact(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
    }

    static func searchable(_ text: String) -> String {
        compact(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    static func tokens(_ text: String) -> [String] {
        searchable(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .compactMap { token in
                let normalized = stem(token)
                guard normalized.count >= 2, !stopWords.contains(normalized) else { return nil }
                return normalized
            }
    }

    static func termFrequencies(_ tokens: [String]) -> [String: Int] {
        tokens.reduce(into: [:]) { counts, token in
            counts[token, default: 0] += 1
        }
    }

    static func valueKey(_ value: String) -> String {
        let tokens = tokens(value)
        if tokens.isEmpty {
            return searchable(value)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        }
        return tokens.joined(separator: " ")
    }

    static func valuesCompatible(_ left: String, _ right: String) -> Bool {
        if left == right { return true }
        guard !left.isEmpty, !right.isEmpty else { return false }

        if left.contains(right), right.count >= 4 { return true }
        if right.contains(left), left.count >= 4 { return true }

        let leftTokens = Set(left.split(separator: " ").map(String.init))
        let rightTokens = Set(right.split(separator: " ").map(String.init))
        guard !leftTokens.isEmpty, !rightTokens.isEmpty else { return false }

        let overlap = leftTokens.intersection(rightTokens).count
        let denominator = max(leftTokens.count, rightTokens.count)
        return Double(overlap) / Double(denominator) >= 0.8
    }

    private static func stem(_ token: String) -> String {
        guard token.count > 4 else { return token }
        if token.hasSuffix("ies") {
            return String(token.dropLast(3)) + "y"
        }
        if token.hasSuffix("ing") {
            return String(token.dropLast(3))
        }
        if token.hasSuffix("ed") {
            return String(token.dropLast(2))
        }
        if token.hasSuffix("es") {
            return String(token.dropLast(2))
        }
        if token.hasSuffix("s"), !token.hasSuffix("ss") {
            return String(token.dropLast())
        }
        return token
    }
}

private nonisolated enum MemoryVectorMath {
    static func normalized(_ vector: [Double]?) -> [Double]? {
        guard let vector, !vector.isEmpty else { return nil }
        var squaredMagnitude = 0.0
        vector.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else { return }
            vDSP_svesqD(baseAddress, 1, &squaredMagnitude, vDSP_Length(vector.count))
        }
        guard squaredMagnitude > 0 else { return nil }

        var scale = 1.0 / sqrt(squaredMagnitude)
        var normalized = [Double](repeating: 0, count: vector.count)
        vector.withUnsafeBufferPointer { source in
            normalized.withUnsafeMutableBufferPointer { destination in
                guard let sourceAddress = source.baseAddress, let destinationAddress = destination.baseAddress else { return }
                vDSP_vsmulD(sourceAddress, 1, &scale, destinationAddress, 1, vDSP_Length(vector.count))
            }
        }
        return normalized
    }

    static func cosine(normalizedQuery: [Double]?, normalizedMemory: [Double]?) -> Double {
        guard let normalizedQuery,
              let normalizedMemory,
              normalizedQuery.count == normalizedMemory.count else {
            return 0
        }

        var dotProduct = 0.0
        normalizedQuery.withUnsafeBufferPointer { queryBuffer in
            normalizedMemory.withUnsafeBufferPointer { memoryBuffer in
                guard let queryAddress = queryBuffer.baseAddress, let memoryAddress = memoryBuffer.baseAddress else { return }
                vDSP_dotprD(queryAddress, 1, memoryAddress, 1, &dotProduct, vDSP_Length(normalizedQuery.count))
            }
        }
        return max(0, min(1, dotProduct))
    }
}

private nonisolated enum MemoryVectorSketch {
    static func keys(for normalizedVector: [Double]?) -> [String] {
        guard let normalizedVector, !normalizedVector.isEmpty else { return [] }

        let rankedDimensions = normalizedVector.enumerated()
            .map { (index: $0.offset, magnitude: abs($0.element), sign: $0.element >= 0 ? "p" : "n") }
            .sorted { $0.magnitude > $1.magnitude }
            .prefix(8)

        var keys: [String] = rankedDimensions.map { "d\($0.index)\($0.sign)" }
        let topDimensions = Array(rankedDimensions.prefix(4))

        for leftIndex in topDimensions.indices {
            for rightIndex in topDimensions.indices where rightIndex > leftIndex {
                let left = topDimensions[leftIndex]
                let right = topDimensions[rightIndex]
                keys.append("p\(left.index)\(left.sign):\(right.index)\(right.sign)")
            }
        }

        return keys
    }
}

private nonisolated enum MemoryFactParser {
    static func signature(for content: String) -> MemoryFactSignature? {
        let text = trimmedSentence(content)
        guard !text.isEmpty else { return nil }

        if let value = value(after: [
            "the user's name is ", "the user’s name is ", "the user is named ", "the user goes by ",
            "my name is ", "my name's ", "my name’s ", "i am called ", "i'm called ", "i’m called "
        ], in: text) {
            return signature(.name, value)
        }

        if let value = value(after: [
            "the user's pronouns are ", "the user’s pronouns are ", "the user uses pronouns ",
            "my pronouns are ", "i use pronouns "
        ], in: text) {
            return signature(.pronouns, value)
        }

        if let value = value(after: [
            "the user no longer lives in ", "the user does not live in ", "the user doesn't live in ",
            "the user doesn’t live in ", "i no longer live in ", "i do not live in ", "i don't live in ",
            "i don’t live in "
        ], in: text, isRetraction: true, relation: .residence) {
            return value
        }

        if let value = value(after: [
            "the user lives in ", "the user lives at ", "the user resides in ", "the user is based in ",
            "the user is located in ", "the user's home is in ", "the user’s home is in ",
            "i live in ", "i live at ", "i reside in ", "i am based in ", "i'm based in ", "i’m based in "
        ], in: text) {
            return signature(.residence, value)
        }

        if let value = value(after: [
            "the user's timezone is ", "the user’s timezone is ", "the user is in timezone ",
            "my timezone is ", "i am in timezone ", "i'm in timezone ", "i’m in timezone "
        ], in: text) {
            return signature(.timezone, value)
        }

        if let value = value(after: [
            "the user works at ", "the user works for ", "the user is employed by ",
            "the user's employer is ", "the user’s employer is ", "i work at ", "i work for ",
            "my employer is "
        ], in: text) {
            return signature(.employer, value)
        }

        if let value = value(after: [
            "the user works as ", "the user is a ", "the user is an ", "the user's role is ",
            "the user’s role is ", "the user's job is ", "the user’s job is ", "i work as ",
            "i am a ", "i am an ", "i'm a ", "i'm an ", "i’m a ", "i’m an ", "my job is ",
            "my role is "
        ], in: text), looksLikeOccupation(value) {
            return signature(.occupation, value)
        }

        if let value = value(after: [
            "the user studies ", "the user is studying ", "the user is learning ", "i study ",
            "i am studying ", "i'm studying ", "i’m studying ", "i am learning ", "i'm learning ",
            "i’m learning "
        ], in: text) {
            return signature(.education, value)
        }

        if let value = value(after: [
            "the user speaks ", "the user's preferred language is ", "the user’s preferred language is ",
            "the user prefers responses in ", "i speak ", "my preferred language is ",
            "i prefer responses in "
        ], in: text) {
            return signature(.language, value)
        }

        if let value = value(after: [
            "the user no longer likes ", "the user no longer loves ", "i no longer like ", "i no longer love "
        ], in: text, isRetraction: true, relation: .likes) {
            return value
        }

        if let value = value(after: [
            "the user dislikes ", "the user hates ", "the user does not like ", "the user doesn't like ",
            "the user doesn’t like ", "i dislike ", "i hate ", "i do not like ", "i don't like ",
            "i don’t like "
        ], in: text) {
            return signature(.dislikes, value)
        }

        if let value = value(after: [
            "the user likes ", "the user loves ", "the user enjoys ", "the user prefers ",
            "the user is a fan of ", "the user is an fan of ", "i like ", "i love ", "i enjoy ",
            "i prefer ", "i am a fan of ", "i'm a fan of ", "i’m a fan of "
        ], in: text) {
            return signature(.likes, value)
        }

        if let value = value(after: [
            "the user wants to ", "the user wants to learn ", "the user plans to ", "the user's goal is ",
            "the user’s goal is ", "i want to ", "i want to learn ", "i plan to ", "my goal is "
        ], in: text) {
            return signature(.goal, value)
        }

        if let value = value(after: [
            "the user is working on ", "the user's project is ", "the user’s project is ",
            "i am working on ", "i'm working on ", "i’m working on ", "my project is "
        ], in: text) {
            return signature(.project, value)
        }

        if let value = value(after: [
            "the user is allergic to ", "the user's allergy is ", "the user’s allergy is ",
            "i am allergic to ", "i'm allergic to ", "i’m allergic to ", "my allergy is "
        ], in: text) {
            return signature(.allergy, value)
        }

        if let value = value(after: [
            "the user is vegan", "the user is vegetarian", "the user keeps kosher", "the user eats halal",
            "i am vegan", "i'm vegan", "i’m vegan", "i am vegetarian", "i'm vegetarian", "i’m vegetarian",
            "i keep kosher", "i eat halal"
        ], in: text, allowEmptyValue: true) {
            return signature(.diet, value.isEmpty ? text : value)
        }

        if let value = value(after: [
            "the user needs ", "the user requires ", "the user cannot ", "the user can't ",
            "the user can’t ", "i need ", "i require ", "i cannot ", "i can't ", "i can’t "
        ], in: text) {
            return signature(.constraint, value)
        }

        if text.lowercased().hasPrefix("the user is ") || text.lowercased().hasPrefix("the user's ") || text.lowercased().hasPrefix("the user’s ") {
            return signature(.identity, text)
        }

        return nil
    }

    static func forgetSignature(for query: String) -> MemoryFactSignature? {
        let text = trimmedSentence(query)
        let lowercased = text.lowercased()

        if lowercased.contains("where i live")
            || lowercased.contains("where i'm based")
            || lowercased.contains("where i’m based")
            || lowercased.contains("my address")
            || lowercased.contains("my home")
            || lowercased == "location" {
            return MemoryFactSignature(relation: .residence, valueKey: "", isRetraction: true)
        }

        if lowercased.contains("my name") || lowercased == "name" {
            return MemoryFactSignature(relation: .name, valueKey: "", isRetraction: true)
        }

        if lowercased.contains("my pronouns") || lowercased == "pronouns" {
            return MemoryFactSignature(relation: .pronouns, valueKey: "", isRetraction: true)
        }

        if let direct = signature(for: text) {
            return MemoryFactSignature(relation: direct.relation, valueKey: direct.valueKey, isRetraction: true)
        }

        let rewritten = MemoryFactParser.rewriteFirstPerson(text)
        if rewritten != text, let rewrittenSignature = signature(for: rewritten) {
            return MemoryFactSignature(relation: rewrittenSignature.relation, valueKey: rewrittenSignature.valueKey, isRetraction: true)
        }

        return nil
    }

    static func rewriteFirstPerson(_ content: String) -> String {
        let replacements: [(String, String)] = [
            (#"^\s*my\s+name\s+is\s+(.+)$"#, "The user's name is $1"),
            (#"^\s*my\s+pronouns\s+are\s+(.+)$"#, "The user's pronouns are $1"),
            (#"^\s*i\s+live\s+in\s+(.+)$"#, "The user lives in $1"),
            (#"^\s*i\s+live\s+at\s+(.+)$"#, "The user lives at $1"),
            (#"^\s*i(?:'|’)?m\s+based\s+in\s+(.+)$"#, "The user is based in $1"),
            (#"^\s*i\s+am\s+based\s+in\s+(.+)$"#, "The user is based in $1"),
            (#"^\s*i\s+work\s+at\s+(.+)$"#, "The user works at $1"),
            (#"^\s*i\s+work\s+for\s+(.+)$"#, "The user works for $1"),
            (#"^\s*i\s+work\s+as\s+(.+)$"#, "The user works as $1"),
            (#"^\s*i(?:'|’)?m\s+an?\s+(.+)$"#, "The user is a $1"),
            (#"^\s*i\s+am\s+an?\s+(.+)$"#, "The user is a $1"),
            (#"^\s*i\s+like\s+(.+)$"#, "The user likes $1"),
            (#"^\s*i\s+love\s+(.+)$"#, "The user likes $1"),
            (#"^\s*i\s+enjoy\s+(.+)$"#, "The user likes $1"),
            (#"^\s*i\s+prefer\s+(.+)$"#, "The user prefers $1"),
            (#"^\s*i\s+do\s+not\s+like\s+(.+)$"#, "The user dislikes $1"),
            (#"^\s*i\s+don(?:'|’)?t\s+like\s+(.+)$"#, "The user dislikes $1"),
            (#"^\s*i\s+dislike\s+(.+)$"#, "The user dislikes $1"),
            (#"^\s*i\s+hate\s+(.+)$"#, "The user dislikes $1"),
            (#"^\s*i\s+want\s+to\s+(.+)$"#, "The user wants to $1"),
            (#"^\s*i\s+plan\s+to\s+(.+)$"#, "The user plans to $1"),
            (#"^\s*i(?:'|’)?m\s+working\s+on\s+(.+)$"#, "The user is working on $1"),
            (#"^\s*i\s+am\s+working\s+on\s+(.+)$"#, "The user is working on $1"),
            (#"^\s*i\s+am\s+allergic\s+to\s+(.+)$"#, "The user is allergic to $1"),
            (#"^\s*i(?:'|’)?m\s+allergic\s+to\s+(.+)$"#, "The user is allergic to $1"),
            (#"^\s*my\s+favorite\s+(.+?)\s+is\s+(.+)$"#, "The user's favorite $1 is $2"),
            (#"^\s*my\s+(.+?)\s+is\s+(.+)$"#, "The user's $1 is $2")
        ]

        for (pattern, template) in replacements {
            if let rewritten = replacingFirstMatch(in: content, pattern: pattern, template: template) {
                return rewritten
            }
        }

        return content
    }

    private static func signature(_ relation: MemoryRelation, _ value: String, isRetraction: Bool = false) -> MemoryFactSignature {
        MemoryFactSignature(relation: relation, valueKey: MemoryText.valueKey(value), isRetraction: isRetraction)
    }

    private static func value(
        after prefixes: [String],
        in text: String,
        isRetraction: Bool = false,
        relation: MemoryRelation? = nil,
        allowEmptyValue: Bool = false
    ) -> MemoryFactSignature? {
        let lowercased = text.lowercased()
        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            let value = trimValue(String(text.dropFirst(prefix.count)))
            guard allowEmptyValue || !value.isEmpty else { return nil }
            guard let relation else { return nil }
            return signature(relation, value, isRetraction: isRetraction)
        }
        return nil
    }

    private static func value(after prefixes: [String], in text: String, allowEmptyValue: Bool = false) -> String? {
        let lowercased = text.lowercased()
        for prefix in prefixes where lowercased.hasPrefix(prefix) {
            let value = trimValue(String(text.dropFirst(prefix.count)))
            if allowEmptyValue || !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func trimValue(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.,;:()[]{}")))
    }

    private static func trimmedSentence(_ content: String) -> String {
        MemoryText.compact(content)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
    }

    private static func looksLikeOccupation(_ value: String) -> Bool {
        let tokens = Set(MemoryText.tokens(value))
        let occupationTerms: Set<String> = [
            "accountant", "artist", "consultant", "designer", "developer", "doctor", "engineer", "founder",
            "lawyer", "manager", "nurse", "professor", "researcher", "scientist", "student", "teacher",
            "writer"
        ]
        return !tokens.intersection(occupationTerms).isEmpty
    }

    private static func replacingFirstMatch(in text: String, pattern: String, template: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard regex.firstMatch(in: text, range: range) != nil else { return nil }
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

private nonisolated struct IndexedMemoryRecord {
    let memoryIndex: Int
    let memory: UserMemory
    let normalizedContent: String
    let tokens: [String]
    let termFrequency: [String: Int]
    let normalizedVector: [Double]?
    let vectorBucketKeys: [String]
    let signature: MemoryFactSignature?
}

private nonisolated struct MemoryVaultIndex {
    let fingerprint: String
    let records: [IndexedMemoryRecord]
    let activeRecordIndexes: [Int]
    let nonArchivedRecordIndexes: [Int]
    let invertedIndex: [String: Set<Int>]
    let documentFrequency: [String: Int]
    let semanticBuckets: [String: Set<Int>]
    let factBuckets: [String: Set<Int>]
    let relationBuckets: [MemoryRelation: Set<Int>]
    let averageDocumentLength: Double

    init(memories: [UserMemory]) {
        fingerprint = Self.fingerprint(for: memories)

        var builtRecords: [IndexedMemoryRecord] = []
        builtRecords.reserveCapacity(memories.count)

        for (memoryIndex, memory) in memories.enumerated() {
            let normalizedContent = MemoryText.compact(memory.content)
            let tokens = MemoryText.tokens(normalizedContent)
            let normalizedVector = MemoryVectorMath.normalized(memory.vector)
            builtRecords.append(
                IndexedMemoryRecord(
                    memoryIndex: memoryIndex,
                    memory: memory,
                    normalizedContent: normalizedContent,
                    tokens: tokens,
                    termFrequency: MemoryText.termFrequencies(tokens),
                    normalizedVector: normalizedVector,
                    vectorBucketKeys: MemoryVectorSketch.keys(for: normalizedVector),
                    signature: MemoryFactParser.signature(for: normalizedContent)
                )
            )
        }

        records = builtRecords
        activeRecordIndexes = builtRecords.indices.filter { builtRecords[$0].memory.status == .active }
        nonArchivedRecordIndexes = builtRecords.indices.filter { builtRecords[$0].memory.status != .archived }

        var invertedIndex: [String: Set<Int>] = [:]
        var documentFrequency: [String: Int] = [:]
        var semanticBuckets: [String: Set<Int>] = [:]
        var factBuckets: [String: Set<Int>] = [:]
        var relationBuckets: [MemoryRelation: Set<Int>] = [:]
        var totalDocumentLength = 0

        for recordIndex in nonArchivedRecordIndexes {
            let record = builtRecords[recordIndex]
            totalDocumentLength += max(record.tokens.count, 1)

            for token in Set(record.tokens) {
                invertedIndex[token, default: []].insert(recordIndex)
                documentFrequency[token, default: 0] += 1
            }

            for key in record.vectorBucketKeys {
                semanticBuckets[key, default: []].insert(recordIndex)
            }

            if let signature = record.signature {
                factBuckets[signature.conflictKey, default: []].insert(recordIndex)
                relationBuckets[signature.relation, default: []].insert(recordIndex)
            }
        }

        self.invertedIndex = invertedIndex
        self.documentFrequency = documentFrequency
        self.semanticBuckets = semanticBuckets
        self.factBuckets = factBuckets
        self.relationBuckets = relationBuckets
        averageDocumentLength = nonArchivedRecordIndexes.isEmpty
            ? 1
            : Double(totalDocumentLength) / Double(nonArchivedRecordIndexes.count)
    }

    func sparseCandidateIndexes(for queryTokens: [String], limit: Int) -> [Int] {
        let candidates = Set(queryTokens.flatMap { invertedIndex[$0] ?? [] })
        return candidates
            .map { (index: $0, score: bm25Score(queryTokens: queryTokens, recordIndex: $0)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.index)
    }

    func semanticCandidateIndexes(for normalizedQueryVector: [Double]?, limit: Int) -> [Int] {
        let bucketKeys = MemoryVectorSketch.keys(for: normalizedQueryVector)
        guard !bucketKeys.isEmpty else { return [] }

        let candidates = Set(bucketKeys.flatMap { semanticBuckets[$0] ?? [] })
        return candidates
            .map {
                (
                    index: $0,
                    score: MemoryVectorMath.cosine(
                        normalizedQuery: normalizedQueryVector,
                        normalizedMemory: records[$0].normalizedVector
                    )
                )
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map(\.index)
    }

    func factCandidateIndexes(for signature: MemoryFactSignature) -> Set<Int> {
        if signature.valueKey.isEmpty {
            return relationBuckets[signature.relation] ?? []
        }
        return factBuckets[signature.conflictKey] ?? relationBuckets[signature.relation] ?? []
    }

    func recentActiveRecordIndexes(limit: Int) -> [Int] {
        activeRecordIndexes
            .sorted { records[$0].memory.updatedAt > records[$1].memory.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    func bm25Score(queryTokens: [String], recordIndex: Int) -> Double {
        guard records.indices.contains(recordIndex), !queryTokens.isEmpty, !nonArchivedRecordIndexes.isEmpty else {
            return 0
        }

        let record = records[recordIndex]
        let queryFrequencies = MemoryText.termFrequencies(queryTokens)
        let documentCount = Double(nonArchivedRecordIndexes.count)
        let documentLength = Double(max(record.tokens.count, 1))
        var score = 0.0

        for (term, queryFrequency) in queryFrequencies {
            guard let termFrequency = record.termFrequency[term],
                  let frequency = documentFrequency[term],
                  frequency > 0 else {
                continue
            }

            let idf = log(1 + ((documentCount - Double(frequency) + 0.5) / (Double(frequency) + 0.5)))
            let tf = Double(termFrequency)
            let denominator = tf + MemoryScoring.bm25K1 * (1 - MemoryScoring.bm25B + MemoryScoring.bm25B * documentLength / averageDocumentLength)
            let queryBoost = min(1 + log(Double(queryFrequency)), 2)
            score += idf * ((tf * (MemoryScoring.bm25K1 + 1)) / denominator) * queryBoost
        }

        return score
    }

    static func fingerprint(for memories: [UserMemory]) -> String {
        memories
            .map { "\($0.id.uuidString):\($0.status.rawValue):\($0.updatedAt.timeIntervalSince1970):\($0.vector?.count ?? 0)" }
            .joined(separator: "|")
    }
}

nonisolated final class MemoryService {
    private let fileManager = FileManager.default
    private let memoriesDirectory: URL
    private let memoriesURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedIndex: MemoryVaultIndex?

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        memoriesDirectory = appSupport.appendingPathComponent(Constants.Storage.memoriesDirectory, isDirectory: true)
        memoriesURL = memoriesDirectory.appendingPathComponent(Constants.Storage.memoriesFilename)
        try? fileManager.createDirectory(at: memoriesDirectory, withIntermediateDirectories: true)
    }

    func listAll() -> [UserMemory] {
        guard let data = try? Data(contentsOf: memoriesURL),
              let memories = try? decoder.decode([UserMemory].self, from: data) else {
            return []
        }
        return memories.sorted { $0.updatedAt > $1.updatedAt }
    }

    func upsert(
        content: String,
        status: UserMemoryStatus,
        captureType: UserMemoryCaptureType,
        personaId: String? = nil,
        category: String? = nil,
        sourceConversationId: UUID? = nil,
        sourceMessageId: UUID? = nil
    ) -> UserMemory? {
        let normalizedContent = normalizedStoredMemoryContent(content)
        guard !normalizedContent.isEmpty else { return nil }
        guard captureType != .inferred || !isLowValueInferredMemory(normalizedContent) else { return nil }

        var memories = listAll()
        let index = searchIndex(for: memories)
        let signature = MemoryFactParser.signature(for: normalizedContent)

        if let signature, signature.isRetraction {
            let archived = archiveContradictingMemories(
                matching: signature,
                in: &memories,
                personaId: personaId,
                now: Date()
            )
            if archived > 0 {
                persist(memories)
            }
            return nil
        }

        if let duplicateIndex = duplicateIndex(for: normalizedContent, signature: signature, in: memories, index: index) {
            var duplicate = memories[duplicateIndex]
            if duplicate.status == .archived || (duplicate.status == .pending && status == .active) {
                duplicate.status = status
            }
            duplicate.content = normalizedContent
            duplicate.personaId = duplicate.personaId ?? personaId
            duplicate.category = duplicate.category ?? category
            duplicate.updatedAt = Date()
            duplicate.vector = duplicate.vector ?? embedding(for: normalizedContent)
            memories[duplicateIndex] = duplicate
            persist(memories)
            return duplicate
        }

        if let signature {
            _ = archiveContradictingMemories(
                matching: signature,
                in: &memories,
                personaId: personaId,
                now: Date()
            )
        }

        let memory = UserMemory(
            content: normalizedContent,
            status: status,
            captureType: captureType,
            personaId: personaId,
            category: category,
            sourceConversationId: sourceConversationId,
            sourceMessageId: sourceMessageId,
            vector: embedding(for: normalizedContent)
        )
        memories.insert(memory, at: 0)
        persist(memories)
        return memory
    }

    func update(_ memory: UserMemory) -> UserMemory {
        var updated = memory
        updated.content = normalizedStoredMemoryContent(memory.content)
        updated.updatedAt = Date()
        updated.vector = embedding(for: updated.content)
        replace(updated)
        return updated
    }

    func setStatus(id: UUID, status: UserMemoryStatus) -> UserMemory? {
        var memories = listAll()
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return nil }
        memories[index].status = status
        memories[index].updatedAt = Date()
        let updated = memories[index]
        persist(memories)
        return updated
    }

    func delete(id: UUID) {
        var memories = listAll()
        memories.removeAll { $0.id == id }
        persist(memories)
    }

    func clearAll() {
        persist([])
    }

    func archiveMatching(_ query: String) -> Int {
        let normalizedQuery = normalizedMemoryContent(query)
        guard !normalizedQuery.isEmpty else { return 0 }

        var memories = listAll()
        let index = searchIndex(for: memories)
        let queryTokens = MemoryText.tokens(normalizedQuery)
        let queryVector = MemoryVectorMath.normalized(embedding(for: normalizedQuery))
        let forgetSignature = MemoryFactParser.forgetSignature(for: normalizedQuery)
        let candidateIndexes = archiveCandidateIndexes(
            queryTokens: queryTokens,
            queryVector: queryVector,
            forgetSignature: forgetSignature,
            index: index
        )
        var archivedCount = 0

        for recordIndex in candidateIndexes {
            let record = index.records[recordIndex]
            guard record.memory.status != .archived else { continue }

            if shouldArchive(
                record: record,
                recordIndex: recordIndex,
                query: normalizedQuery,
                queryTokens: queryTokens,
                queryVector: queryVector,
                forgetSignature: forgetSignature,
                index: index
            ) {
                memories[record.memoryIndex].status = .archived
                memories[record.memoryIndex].updatedAt = Date()
                archivedCount += 1
            }
        }

        if archivedCount > 0 {
            persist(memories)
        }

        return archivedCount
    }

    func retrieveActiveMemories(
        for query: String,
        personaId: String?,
        limit: Int,
        maxCharacters: Int
    ) -> [UserMemory] {
        let normalizedQuery = normalizedMemoryContent(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let memories = listAll()
        let index = searchIndex(for: memories)
        let queryTokens = MemoryText.tokens(normalizedQuery)
        let queryVector = MemoryVectorMath.normalized(embedding(for: normalizedQuery))
        let querySignature = MemoryFactParser.forgetSignature(for: normalizedQuery)
        let candidateIndexes = retrievalCandidateIndexes(
            queryTokens: queryTokens,
            queryVector: queryVector,
            querySignature: querySignature,
            index: index
        )
        var usedCharacters = 0

        let ranked = candidateIndexes
            .compactMap { recordIndex in
                retrievalCandidate(
                    query: normalizedQuery,
                    queryTokens: queryTokens,
                    queryVector: queryVector,
                    record: index.records[recordIndex],
                    recordIndex: recordIndex,
                    index: index,
                    personaId: personaId
                )
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.memory.updatedAt > $1.memory.updatedAt
                }
                return $0.score > $1.score
            }

        var selected: [UserMemory] = []
        for candidate in ranked {
            guard selected.count < limit else { break }
            let addedCharacters = candidate.memory.content.count + 4
            guard usedCharacters + addedCharacters <= maxCharacters || selected.isEmpty else { break }
            selected.append(candidate.memory)
            usedCharacters += addedCharacters
        }

        return selected
    }

    func markUsed(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        var memories = listAll()
        var changed = false

        for index in memories.indices where idSet.contains(memories[index].id) {
            memories[index].usageCount += 1
            memories[index].lastUsedAt = Date()
            changed = true
        }

        if changed {
            persist(memories)
        }
    }

    func pendingCount() -> Int {
        listAll().filter { $0.status == .pending }.count
    }

    func extractionCandidates(from rawOutput: String, sourceText: String? = nil) -> [String] {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isNoMemoryMarker(trimmed) else { return [] }

        for payload in jsonPayloads(in: trimmed) {
            if let candidates = extractionCandidatesFromJSON(payload) {
                return sanitizedCandidates(candidates, sourceText: sourceText)
            }
        }

        return sanitizedCandidates(fallbackExtractionCandidates(from: trimmed), sourceText: sourceText)
    }

    private func replace(_ memory: UserMemory) {
        var memories = listAll()
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        } else {
            memories.insert(memory, at: 0)
        }
        persist(memories)
    }

    private func persist(_ memories: [UserMemory]) {
        guard let data = try? encoder.encode(memories.sorted(by: { $0.updatedAt > $1.updatedAt })) else { return }
        try? data.write(to: memoriesURL, options: .atomic)
        cachedIndex = nil
    }

    private func searchIndex(for memories: [UserMemory]) -> MemoryVaultIndex {
        let fingerprint = MemoryVaultIndex.fingerprint(for: memories)
        if let cachedIndex, cachedIndex.fingerprint == fingerprint {
            return cachedIndex
        }
        let index = MemoryVaultIndex(memories: memories)
        cachedIndex = index
        return index
    }

    private func duplicateIndex(
        for content: String,
        signature: MemoryFactSignature?,
        in memories: [UserMemory],
        index: MemoryVaultIndex
    ) -> Int? {
        let queryTokens = MemoryText.tokens(content)
        let queryVector = MemoryVectorMath.normalized(embedding(for: content))
        var candidateIndexes: Set<Int>

        if index.nonArchivedRecordIndexes.count <= MemoryScoring.exactScanLimit {
            candidateIndexes = Set(index.nonArchivedRecordIndexes)
        } else if let signature {
            candidateIndexes = index.factCandidateIndexes(for: signature)
            candidateIndexes.formUnion(index.sparseCandidateIndexes(for: queryTokens, limit: MemoryScoring.sparseCandidateLimit))
            candidateIndexes.formUnion(
                index.semanticCandidateIndexes(for: queryVector, limit: MemoryScoring.semanticCandidateLimit)
            )
        } else {
            candidateIndexes = Set(index.sparseCandidateIndexes(for: queryTokens, limit: MemoryScoring.sparseCandidateLimit))
            candidateIndexes.formUnion(
                index.semanticCandidateIndexes(for: queryVector, limit: MemoryScoring.semanticCandidateLimit)
            )
        }

        for recordIndex in candidateIndexes {
            let record = index.records[recordIndex]
            guard memories.indices.contains(record.memoryIndex), memories[record.memoryIndex].status != .archived else { continue }

            if record.normalizedContent == content {
                return record.memoryIndex
            }

            if let signature, let existingSignature = record.signature {
                if signature.isDuplicate(of: existingSignature) {
                    return record.memoryIndex
                }
                if signature.conflicts(with: existingSignature) {
                    continue
                }
            }

            let containmentMatch = record.normalizedContent.contains(content) || content.contains(record.normalizedContent)
            let sparseScore = normalizedBM25Score(index.bm25Score(queryTokens: queryTokens, recordIndex: recordIndex))
            let semanticScore = MemoryVectorMath.cosine(normalizedQuery: queryVector, normalizedMemory: record.normalizedVector)
            let coverageScore = termCoverageScore(queryTokens: queryTokens, documentTokens: record.tokens)
            let hybridScore = max((semanticScore * 0.7) + (sparseScore * 0.3), coverageScore)

            if containmentMatch, coverageScore >= 0.72 {
                return record.memoryIndex
            }

            if hybridScore >= Constants.Memory.duplicateScoreThreshold {
                return record.memoryIndex
            }
        }

        return nil
    }

    private func archiveContradictingMemories(
        matching signature: MemoryFactSignature,
        in memories: inout [UserMemory],
        personaId: String?,
        now: Date
    ) -> Int {
        let index = searchIndex(for: memories)
        let candidateIndexes: Set<Int>
        if signature.isRetraction {
            candidateIndexes = index.factCandidateIndexes(for: signature)
        } else if signature.relation.isSingleValued {
            candidateIndexes = index.relationBuckets[signature.relation] ?? []
        } else {
            candidateIndexes = index.factCandidateIndexes(for: signature)
        }
        var archivedCount = 0

        for recordIndex in candidateIndexes {
            let record = index.records[recordIndex]
            guard memories.indices.contains(record.memoryIndex),
                  memories[record.memoryIndex].status != .archived,
                  memoryScopesCanConflict(existing: memories[record.memoryIndex].personaId, incoming: personaId),
                  let existingSignature = record.signature else {
                continue
            }

            let shouldArchive = signature.isRetraction
                ? signature.matchesForgetTarget(existingSignature)
                : signature.conflicts(with: existingSignature)

            if shouldArchive {
                memories[record.memoryIndex].status = .archived
                memories[record.memoryIndex].updatedAt = now
                archivedCount += 1
            }
        }

        return archivedCount
    }

    private func archiveCandidateIndexes(
        queryTokens: [String],
        queryVector: [Double]?,
        forgetSignature: MemoryFactSignature?,
        index: MemoryVaultIndex
    ) -> Set<Int> {
        if index.nonArchivedRecordIndexes.count <= MemoryScoring.exactScanLimit {
            return Set(index.nonArchivedRecordIndexes)
        }

        var candidateIndexes = Set<Int>()
        if let forgetSignature {
            candidateIndexes.formUnion(index.factCandidateIndexes(for: forgetSignature))
        }
        candidateIndexes.formUnion(index.sparseCandidateIndexes(for: queryTokens, limit: MemoryScoring.sparseCandidateLimit))
        candidateIndexes.formUnion(index.semanticCandidateIndexes(for: queryVector, limit: MemoryScoring.semanticCandidateLimit))
        return candidateIndexes
    }

    private func shouldArchive(
        record: IndexedMemoryRecord,
        recordIndex: Int,
        query: String,
        queryTokens: [String],
        queryVector: [Double]?,
        forgetSignature: MemoryFactSignature?,
        index: MemoryVaultIndex
    ) -> Bool {
        if let forgetSignature, let memorySignature = record.signature, forgetSignature.matchesForgetTarget(memorySignature) {
            return true
        }

        let memoryContent = normalizedMemoryContent(record.normalizedContent)
        if memoryContent.contains(query) || query.contains(memoryContent) {
            return true
        }

        let score = relevanceScore(
            query: query,
            queryTokens: queryTokens,
            queryVector: queryVector,
            record: record,
            recordIndex: recordIndex,
            index: index,
            personaId: nil
        )
        return score >= Constants.Memory.forgetMatchThreshold
    }

    private func retrievalCandidateIndexes(
        queryTokens: [String],
        queryVector: [Double]?,
        querySignature: MemoryFactSignature?,
        index: MemoryVaultIndex
    ) -> Set<Int> {
        if index.activeRecordIndexes.count <= MemoryScoring.exactScanLimit {
            return Set(index.activeRecordIndexes)
        }

        var candidateIndexes = Set<Int>()
        candidateIndexes.formUnion(index.sparseCandidateIndexes(for: queryTokens, limit: MemoryScoring.sparseCandidateLimit))
        candidateIndexes.formUnion(index.semanticCandidateIndexes(for: queryVector, limit: MemoryScoring.semanticCandidateLimit))

        if let querySignature {
            candidateIndexes.formUnion(index.factCandidateIndexes(for: querySignature))
        }

        candidateIndexes.formUnion(index.recentActiveRecordIndexes(limit: MemoryScoring.fallbackRecentCandidateLimit))
        return candidateIndexes.filter { index.records[$0].memory.status == .active }
    }

    private func retrievalCandidate(
        query: String,
        queryTokens: [String],
        queryVector: [Double]?,
        record: IndexedMemoryRecord,
        recordIndex: Int,
        index: MemoryVaultIndex,
        personaId: String?
    ) -> MemoryRetrievalCandidate? {
        guard record.memory.status == .active else { return nil }

        let baseScore = relevanceScore(
            query: query,
            queryTokens: queryTokens,
            queryVector: queryVector,
            record: record,
            recordIndex: recordIndex,
            index: index,
            personaId: personaId
        )
        let topicalScore = topicalAffinityScore(query: query, memoryContent: record.normalizedContent)
        let identityScore = identityAffinityScore(query: query, memoryContent: record.normalizedContent)
        let eligibilityScore = max(baseScore, topicalScore, identityScore)

        guard eligibilityScore >= Constants.Memory.minimumBaseRetrievalScore else { return nil }

        var score = eligibilityScore
        if let memoryPersonaId = record.memory.personaId, let personaId, memoryPersonaId == personaId {
            score += Constants.Memory.personaMatchBoost
        } else if record.memory.personaId == nil {
            score += Constants.Memory.globalMemoryBoost
        }

        return MemoryRetrievalCandidate(memory: record.memory, score: min(score, 1.0))
    }

    private func relevanceScore(
        query: String,
        queryTokens: [String],
        queryVector: [Double]?,
        record: IndexedMemoryRecord,
        recordIndex: Int,
        index: MemoryVaultIndex,
        personaId: String?
    ) -> Double {
        let sparseScore = normalizedBM25Score(index.bm25Score(queryTokens: queryTokens, recordIndex: recordIndex))
        let semanticScore = MemoryVectorMath.cosine(normalizedQuery: queryVector, normalizedMemory: record.normalizedVector)
        let coverageScore = termCoverageScore(queryTokens: queryTokens, documentTokens: record.tokens)
        var score = semanticScore > 0
            ? (semanticScore * MemoryScoring.semanticWeight)
                + (sparseScore * MemoryScoring.sparseWeight)
                + (coverageScore * MemoryScoring.coverageWeight)
            : max(sparseScore, coverageScore)

        if query.contains(record.normalizedContent) || record.normalizedContent.contains(query) {
            score += Constants.Memory.substringMatchBoost
        }

        if let memoryPersonaId = record.memory.personaId, let personaId, memoryPersonaId == personaId {
            score += Constants.Memory.personaMatchBoost
        } else if record.memory.personaId == nil {
            score += Constants.Memory.globalMemoryBoost
        }

        return min(score, 1.0)
    }

    private func normalizedBM25Score(_ score: Double) -> Double {
        guard score > 0 else { return 0 }
        return score / (score + MemoryScoring.bm25Saturation)
    }

    private func termCoverageScore(queryTokens: [String], documentTokens: [String]) -> Double {
        let queryTerms = Set(queryTokens)
        let documentTerms = Set(documentTokens)
        guard !queryTerms.isEmpty, !documentTerms.isEmpty else { return 0 }

        let overlap = queryTerms.intersection(documentTerms).count
        guard overlap > 0 else { return 0 }
        return Double(overlap) / Double(queryTerms.count)
    }

    private func topicalAffinityScore(query: String, memoryContent: String) -> Double {
        let sharedTopics = topicCategories(for: query).intersection(topicCategories(for: memoryContent))
        return sharedTopics.isEmpty ? 0 : Constants.Memory.topicalAffinityScore
    }

    private func identityAffinityScore(query: String, memoryContent: String) -> Double {
        guard isUserNameMemory(memoryContent) else { return 0 }
        let queryTerms = Set(MemoryText.tokens(query))
        return queryTerms.contains("name") || queryTerms.contains("identity") || query.lowercased().contains("who am i")
            ? Constants.Memory.coreIdentityRetrievalScore
            : 0
    }

    private func topicCategories(for text: String) -> Set<String> {
        let normalized = normalizedMemoryContent(text).lowercased()
        var topics = Set<String>()

        if containsAny(
            [
                "breakfast", "carb", "cook", "cuisine", "dessert", "dinner", "dish", "eat", "food",
                "italian", "lunch", "meal", "pasta", "pizza", "recipe", "restaurant", "snack", "sushi",
                "vegan", "vegetarian"
            ],
            in: normalized
        ) {
            topics.insert("food")
        }

        if containsAny(
            [
                "barca", "barcelona", "champions league", "club", "fc ", "football", "goal", "la liga",
                "laliga", "league", "madrid", "match", "messi", "player", "soccer", "sport", "team"
            ],
            in: normalized
        ) {
            topics.insert("sports")
        }

        if containsAny(
            [
                "game", "gaming", "mario", "nintendo", "playstation", "pokemon", "switch", "videogame",
                "video game", "xbox", "zelda"
            ],
            in: normalized
        ) {
            topics.insert("gaming")
        }

        if containsAny(
            [
                "code", "developer", "engineer", "programming", "rust", "software", "swift", "xcode"
            ],
            in: normalized
        ) {
            topics.insert("tech")
        }

        return topics
    }

    private func containsAny(_ terms: [String], in text: String) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func isUserNameMemory(_ content: String) -> Bool {
        let normalized = content.lowercased()
        return normalized.hasPrefix("the user's name is ")
            || normalized.hasPrefix("the user’s name is ")
            || normalized.hasPrefix("my name is ")
    }

    private func embedding(for text: String) -> [Double]? {
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

    private func normalizedMemoryContent(_ content: String) -> String {
        MemoryText.compact(content)
    }

    private func normalizedStoredMemoryContent(_ content: String) -> String {
        var normalized = normalizedMemoryContent(content)
        normalized = durableMemoryContent(from: normalized)
        normalized = MemoryFactParser.rewriteFirstPerson(normalized)
        normalized = normalizedUserMemorySentence(normalized)

        if let lastCharacter = normalized.last, !".!?".contains(lastCharacter) {
            normalized += "."
        }

        return normalized
    }

    private func sanitizedCandidates(_ candidates: [String], sourceText: String? = nil) -> [String] {
        var seen = Set<String>()
        var latestByConflictKey: [String: String] = [:]
        var orderedKeys: [String] = []

        for candidate in candidates {
            guard var normalized = normalizedExtractionCandidate(candidate) else { continue }
            guard isGroundedInUserMessage(normalized, sourceText: sourceText) else { continue }
            guard normalized.count >= Constants.Memory.minimumCandidateCharacters else { continue }
            if normalized.count > Constants.Memory.maximumCandidateCharacters {
                normalized = String(normalized.prefix(Constants.Memory.maximumCandidateCharacters))
            }

            let dedupeKey = normalized.lowercased()
            guard seen.insert(dedupeKey).inserted else { continue }

            if let signature = MemoryFactParser.signature(for: normalized), !signature.isRetraction {
                let key = signature.conflictKey
                if latestByConflictKey[key] == nil {
                    orderedKeys.append(key)
                }
                latestByConflictKey[key] = normalized
            } else {
                let key = "raw:\(dedupeKey)"
                orderedKeys.append(key)
                latestByConflictKey[key] = normalized
            }
        }

        return orderedKeys.compactMap { latestByConflictKey[$0] }
    }

    private func normalizedExtractionCandidate(_ candidate: String) -> String? {
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

    private func normalizedUserMemorySentence(_ content: String) -> String {
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

    private func isWellFormedUserMemory(_ content: String) -> Bool {
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

    private func isGenericRequestMemory(_ content: String) -> Bool {
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

    private func isLowValueInferredMemory(_ content: String) -> Bool {
        isGenericRequestMemory(content)
            || isEphemeralConversationMemory(content)
            || isLowConfidenceAttributionMemory(content)
    }

    private func isEphemeralConversationMemory(_ content: String) -> Bool {
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

    private func isLowConfidenceAttributionMemory(_ content: String) -> Bool {
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

    private func isGroundedInUserMessage(_ candidate: String, sourceText: String?) -> Bool {
        guard let sourceText else { return true }

        let normalizedSource = normalizedMemoryContent(sourceText)
        guard !normalizedSource.isEmpty else { return false }

        let candidateNumbers = numericTokens(in: candidate)
        let sourceNumbers = numericTokens(in: normalizedSource)
        guard candidateNumbers.isSubset(of: sourceNumbers) else { return false }

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

    private func sourceContainsExplicitPreference(_ sourceText: String) -> Bool {
        let normalized = sourceText.lowercased()
        let markers = [
            "i like", "i love", "i enjoy", "i prefer", "i'm a fan", "i’m a fan", "i am a fan",
            "my favorite", "i dislike", "i hate", "i don't like", "i don’t like", "i do not like"
        ]
        return markers.contains { normalized.contains($0) }
    }

    private func numericTokens(in text: String) -> Set<String> {
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

    private func durableMemoryContent(from content: String) -> String {
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

    private func extractionCandidatesFromJSON(_ text: String) -> [String]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return memoryStrings(fromJSON: object)
    }

    private func memoryStrings(fromJSON object: Any) -> [String] {
        if let string = object as? String {
            return [string]
        }

        if let array = object as? [Any] {
            return array.flatMap(memoryStrings(fromJSON:))
        }

        guard let dictionary = object as? [String: Any] else {
            return []
        }

        let containerKeys = ["memories", "memory", "facts", "fact", "items", "results", "candidates"]
        let stringKeys = ["content", "text", "sentence", "value"]
        var strings: [String] = []

        for key in containerKeys {
            if let value = value(for: key, in: dictionary) {
                strings.append(contentsOf: memoryStrings(fromJSON: value))
            }
        }

        for key in stringKeys {
            if let string = value(for: key, in: dictionary) as? String {
                strings.append(string)
            }
        }

        return strings
    }

    private func value(for lowercaseKey: String, in dictionary: [String: Any]) -> Any? {
        dictionary.first { $0.key.lowercased() == lowercaseKey }?.value
    }

    private func jsonPayloads(in text: String) -> [String] {
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

    private func fencedCodePayloads(in text: String) -> [String] {
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

    private func balancedJSONFragments(in text: String) -> [String] {
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

    private func fallbackExtractionCandidates(from text: String) -> [String] {
        let stripped = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
        let lineCandidates = stripped
            .components(separatedBy: .newlines)
            .flatMap(sentenceCandidates(from:))
        return lineCandidates.isEmpty ? sentenceCandidates(from: stripped) : lineCandidates
    }

    private func sentenceCandidates(from text: String) -> [String] {
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

    private func strippedCandidate(_ candidate: String) -> String {
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

    private func isNoMemoryMarker(_ text: String) -> Bool {
        let normalized = MemoryText.searchable(text)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        let markers: Set<String> = [
            "[]", "null", "none", "no memory", "no memories", "no durable memories",
            "nothing", "nothing to remember", "n/a", "na"
        ]
        return markers.contains(normalized)
    }

    private func memoryScopesCanConflict(existing: String?, incoming: String?) -> Bool {
        existing == incoming || existing == nil || incoming == nil
    }
}
