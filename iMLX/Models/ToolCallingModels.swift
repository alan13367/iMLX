import Foundation

nonisolated struct ToolDefinition: Codable, Hashable, Sendable {
    let name: String
    let description: String
    let argumentSchema: [ToolArgument]
    let metadata: ToolMetadata

    init(
        name: String,
        description: String,
        argumentSchema: [ToolArgument],
        metadata: ToolMetadata = ToolMetadata()
    ) {
        self.name = name
        self.description = description
        self.argumentSchema = argumentSchema
        self.metadata = metadata
    }
}

nonisolated struct ToolArgument: Codable, Hashable, Sendable {
    let name: String
    let type: String
    let required: Bool
    let description: String
}

nonisolated enum ToolExecutionClass: String, Codable, Hashable, Sendable {
    case local
    case network
}

nonisolated struct ToolMetadata: Codable, Hashable, Sendable {
    let requiresWebAccessToggle: Bool
    let requiresAttachedImages: Bool
    let requiresAttachedDocuments: Bool
    let requiresSinglePublicURL: Bool
    let executionClass: ToolExecutionClass

    init(
        requiresWebAccessToggle: Bool = false,
        requiresAttachedImages: Bool = false,
        requiresAttachedDocuments: Bool = false,
        requiresSinglePublicURL: Bool = false,
        executionClass: ToolExecutionClass = .local
    ) {
        self.requiresWebAccessToggle = requiresWebAccessToggle
        self.requiresAttachedImages = requiresAttachedImages
        self.requiresAttachedDocuments = requiresAttachedDocuments
        self.requiresSinglePublicURL = requiresSinglePublicURL
        self.executionClass = executionClass
    }
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
    let attachedDocuments: [ConversationDocumentReference]
    let hasNewlyAttachedDocuments: Bool
    let detectedPublicURLs: [URL]

    init(
        latestUserMessage: String,
        attachedImages: [ChatAttachmentImage],
        attachedDocuments: [ConversationDocumentReference] = [],
        hasNewlyAttachedDocuments: Bool = false,
        detectedPublicURLs: [URL]
    ) {
        self.latestUserMessage = latestUserMessage
        self.attachedImages = attachedImages
        self.attachedDocuments = attachedDocuments
        self.hasNewlyAttachedDocuments = hasNewlyAttachedDocuments
        self.detectedPublicURLs = detectedPublicURLs
    }

    var singleDetectedPublicURL: URL? {
        guard detectedPublicURLs.count == 1 else { return nil }
        return detectedPublicURLs[0]
    }
}

nonisolated enum ToolExecutionStatus: String, Codable, Hashable, Sendable {
    case success
    case invalidArguments
    case noContent
    case networkUnavailable
    case timedOut
    case permissionDenied
    case unavailable
    case executionFailed
}

nonisolated struct ToolExecutionResult: Codable, Hashable, Sendable {
    let toolName: String
    let status: ToolExecutionStatus
    let message: String?
    let contextBlock: String
    let sources: [MessageSource]
    let durationSeconds: TimeInterval

    var success: Bool {
        status == .success
    }
}

nonisolated struct ToolCallTrace: Codable, Hashable, Sendable {
    let toolName: String
    let displayInput: String?
    let status: ToolExecutionStatus?
    let durationSeconds: TimeInterval?
    let success: Bool
    let sourceCount: Int

    private enum CodingKeys: String, CodingKey {
        case toolName
        case displayInput
        case rewrittenQuery
        case status
        case durationSeconds
        case success
        case sourceCount
    }

    init(
        toolName: String,
        displayInput: String?,
        status: ToolExecutionStatus?,
        durationSeconds: TimeInterval?,
        success: Bool,
        sourceCount: Int
    ) {
        self.toolName = toolName
        self.displayInput = displayInput
        self.status = status
        self.durationSeconds = durationSeconds
        self.success = success
        self.sourceCount = sourceCount
    }

    init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolName = try container.decode(String.self, forKey: .toolName)
        displayInput = try container.decodeIfPresent(String.self, forKey: .displayInput)
            ?? container.decodeIfPresent(String.self, forKey: .rewrittenQuery)
        status = try container.decodeIfPresent(ToolExecutionStatus.self, forKey: .status)
        durationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .durationSeconds)
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        sourceCount = try container.decodeIfPresent(Int.self, forKey: .sourceCount) ?? 0
    }

    func encode(to encoder: any Swift.Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolName, forKey: .toolName)
        try container.encodeIfPresent(displayInput, forKey: .displayInput)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encode(success, forKey: .success)
        try container.encode(sourceCount, forKey: .sourceCount)
    }
}
