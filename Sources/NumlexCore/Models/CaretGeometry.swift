import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Pure geometry shared by the notebook caret, the line-number gutter and
/// the tests. All coordinates are in TextKit CONTAINER space (the first
/// line fragment's top is y = 0); the editor adds the container inset to
/// convert to view coordinates. No AppKit types, so the exact same math
/// that draws the caret is what the test runner asserts on.
public enum CaretGeometry {
    /// Perceived caret thickness in points. Two points is the target
    /// weight at every scale (on 2x displays that is exactly 4 device
    /// pixels, so it is pixel aligned without any scale branching).
    public static let caretWidth: CGFloat = 2

    /// Synthetic fragment for a line that has no glyphs of its own:
    /// either the first line of an EMPTY document (top = 0) or the
    /// trailing empty line after a final newline (top = document height
    /// minus one fixed line height). The fixed paragraph min/max line
    /// height makes both fragments exactly `lineHeight` tall.
    public static func emptyLineFragment(top: CGFloat, lineHeight: CGFloat) -> CGRect {
        CGRect(x: 0, y: Swift.max(0, top), width: 0, height: Swift.max(lineHeight, 1))
    }

    /// Final insertion-point rect: `caretWidth` wide, pixel aligned (all
    /// edges rounded to the point grid), vertically centered on the SAME
    /// fragment midline the glyphs and gutter numbers use. The natural
    /// glyph height (ascender − descender + leading) is clamped to the
    /// fragment so a stretched line never shrinks the caret and the
    /// caret never outgrows its line.
    public static func caretRect(
        x: CGFloat,
        fragment: CGRect,
        containerInsetY: CGFloat,
        naturalGlyphHeight: CGFloat
    ) -> CGRect {
        let height = Swift.min(Swift.max(naturalGlyphHeight, 1), Swift.max(fragment.height, 1))
        let centerY = fragment.midY + containerInsetY
        let y = centerY - height / 2
        return CGRect(
            x: x.rounded(),
            y: y.rounded(),
            width: caretWidth,
            height: height.rounded()
        )
    }
}
