import Foundation
import CoreGraphics

/// The bottom Total bar's layout: the footer shows the localized label beside
/// the value while both fit, and collapses to a trailing value-only bubble
/// when the value would otherwise collide with the label.
///
/// Pure and deterministic: the caller supplies ACTUAL measured text widths
/// (AppKit metrics), and this type only decides which mode applies and how
/// wide the glass bubble has to be. Nothing here aggregates, formats or
/// rounds the value — the Total's number semantics are unchanged.
public enum FooterTotalLayout {

    // MARK: geometry (the answer column's footer design numbers)

    /// Default-width compatibility constant ONLY: the legacy fixed panel
    /// width. The column is user-adjustable (140...400 pt, see
    /// `AnswerColumnGeometry`); runtime layout ALWAYS receives the
    /// actual container width and never reads this value. Kept for
    /// tests of the 200 pt default behavior.
    public static let panelWidth: CGFloat = AnswerColumnGeometry.defaultWidth
    /// Outer inset around the glass bubble on every side.
    public static let outerInset: CGFloat = 8
    /// The bubble's own horizontal padding.
    public static let innerPadding: CGFloat = 12
    /// The gap between the label and the value.
    public static let labelGap: CGFloat = 8
    /// The collision-safety reserve: on top of the VISUAL separation the
    /// `labelGap` (8 pt) already provides, the pair must still leave this
    /// much room inside the content width. It is deliberately small (2 pt)
    /// and is NOT a design preference: it only covers subpixel rounding and
    /// antialiasing slack on the measured widths. The label therefore stays
    /// visible until the measured label + gap + value genuinely reaches the
    /// content edge, instead of disappearing while a large empty gap remains.
    /// The caller's widths are already pixel-safe (`ceil(width) + 0.5` in the
    /// view), so this is the final margin, not the separation itself.
    public static let safetyReserve: CGFloat = 2

    /// Default-width compatibility value ONLY: the full bubble width of
    /// the legacy 200 pt column (184 pt). Runtime code derives the
    /// bubble from the ACTUAL container width; tests use this to assert
    /// the 200 pt default geometry.
    public static var bubbleWidth: CGFloat { panelWidth - 2 * outerInset }
    /// Default-width compatibility value ONLY: the full content width of
    /// the legacy 200 pt column (160 pt); see `bubbleWidth`.
    public static var contentWidth: CGFloat { bubbleWidth - 2 * innerPadding }

    /// Both mode ENDPOINT geometries for one measurement.
    ///
    /// The footer's animated transition interpolates between these two, so the
    /// caller needs them independently of which mode currently wins: the live
    /// endpoints keep following the cursor while a separate animation progress
    /// advances. `layout` is expressed in terms of this pair, so the fit
    /// decision and the endpoints can never drift apart.
    public struct ModeGeometry: Equatable, Sendable {
        /// The geometry while the label is drawn beside the value.
        public let expanded: Result
        /// The geometry while only the value is drawn.
        public let compact: Result
        public init(expanded: Result, compact: Result) {
            self.expanded = expanded
            self.compact = compact
        }
        /// The endpoint for a mode.
        public func endpoint(showsLabel: Bool) -> Result {
            showsLabel ? expanded : compact
        }
    }

    public struct Result: Equatable, Sendable {
        /// True while the label is drawn beside the value.
        public let showsLabel: Bool
        /// The glass bubble's outer width for this mode.
        public let bubbleWidth: CGFloat
        /// The content width available to the label + gap + value.
        public let contentWidth: CGFloat
    }

    /// Decides the footer mode for one measurement.
    ///
    /// - Parameters:
    ///   - containerWidth: the answer column's ACTUAL width (the
    ///     adjusted width; the 200 pt default reproduces the legacy
    ///     geometry exactly).
    ///   - labelWidth: the measured width of the localized `total` label.
    ///   - valueWidth: the measured width of the formatted Total value.
    /// - Returns: the mode plus the widths the caller should lay out with.
    ///   Hostile input (NaN, infinity, negatives, a zero/negative container)
    ///   is clamped rather than propagated into the view geometry.
    public static func layout(containerWidth: CGFloat,
                              labelWidth: CGFloat,
                              valueWidth: CGFloat) -> Result {
        let container = sanitized(containerWidth)
        let label = sanitized(labelWidth)
        let geometry = modeGeometry(containerWidth: container, valueWidth: valueWidth)
        // Expanded requires the label, its gap, the value AND the small
        // safety reserve inside the full content width. The reserve is only
        // collision/subpixel protection on top of the 8 pt visual gap, so the
        // label survives right up to the measured boundary.
        let valueIsKnown = valueWidth.isFinite && valueWidth > 0
        let value = valueIsKnown ? valueWidth : 0
        let needed = label + (label > 0 ? labelGap : 0) + value + safetyReserve
        let showsLabel = valueIsKnown && label > 0 && needed <= geometry.expanded.contentWidth
        return geometry.endpoint(showsLabel: showsLabel)
    }

    /// The two mode endpoint geometries for one measurement, sanitized and
    /// clamped exactly once.
    ///
    /// This is the ONLY place the footer's widths are derived, so the fit
    /// decision in `layout` and the animated transition between the endpoints
    /// share one formula. The caller passes the CURRENT container and value
    /// measurements; a hostile value width (NaN / infinite / negative) is
    /// treated as UNKNOWN rather than zero — the compact endpoint then keeps
    /// the value's full bubble so a bad measurement can never make the two
    /// texts overlap — and a hostile container can only shrink the footer.
    public static func modeGeometry(containerWidth: CGFloat,
                                    valueWidth: CGFloat) -> ModeGeometry {
        let container = sanitized(containerWidth)
        let valueIsKnown = valueWidth.isFinite && valueWidth > 0
        let value = valueIsKnown ? valueWidth : 0

        // The bubble never exceeds the ACTUAL panel (the adjusted column
        // width) and the content never exceeds the bubble: both are
        // clamped so a hostile container can only shrink the footer,
        // never overflow it.
        let fullBubble = max(0, container - 2 * outerInset)
        let fullContent = max(0, fullBubble - 2 * innerPadding)

        let expanded = Result(showsLabel: true,
                              bubbleWidth: fullBubble,
                              contentWidth: fullContent)
        // Compact: the bubble shrinks around the value itself, capped to the
        // full bubble so a very long value keeps the existing maximum width
        // and its one-line overflow behaviour.
        let compactContent = valueIsKnown ? min(value, fullContent) : fullContent
        // The compact bubble is the value plus its inner padding, but it can
        // never grow past what the container allows.
        let compactBubble = min(compactContent + 2 * innerPadding, fullBubble)
        let compact = Result(showsLabel: false,
                             bubbleWidth: compactBubble,
                             contentWidth: min(compactContent, max(0, compactBubble - 2 * innerPadding)))
        return ModeGeometry(expanded: expanded, compact: compact)
    }

    /// Non-finite and negative widths collapse to zero.
    private static func sanitized(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }
}
