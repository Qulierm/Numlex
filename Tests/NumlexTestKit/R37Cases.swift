import AppKit
import Foundation
import NumlexCore

/// r37: the pure source-answer hover outline geometry
/// (`AnswerBaseline.hoverOutline`) — the stroke drawn around the SOURCE
/// answer of a hovered token. The app-side hit-testing/bridge is UI
/// state (not exercised here, per the no-inflation rule); the baseline
/// math it feeds is the testable core.
public let r37Cases: [EngineCase] = [
    EngineCase("r37-hover-outline-ink-centerline") {
        // Fixed 28 pt row, natural glyph box 16.79, cap 11.42:
        // center = baseline − cap/2 (the shared caret/gutter ink rule),
        // height = one natural line box.
        let g = AnswerBaseline.hoverOutline(
            baseline: 28, rowHeight: 28, naturalHeight: 16.79, capHeight: 11.42)
        try expectClose(g.centerY, 28 - 11.42 / 2, 0.001,
                        "center is the answer's ink centerline")
        try expectEqual(g.centerY, CaretGeometry.inkCenter(baseline: 28, capHeight: 11.42),
                        "identical to the caret/gutter ink centerline")
        try expectEqual(g.height, 16.79, "one natural line box for a normal row")
    },
    EngineCase("r37-hover-outline-wrapped-row-one-line-height") {
        // A wrapped source block (60 pt tall) keeps a single-line-height
        // outline aligned to the centered answer — never a giant block.
        let g = AnswerBaseline.hoverOutline(
            baseline: 55, rowHeight: 60, naturalHeight: 24, capHeight: 15)
        try expectEqual(g.height, 24, "wrapped block keeps the single-line outline")
        try expectClose(g.centerY, 55 - 7.5, 0.001,
                        "center follows the measured answer baseline")
    },
    EngineCase("r37-hover-outline-clamped-to-row") {
        // A stretched/short row never yields an outline taller than it.
        let g = AnswerBaseline.hoverOutline(
            baseline: 10, rowHeight: 12, naturalHeight: 24, capHeight: 10)
        try expectEqual(g.height, 12, "height clamped to the row")
    },
    EngineCase("r37-hover-outline-degenerate-inputs") {
        let g = AnswerBaseline.hoverOutline(
            baseline: 0, rowHeight: 0, naturalHeight: 0, capHeight: 0)
        try expectEqual(g.height, 1, "degenerate height clamped to 1 pt")
        try expectEqual(g.centerY, 0, "center stays on the baseline")
    },
    EngineCase("r37-hover-outline-settings-font-sizes") {
        // The real 18/20/30 pt system faces (dynamic metrics, no
        // hardcoded constants): the outline is one line box, centered
        // on the row's ink centerline, at every settings size.
        for size in [18.0, 20.0, 30.0] {
            let f = NSFont.systemFont(ofSize: size)
            let natural = f.ascender - f.descender + f.leading
            let row = (size * 1.6).rounded()
            let baseline = AnswerBaseline.baseline(
                rowTop: 0, rowHeight: row, fragmentCount: 1,
                ascender: f.ascender, naturalHeight: natural, capHeight: f.capHeight)
            let g = AnswerBaseline.hoverOutline(
                baseline: baseline, rowHeight: row,
                naturalHeight: natural, capHeight: f.capHeight)
            try expectClose(g.centerY, baseline - f.capHeight / 2, 0.001,
                            "center = baseline − cap/2 at \(size) pt")
            try expectClose(g.height, min(natural, row), 0.001,
                            "height = min(natural line box, row) at \(size) pt")
            try expect(g.centerY - g.height / 2 > 0,
                       "outline top stays inside the row at \(size) pt")
            // The SAME centering rule the editor's token capsule uses
            // (ink centerline + natural line box) can descend ≤1 pt
            // past the row bottom (the cap center sits above the box
            // center) — parity with the capsule, not a defect.
            try expect(g.centerY + g.height / 2 <= row + 1.0,
                       "outline bottom stays on the row at \(size) pt")
        }
    }
]
