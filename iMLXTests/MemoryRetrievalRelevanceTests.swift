import XCTest
@testable import iMLX

final class MemoryRetrievalRelevanceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var defaultsSuiteNames: [String] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        for suiteName in defaultsSuiteNames {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
        }
        temporaryDirectories = []
        defaultsSuiteNames = []
        super.tearDown()
    }

    func testCodingRequestSuppressesUnrelatedPersonalMemories() async {
        let system = makeMemorySystem()
        save(system, "The user likes pasta.", relation: "likes", value: "pasta", quote: "I like pasta.")
        save(system, "The user lives in Barcelona.", relation: "residence", value: "Barcelona", quote: "I live in Barcelona.")
        save(system, "The user likes football.", relation: "likes", value: "football", quote: "I like football.")

        let result = await system.retrieveMemoryResultAsync(
            for: "Help me fix this SwiftUI layout bug.",
            limit: 4,
            maxCharacters: 1_200
        )

        XCTAssertTrue(result.memories.isEmpty)
        XCTAssertEqual(result.contextBlock, "")
    }

    func testDinnerRecommendationRetrievesFoodPreferenceOnly() async {
        let system = makeMemorySystem()
        save(system, "The user likes pasta.", relation: "likes", value: "pasta", quote: "I like pasta.")
        save(system, "The user lives in Barcelona.", relation: "residence", value: "Barcelona", quote: "I live in Barcelona.")
        save(system, "The user likes football.", relation: "likes", value: "football", quote: "I like football.")

        let result = await system.retrieveMemoryResultAsync(
            for: "Suggest dinner ideas I might like.",
            limit: 4,
            maxCharacters: 1_200
        )

        XCTAssertEqual(result.memories.map(\.content), ["The user likes pasta."])
        XCTAssertTrue(result.contextBlock.contains("Evidence: \"I like pasta.\""))
    }

    func testCityPlanningRetrievesResidence() async {
        let system = makeMemorySystem()
        save(system, "The user lives in Barcelona.", relation: "residence", value: "Barcelona", quote: "I live in Barcelona.")
        save(system, "The user likes football.", relation: "likes", value: "football", quote: "I like football.")

        let result = await system.retrieveMemoryResultAsync(
            for: "Plan a weekend in my city.",
            limit: 4,
            maxCharacters: 1_200
        )

        XCTAssertEqual(result.memories.map(\.content), ["The user lives in Barcelona."])
    }

    func testExplicitMemoryRecallIntentionallyRetrievesSavedMemories() async {
        let system = makeMemorySystem()
        save(system, "The user likes pasta.", relation: "likes", value: "pasta", quote: "I like pasta.")
        save(system, "The user lives in Barcelona.", relation: "residence", value: "Barcelona", quote: "I live in Barcelona.")
        save(system, "The user likes football.", relation: "likes", value: "football", quote: "I like football.")

        let result = await system.retrieveMemoryResultAsync(
            for: "What do you remember about me?",
            limit: 4,
            maxCharacters: 1_200
        )

        XCTAssertEqual(Set(result.memories.map(\.content)), [
            "The user likes pasta.",
            "The user lives in Barcelona.",
            "The user likes football."
        ])
        XCTAssertFalse(result.contextBlock.isEmpty)
    }

    func testScopedMemoryRecallSuppressesOutOfScopeMemories() async {
        let system = makeMemorySystem()
        save(system, "The user likes pasta.", relation: "likes", value: "pasta", quote: "I like pasta.")
        save(system, "The user lives in Barcelona.", relation: "residence", value: "Barcelona", quote: "I live in Barcelona.")
        save(system, "The user's name is Alan.", relation: "name", value: "Alan", quote: "My name is Alan.")

        let result = await system.retrieveMemoryResultAsync(
            for: "What do you remember about my preferences?",
            limit: 4,
            maxCharacters: 1_200
        )

        XCTAssertEqual(result.memories.map(\.content), ["The user likes pasta."])
    }

    func testOnlyRelevantMemorySurvivesMixedCandidateSet() async {
        let system = makeMemorySystem()
        save(system, "The user dislikes broccoli.", relation: "dislikes", value: "broccoli", quote: "I dislike broccoli.")
        save(system, "The user likes tennis.", relation: "likes", value: "tennis", quote: "I like tennis.")
        save(system, "The user's name is Alan.", relation: "name", value: "Alan", quote: "My name is Alan.")

        let result = await system.retrieveMemoryResultAsync(
            for: "Can you recommend a dinner recipe for me?",
            limit: 4,
            maxCharacters: 1_200
        )

        XCTAssertEqual(result.memories.map(\.content), ["The user dislikes broccoli."])
    }

    func testPromptContextClipsAndIncludesEvidence() async {
        let system = makeMemorySystem()
        let longQuote = "I like pasta, especially with tomatoes, basil, olive oil, parmesan, garlic, pepper, lemon, and a long list of pantry details that should not expand the prompt without bounds."
        save(system, "The user likes pasta.", relation: "likes", value: "pasta", quote: longQuote)

        let result = await system.retrieveMemoryResultAsync(
            for: "Suggest dinner ideas I might like.",
            limit: 4,
            maxCharacters: 160
        )

        XCTAssertTrue(result.contextBlock.contains("- Memory: The user likes pasta."))
        XCTAssertTrue(result.contextBlock.contains("Evidence: \"I like pasta"))
        XCTAssertLessThan(result.contextBlock.count, 700)
    }

    func testPromptBudgetUsesClippedEvidenceLength() async {
        let system = makeMemorySystem()
        let longPastaQuote = "I like pasta. " + String(repeating: "Extra pasta detail. ", count: 80)
        let longSushiQuote = "I like sushi. " + String(repeating: "Extra sushi detail. ", count: 80)
        save(system, "The user likes pasta.", relation: "likes", value: "pasta", quote: longPastaQuote)
        save(system, "The user likes sushi.", relation: "likes", value: "sushi", quote: longSushiQuote)

        let result = await system.retrieveMemoryResultAsync(
            for: "What are my preferences?",
            limit: 4,
            maxCharacters: 520
        )

        XCTAssertEqual(Set(result.memories.map(\.content)), [
            "The user likes pasta.",
            "The user likes sushi."
        ])
    }

    func testDirectNameAndPreferenceLookupsStillRetrieveFacts() async {
        let system = makeMemorySystem()
        save(system, "The user's name is Alan.", relation: "name", value: "Alan", quote: "My name is Alan.")
        save(system, "The user likes pasta.", relation: "likes", value: "pasta", quote: "I like pasta.")
        save(system, "The user dislikes broccoli.", relation: "dislikes", value: "broccoli", quote: "I dislike broccoli.")

        let nameResult = await system.retrieveMemoryResultAsync(
            for: "What is my name?",
            limit: 4,
            maxCharacters: 1_200
        )
        XCTAssertEqual(nameResult.memories.map(\.content), ["The user's name is Alan."])

        let preferenceResult = await system.retrieveMemoryResultAsync(
            for: "What are my preferences?",
            limit: 4,
            maxCharacters: 1_200
        )
        XCTAssertEqual(Set(preferenceResult.memories.map(\.content)), [
            "The user likes pasta.",
            "The user dislikes broccoli."
        ])
    }

    private func makeMemorySystem() -> MemorySystem {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iMLX-memory-tests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "iMLX.memory.tests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)
        temporaryDirectories.append(directory)
        defaultsSuiteNames.append(suiteName)
        return MemorySystem(
            userDefaults: userDefaults,
            memoriesDirectory: directory,
            resetStorageIfNeeded: false
        )
    }

    @discardableResult
    private func save(
        _ system: MemorySystem,
        _ content: String,
        relation: String,
        value: String,
        quote: String,
        confidence: Double = 0.95
    ) -> UserMemory {
        let memory = system.upsert(
            content: content,
            status: .active,
            captureType: .inferred,
            sourceQuote: quote,
            factRelation: relation,
            factValue: value,
            confidence: confidence
        )
        XCTAssertNotNil(memory)
        return memory!
    }
}
