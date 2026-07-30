import SwiftUI

/// Shared layout values for chat content.
///
/// Inline chat content is deliberately surface-less: activity rows, sources, and
/// answers all align to a single left gutter so the transcript reads as one
/// column of text instead of a stack of floating cards. These constants keep
/// that alignment consistent across the components that make it up.
enum ChatMetrics {
    /// Width of the leading symbol/spinner column in activity rows. The hairline
    /// rule and every expanded body indent to the center of this column.
    static let gutterWidth: CGFloat = 20

    /// Horizontal gap between the gutter and its row label.
    static let gutterSpacing: CGFloat = 8

    /// Leading inset applied to content that indents under a gutter row.
    static var gutterIndent: CGFloat { gutterWidth + gutterSpacing }

    /// Vertical spacing between consecutive activity rows.
    static let activityRowSpacing: CGFloat = 6

    /// Vertical spacing between the activity region, the answer, and sources.
    static let messageSectionSpacing: CGFloat = 12

    /// Corner radius for the user message bubble.
    static let bubbleCornerRadius: CGFloat = 18

    /// Corner radius for small inline chips such as attachments.
    static let chipCornerRadius: CGFloat = 10

    /// Fill used behind the user message bubble and inline chips.
    static let inlineFillOpacity: Double = 0.12

    /// Opacity for hand-drawn hairline rules, matching a system separator.
    static let hairlineOpacity: Double = 0.22
}
