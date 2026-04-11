import Accelerate
import Foundation
import NaturalLanguage

nonisolated struct MemoryRetrievalCandidate {
    let memory: UserMemory
    let score: Double
}

nonisolated struct RawMemoryExtractionCandidate {
    let canonicalContent: String
    let relation: String?
    let value: String?
    let sourceQuote: String?
    let sourceLanguageCode: String?
    let confidence: Double?
    let requiresSourceQuote: Bool
}

nonisolated enum MemoryRelation: String, Hashable {
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

    init?(externalValue: String?) {
        guard let externalValue else { return nil }
        let normalized = MemoryText.searchable(externalValue)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        switch normalized {
        case "name", "user_name":
            self = .name
        case "pronoun", "pronouns":
            self = .pronouns
        case "residence", "home", "location", "lives_in", "based_in", "address":
            self = .residence
        case "timezone", "time_zone":
            self = .timezone
        case "occupation", "job", "role", "profession":
            self = .occupation
        case "employer", "company", "workplace":
            self = .employer
        case "education", "study", "studies", "learning":
            self = .education
        case "language", "preferred_language":
            self = .language
        case "likes", "like", "preference", "prefers", "favorite":
            self = .likes
        case "dislikes", "dislike":
            self = .dislikes
        case "goal", "goals", "intent":
            self = .goal
        case "project", "projects":
            self = .project
        case "constraint", "constraints", "need", "needs", "requirement":
            self = .constraint
        case "allergy", "allergies":
            self = .allergy
        case "diet", "dietary":
            self = .diet
        case "identity":
            self = .identity
        case "general", "other":
            self = .general
        default:
            return nil
        }
    }
}

nonisolated struct MemoryFactSignature: Hashable {
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

nonisolated enum MemoryScoring {
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
    static let relationIntentRetrievalScore = 0.36
    static let minimumExtractionConfidence = 0.62
}

nonisolated enum MemoryText {
    private static let stopWords: Set<String> = [
        "a", "about", "all", "also", "am", "an", "and", "are", "as", "at", "be", "because", "but",
        "by", "can", "do", "does", "for", "from", "had", "has", "have", "i", "if", "in", "into",
        "is", "it", "its", "me", "my", "of", "on", "or", "our", "so", "that", "the", "their",
        "them", "they", "this", "to", "user", "users", "was", "we", "were", "with", "would", "you",
        "your",
        "al", "algo", "como", "con", "de", "del", "el", "ella", "en", "es", "la", "las", "lo",
        "los", "me", "mi", "mis", "para", "pero", "por", "que", "se", "si", "soy", "su", "sus",
        "te", "un", "una", "y", "yo",
        "des", "du", "est", "et", "je", "la", "le", "les", "ma", "mes", "mon", "pour", "que",
        "qui", "sur", "un", "une",
        "bin", "das", "der", "die", "ein", "eine", "ich", "im", "ist", "mein", "meine", "mit",
        "und", "zu",
        "che", "con", "di", "e", "gli", "il", "io", "la", "le", "mi", "per", "sono", "un",
        "una",
        "com", "da", "de", "do", "e", "em", "eu", "meu", "minha", "o", "os", "para", "por",
        "que", "sou", "um", "uma"
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

    static func aliasSearchable(_ text: String) -> String {
        searchable(text)
            .replacingOccurrences(of: #"[\p{P}\p{S}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func tokens(_ text: String) -> [String] {
        let normalized = searchable(text)
        guard !normalized.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = normalized

        var tokens: [String] = []
        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            if let token = normalizedToken(String(normalized[range])) {
                tokens.append(token)
            }
            return true
        }

        if !tokens.isEmpty {
            return tokens
        }

        return normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .compactMap(normalizedToken)
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

    private static func normalizedToken(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines
                .union(.punctuationCharacters)
                .union(.symbols)
        )
        guard !trimmed.isEmpty else { return nil }

        let normalized = isLatinToken(trimmed) ? stem(trimmed) : trimmed
        guard normalized.count >= 2 || containsNonLatinLetter(normalized) || containsDigit(normalized) else { return nil }
        guard !stopWords.contains(normalized) else { return nil }
        return normalized
    }

    private static func isLatinToken(_ token: String) -> Bool {
        token.unicodeScalars.allSatisfy { scalar in
            CharacterSet.decimalDigits.contains(scalar) || scalar.value <= 0x024F
        }
    }

    private static func containsNonLatinLetter(_ token: String) -> Bool {
        token.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar) && scalar.value > 0x024F
        }
    }

    private static func containsDigit(_ token: String) -> Bool {
        token.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) }
    }
}

nonisolated enum MemoryVectorMath {
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

nonisolated enum MemoryVectorSketch {
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

nonisolated enum MemoryFactParser {
    static func normalizedRelationRawValue(_ rawValue: String?) -> String? {
        MemoryRelation(externalValue: rawValue)?.rawValue
    }

    static func signature(relation rawRelation: String?, value rawValue: String?, isRetraction: Bool = false) -> MemoryFactSignature? {
        guard let relation = MemoryRelation(externalValue: rawRelation) else { return nil }
        let value = MemoryText.compact(rawValue ?? "")
        guard !value.isEmpty else { return nil }
        return signature(relation, value, isRetraction: isRetraction)
    }

    static func signature(for memory: UserMemory) -> MemoryFactSignature? {
        signature(relation: memory.factRelation, value: memory.factValue) ?? signature(for: memory.content)
    }

    static func queryIntentSignatures(for query: String) -> [MemoryFactSignature] {
        let text = MemoryText.aliasSearchable(query)
        guard !text.isEmpty else { return [] }

        var relations: [MemoryRelation] = []
        func append(_ relation: MemoryRelation) {
            guard !relations.contains(relation) else { return }
            relations.append(relation)
        }

        if containsAny([
            "what is my name", "what s my name", "who am i", "my name", "como me llamo",
            "cual es mi nombre", "mi nombre", "comment je m appelle", "mon nom", "wie heisse ich",
            "wie heiße ich", "mein name", "come mi chiamo", "qual e il mio nome", "qual e meu nome",
            "como me chamo", "我的名字", "我叫什么", "私の名前", "내 이름"
        ], in: text) {
            append(.name)
        }

        if containsAny([
            "where do i live", "where i live", "my address", "my home", "where am i based",
            "donde vivo", "dónde vivo", "mi casa", "mi direccion", "mi dirección", "où j habite",
            "ou j habite", "mon adresse", "wo wohne", "wo lebe", "dove vivo", "dove abito",
            "onde moro", "onde vivo", "我住", "住んで", "어디 살아"
        ], in: text) {
            append(.residence)
        }

        if containsAny([
            "what language", "which language", "my language", "preferred language", "idioma",
            "lengua", "langue", "sprache", "lingua", "linguagem", "语言", "言語", "언어"
        ], in: text) {
            append(.language)
        }

        if containsAny([
            "what is my job", "what do i do", "my job", "my work", "my profession",
            "mi trabajo", "mi profesion", "mi profesión", "a que me dedico", "a quoi je travaille",
            "mon metier", "mein beruf", "mein job", "il mio lavoro", "minha profissão", "我的工作"
        ], in: text) {
            append(.occupation)
            append(.employer)
        }

        if containsAny([
            "what do i like", "what are my preferences", "my preferences", "things i like",
            "que me gusta", "qué me gusta", "mis gustos", "mes preferences", "ce que j aime",
            "was mag ich", "cosa mi piace", "o que eu gosto", "我喜欢", "好きな"
        ], in: text) {
            append(.likes)
        }

        if containsAny([
            "what do i dislike", "what do i hate", "things i dislike", "que odio", "qué odio",
            "que no me gusta", "qué no me gusta", "ce que je deteste", "was hasse ich",
            "cosa odio", "o que eu odeio", "我讨厌", "嫌い"
        ], in: text) {
            append(.dislikes)
        }

        if containsAny([
            "my goal", "my goals", "what do i want", "what am i trying to", "mi objetivo",
            "mis objetivos", "quiero hacer", "mon objectif", "mein ziel", "il mio obiettivo",
            "meu objetivo", "目标", "目標", "목표"
        ], in: text) {
            append(.goal)
        }

        if containsAny([
            "my project", "my projects", "what am i working on", "mi proyecto", "mis proyectos",
            "en que estoy trabajando", "mon projet", "mein projekt", "il mio progetto",
            "meu projeto", "项目", "プロジェクト", "프로젝트"
        ], in: text) {
            append(.project)
        }

        if containsAny([
            "my constraints", "my limits", "what can i not", "what do i need", "mis limites",
            "mis límites", "mis restricciones", "contraintes", "einschrankungen", "einschränkungen",
            "vincoli", "restricoes", "restrições", "限制", "制約", "제약"
        ], in: text) {
            append(.constraint)
        }

        return relations.map {
            MemoryFactSignature(relation: $0, valueKey: "", isRetraction: false)
        }
    }

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

    private static func containsAny(_ terms: [String], in text: String) -> Bool {
        terms.contains { text.contains($0) }
    }
}

nonisolated struct IndexedMemoryRecord {
    let memoryIndex: Int
    let memory: UserMemory
    let normalizedContent: String
    let tokens: [String]
    let termFrequency: [String: Int]
    let normalizedVector: [Double]?
    let vectorBucketKeys: [String]
    let signature: MemoryFactSignature?
}

nonisolated struct MemoryVaultIndex {
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
            let indexedText = [normalizedContent, memory.sourceQuote]
                .compactMap { $0 }
                .filter { !MemoryText.compact($0).isEmpty }
                .joined(separator: " ")
            let tokens = MemoryText.tokens(indexedText)
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
                    signature: MemoryFactParser.signature(for: memory)
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
            .map { "\($0.id.uuidString):\($0.status.rawValue):\($0.updatedAt.timeIntervalSince1970):\($0.vector?.count ?? 0):\($0.sourceQuote ?? ""):\($0.factRelation ?? ""):\($0.factValue ?? "")" }
            .joined(separator: "|")
    }
}
