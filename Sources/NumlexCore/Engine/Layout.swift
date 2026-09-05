import Foundation

/// Per-logical-line layout metrics reported by the notebook editor.
/// One entry per logical source line, whose block covers the union of all
/// its visual fragments (wrapped lines included).
public struct LineMetrics: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        public var index: Int      // 0-based logical line
        public var top: CGFloat    // top of the block in text-container coordinates
        public var height: CGFloat // total visual height of every fragment of this line
        /// Number of visual fragments this logical line occupies (2+ means
        /// the line wrapped). 0 marks a synthesized blank line (no glyphs),
        /// which still occupies one fixed line height in the layout.
        public var fragmentCount: Int
        /// First-text baseline the answer for this line must sit on, in the
        /// SAME text-container coordinates as `top`/`height`. Computed by
        /// the editor with the actual NSFont metrics via
        /// `AnswerBaseline.baseline` — the same rule the caret and gutter
        /// draw from. 0 when not yet computed.
        public var answerBaseline: CGFloat

        public init(index: Int, top: CGFloat, height: CGFloat,
                    fragmentCount: Int = 1, answerBaseline: CGFloat = 0) {
            self.index = index
            self.top = top
            self.height = height
            self.fragmentCount = fragmentCount
            self.answerBaseline = answerBaseline
        }
    }

    public var lines: [Line]
    public init(lines: [Line]) { self.lines = lines }

    public subscript(index: Int) -> Line? {
        index >= 0 && index < lines.count ? lines[index] : nil
    }
}

/// Pure answer-baseline geometry. Kept framework-free (plain CGFloat font
/// metrics in, container-coordinate baseline out) so the exact rule the
/// editor uses to compute `LineMetrics.Line.answerBaseline` is unit-
/// testable without AppKit.
public enum AnswerBaseline {
    /// Target first-text baseline for the answer of one logical line,
    /// in text-container coordinates.
    ///
    /// - Single visual fragment (or a synthesized blank line, count 0,
    ///   and defensive missing-metrics fallbacks): the editor's own glyph
    ///   baseline for the row — `CaretGeometry.baseline`, the same rule
    ///   the caret and gutter numbers draw from. The answer digit then
    ///   sits exactly on the source line's baseline.
    /// - Wrapped line (2+ fragments): the approved centered semantic —
    ///   the answer's ink center is centered across the full logical
    ///   visual block, expressed as a target baseline using the answer
    ///   font's cap height: `rowTop + rowHeight/2 + capHeight/2`.
    ///
    /// No empirical offset: every term comes from the row geometry or
    /// the font's own metrics.
    public static func baseline(
        rowTop: CGFloat,
        rowHeight: CGFloat,
        fragmentCount: Int,
        ascender: CGFloat,
        naturalHeight: CGFloat,
        capHeight: CGFloat
    ) -> CGFloat {
        if fragmentCount >= 2 {
            return rowTop + rowHeight / 2 + capHeight / 2
        }
        return CaretGeometry.baseline(
            rowTop: rowTop,
            rowHeight: Swift.max(rowHeight, 1),
            ascender: ascender,
            naturalHeight: naturalHeight
        )
    }

    /// r37: the source-answer hover outline geometry for one answer row.
    /// When a token capsule is hovered, the answer column strokes a
    /// rounded rectangle around the SOURCE answer. The outline wraps the
    /// answer's INK: vertically centered on the answer's ink centerline
    /// (its measured baseline minus half a cap height — the SAME rule the
    /// editor's caret and gutter share, so the outline and the answer
    /// text can never disagree about the center), with ONE natural
    /// line-box height (clamped to the row): a normal single line gets a
    /// one-line-height outline, and a wrapped source line gets the same
    /// single-line-height outline aligned to the centered answer — never
    /// a giant full-block rect and never an empirical y offset.
    public static func hoverOutline(
        baseline: CGFloat,
        rowHeight: CGFloat,
        naturalHeight: CGFloat,
        capHeight: CGFloat
    ) -> (centerY: CGFloat, height: CGFloat) {
        let center = CaretGeometry.inkCenter(baseline: baseline, capHeight: capHeight)
        let height = Swift.min(Swift.max(naturalHeight, 1), Swift.max(rowHeight, 1))
        return (center, height)
    }
}

/// Pure mapping between editor line metrics and answer-column row frames.
/// Kept framework-free so the placement logic is unit-testable.
public enum NotebookLayout {
    /// Top and height of answer row `index` in answer-content coordinates.
    ///
    /// `topInset` is the vertical shift between the answer column's content
    /// origin and the editor's text-container origin (the editor's top
    /// container inset once both views are full-bleed).
    public static func answerRow(index: Int,
                                 lines: [LineMetrics.Line],
                                 topInset: CGFloat) -> (top: CGFloat, height: CGFloat) {
        if let line = lines[safe: index] {
            return (topInset + line.top, max(line.height, 1))
        }
        // Rows beyond the measured metrics (defensive): continue after the
        // last measured block with its rhythm — the first missing row
        // (index == lines.count) starts right below the last block.
        guard let last = lines.last else {
            return (topInset, 0)
        }
        let extra = index - lines.count
        return (topInset + last.top + last.height + CGFloat(extra) * last.height,
                max(last.height, 1))
    }

    /// Index of the row whose block contains editor-content y `offset`,
    /// or the last row when the offset is beyond the content.
    public static func rowContaining(offset: CGFloat,
                                     lines: [LineMetrics.Line],
                                     topInset: CGFloat,
                                     rowCount: Int) -> Int {
        guard rowCount > 0 else { return 0 }
        var best = 0
        for i in 0..<min(lines.count, rowCount) {
            let top = topInset + lines[i].top
            if offset >= top - 0.5 { best = i } else { break }
        }
        return best
    }
}

/// Pure centered-divider geometry for inline `total` rows (r58).
/// Kept framework-free (plain CGFloat metrics in, content-coordinate
/// Y out) so the exact placement rule is unit-testable without
/// AppKit. The divider sits EXACTLY halfway between the previous
/// visible answer's ink center and the total's ink center — never
/// pinned to the total row's top edge (a row-top pin sits closer to
/// the upper row by half the ascender-to-top gap, a systematic
/// upward bias). All inputs come from evaluated `SheetLine` metadata
/// and measured `LineMetrics`, never from source text.
public enum TotalDivider {
    /// Whether the evaluated row renders answer ink in the answer
    /// column. Blanks, skips and titles render `Color.clear`, and so
    /// do quiet generic errors — only the two explicit status rows
    /// (the terminal weather failure, localized at render time, and
    /// the `Rates unavailable` state) render text. Every other result
    /// — ordinary numbers (unit-bearing conversions and weather
    /// included), variables, money, dates and inactive-token labels —
    /// renders an answer. The divider anchors to actually rendered
    /// answers only.
    public static func isVisibleAnswer(_ result: LineResult) -> Bool {
        switch result {
        case .blank, .skip, .title:
            return false
        case .error(let message):
            return WeatherQuery.isUnavailableMessage(message)
                || message == "Rates unavailable"
        default:
            return true
        }
    }

    /// Index of the nearest preceding visible answer before the total
    /// at `totalIndex` (a position in `lines`), searching only inside
    /// the just-finished section: the scan skips invisible rows
    /// (blanks, prose, titles, quiet errors) and STOPS at a prior
    /// total command (the section boundary) or at the sheet start.
    /// nil means the fallback owns the divider — a leading total or
    /// back-to-back totals with an empty section between them.
    public static func previousVisibleIndex(totalIndex: Int, lines: [SheetLine]) -> Int? {
        var j = totalIndex - 1
        while j >= 0 {
            if lines[j].isTotal { return nil }
            if isVisibleAnswer(lines[j].result) { return j }
            j -= 1
        }
        return nil
    }

    /// Ink centerline of one rendered answer in answer-content
    /// coordinates: the row's measured answer baseline (the exact
    /// offset the row's text sits on — the total's own
    /// block-centered baseline for wrapped lines, the TextKit
    /// baseline otherwise) minus half the cap height of the weight
    /// that row renders in (regular for ordinary rows, semibold for
    /// totals). The same centerline the hover outline uses, so
    /// dividers and outlines can never disagree about a row.
    public static func answerInkCenter(rowTop: CGFloat,
                                       baselineOffset: CGFloat,
                                       capHeight: CGFloat) -> CGFloat {
        rowTop + baselineOffset - capHeight / 2
    }

    /// Snapped divider Y in answer-content coordinates: the exact
    /// midpoint of the two ink centers, rounded (never floored or
    /// ceiled) to the device pixel grid. Rounding keeps the snapped
    /// line within half a physical pixel of the true midpoint —
    /// mathematically centered, with no bias toward either row.
    public static func midpoint(previousCenter: CGFloat,
                                totalCenter: CGFloat,
                                displayScale: CGFloat) -> CGFloat {
        let exact = (previousCenter + totalCenter) / 2
        let scale = Swift.max(displayScale, 1)
        return (exact * scale).rounded() / scale
    }

    /// Fallback divider Y when no previous visible answer exists:
    /// the nominal preceding center sits exactly one own-row-height
    /// above the total's center, so the divider lands precisely on
    /// the total row's top edge — derived from the row's own
    /// measured height, never a magic constant.
    public static func fallback(totalCenter: CGFloat,
                                totalRowHeight: CGFloat) -> CGFloat {
        totalCenter - Swift.max(totalRowHeight, 1) / 2
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
