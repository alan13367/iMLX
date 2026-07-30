import SwiftUI

/// Tool / activity phase driving the activity region.
enum MessageActivityToolPhase: Equatable {
    case planning
    case running(toolName: String, displayInput: String?)
    case completed(ToolCallTrace)
    /// Hidden-reasoning / thinking toggle content.
    case reasoning(text: String, isLive: Bool)

    var isLive: Bool {
        switch self {
        case .planning, .running:
            return true
        case .reasoning(_, let isLive):
            return isLive
        case .completed:
            return false
        }
    }
}

/// Surface-less activity region rendered above an assistant answer.
///
/// Replaces the container roles of the old tool-call card and thinking panel.
/// Tool rows stay in this column; mid-turn assistant prose is rendered as
/// normal response text between tools by the message/list layout.
struct MessageActivityView: View {
    let toolPhases: [MessageActivityToolPhase]
    let thinking: String?
    let isStreaming: Bool
    let isWaitingForAnswer: Bool
    @Binding var isThinkingExpanded: Bool
    var onToggleThinking: (() -> Void)?

    @State private var expandedToolIndices: Set<Int> = []
    @State private var expandedReasoningIndices: Set<Int> = []
    @State private var hapticSelectionTrigger = 0

    private var timelineEntries: [MessageActivityToolPhase] {
        var entries = toolPhases
        if let thinking, !thinking.isEmpty,
           !toolPhases.contains(where: {
               if case .reasoning(let text, _) = $0 { return text == thinking }
               return false
           }) {
            entries.append(.reasoning(text: thinking, isLive: isStreaming && isWaitingForAnswer))
        }
        return entries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ChatMetrics.activityRowSpacing) {
            ForEach(Array(timelineEntries.enumerated()), id: \.offset) { index, phase in
                timelineEntry(phase, index: index)
            }
        }
        .sensoryFeedback(.selection, trigger: hapticSelectionTrigger)
    }

    // MARK: - Timeline

    @ViewBuilder
    private func timelineEntry(_ phase: MessageActivityToolPhase, index: Int) -> some View {
        switch phase {
        case .planning, .running:
            ActivityRow(
                leading: .progress,
                label: liveToolLabel(phase),
                trailing: nil,
                disclosure: nil
            )
            .accessibilityAddTraits(.updatesFrequently)
        case .completed(let trace):
            VStack(alignment: .leading, spacing: ChatMetrics.activityRowSpacing) {
                ActivityRow(
                    leading: .symbol(
                        trace.success
                            ? MessageToolPresentation.icon(toolName: trace.toolName)
                            : "exclamationmark.triangle",
                        tint: trace.success ? .secondary : .orange
                    ),
                    label: MessageToolPresentation.label(
                        toolName: trace.toolName,
                        success: trace.success
                    ),
                    trailing: durationLabel(trace.durationSeconds),
                    disclosure: ActivityDisclosure(isExpanded: expandedToolIndices.contains(index)) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if expandedToolIndices.contains(index) {
                                expandedToolIndices.remove(index)
                            } else {
                                expandedToolIndices.insert(index)
                            }
                        }
                        hapticSelectionTrigger += 1
                    }
                )

                if expandedToolIndices.contains(index) {
                    ActivityDetailBody {
                        toolSteps(for: trace)
                    }
                    .transition(.opacity)
                }
            }
        case .reasoning(let text, let isLive):
            noteEntry(
                text: text,
                isLive: isLive,
                index: index
            )
        }
    }

    private func toolSteps(for trace: ToolCallTrace) -> some View {
        VStack(alignment: .leading, spacing: ChatMetrics.activityRowSpacing) {
            ActivityStepLine(
                text: String.appLocalized("tool.activity.planning"),
                state: .completed
            )

            if let execution = MessageToolPresentation.execution(
                toolName: trace.toolName,
                displayInput: trace.displayInput
            ) {
                ActivityStepLine(
                    text: execution.text,
                    state: trace.success ? .completed : .failed
                )
            }

            if trace.success, trace.sourceCount > 0 {
                ActivityStepLine(
                    text: String(
                        format: String.appLocalized("tool.trace.sources_found"),
                        trace.sourceCount
                    ),
                    state: .completed
                )
            }
        }
    }

    private func liveToolLabel(_ phase: MessageActivityToolPhase) -> String {
        switch phase {
        case .planning:
            return String.appLocalized("tool.activity.planning")
        case .running(let toolName, let displayInput):
            return MessageToolPresentation.execution(
                toolName: toolName,
                displayInput: displayInput
            )?.text ?? toolName
        case .completed, .reasoning:
            return ""
        }
    }

    private func durationLabel(_ duration: TimeInterval?) -> String? {
        guard let duration, duration >= 0.1 else { return nil }
        return String(format: "%.1fs", duration)
    }

    @ViewBuilder
    private func noteEntry(text: String, isLive: Bool, index: Int) -> some View {
        let isExpanded = isLive || expandedReasoningIndices.contains(index)
        VStack(alignment: .leading, spacing: ChatMetrics.activityRowSpacing) {
            ActivityRow(
                leading: isLive ? .progress : .symbol("brain", tint: .secondary),
                label: isLive
                    ? String.appLocalized("message.thinking")
                    : String.appLocalized("message.thinking.summary"),
                trailing: nil,
                disclosure: isLive
                    ? nil
                    : ActivityDisclosure(isExpanded: isExpanded) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            if expandedReasoningIndices.contains(index) {
                                expandedReasoningIndices.remove(index)
                            } else {
                                expandedReasoningIndices.insert(index)
                            }
                        }
                        hapticSelectionTrigger += 1
                        if index == timelineEntries.count - 1 {
                            onToggleThinking?()
                            isThinkingExpanded = !isExpanded
                        }
                    }
            )
            .accessibilityLabel(
                isLive
                    ? String.appLocalized("message.thinking")
                    : String.appLocalized("message.thinking.summary")
            )
            .accessibilityAddTraits(isLive ? .updatesFrequently : [])

            if isExpanded, !text.isEmpty {
                ActivityDetailBody {
                    MessageMarkdownText(
                        text: text,
                        isStreaming: isLive,
                        linkTint: BrandPalette.accent
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            if isLive == false,
               index == timelineEntries.count - 1,
               isThinkingExpanded {
                expandedReasoningIndices.insert(index)
            }
        }
        .onChange(of: isThinkingExpanded) { _, expanded in
            guard index == timelineEntries.count - 1 else { return }
            if expanded {
                expandedReasoningIndices.insert(index)
            } else {
                expandedReasoningIndices.remove(index)
            }
        }
    }
}

// MARK: - Row primitives

/// Leading glyph slot for an activity row. Occupies a fixed-width column so
/// every row, expanded body, and hairline aligns to the same gutter.
enum ActivityRowLeading: Equatable {
    case symbol(String, tint: Color)
    case progress
}

struct ActivityDisclosure {
    let isExpanded: Bool
    let toggle: () -> Void
}

/// One quiet line of activity: gutter glyph, label, optional trailing detail,
/// and an optional inline disclosure chevron. Deliberately has no background.
struct ActivityRow: View {
    let leading: ActivityRowLeading
    let label: String
    let trailing: String?
    let disclosure: ActivityDisclosure?

    var body: some View {
        if let disclosure {
            Button(action: disclosure.toggle) {
                content(isExpanded: disclosure.isExpanded)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
        } else {
            content(isExpanded: nil)
                .accessibilityElement(children: .combine)
        }
    }

    private func content(isExpanded: Bool?) -> some View {
        HStack(spacing: ChatMetrics.gutterSpacing) {
            leadingGlyph
                .frame(width: ChatMetrics.gutterWidth, alignment: .center)

            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            if let trailing {
                Text(trailing)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if let isExpanded {
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(.easeInOut(duration: 0.18), value: isExpanded)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        switch leading {
        case .symbol(let name, let tint):
            Image(systemName: name)
                .font(.footnote)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
        case .progress:
            ProgressView()
                .controlSize(.mini)
                .accessibilityHidden(true)
        }
    }
}

/// Expanded body for an activity entry. Indents to the gutter and marks its
/// subordinate relationship with a hairline rule instead of a filled surface.
struct ActivityDetailBody<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: ChatMetrics.gutterSpacing) {
            Rectangle()
                .fill(PlatformColors.separator)
                .frame(width: 1)
                .accessibilityHidden(true)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, (ChatMetrics.gutterWidth - 1) / 2)
    }
}

enum ActivityStepState {
    case completed
    case failed
}

/// A single step inside an expanded tool trace.
struct ActivityStepLine: View {
    let text: String
    let state: ActivityStepState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: state == .completed ? "checkmark" : "xmark")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(state == .completed ? .secondary : Color.orange)
                .accessibilityHidden(true)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Presentation helpers

enum MessageToolPresentation {
    static func execution(toolName: String, displayInput: String?) -> (icon: String, text: String)? {
        switch toolName {
        case "web_search":
            guard let displayInput, !displayInput.isEmpty else { return nil }
            return ("globe", String(format: String.appLocalized("tool.activity.searching"), displayInput))
        case "read_url":
            guard let displayInput, !displayInput.isEmpty else { return nil }
            return ("link", String(format: String.appLocalized("tool.activity.read_url"), displayInput))
        case "ocr_image_text":
            return ("text.viewfinder", String.appLocalized("tool.activity.ocr_image_text"))
        case "document_synthesize":
            guard let displayInput, !displayInput.isEmpty else {
                return ("doc.text.magnifyingglass", String.appLocalized("tool.activity.document_synthesize"))
            }
            return (
                "doc.text.magnifyingglass",
                String(format: String.appLocalized("tool.activity.document_synthesize_query"), displayInput)
            )
        case "calendar_brief":
            guard let displayInput, !displayInput.isEmpty else {
                return ("calendar", String.appLocalized("tool.activity.calendar_brief"))
            }
            return (
                "calendar",
                String(format: String.appLocalized("tool.activity.calendar_brief_range"), displayInput)
            )
        case "calendar_create":
            guard let displayInput, !displayInput.isEmpty else {
                return ("calendar.badge.plus", String.appLocalized("tool.activity.calendar_create"))
            }
            return (
                "calendar.badge.plus",
                String(format: String.appLocalized("tool.activity.calendar_create_title"), displayInput)
            )
        case "current_datetime":
            return ("clock", String.appLocalized("tool.activity.current_datetime"))
        case "reminders_brief":
            guard let displayInput, !displayInput.isEmpty else {
                return ("checklist", String.appLocalized("tool.activity.reminders_brief"))
            }
            return (
                "checklist",
                String(format: String.appLocalized("tool.activity.reminders_brief_range"), displayInput)
            )
        case "reminders_create":
            guard let displayInput, !displayInput.isEmpty else {
                return ("checklist.checked", String.appLocalized("tool.activity.reminders_create"))
            }
            return (
                "checklist.checked",
                String(format: String.appLocalized("tool.activity.reminders_create_title"), displayInput)
            )
        case "timer_create":
            guard let displayInput, !displayInput.isEmpty else {
                return ("timer", String.appLocalized("tool.activity.timer_create"))
            }
            return (
                "timer",
                String(format: String.appLocalized("tool.activity.timer_create_duration"), displayInput)
            )
        case "contacts_lookup":
            guard let displayInput, !displayInput.isEmpty else {
                return ("person.crop.circle.badge.questionmark", String.appLocalized("tool.activity.contacts_lookup"))
            }
            return (
                "person.crop.circle.badge.questionmark",
                String(format: String.appLocalized("tool.activity.contacts_lookup_query"), displayInput)
            )
        default:
            return nil
        }
    }

    static func label(toolName: String, success: Bool) -> String {
        switch (toolName, success) {
        case ("read_url", true):
            return String.appLocalized("tool.trace.read_url")
        case ("read_url", false):
            return String.appLocalized("tool.trace.read_url_failed")
        case ("ocr_image_text", true):
            return String.appLocalized("tool.trace.ocr_image_text")
        case ("ocr_image_text", false):
            return String.appLocalized("tool.trace.ocr_image_text_failed")
        case ("web_search", true):
            return String.appLocalized("tool.trace.web_search")
        case ("web_search", false):
            return String.appLocalized("tool.trace.web_search_failed")
        case ("document_synthesize", true):
            return String.appLocalized("tool.trace.document_synthesize")
        case ("document_synthesize", false):
            return String.appLocalized("tool.trace.document_synthesize_failed")
        case ("calendar_brief", true):
            return String.appLocalized("tool.trace.calendar_brief")
        case ("calendar_brief", false):
            return String.appLocalized("tool.trace.calendar_brief_failed")
        case ("calendar_create", true):
            return String.appLocalized("tool.trace.calendar_create")
        case ("calendar_create", false):
            return String.appLocalized("tool.trace.calendar_create_failed")
        case ("current_datetime", true):
            return String.appLocalized("tool.trace.current_datetime")
        case ("current_datetime", false):
            return String.appLocalized("tool.trace.current_datetime_failed")
        case ("reminders_brief", true):
            return String.appLocalized("tool.trace.reminders_brief")
        case ("reminders_brief", false):
            return String.appLocalized("tool.trace.reminders_brief_failed")
        case ("reminders_create", true):
            return String.appLocalized("tool.trace.reminders_create")
        case ("reminders_create", false):
            return String.appLocalized("tool.trace.reminders_create_failed")
        case ("timer_create", true):
            return String.appLocalized("tool.trace.timer_create")
        case ("timer_create", false):
            return String.appLocalized("tool.trace.timer_create_failed")
        case ("contacts_lookup", true):
            return String.appLocalized("tool.trace.contacts_lookup")
        case ("contacts_lookup", false):
            return String.appLocalized("tool.trace.contacts_lookup_failed")
        default:
            return success ? toolName : "\(toolName) Failed"
        }
    }

    static func icon(toolName: String) -> String {
        switch toolName {
        case "read_url": "link"
        case "ocr_image_text": "text.viewfinder"
        case "web_search": "globe"
        case "document_synthesize": "doc.text.magnifyingglass"
        case "calendar_brief": "calendar"
        case "calendar_create": "calendar.badge.plus"
        case "current_datetime": "clock"
        case "reminders_brief": "checklist"
        case "reminders_create": "checklist.checked"
        case "timer_create": "timer"
        case "contacts_lookup": "person.crop.circle.badge.questionmark"
        default: "wrench.and.screwdriver"
        }
    }
}

// MARK: - Previews

#Preview("Activity — running") {
    MessageActivityView(
        toolPhases: [.running(toolName: "web_search", displayInput: "tallest building in the world 2026")],
        thinking: nil,
        isStreaming: true,
        isWaitingForAnswer: true,
        isThinkingExpanded: .constant(false)
    )
    .padding()
}

#Preview("Activity — completed with reasoning") {
    ActivityPreviewWrapper(false) { binding in
        MessageActivityView(
            toolPhases: [.completed(
                ToolCallTrace(
                    toolName: "web_search",
                    displayInput: "tallest building in the world 2026",
                    status: .success,
                    durationSeconds: 6.5,
                    success: true,
                    sourceCount: 3
                )
            )],
            thinking: "The user wants a current fact, so a web lookup is warranted.",
            isStreaming: false,
            isWaitingForAnswer: false,
            isThinkingExpanded: binding
        )
        .padding()
    }
}

#Preview("Activity — interleaved tools and reasoning") {
    ActivityPreviewWrapper(true) { binding in
        MessageActivityView(
            toolPhases: [
                .completed(
                    ToolCallTrace(
                        toolName: "current_datetime",
                        displayInput: nil,
                        status: .success,
                        durationSeconds: 0.0,
                        success: true,
                        sourceCount: 0
                    )
                ),
                .completed(
                    ToolCallTrace(
                        toolName: "calendar_brief",
                        displayInput: "today",
                        status: .noContent,
                        durationSeconds: 0.2,
                        success: true,
                        sourceCount: 0
                    )
                )
            ],
            thinking: "No events were returned, so I can answer both parts now.",
            isStreaming: false,
            isWaitingForAnswer: false,
            isThinkingExpanded: binding
        )
        .padding()
    }
}

#Preview("Activity — failed tool") {
    MessageActivityView(
        toolPhases: [.completed(
            ToolCallTrace(
                toolName: "read_url",
                displayInput: "https://example.com",
                status: .networkUnavailable,
                durationSeconds: 0.3,
                success: false,
                sourceCount: 0
            )
        )],
        thinking: nil,
        isStreaming: false,
        isWaitingForAnswer: false,
        isThinkingExpanded: .constant(false)
    )
    .padding()
}

private struct ActivityPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content

    init(_ value: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        self._value = State(initialValue: value)
        self.content = content
    }

    var body: some View { content($value) }
}
