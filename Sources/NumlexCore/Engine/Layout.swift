import Foundation

/// Per-logical-line layout metrics reported by the notebook editor.
/// One entry per logical source line, whose block covers the union of all
/// its visual fragments (wrapped lines included).
public struct LineMetrics: Sendable, Equatable {
    public struct Line: Sendable, Equatable {
        public var index: Int      // 0-based logical line
        public var top: CGFloat    // top of the block in text-container coordinates
        public var height: CGFloat // total visual height of every fragment of this line

        public init(index: Int, top: CGFloat, height: CGFloat) {
            self.index = index
            self.top = top
            self.height = height
        }
    }

    public var lines: [Line]
    public init(lines: [Line]) { self.lines = lines }

    public subscript(index: Int) -> Line? {
        index >= 0 && index < lines.count ? lines[index] : nil
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
        // last measured block with its rhythm.
        guard let last = lines.last else {
            return (topInset, 0)
        }
        let extra = index - lines.count
        return (topInset + last.top + last.height + CGFloat(extra - 1) * last.height,
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
