import SwiftUI

/// Single canonical tool-call card. Replaces the previous trio of
/// `ToolActivityChainView`, `CompletedToolChainView`, and `ToolTraceChainView`.
///
/// Three input modes:
/// - `.planning` — model is choosing a tool.
/// - `.running(toolName, displayInput)` — tool is executing.
/// - `.completed(trace)` — finalized trace, success or failure.
struct MessageToolCallCard: View {
    enum Phase: Equatable {
        case planning
        case running(toolName: String, displayInput: String?)
        case completed(ToolCallTrace)
    }

    let phase: Phase
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            if isExpanded || isLive {
                Divider()
                    .padding(.horizontal, 12)

                steps
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(railStyle)
                .frame(width: 2)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Header

    private var header: some View {
        Group {
            if isLive {
                liveHeader
            } else {
                completedHeader
            }
        }
    }

    private var liveHeader: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(BrandPalette.cyan)

            Text(liveLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)
        }
    }

    private var completedHeader: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
            Haptics.selectionChanged()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: completedIconName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(completedIconStyle)
                    .frame(width: 22, height: 22)
                    .symbolRenderingMode(.hierarchical)

                Text(completedLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if case .completed(let trace) = phase,
                   let duration = trace.durationSeconds,
                   duration >= 0.1 {
                    Text(String(format: "%.1fs", duration))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(.easeInOut(duration: 0.18), value: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Steps

    @ViewBuilder
    private var steps: some View {
        VStack(alignment: .leading, spacing: 0) {
            ToolActivityStepRow(
                icon: "wand.and.stars",
                text: String.appLocalized("tool.activity.planning"),
                state: planningStepState
            )

            if let executionDetails {
                ToolActivityConnector()
                ToolActivityStepRow(
                    icon: executionDetails.icon,
                    text: executionDetails.text,
                    state: executionStepState
                )
            }

            if case .completed(let trace) = phase, trace.success, trace.sourceCount > 0 {
                ToolActivityConnector()
                ToolActivityStepRow(
                    icon: "doc.text.magnifyingglass",
                    text: String(format: String.appLocalized("tool.trace.sources_found"), trace.sourceCount),
                    state: .completed
                )
            }
        }
    }

    // MARK: - Derived

    private var isLive: Bool {
        switch phase {
        case .planning, .running: true
        case .completed: false
        }
    }

    private var liveLabel: String {
        switch phase {
        case .planning:
            return String.appLocalized("tool.activity.planning")
        case .running(let toolName, let displayInput):
            return MessageToolPresentation.execution(toolName: toolName, displayInput: displayInput)?.text
                ?? toolName
        case .completed:
            return ""
        }
    }

    private var completedLabel: String {
        guard case .completed(let trace) = phase else { return "" }
        return MessageToolPresentation.label(toolName: trace.toolName, success: trace.success)
    }

    private var completedIconName: String {
        guard case .completed(let trace) = phase else { return "wand.and.stars" }
        if !trace.success { return "exclamationmark.triangle.fill" }
        return MessageToolPresentation.icon(toolName: trace.toolName)
    }

    private var completedIconStyle: Color {
        guard case .completed(let trace) = phase else { return BrandPalette.cyan }
        return trace.success ? BrandPalette.cyan : .orange
    }

    private var railStyle: AnyShapeStyle {
        switch phase {
        case .completed(let trace) where !trace.success:
            return AnyShapeStyle(Color.orange.opacity(0.7))
        default:
            return AnyShapeStyle(BrandPalette.primaryGradient)
        }
    }

    private var planningStepState: ToolActivityStepState {
        switch phase {
        case .planning: .active
        case .running: .completed
        case .completed: .completed
        }
    }

    private var executionStepState: ToolActivityStepState {
        switch phase {
        case .planning: .pending
        case .running: .active
        case .completed(let trace): trace.success ? .completed : .failed
        }
    }

    private var executionDetails: (icon: String, text: String)? {
        switch phase {
        case .planning:
            return nil
        case .running(let toolName, let displayInput):
            return MessageToolPresentation.execution(toolName: toolName, displayInput: displayInput)
        case .completed(let trace):
            return MessageToolPresentation.execution(toolName: trace.toolName, displayInput: trace.displayInput)
        }
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
        default: "wand.and.stars"
        }
    }
}

// MARK: - Step row + connector

enum ToolActivityStepState {
    case pending
    case active
    case completed
    case failed
}

struct ToolActivityStepRow: View {
    let icon: String
    let text: String
    let state: ToolActivityStepState

    var body: some View {
        HStack(spacing: 10) {
            statusIndicator
                .frame(width: 18, height: 18)

            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(iconColor)
                .frame(width: 14)

            Text(text)
                .font(.callout)
                .foregroundStyle(textColor)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch state {
        case .active:
            ProgressView()
                .controlSize(.mini)
                .tint(BrandPalette.cyan)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.red)
        case .pending:
            Image(systemName: "circle")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
    }

    private var iconColor: Color {
        switch state {
        case .active: BrandPalette.cyan
        case .completed: .secondary
        case .failed: .secondary
        case .pending: Color(.quaternaryLabel)
        }
    }

    private var textColor: Color {
        switch state {
        case .active: .primary
        case .completed: .secondary
        case .failed: .secondary
        case .pending: Color(.quaternaryLabel)
        }
    }
}

struct ToolActivityConnector: View {
    var body: some View {
        Capsule()
            .fill(BrandPalette.cyan.opacity(0.18))
            .frame(width: 2, height: 12)
            .padding(.leading, 8)
            .accessibilityHidden(true)
    }
}

#Preview("Tool — planning") {
    MessageToolCallCard(phase: .planning).padding()
}

#Preview("Tool — running") {
    MessageToolCallCard(phase: .running(toolName: "web_search", displayInput: "swiftui ios 18 hero animations"))
        .padding()
}

#Preview("Tool — completed success") {
    MessageToolCallCard(
        phase: .completed(
            ToolCallTrace(
                toolName: "web_search",
                displayInput: "swiftui ios 18 hero animations",
                status: .success,
                durationSeconds: 1.42,
                success: true,
                sourceCount: 3
            )
        )
    )
    .padding()
}

#Preview("Tool — completed failed") {
    MessageToolCallCard(
        phase: .completed(
            ToolCallTrace(
                toolName: "read_url",
                displayInput: "https://example.com",
                status: .networkUnavailable,
                durationSeconds: 0.3,
                success: false,
                sourceCount: 0
            )
        )
    )
    .padding()
}
