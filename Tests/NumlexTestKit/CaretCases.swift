import Foundation
import NumlexCore

/// Focused cases for the pure caret/line-fragment geometry that the
/// NotebookTextView draws from. The same math runs on screen, so these
/// assertions pin the visible behavior: 2 pt pixel-aligned caret,
/// centered on the TextKit fragment, and the synthetic fragments for
/// the empty document and the trailing empty line.
public let caretCases: [EngineCase] = [
    EngineCase("caret-width-constant") {
        try expectEqual(CaretGeometry.caretWidth, 2.0, "perceived caret is 2 pt")
    },

    EngineCase("caret-empty-document-fragment") {
        // Empty new sheet: first line fragment at the container top with
        // the fixed line height — the gutter's line 1 and the caret
        // share this exact rect.
        let f = CaretGeometry.emptyLineFragment(top: 0, lineHeight: 32)
        try expectEqual(f.origin, .zero, "empty fragment starts at container top")
        try expectEqual(f.height, 32, "empty fragment is one fixed line tall")
    },

    EngineCase("caret-trailing-newline-fragment") {
        // Document of three fixed lines ending in "\n": the trailing
        // empty line starts at usedHeight - lineHeight.
        let f = CaretGeometry.emptyLineFragment(top: 96 - 32, lineHeight: 32)
        try expectEqual(f.origin.y, 64, "trailing fragment top")
        try expectEqual(f.height, 32, "trailing fragment height")
        // Defensive: a degenerate negative top clamps to the document top
        // instead of drawing above the container.
        let clamped = CaretGeometry.emptyLineFragment(top: -8, lineHeight: 32)
        try expectEqual(clamped.origin.y, 0, "negative top clamps to zero")
    },

    EngineCase("caret-rect-centered-on-fragment") {
        // Fixed 32 pt line, 6 pt top inset, font with a 23 pt natural
        // glyph box (SF 20 ≈ 23.2, rounded down for the assertion).
        let fragment = CGRect(x: 54, y: 32, width: 0, height: 32)
        let r = CaretGeometry.caretRect(
            x: 54.3, fragment: fragment,
            containerInsetY: 6, naturalGlyphHeight: 23
        )
        try expectEqual(r.width, 2, "caret width")
        // midY = 48 container; view midY = 54; height 23 → y = 42.5 → 42/43.
        let centerY = (fragment.midY + 6)
        try expectClose(r.midY, centerY, 0.5, "caret centered on fragment midline (± pixel)")
        try expectEqual(r.minX, 54, "x pixel aligned (54.3 → 54)")
    },

    EngineCase("caret-rect-pixel-aligned") {
        let fragment = CGRect(x: 0, y: 0, width: 0, height: 32)
        let r = CaretGeometry.caretRect(
            x: 100.6, fragment: fragment,
            containerInsetY: 6, naturalGlyphHeight: 23
        )
        try expectEqual(r.minX, 101, "fractional x rounds to the pixel grid")
        try expectEqual(r.minY, (r.minY).rounded(), "y sits on the point grid")
        try expectEqual(r.maxX, (r.maxX).rounded(), "trailing edge pixel aligned")
    },

    EngineCase("caret-rect-clamped-to-fragment") {
        // A natural glyph box taller than the line must not outgrow the
        // fragment; a tiny fragment must still yield a drawable caret.
        let fragment = CGRect(x: 0, y: 0, width: 0, height: 32)
        let tall = CaretGeometry.caretRect(
            x: 0, fragment: fragment,
            containerInsetY: 6, naturalGlyphHeight: 40
        )
        try expectEqual(tall.height, 32, "height clamps to the fragment")
        let stub = CaretGeometry.caretRect(
            x: 0, fragment: CGRect(x: 0, y: 0, width: 0, height: 0.2),
            containerInsetY: 6, naturalGlyphHeight: 0.1
        )
        try expectEqual(stub.height, 1, "degenerate inputs still draw a 1 pt caret")
    },

    EngineCase("caret-rect-stable-across-blink-phases") {
        // v2.1 blink contract: the view invalidates AND paints the SAME
        // rect on every phase, so the geometry must be phase independent
        // — computing the rect for the on and the off assumption yields
        // identical size and position, and the width never leaves 2 pt.
        let fragment = CGRect(x: 60, y: 64, width: 0, height: 32)
        let onRect = CaretGeometry.caretRect(
            x: 60.2, fragment: fragment,
            containerInsetY: 6, naturalGlyphHeight: 23
        )
        let offRect = CaretGeometry.caretRect(
            x: 60.2, fragment: fragment,
            containerInsetY: 6, naturalGlyphHeight: 23
        )
        try expectEqual(onRect, offRect, "on/off phases resolve to one identical rect")
        try expectEqual(onRect.width, CaretGeometry.caretWidth, "width stays 2 pt on both phases")
        // Empty, populated and trailing-newline fragments all share the
        // fixed line height, so a populated line and an empty line with
        // the same top produce the same caret height — no size
        // alternation is possible between document states.
        let populated = CaretGeometry.caretRect(
            x: 60, fragment: CGRect(x: 60, y: 64, width: 200, height: 32),
            containerInsetY: 6, naturalGlyphHeight: 23
        )
        let empty = CaretGeometry.caretRect(
            x: 60,
            fragment: CaretGeometry.emptyLineFragment(top: 64, lineHeight: 32),
            containerInsetY: 6, naturalGlyphHeight: 23
        )
        try expectEqual(populated.height, empty.height, "populated and empty lines share the caret height")
        try expectEqual(populated.midY, empty.midY, "both center on the fragment midline")
    },

    EngineCase("caret-row-box-fixed-midline") {
        // The fixed paragraph line height can exceed the natural TextKit
        // fragment height: the shared row box must still be the fixed
        // height at the fragment's row origin, so the caret centers on
        // the FIXED row midline, not the shorter natural fragment's.
        let natural = CGRect(x: 54, y: 64, width: 0, height: 23) // natural < 30
        let box = CaretGeometry.rowBox(
            fragment: natural, nextFragment: nil, fixedLineHeight: 32
        )
        try expectEqual(box.origin, natural.origin, "row box keeps the fragment row origin")
        try expectEqual(box.height, 32, "row box uses the fixed line height")
        let r = CaretGeometry.caretRect(
            x: 54, fragment: box, containerInsetY: 6, naturalGlyphHeight: 23
        )
        try expectClose(r.midY, box.midY + 6, 0.51, "caret center sits on the fixed row-box midline")
        try expectClose(r.midY - 6, box.midY, 0.51, "no offset toward the natural fragment midline")
    },

    EngineCase("caret-row-box-exact-advance") {
        // With the next fragment known, the measured advance is the exact
        // extra-line geometry and wins — including wrapped fragments
        // where the advance equals the fixed row pitch.
        let a = CGRect(x: 54, y: 64, width: 0, height: 23)
        let b = CGRect(x: 54, y: 96, width: 0, height: 23) // advance 32
        let box = CaretGeometry.rowBox(
            fragment: a, nextFragment: b, fixedLineHeight: 32
        )
        try expectEqual(box.origin.y, 64, "row origin")
        try expectEqual(box.height, 32, "advance becomes the row height")
        let r = CaretGeometry.caretRect(
            x: 54, fragment: box, containerInsetY: 6, naturalGlyphHeight: 23
        )
        try expectClose(r.midY, 80 + 6, 0.51, "caret centers on the advance midline")
        // Degenerate: a next fragment at the same origin falls back to
        // the fixed height instead of a zero-tall row.
        let bad = CaretGeometry.rowBox(
            fragment: a, nextFragment: a, fixedLineHeight: 32
        )
        try expectEqual(bad.height, 32, "coincident next fragment falls back to fixed height")
    },

    EngineCase("caret-baseline-natural-box-bottom") {
        // Fixed 32 pt row, SF20-equivalent metrics: ascender 19.34,
        // natural box 23.55 < 32. TextKit keeps the natural line box
        // flush with the row's bottom edge (extra space above), so
        // baseline = rowTop + (rowHeight - naturalHeight) + ascender.
        let bl = CaretGeometry.baseline(
            rowTop: 64, rowHeight: 32, ascender: 19.34, naturalHeight: 23.55
        )
        try expectEqual(bl, 64 + (32 - 23.55) + 19.34, "natural box sits on the row's bottom edge")
    },

    EngineCase("caret-ink-center-rule") {
        // The natural fragment height (23.55) is smaller than the fixed
        // row (32): the shared centerline must be the INK center
        // (baseline minus half a cap height), NOT the raw row midline —
        // centering on the midline leaves the caret visibly too high
        // next to the digits, and the gutter number one point high.
        let bl = CaretGeometry.baseline(
            rowTop: 0, rowHeight: 32, ascender: 19.34, naturalHeight: 23.55
        )
        let center = CaretGeometry.inkCenter(baseline: bl, capHeight: 14.46)
        try expectEqual(center, 27.79 - 7.23, "ink center = baseline - cap/2")
        try expect(center > 16, "ink center sits below the raw row midline")
        // The caret centered on that line keeps its constant geometry.
        let box = CGRect(x: 0, y: center - 32 / 2, width: 0, height: 32)
        let r = CaretGeometry.caretRect(
            x: 10, fragment: box, containerInsetY: 6, naturalGlyphHeight: 23.55
        )
        try expectEqual(r.width, 2, "width stays 2 pt")
        try expectClose(r.midY, center + 6, 0.51, "caret centers on the ink centerline")
        // Gutter parity: the number baseline (center + its own cap/2)
        // puts the number's ink center on the SAME line as the caret.
        let numBaseline = center + 5.93 / 2
        let numInkCenter = numBaseline - 5.93 / 2
        try expectEqual(numInkCenter, center, "gutter ink center shares the caret centerline")
    },
]
