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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
