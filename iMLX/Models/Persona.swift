import Foundation

nonisolated enum PersonaTone: String, Codable, CaseIterable, Identifiable {
    case balanced
    case supportive
    case professional
    case concise
    case creative

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced:
            String.appLocalized("tone.balanced")
        case .supportive:
            String.appLocalized("tone.supportive")
        case .professional:
            String.appLocalized("tone.professional")
        case .concise:
            String.appLocalized("tone.concise")
        case .creative:
            String.appLocalized("tone.creative")
        }
    }

    var instruction: String {
        switch self {
        case .balanced:
            "Keep the tone clear, approachable, and practical."
        case .supportive:
            "Sound encouraging, calm, and helpful without sounding vague."
        case .professional:
            "Sound polished, precise, and trustworthy."
        case .concise:
            "Be direct, efficient, and avoid unnecessary filler."
        case .creative:
            "Be imaginative, vivid, and open to varied phrasing while staying useful."
        }
    }
}

nonisolated struct Persona: Identifiable, Codable, Equatable {
    static let defaultID = "general-assistant"

    let id: String
    var name: String
    var summary: String
    var goal: String
    var tone: PersonaTone
    var suggestedOpening: String
    var defaultModelId: String?
    var temperature: Double
    var topP: Double
    var repetitionPenalty: Double
    var systemPrompt: String
    var usesCustomSystemPrompt: Bool
    var symbolName: String
    var isBuiltIn: Bool
    let createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        name: String,
        summary: String,
        goal: String,
        tone: PersonaTone,
        suggestedOpening: String,
        defaultModelId: String?,
        temperature: Double,
        topP: Double,
        repetitionPenalty: Double,
        systemPrompt: String = "",
        usesCustomSystemPrompt: Bool = false,
        symbolName: String,
        isBuiltIn: Bool,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.goal = goal
        self.tone = tone
        self.suggestedOpening = suggestedOpening
        self.defaultModelId = defaultModelId
        self.temperature = temperature
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
        self.systemPrompt = systemPrompt
        self.usesCustomSystemPrompt = usesCustomSystemPrompt
        self.symbolName = symbolName
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var effectiveSystemPrompt: String {
        let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if usesCustomSystemPrompt && !trimmedPrompt.isEmpty {
            return trimmedPrompt
        }
        return Self.generatedSystemPrompt(
            name: name,
            summary: summary,
            goal: goal,
            tone: tone
        )
    }

    var displaySummary: String {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty {
            return trimmedSummary
        }
        return goal
    }

    var localizedName: String {
        guard isBuiltIn else { return name }
        return String.appLocalized("persona.\(id).name")
    }

    var localizedDisplaySummary: String {
        guard isBuiltIn else { return displaySummary }
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty {
            return String.appLocalized("persona.\(id).summary")
        }
        return String.appLocalized("persona.\(id).goal")
    }

    func refreshedTimestamp() -> Persona {
        var updated = self
        updated.updatedAt = Date()
        return updated
    }

    static func generatedSystemPrompt(
        name: String,
        summary: String,
        goal: String,
        tone: PersonaTone
    ) -> String {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        let roleLine = trimmedSummary.isEmpty
            ? "You are \(name)."
            : "You are \(name), \(trimmedSummary.lowercased())."

        return [
            roleLine,
            trimmedGoal.isEmpty ? nil : "Primary role: \(trimmedGoal)",
            tone.instruction,
            "Give actionable answers, point out uncertainty when needed, and explain important tradeoffs in plain language.",
            "Do not claim professional credentials, legal authority, or guaranteed outcomes. Encourage the user to verify critical real-world decisions when appropriate."
        ]
        .compactMap { $0 }
        .joined(separator: "\n\n")
    }

    static func starterPersonas() -> [Persona] {
        [
            Persona(
                id: defaultID,
                name: "General Assistant",
                summary: "a clear everyday helper",
                goal: "Help with common questions, planning, summaries, and practical problem solving.",
                tone: .balanced,
                suggestedOpening: "Help me think through a decision.",
                defaultModelId: "qwen3-1.7b-4bit",
                temperature: 0.7,
                topP: 1.0,
                repetitionPenalty: 1.0,
                symbolName: "sparkles",
                isBuiltIn: true
            ),
            Persona(
                id: "personal-financial-advisor",
                name: "Personal Financial Advisor",
                summary: "a cautious budgeting and planning coach",
                goal: "Help users think through budgeting, spending priorities, savings plans, debt paydown tradeoffs, and everyday financial decisions in plain language.",
                tone: .professional,
                suggestedOpening: "Help me build a monthly budget.",
                defaultModelId: "qwen3-4b-4bit",
                temperature: 0.4,
                topP: 0.9,
                repetitionPenalty: 1.0,
                symbolName: "dollarsign.circle",
                isBuiltIn: true
            ),
            Persona(
                id: "code-reviewer",
                name: "Code Reviewer",
                summary: "a practical software reviewer",
                goal: "Review code for correctness, regressions, maintainability, and edge cases. Prefer concrete findings and suggestions over vague praise.",
                tone: .concise,
                suggestedOpening: "Review this Swift function for bugs.",
                defaultModelId: "qwen3.5-4b-4bit",
                temperature: 0.25,
                topP: 0.85,
                repetitionPenalty: 1.0,
                symbolName: "chevron.left.slash.chevron.right",
                isBuiltIn: true
            ),
            Persona(
                id: "creative-writer",
                name: "Creative Writer",
                summary: "an imaginative storytelling partner",
                goal: "Help brainstorm ideas, improve prose, and write scenes, dialogue, outlines, and character concepts with vivid but coherent language.",
                tone: .creative,
                suggestedOpening: "Help me draft a short story scene.",
                defaultModelId: "qwen3.5-2b-4bit",
                temperature: 1.0,
                topP: 1.0,
                repetitionPenalty: 1.0,
                symbolName: "pencil.and.scribble",
                isBuiltIn: true
            ),
            Persona(
                id: "study-tutor",
                name: "Study Tutor",
                summary: "a patient explainer and quiz partner",
                goal: "Teach concepts step by step, check understanding, and adapt explanations to the learner's level without overwhelming them.",
                tone: .supportive,
                suggestedOpening: "Explain this topic like I'm new to it.",
                defaultModelId: "qwen3-1.7b-4bit",
                temperature: 0.55,
                topP: 0.95,
                repetitionPenalty: 1.0,
                symbolName: "book.closed",
                isBuiltIn: true
            )
        ]
    }
}
