import XCTest
@testable import iMLX

final class IFBenchModelsTests: XCTestCase {
    func testIFBenchPromptDecodesJSONLWithStringAndIntegerKeys() throws {
        let jsonl = """
        {"key":"0","prompt":"First prompt","instruction_id_list":["count:keywords_multiple"],"kwargs":[{}]}
        {"key":1,"prompt":"Second prompt","instruction_id_list":["count:conjunctions"],"kwargs":[{}]}
        """

        let prompts = try IFBenchPrompt.decodeJSONL(jsonl)

        XCTAssertEqual(prompts.count, 2)
        XCTAssertEqual(prompts[0].key, "0")
        XCTAssertEqual(prompts[0].prompt, "First prompt")
        XCTAssertEqual(prompts[1].key, "1")
        XCTAssertEqual(prompts[1].prompt, "Second prompt")
    }

    func testIFBenchOfficialResponsesJSONLMatchesEvaluatorShape() throws {
        let result = IFBenchRunResult(
            modelName: "Test Model",
            runContext: nil,
            responseRecords: [
                IFBenchResponseRecord(
                    key: "0",
                    prompt: "Say hello.",
                    response: "Hello.",
                    profileID: nil
                )
            ],
            profiles: []
        )

        let line = try XCTUnwrap(result.officialResponsesJSONL.split(whereSeparator: \.isNewline).first)
        let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String]

        XCTAssertEqual(object?["prompt"], "Say hello.")
        XCTAssertEqual(object?["response"], "Hello.")
        XCTAssertNil(object?["key"])
    }
}
