import XCTest
@testable import iMLX

final class MemoryDeterministicExtractionTests: XCTestCase {
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

    func testDeterministicNameExtractionUsesGroundedMetadata() {
        let service = makeMemoryService()

        let candidates = service.deterministicCandidates(from: "Me llamo Alan")

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.canonicalContent, "The user's name is Alan.")
        XCTAssertEqual(candidates.first?.relation, "name")
        XCTAssertEqual(candidates.first?.value, "Alan")
        XCTAssertEqual(candidates.first?.sourceQuote, "Me llamo Alan")
        XCTAssertGreaterThanOrEqual(candidates.first?.confidence ?? 0, 0.95)
    }

    func testDeterministicPreferenceExtractionHandlesSpanishDislike() {
        let service = makeMemoryService()

        let candidates = service.deterministicCandidates(from: "Odio el brócoli")

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.canonicalContent, "The user dislikes brócoli.")
        XCTAssertEqual(candidates.first?.relation, "dislikes")
        XCTAssertEqual(candidates.first?.value, "brócoli")
        XCTAssertEqual(candidates.first?.sourceQuote, "Odio el brócoli")
    }

    func testDeterministicGoalExtractionKeepsRequestTailOut() {
        let service = makeMemoryService()

        let candidates = service.deterministicCandidates(
            from: "My goal is to run a marathon, and can you help me make a plan?"
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates.first?.canonicalContent, "The user's goal is to run a marathon.")
        XCTAssertEqual(candidates.first?.relation, "goal")
        XCTAssertEqual(candidates.first?.value, "run a marathon")
    }

    func testDeterministicExtractionSkipsQuestionAboutATopic() {
        let service = makeMemoryService()

        XCTAssertTrue(service.deterministicCandidates(from: "What is MLX?").isEmpty)
        XCTAssertFalse(service.shouldRunLLMMemoryExtraction(for: "What is MLX?"))
    }

    func testGateSkipsLowValueTurnsAndRequestOnlyWantPhrases() {
        let service = makeMemoryService()

        XCTAssertFalse(service.shouldRunLLMMemoryExtraction(for: "thanks"))
        XCTAssertFalse(service.shouldRunLLMMemoryExtraction(for: "I want to know what MLX is"))
        XCTAssertFalse(service.shouldRunLLMMemoryExtraction(for: "Quiero saber qué es MLX"))
    }

    func testGateAllowsAmbiguousDurableSelfFactWhenDeterministicDidNotMatch() {
        let service = makeMemoryService()

        XCTAssertTrue(service.deterministicCandidates(from: "I'm trying to become a better runner").isEmpty)
        XCTAssertTrue(service.shouldRunLLMMemoryExtraction(for: "I'm trying to become a better runner"))
    }

    func testGateSkipsWhenDeterministicCandidatesExist() {
        let service = makeMemoryService()
        let candidates = service.deterministicCandidates(from: "I live in Madrid. What should I do this weekend?")

        XCTAssertEqual(candidates.first?.canonicalContent, "The user lives in Madrid.")
        XCTAssertFalse(
            service.shouldRunLLMMemoryExtraction(
                for: "I live in Madrid. What should I do this weekend?",
                hasDeterministicCandidates: !candidates.isEmpty
            )
        )
    }

    private func makeMemoryService() -> MemoryService {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iMLX-memory-deterministic-tests-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "iMLX.memory.deterministic.tests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)
        temporaryDirectories.append(directory)
        defaultsSuiteNames.append(suiteName)
        return MemoryService(
            userDefaults: userDefaults,
            memoriesDirectory: directory,
            resetStorageIfNeeded: false
        )
    }
}
