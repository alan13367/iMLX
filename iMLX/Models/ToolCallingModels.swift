import Foundation

nonisolated struct ToolDefinition: Codable, Hashable, Sendable {
    let name: String
    let description: String
    let argumentSchema: [ToolArgument]
}

nonisolated struct ToolArgument: Codable, Hashable, Sendable {
    let name: String
    let type: String
    let required: Bool
    let description: String
}

nonisolated enum ToolDecision: Codable, Equatable, Sendable {
    case none
    case call(ToolCallRequest)

    private enum CodingKeys: String, CodingKey {
        case tool
        case args
    }

    init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let toolName = try container.decodeIfPresent(String.self, forKey: .tool) ?? "none"
        if toolName == "none" {
            self = .none
            return
        }
        let arguments = try container.decodeIfPresent([String: String].self, forKey: .args) ?? [:]
        self = .call(
            ToolCallRequest(
                toolName: toolName,
                arguments: arguments
            )
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try container.encode("none", forKey: .tool)
        case .call(let request):
            try container.encode(request.toolName, forKey: .tool)
            try container.encode(request.arguments, forKey: .args)
        }
    }
}

nonisolated struct ToolCallRequest: Codable, Hashable, Sendable {
    let toolName: String
    let arguments: [String: String]
}

nonisolated struct ToolExecutionResult: Codable, Hashable, Sendable {
    let toolName: String
    let contextBlock: String
    let sources: [MessageSource]
    let success: Bool
    let durationSeconds: TimeInterval
}

nonisolated struct ToolCallTrace: Codable, Hashable, Sendable {
    let toolName: String
    let rewrittenQuery: String?
    let durationSeconds: TimeInterval?
    let success: Bool
    let sourceCount: Int
}
