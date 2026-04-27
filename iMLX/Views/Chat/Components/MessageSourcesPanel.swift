import SwiftUI

/// Compact sources disclosure. Renders as a single pill ("Sources · 3") that
/// expands inline to show kind-grouped source rows.
struct MessageSourcesPanel: View {
    let sources: [MessageSource]
    let openSource: (URL?) -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclosureButton

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sources) { source in
                        SourceRowView(source: source) {
                            openSource(source.url)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var disclosureButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
            Haptics.selectionChanged()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(String(format: String.appLocalized("message.sources_count"), sources.count))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(.easeInOut(duration: 0.18), value: isExpanded)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: String.appLocalized("message.sources_count"), sources.count))
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityAddTraits(.isButton)
    }
}

private struct SourceRowView: View {
    let source: MessageSource
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: kindIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandPalette.accent)
                    .frame(width: 18, height: 18)
                    .padding(.top, 2)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    if !source.excerpt.isEmpty {
                        Text(source.excerpt)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if source.url != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(source.url == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(source.excerpt)")
        .accessibilityAddTraits(source.url != nil ? .isLink : [])
    }

    private var title: String {
        if let location = source.location, !location.isEmpty {
            return "\(source.title) · \(location)"
        }
        return source.title
    }

    private var kindIcon: String {
        switch source.kind {
        case .web: "globe"
        case .document: "doc.text"
        case .image: "photo"
        case .calendar: "calendar"
        }
    }
}

#Preview("Sources — collapsed") {
    MessageSourcesPanel(
        sources: [
            MessageSource(id: "1", kind: .document, title: "MANDATO GESTORIA", excerpt: "ALAN BELTRAN POZO 53321921D SEAT IBIZA 1,0 TSI 115CV…", location: "Page 1", url: nil, score: 0.9)
        ],
        openSource: { _ in }
    )
    .padding()
}
