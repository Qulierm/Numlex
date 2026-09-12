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

    // MARK: geometry (the editor's existing numbers)

    /// The answer panel is a fixed 200 pt column.
    public static let panelWidth: CGFloat = 200
    /// Outer inset around the glass bubble on every side.
    public static let outerInset: CGFloat = 8
    /// The bubble's own horizontal padding.
    public static let innerPadding: CGFloat = 12
    /// The gap between the label and the value.
    public static let labelGap: CGFloat = 8
    /// A little air so the label disappears BEFORE it can collide or the
    /// value would be squeezed into truncation (subpixel rounding included).
    public static let safetyReserve: CGFloat = 2

    /// Full bubble width inside the panel (184 pt).
    public static var bubbleWidth: CGFloat { panelWidth - 2 * outerInset }
    /// Full content width inside the bubble (160 pt).
    public static var contentWidth: CGFloat { bubbleWidth - 2 * innerPadding }

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
    ///   - containerWidth: the answer panel's width (normally 200).
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
        // A hostile value width (NaN / infinite / negative) is treated as
        // UNKNOWN rather than zero: the footer then keeps the value's full
        // bubble and drops the label, so a bad measurement can never make the
        // two texts overlap.
        let valueIsKnown = valueWidth.isFinite && valueWidth > 0
        let value = valueIsKnown ? valueWidth : 0

        // The bubble never exceeds the panel, and the content never exceeds
        // the bubble: both are clamped so a hostile container can only
        // shrink the footer, never overflow it.
        let fullBubble = max(0, min(container - 2 * outerInset, bubbleWidth))
        let fullContent = max(0, fullBubble - 2 * innerPadding)

        // Expanded requires the label, its gap, the value AND the safety
        // reserve inside the full content width (so the switch happens one
        // step early instead of exactly at overlap).
        let needed = label + (label > 0 ? labelGap : 0) + value + safetyReserve
        let showsLabel = valueIsKnown && label > 0 && needed <= fullContent

        if showsLabel {
            return Result(showsLabel: true, bubbleWidth: fullBubble, contentWidth: fullContent)
        }
        // Compact: the bubble shrinks around the value itself, capped to the
        // full bubble so a very long value keeps the existing maximum width
        // and its one-line overflow behaviour.
        let compactContent = valueIsKnown ? min(value, fullContent) : fullContent
        // The compact bubble is the value plus its inner padding, but it can
        // never grow past what the container allows.
        let compactBubble = min(compactContent + 2 * innerPadding, fullBubble)
        return Result(showsLabel: false,
                      bubbleWidth: compactBubble,
                      contentWidth: min(compactContent, max(0, compactBubble - 2 * innerPadding)))
    }

    /// Non-finite and negative widths collapse to zero.
    private static func sanitized(_ value: CGFloat) -> CGFloat {
        guard value.isFinite, value > 0 else { return 0 }
        return value
    }
}
