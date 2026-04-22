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

    func encode(to encoder: any Swift.Encoder) throws {
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

nonisolated struct ToolInputContext: Sendable {
    let latestUserMessage: String
    let attachedImages: [ChatAttachmentImage]
    let detectedPublicURLs: [URL]

    var singleDetectedPublicURL: URL? {
        guard detectedPublicURLs.count == 1 else { return nil }
        return detectedPublicURLs[0]
    }
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
    let displayInput: String?
    let durationSeconds: TimeInterval?
    let success: Bool
    let sourceCount: Int

    private enum CodingKeys: String, CodingKey {
        case toolName
        case displayInput
        case rewrittenQuery
        case durationSeconds
        case success
        case sourceCount
    }

    init(
        toolName: String,
        displayInput: String?,
        durationSeconds: TimeInterval?,
        success: Bool,
        sourceCount: Int
    ) {
        self.toolName = toolName
        self.displayInput = displayInput
        self.durationSeconds = durationSeconds
        self.success = success
        self.sourceCount = sourceCount
    }

    init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolName = try container.decode(String.self, forKey: .toolName)
        displayInput = try container.decodeIfPresent(String.self, forKey: .displayInput)
            ?? container.decodeIfPresent(String.self, forKey: .rewrittenQuery)
        durationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .durationSeconds)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        sourceCount = try container.decodeIfPresent(Int.self, forKey: .sourceCount) ?? 0
    }

    func encode(to encoder: any Swift.Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolName, forKey: .toolName)
        try container.encodeIfPresent(displayInput, forKey: .displayInput)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encode(success, forKey: .success)
        try container.encode(sourceCount, forKey: .sourceCount)
    }
}
