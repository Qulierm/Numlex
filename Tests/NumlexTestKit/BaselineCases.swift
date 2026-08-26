import AppKit
import Foundation
import NumlexCore

/// Real system-font metrics at a size, used as DYNAMIC input for the pure
/// baseline geometry (no hardcoded metric constants in the assertions):
/// the same NSFont the editor draws regular lines and answer values with.
private func fontMetrics(_ size: Double) -> (ascender: Double, natural: Double, cap: Double) {
    let f = NSFont.systemFont(ofSize: size)
    return (f.ascender, f.ascender - f.descender + f.leading, f.capHeight)
}

/// The settings line height for a font size (round(size × 1.6), the exact
/// AppSettings rule).
private func lineHeight(_ size: Double) -> Double { (size * 1.6).rounded() }

/// Pure baseline-geometry cases for `AnswerBaseline` (the rule the
/// coordinator bakes into `LineMetrics.Line.answerBaseline`), the
/// indexed row placement on top of it, and the strict one-line-per-source
/// contract states: single line, heading before the answer, multiple
/// blanks/comments, trailing newline, missing-metrics fallback, wrapped
/// 2/3 fragment blocks, source indexes, and the settings font sizes
/// 18/20/30 with dynamic font metrics.
public let baselineCases: [EngineCase] = [
    // MARK: Pure formula pins (synthetic metrics)

    EngineCase("baseline-single-fragment-formula") {
        // Fixed 28 pt row, natural glyph box 16.79, ascender 13.29:
        // baseline = rowTop + (rowHeight − naturalHeight) + ascender.
        let b = AnswerBaseline.baseline(
            rowTop: 40, rowHeight: 28, fragmentCount: 1,
            ascender: 13.29, naturalHeight: 16.79, capHeight: 11.42
        )
        try expectClose(b, 64.5, 0.001, "single fragment = CaretGeometry.baseline rule")
        try expectEqual(b, CaretGeometry.baseline(
            rowTop: 40, rowHeight: 28, ascender: 13.29, naturalHeight: 16.79
        ), "identical to the caret/gutter rule")
    },

    EngineCase("baseline-wrapped-fragment-formula") {
        // Two 28 pt fragments (56 pt block) starting at rowTop 28,
        // cap height 11.42: the answer ink center is centered across the
        // whole block → baseline = blockCenter + capHeight/2.
        let b = AnswerBaseline.baseline(
            rowTop: 28, rowHeight: 56, fragmentCount: 2,
            ascender: 13.29, naturalHeight: 16.79, capHeight: 11.42
        )
        try expectClose(b, 28 + 28 + 5.71, 0.001, "wrapped = block center + half cap")
        // Ink center (baseline − capHeight/2) is exactly the block center.
        try expectClose(b - 5.71, 28 + 28, 0.001, "ink center centered across the block")
    },

    EngineCase("baseline-wrapped-three-fragments") {
        // Three 32 pt fragments (96 pt block) from the container top.
        let b = AnswerBaseline.baseline(
            rowTop: 0, rowHeight: 96, fragmentCount: 3,
            ascender: 19.04, naturalHeight: 23.24, capHeight: 14.06
        )
        try expectClose(b, 48 + 7.03, 0.001, "block center 48 + half cap")
        try expectClose(b - 7.03, 48, 0.001, "ink center at block center")
    },

    EngineCase("baseline-missing-metrics-fallback") {
        // Defensive: no fragments (0) — and a degenerate zero-height row —
        // both fall back to the single-fragment rule with the row clamped.
        let m = AnswerBaseline.baseline(
            rowTop: 64, rowHeight: 32, fragmentCount: 0,
            ascender: 13.29, naturalHeight: 16.79, capHeight: 11.42
        )
        try expectEqual(m, CaretGeometry.baseline(
            rowTop: 64, rowHeight: 32, ascender: 13.29, naturalHeight: 16.79
        ), "count 0 uses the single-fragment rule")
        let degenerate = AnswerBaseline.baseline(
            rowTop: 0, rowHeight: 0, fragmentCount: 1,
            ascender: 13.29, naturalHeight: 16.79, capHeight: 11.42
        )
        try expectEqual(degenerate, CaretGeometry.baseline(
            rowTop: 0, rowHeight: 1, ascender: 13.29, naturalHeight: 16.79
        ), "zero height clamps to 1")
    },

    // MARK: Settings font sizes with dynamic metrics

    EngineCase("baseline-settings-sizes-18-20-30") {
        // Every settings level: the single-line answer baseline sits on the
        // editor glyph baseline (same rule as caret/gutter), inside the
        // fixed row, below the row midline.
        var previous: Double?
        for size in [18.0, 20.0, 30.0] {
            let m = fontMetrics(size)
            let lh = lineHeight(size)
            let b = AnswerBaseline.baseline(
                rowTop: 0, rowHeight: lh, fragmentCount: 1,
                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap
            )
            try expectEqual(b, CaretGeometry.baseline(
                rowTop: 0, rowHeight: lh, ascender: m.ascender, naturalHeight: m.natural
            ), "size \(Int(size)): baseline = source glyph baseline")
            try expect(b > 0 && b < lh, "size \(Int(size)): baseline inside the row")
            try expect(b > lh / 2, "size \(Int(size)): baseline below the midline")
            try expect(b - lh / 2 < m.cap, "size \(Int(size)): ink fits the row")
            if let p = previous {
                try expect(b > p, "baseline grows with the font size")
            }
            previous = b
        }
    },

    EngineCase("baseline-settings-sizes-wrapped-blocks") {
        // Wrapped blocks at every settings level keep the centered-ink
        // semantic with the real cap height of the real font.
        for size in [18.0, 20.0, 30.0] {
            let m = fontMetrics(size)
            let lh = lineHeight(size)
            for fragments in [2, 3] {
                let b = AnswerBaseline.baseline(
                    rowTop: lh, rowHeight: lh * CGFloat(fragments),
                    fragmentCount: fragments,
                    ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap
                )
                let blockCenter = lh + (lh * CGFloat(fragments)) / 2
                try expectClose(b - m.cap / 2, blockCenter, 0.001,
                                "size \(Int(size)) × \(fragments): ink center at block center")
            }
        }
    },

    // MARK: Indexed rows + baselines (sheet contract states)

    EngineCase("baseline-repro-sheet-heading-before-answer") {
        // The exact user repro: `# Heading\nx = 5\nx + 1\n10 km to meter`.
        // The heading keeps source line 0; every answer binds to its own
        // line index, and each line's answer baseline is the single-
        // fragment glyph baseline of THAT line's block.
        let content = "# Heading\nx = 5\nx + 1\n10 km to meter"
        var vars: [String: Double] = [:]
        let rows = evaluateSheet(content, variables: &vars, rates: Rates(), decimalPlaces: 7)
        let m = fontMetrics(20)
        let lh = lineHeight(20)
        let expected: [LineResult] = [
            .blank,
            .variable(name: "x", value: 5),
            .number(value: 6, unit: nil),
            .number(value: 10_000, unit: "meters"),
        ]
        try expectEqual(rows.count, 4, "one line per logical source line")
        try expectEqual(rows.map { $0.result }, expected, "results on their own lines")
        try expectEqual(rows.map { $0.sourceLineIndex }, [0, 1, 2, 3], "identity indexes")
        // Measured metrics at the fixed rhythm with the real font.
        let lines = (0..<4).map { i in
            LineMetrics.Line(
                index: i,
                top: lh * CGFloat(i),
                height: lh,
                fragmentCount: 1,
                answerBaseline: AnswerBaseline.baseline(
                    rowTop: lh * CGFloat(i), rowHeight: lh, fragmentCount: 1,
                    ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap
                )
            )
        }
        for i in [1, 2, 3] {
            let row = NotebookLayout.answerRow(index: i, lines: lines, topInset: 6)
            try expectEqual(row.top, 6 + lh * CGFloat(i), "row \(i) top")
            let offset = lines[i].answerBaseline - lines[i].top
            try expectEqual(offset, CaretGeometry.baseline(
                rowTop: 0, rowHeight: lh, ascender: m.ascender, naturalHeight: m.natural
            ), "row \(i) baseline offset = glyph baseline offset")
        }
    },

    EngineCase("baseline-multiple-blanks-and-comments") {
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("# H\n\n// T\n# G\n5", variables: &vars,
                                 rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.map { $0.result },
                        [.blank, .blank, .title("T"), .blank, .number(value: 5, unit: nil)],
                        "heading, blank, title, heading, value")
        try expectEqual(rows.map { $0.sourceLineIndex }, [0, 1, 2, 3, 4])
        // The value's line (4) binds its answer to the block that starts
        // after all four hidden rows — never to the first visible row.
        let lh = 32.0
        let lines = (0..<5).map { i in
            LineMetrics.Line(index: i, top: lh * CGFloat(i), height: lh, fragmentCount: 1)
        }
        let row = NotebookLayout.answerRow(index: 4, lines: lines, topInset: 6)
        try expectEqual(row.top, 6 + lh * 4, "value answer after four hidden rows")
    },

    EngineCase("baseline-trailing-newline-row") {
        // "x = 5\n" has a trailing empty logical line: one row each, and
        // the synthesized trailing row carries a real single-fragment
        // baseline (the same rule the gutter's trailing number uses).
        var vars: [String: Double] = [:]
        let rows = evaluateSheet("x = 5\n", variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.count, 2)
        try expectEqual(rows[1].result, LineResult.blank, "trailing line is blank")
        try expectEqual(rows[1].sourceLineIndex, 1)
        let m = fontMetrics(20)
        let lh = lineHeight(20)
        let trailing = AnswerBaseline.baseline(
            rowTop: lh, rowHeight: lh, fragmentCount: 0,
            ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap
        )
        try expectEqual(trailing, CaretGeometry.baseline(
            rowTop: lh, rowHeight: lh, ascender: m.ascender, naturalHeight: m.natural
        ), "trailing blank baseline = glyph baseline of that row")
    },

    EngineCase("baseline-wrapped-line-answer-uses-block-baseline") {
        // A logical line wrapped to two fragments: its answer baseline is
        // the block-centered ink baseline, and the NEXT line's answer
        // starts below the full block.
        let m = fontMetrics(20)
        let lh = lineHeight(20)
        let lines = [
            LineMetrics.Line(index: 0, top: 0, height: lh, fragmentCount: 1,
                             answerBaseline: AnswerBaseline.baseline(
                                rowTop: 0, rowHeight: lh, fragmentCount: 1,
                                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap)),
            LineMetrics.Line(index: 1, top: lh, height: lh * 2, fragmentCount: 2,
                             answerBaseline: AnswerBaseline.baseline(
                                rowTop: lh, rowHeight: lh * 2, fragmentCount: 2,
                                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap)),
            LineMetrics.Line(index: 2, top: lh * 3, height: lh, fragmentCount: 1,
                             answerBaseline: AnswerBaseline.baseline(
                                rowTop: lh * 3, rowHeight: lh, fragmentCount: 1,
                                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap)),
        ]
        let wrapped = NotebookLayout.answerRow(index: 1, lines: lines, topInset: 6)
        try expectEqual(wrapped.height, lh * 2, "wrapped block keeps full height")
        let wrappedOffset = lines[1].answerBaseline - lines[1].top
        try expectEqual(wrappedOffset, lh + m.cap / 2, "wrapped baseline centered on the block")
        let next = NotebookLayout.answerRow(index: 2, lines: lines, topInset: 6)
        try expectEqual(next.top, 6 + lh * 3, "next line starts below the full block")
    },

    EngineCase("baseline-missing-metric-row-falls-back-per-row") {
        // Defensive: a source index beyond the measured metrics continues
        // the last block's rhythm (NotebookLayout.answerRow) and the
        // single-fragment baseline rule applies to the synthesized row.
        let m = fontMetrics(20)
        let lh = lineHeight(20)
        let lines = [
            LineMetrics.Line(index: 0, top: 0, height: lh, fragmentCount: 1,
                             answerBaseline: AnswerBaseline.baseline(
                                rowTop: 0, rowHeight: lh, fragmentCount: 1,
                                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap)),
            LineMetrics.Line(index: 1, top: lh, height: lh, fragmentCount: 1,
                             answerBaseline: AnswerBaseline.baseline(
                                rowTop: lh, rowHeight: lh, fragmentCount: 1,
                                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap)),
        ]
        let synthetic = NotebookLayout.answerRow(index: 2, lines: lines, topInset: 6)
        try expectEqual(synthetic.top, 6 + lh * 2, "synthesized row continues the rhythm")
        let fallback = AnswerBaseline.baseline(
            rowTop: 0, rowHeight: synthetic.height, fragmentCount: 1,
            ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap
        )
        try expectEqual(fallback, CaretGeometry.baseline(
            rowTop: 0, rowHeight: synthetic.height,
            ascender: m.ascender, naturalHeight: m.natural
        ), "fallback row uses the single-fragment rule")
    },

    EngineCase("baseline-source-index-binding-through-hidden-rows") {
        // End-to-end binding: evaluateSheet indexes + metrics placement +
        // baseline offset, with a wrapped expression and hidden rows.
        let content = "long = 1\nlong * long\n\n5 + 5"
        var vars: [String: Double] = [:]
        let rows = evaluateSheet(content, variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(rows.map { $0.sourceLineIndex }, [0, 1, 2, 3])
        let m = fontMetrics(20)
        let lh = lineHeight(20)
        // Line 1 wraps to two fragments in the simulated metrics.
        let lines = [
            LineMetrics.Line(index: 0, top: 0, height: lh, fragmentCount: 1,
                             answerBaseline: AnswerBaseline.baseline(
                                rowTop: 0, rowHeight: lh, fragmentCount: 1,
                                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap)),
            LineMetrics.Line(index: 1, top: lh, height: lh * 2, fragmentCount: 2,
                             answerBaseline: AnswerBaseline.baseline(
                                rowTop: lh, rowHeight: lh * 2, fragmentCount: 2,
                                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap)),
            LineMetrics.Line(index: 2, top: lh * 3, height: lh, fragmentCount: 0,
                             answerBaseline: AnswerBaseline.baseline(
                                rowTop: lh * 3, rowHeight: lh, fragmentCount: 0,
                                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap)),
            LineMetrics.Line(index: 3, top: lh * 4, height: lh, fragmentCount: 1,
                             answerBaseline: AnswerBaseline.baseline(
                                rowTop: lh * 4, rowHeight: lh, fragmentCount: 1,
                                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap)),
        ]
        // The blank row (index 2) still holds the space: the "5 + 5"
        // answer sits on the block at top 4×lh, not on the blank's.
        let row3 = NotebookLayout.answerRow(index: 3, lines: lines, topInset: 6)
        try expectEqual(row3.top, 6 + lh * 4, "value keeps its block after the blank")
        try expectEqual(row3.height, lh)
        // Row 1's answer baseline is the wrapped block's centered ink
        // baseline; the blank's synthesized baseline equals the
        // single-fragment rule for its own row.
        try expectEqual(lines[1].answerBaseline - lines[1].top, lh + m.cap / 2)
        try expectEqual(lines[2].answerBaseline - lines[2].top,
                        CaretGeometry.baseline(
                            rowTop: 0, rowHeight: lh,
                            ascender: m.ascender, naturalHeight: m.natural))
    },

    // MARK: Token capsule geometry (r14)

    EngineCase("capsule-height-is-measured-natural-line-box") {
        // At every settings size the capsule is the font's measured
        // natural line box (≈23 pt at 20 pt), not a fraction of the row.
        for size in [18.0, 20.0, 30.0] {
            let m = fontMetrics(size)
            let row = lineHeight(size)
            try expect(m.natural <= row, "settings row at \(size) pt is ≥ the natural box")
            let h = CaretGeometry.tokenCapsuleHeight(
                naturalHeight: m.natural, rowHeight: row)
            try expectEqual(h, m.natural, "\(size) pt: capsule = natural line box")
        }
        // The default 20 pt size must land on the reference design's
        // ≈23 pt badge, not the old tight ≈20.5 pt one.
        let h20 = CaretGeometry.tokenCapsuleHeight(
            naturalHeight: fontMetrics(20).natural, rowHeight: lineHeight(20))
        try expect(h20 > 22 && h20 < 25, "20 pt capsule is the reference ≈23 pt, got \(h20)")
    },

    EngineCase("capsule-clamps-to-short-custom-row") {
        // A customized (tight) line height shorter than the natural box
        // clamps the capsule to the row — never taller than its line.
        let m = fontMetrics(20)
        let h = CaretGeometry.tokenCapsuleHeight(naturalHeight: m.natural, rowHeight: 20)
        try expectEqual(h, 20, "clamped to the 20 pt row")
        try expect(h < m.natural, "smaller than the natural box")
    },

    EngineCase("capsule-centers-on-shared-ink-centerline") {
        // The capsule midline IS the row's ink centerline and the label
        // sits on the row baseline — the same rules as caret and gutter.
        for size in [18.0, 20.0, 30.0] {
            let m = fontMetrics(size)
            let row = lineHeight(size)
            let rowTop: CGFloat = 64
            let c = CaretGeometry.tokenCapsule(
                rowTop: rowTop, rowHeight: row,
                ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap,
                x: 100, width: 40)
            let baseline = CaretGeometry.baseline(
                rowTop: rowTop, rowHeight: row,
                ascender: m.ascender, naturalHeight: m.natural)
            let center = CaretGeometry.inkCenter(baseline: baseline, capHeight: m.cap)
            try expectEqual(c.labelBaseline, baseline, "\(size) pt label on the row baseline")
            try expectEqual(c.rect.midY, center, "\(size) pt capsule centered on the ink centerline")
            try expectEqual(c.rect.height, CaretGeometry.tokenCapsuleHeight(
                naturalHeight: m.natural, rowHeight: row), "\(size) pt capsule height")
            try expectEqual(c.cornerRadius, c.rect.height * 0.20, "\(size) pt corner = 20% of height")
        }
    },

    EngineCase("capsule-uses-actual-fragment-row-box") {
        // The capsule derives its row from the marker's ACTUAL fragment
        // and the next fragment's advance — the same rowBox the caret
        // uses — so it follows wrapped and fixed-height lines alike.
        let m = fontMetrics(20)
        let lh = CGFloat(lineHeight(20))
        // Second line: fragment at y = lh, next at y = 2×lh.
        let frag = CGRect(x: 0, y: lh, width: 30, height: 20)
        let next = CGRect(x: 0, y: lh * 2, width: 30, height: 20)
        let row = CaretGeometry.rowBox(fragment: frag, nextFragment: next, fixedLineHeight: lh)
        try expectEqual(row.minY, lh, "row starts at the fragment")
        try expectEqual(row.height, lh, "row height = fragment advance")
        let c = CaretGeometry.tokenCapsule(
            rowTop: row.minY, rowHeight: row.height,
            ascender: m.ascender, naturalHeight: m.natural, capHeight: m.cap,
            x: 8, width: 44)
        let baseline = CaretGeometry.baseline(
            rowTop: row.minY, rowHeight: row.height,
            ascender: m.ascender, naturalHeight: m.natural)
        // The capsule center sits in the row; its natural-box height,
        // centered on the ink center, may overshoot the row edge by a
        // sub-point fraction (ink center ≠ natural-box center) but never
        // approaches the next line's ink (≈8 pt clearance).
        try expect(c.rect.midY >= row.minY && c.rect.midY <= row.minY + row.height,
                   "capsule center inside its row")
        try expect(c.rect.maxY - (row.minY + row.height) < 1,
                   "no visible bleed into the next row")
        try expectEqual(c.labelBaseline, baseline, "label on the fragment row's baseline")
        // No next fragment (last line): the fixed height applies.
        let last = CaretGeometry.rowBox(
            fragment: CGRect(x: 0, y: lh * 3, width: 30, height: 20),
            nextFragment: nil, fixedLineHeight: lh)
        try expectEqual(last.height, lh, "trailing row uses the fixed line height")
    }
]
