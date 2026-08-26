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

    /// Shared visual ROW BOX: the fragment's row origin (its container
    /// y) with the configured FIXED line height. TextKit's natural
    /// `lineFragmentRect` can be shorter than the fixed paragraph line
    /// height, so centering on the natural fragment midline sits the
    /// caret and the gutter number too high. The row box is the exact
    /// vertical span the glyphs visually occupy: when the next fragment
    /// is known, its measured advance (exact TextKit extra-line
    /// geometry) wins; otherwise the configured fixed line height does.
    /// The SAME box centers both the custom caret and the gutter
    /// baseline for empty, populated, end-of-text, trailing-newline and
    /// wrapped visual fragments alike.
    public static func rowBox(
        fragment: CGRect,
        nextFragment: CGRect?,
        fixedLineHeight: CGFloat
    ) -> CGRect {
        let height: CGFloat
        if let next = nextFragment, next.minY > fragment.minY {
            height = next.minY - fragment.minY
        } else {
            height = Swift.max(fixedLineHeight, fragment.height, 1)
        }
        return CGRect(x: fragment.minX, y: fragment.minY, width: 0, height: height)
    }

    /// Baseline of a FIXED-height row: TextKit keeps the natural line
    /// box (ascender − descender + leading) flush with the row's bottom
    /// edge — the extra space above it is `rowHeight - naturalHeight` —
    /// so `baseline = rowTop + (rowHeight - naturalHeight) + ascender`.
    /// Verified against the drawn glyph ink: the digits' baseline lands
    /// exactly here (a plain `rowTop + rowHeight - descender` is off by
    /// the leading and lands several points below the row).
    public static func baseline(
        rowTop: CGFloat,
        rowHeight: CGFloat,
        ascender: CGFloat,
        naturalHeight: CGFloat
    ) -> CGFloat {
        rowTop + (rowHeight - naturalHeight) + ascender
    }

    /// Visual center of a line's numeric ink: half a cap height above
    /// the baseline. This is the ONE centerline the large custom caret
    /// and the gutter number share — the fragment midline itself sits
    /// several points too high because the fixed row's extra space is
    /// taken from above the natural line box.
    public static func inkCenter(
        baseline: CGFloat,
        capHeight: CGFloat
    ) -> CGFloat {
        baseline - capHeight / 2
    }

    /// Answer-token capsule height: the font's MEASURED natural line
    /// box (ascender − descender + leading), clamped to the configured
    /// row height. One constant badge size at every scale (≈23 pt at
    /// the 20 pt system font — the reference design's height), never
    /// taller than its row, never a fraction of the line height.
    public static func tokenCapsuleHeight(
        naturalHeight: CGFloat,
        rowHeight: CGFloat
    ) -> CGFloat {
        Swift.min(Swift.max(naturalHeight, 1), Swift.max(rowHeight, 1))
    }

    /// The answer-token capsule inside one row, sharing the row's
    /// baseline and ink centerline with the caret and the gutter.
    /// `rowTop`/`rowHeight` must be the marker's ACTUAL row box (see
    /// rowBox) in the same coordinate space the caret and gutter draw
    /// in. The label baseline is the row baseline (the same rule the
    /// editor's own glyphs sit on) and the capsule is centered on the
    /// row's ink centerline — the ONE shared visual center. The corner
    /// radius is 20% of the capsule height, measured from the reference
    /// design (no hand-tuned offset anywhere: everything derives from
    /// rowBox + baseline + inkCenter).
    public static func tokenCapsule(
        rowTop: CGFloat,
        rowHeight: CGFloat,
        ascender: CGFloat,
        naturalHeight: CGFloat,
        capHeight: CGFloat,
        x: CGFloat,
        width: CGFloat
    ) -> (rect: CGRect, labelBaseline: CGFloat, cornerRadius: CGFloat) {
        let baseline = CaretGeometry.baseline(
            rowTop: rowTop, rowHeight: rowHeight,
            ascender: ascender, naturalHeight: naturalHeight
        )
        let center = CaretGeometry.inkCenter(baseline: baseline, capHeight: capHeight)
        let height = CaretGeometry.tokenCapsuleHeight(
            naturalHeight: naturalHeight, rowHeight: rowHeight
        )
        return (
            CGRect(x: x, y: center - height / 2, width: width, height: height),
            baseline,
            height * 0.20
        )
    }

    /// Final insertion-point rect: `caretWidth` wide, pixel aligned (all
    /// edges rounded to the point grid), vertically centered on the rect
    /// passed in — the editor passes a row box whose midline IS the
    /// ink centerline (see rowBox, baseline, inkCenter) so the caret
    /// and the gutter numbers share one center. The natural glyph
    /// height (ascender − descender + leading) is clamped to the box so
    /// a stretched line never shrinks the caret and the caret never
    /// outgrows its line.
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
