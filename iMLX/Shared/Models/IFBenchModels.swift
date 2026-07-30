import Foundation

nonisolated enum IFBenchJSONLError: LocalizedError {
    case empty
    case invalidLine(Int, String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "The IFBench JSONL file did not contain any prompts."
        case .invalidLine(let lineNumber, let message):
            return "Could not decode IFBench JSONL line \(lineNumber): \(message)"
        }
    }
}

nonisolated struct IFBenchPrompt: Identifiable, Codable, Hashable, Sendable {
    let key: String
    let prompt: String

    var id: String { key }

    private enum CodingKeys: String, CodingKey {
        case key
        case prompt
    }

    init(key: String, prompt: String) {
        self.key = key
        self.prompt = prompt
    }

    init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let key = try? container.decode(String.self, forKey: .key) {
            self.key = key
        } else {
            self.key = String(try container.decode(Int.self, forKey: .key))
        }
        self.prompt = try container.decode(String.self, forKey: .prompt)
    }

    func encode(to encoder: any Swift.Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(prompt, forKey: .prompt)
    }

    static func decodeJSONL(_ text: String) throws -> [IFBenchPrompt] {
        let decoder = JSONDecoder()
        var prompts: [IFBenchPrompt] = []

        for (lineIndex, line) in text.split(whereSeparator: \.isNewline).enumerated() {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }
            do {
                let prompt = try decoder.decode(IFBenchPrompt.self, from: Data(trimmedLine.utf8))
                prompts.append(prompt)
            } catch {
                throw IFBenchJSONLError.invalidLine(lineIndex + 1, error.localizedDescription)
            }
        }

        guard !prompts.isEmpty else {
            throw IFBenchJSONLError.empty
        }
        return prompts
    }
}

nonisolated struct IFBenchResponseRecord: Codable, Hashable, Sendable {
    let key: String
    let prompt: String
    let response: String
    let profileID: UUID?

    init(
        key: String,
        prompt: String,
        response: String,
        profileID: UUID?
    ) {
        self.key = key
        self.prompt = prompt
        self.response = response
        self.profileID = profileID
    }
}

nonisolated struct IFBenchRunResult: Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    let benchmarkName: String
    let benchmarkRepository: String
    let modelName: String
    let runContext: LLMProfilingRunContext?
    let promptCount: Int
    let responseRecords: [IFBenchResponseRecord]
    let profiles: [LLMExecutionProfile]
    let totalInferenceTime: LLMBenchmarkMetricSummary?
    let timeToFirstToken: LLMBenchmarkMetricSummary?
    let tokensPerSecond: LLMBenchmarkMetricSummary?
    let charactersPerSecond: LLMBenchmarkMetricSummary?
    let memoryDelta: LLMBenchmarkMetricSummary?
    let memoryPeakDuringInference: LLMBenchmarkMetricSummary?

    init(
        modelName: String,
        runContext: LLMProfilingRunContext?,
        responseRecords: [IFBenchResponseRecord],
        profiles: [LLMExecutionProfile]
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.benchmarkName = "IFBench"
        self.benchmarkRepository = "allenai/IFBench"
        self.modelName = modelName
        self.runContext = runContext
        self.promptCount = responseRecords.count
        self.responseRecords = responseRecords
        self.profiles = profiles
        self.totalInferenceTime = LLMBenchmarkMetricSummary(profiles.compactMap(\.totalInferenceDuration))
        self.timeToFirstToken = LLMBenchmarkMetricSummary(profiles.compactMap(\.timeToFirstGeneratedToken))
        self.tokensPerSecond = LLMBenchmarkMetricSummary(profiles.compactMap(\.tokensPerSecond))
        self.charactersPerSecond = LLMBenchmarkMetricSummary(profiles.compactMap(\.outputCharactersPerSecond))
        self.memoryDelta = LLMBenchmarkMetricSummary(profiles.compactMap { profile in
            profile.memoryDelta.map(Double.init)
        })
        self.memoryPeakDuringInference = LLMBenchmarkMetricSummary(profiles.compactMap { profile in
            profile.memoryPeakDuringInference.map { Double($0) }
        })
    }

    var officialResponsesJSONL: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let lines = responseRecords.compactMap { record -> String? in
            let officialRecord = IFBenchOfficialResponse(prompt: record.prompt, response: record.response)
            guard let data = try? encoder.encode(officialRecord) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        return lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
    }

    var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

private struct IFBenchOfficialResponse: Encodable {
    let prompt: String
    let response: String
}
