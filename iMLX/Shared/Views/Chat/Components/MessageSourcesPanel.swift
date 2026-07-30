import SwiftUI

/// Sources disclosure rendered below a finalized answer.
///
/// A plain text header expands into hairline-separated rows. Web sources lead
/// with their domain so the list scans like a citation list rather than a stack
/// of cards; nothing here draws a background or capsule.
struct MessageSourcesPanel: View {
    let sources: [MessageSource]
    let openSource: (URL?) -> Void

    @State private var isExpanded: Bool = false
    @State private var hapticSelectionTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: ChatMetrics.activityRowSpacing) {
            ActivityRow(
                leading: .symbol("text.quote", tint: .secondary),
                label: String(
                    format: String.appLocalized("message.sources_count"),
                    sources.count
                ),
                trailing: nil,
                disclosure: ActivityDisclosure(isExpanded: isExpanded) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                    hapticSelectionTrigger += 1
                }
            )
            .accessibilityLabel(
                String(format: String.appLocalized("message.sources_count"), sources.count)
            )
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

            if isExpanded {
                ActivityDetailBody {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                            if index > 0 {
                                Divider()
                            }
                            SourceRowView(source: source) {
                                openSource(source.url)
                            }
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .sensoryFeedback(.selection, trigger: hapticSelectionTrigger)
    }
}

private struct SourceRowView: View {
    let source: MessageSource
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: kindIcon)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)

                    Text(provenance)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if source.url != nil {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }

                    Spacer(minLength: 0)
                }

                Text(source.title)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                if !source.excerpt.isEmpty {
                    Text(source.excerpt)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(source.url == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(source.title). \(provenance)")
        .accessibilityAddTraits(source.url != nil ? .isLink : [])
    }

    /// Where the source came from: a host for web results, otherwise the
    /// in-document location such as a page number.
    private var provenance: String {
        if let host = source.url?.host()?.replacingOccurrences(of: "www.", with: ""), !host.isEmpty {
            if let location = source.location, !location.isEmpty {
                return "\(host) · \(location)"
            }
            return host
        }
        if let location = source.location, !location.isEmpty {
            return location
        }
        return kindLabel
    }

    private var kindLabel: String {
        switch source.kind {
        case .web: "Web"
        case .document: "Document"
        case .image: "Image"
        case .calendar: "Calendar"
        case .reminder: "Reminder"
        case .contact: "Contact"
        }
    }

    private var kindIcon: String {
        switch source.kind {
        case .web: "globe"
        case .document: "doc.text"
        case .image: "photo"
        case .calendar: "calendar"
        case .reminder: "checklist"
        case .contact: "person.crop.circle"
        }
    }
}

#Preview("Sources") {
    MessageSourcesPanel(
        sources: [
            MessageSource(
                id: "1",
                kind: .web,
                title: "20 Tallest Buildings in the World 2026",
                excerpt: "Merdeka 118 standard height and total height figures.",
                location: nil,
                url: URL(string: "https://www.thetowerinfo.com/tallest"),
                score: 0.9
            ),
            MessageSource(
                id: "2",
                kind: .document,
                title: "MANDATO GESTORIA",
                excerpt: "ALAN BELTRAN POZO SEAT IBIZA 1,0 TSI 115CV",
                location: "Page 1",
                url: nil,
                score: 0.7
            )
        ],
        openSource: { _ in }
    )
    .padding()
}
