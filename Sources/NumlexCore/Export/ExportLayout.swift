import Foundation
import CoreGraphics

/// Print geometry in TOP-DOWN page coordinates (y grows downward from
/// the page's top edge). Renderers convert to their own coordinate
/// system; the layout itself stays pure and deterministic.
public struct ExportInsets: Equatable, Sendable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public static let standard = ExportInsets(top: 48, left: 54, bottom: 48, right: 54)
}

/// Every measured input the pagination needs. The renderer derives these
/// from its real CoreText fonts; tests inject deterministic values, so
/// pagination edge cases are provable without any drawing.
public struct ExportLayoutMetrics: Equatable, Sendable {
    public var expressionLineHeight: Double
    public var answerLineHeight: Double
    public var headingLineHeight: Double
    public var chromeLineHeight: Double
    public var tokenLineHeight: Double
    public var rowSpacing: Double
    public var visualSpacing: Double
    public var headerHeight: Double
    public var totalSpacingBefore: Double
    public var totalLineHeight: Double
    public var gutterWidth: Double
    public var columnGap: Double
    /// Share of the body width reserved for the answer column.
    public var answerFraction: Double
    public var minimumRowHeight: Double
    public var pageSize: CGSize
    public var margins: ExportInsets

    public init(expressionLineHeight: Double = 24,
                answerLineHeight: Double = 24,
                headingLineHeight: Double = 26,
                chromeLineHeight: Double = 14,
                tokenLineHeight: Double = 20,
                rowSpacing: Double = 6,
                visualSpacing: Double = 2,
                headerHeight: Double = 30,
                totalSpacingBefore: Double = 10,
                totalLineHeight: Double = 24,
                gutterWidth: Double = 34,
                columnGap: Double = 14,
                answerFraction: Double = 0.32,
                minimumRowHeight: Double = 0,
                pageSize: CGSize = CGSize(width: 595.276, height: 841.89),
                margins: ExportInsets = .standard) {
        self.expressionLineHeight = expressionLineHeight
        self.answerLineHeight = answerLineHeight
        self.headingLineHeight = headingLineHeight
        self.chromeLineHeight = chromeLineHeight
        self.tokenLineHeight = tokenLineHeight
        self.rowSpacing = rowSpacing
        self.visualSpacing = visualSpacing
        self.headerHeight = headerHeight
        self.totalSpacingBefore = totalSpacingBefore
        self.totalLineHeight = totalLineHeight
        self.gutterWidth = gutterWidth
        self.columnGap = columnGap
        self.answerFraction = answerFraction
        self.minimumRowHeight = minimumRowHeight
        self.pageSize = pageSize
        self.margins = margins
    }

    /// The standard US Letter page in points.
    public static let letter = ExportLayoutMetrics(
        pageSize: CGSize(width: 612, height: 792))
    /// The standard A4 page in points.
    public static let a4 = ExportLayoutMetrics(
        pageSize: CGSize(width: 595.276, height: 841.89))
}

/// The greedy word wrapper shared by layout and drawing: every visual
/// line is an `NSRange` into the row's display text, so the renderer
/// draws exactly the text the layout measured. An unbreakable word
/// wider than the column stays on its own (clipped) line — it is never
/// dropped and never overlaps the following line.
public enum ExportTextWrapper {
    public static func wrap(_ text: String,
                            maxWidth: Double,
                            measure: (String) -> Double) -> [NSRange] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        var ranges: [NSRange] = []
        var lineStart = 0
        var cursor = 0
        while cursor < ns.length {
            // Find the end of the next word (the next space or the end).
            var wordEnd = cursor
            while wordEnd < ns.length, ns.character(at: wordEnd) != 32 { wordEnd += 1 }
            let candidateEnd = wordEnd
            let candidate = ns.substring(with: NSRange(location: lineStart,
                                                       length: candidateEnd - lineStart))
            let candidateWidth = measure(candidate)
            let isSingleWord = lineStart == cursor
            if !isSingleWord, candidateWidth > maxWidth, maxWidth > 0 {
                // Break BEFORE this word: the previous line (already
                // measured to fit) is complete.
                ranges.append(NSRange(location: lineStart, length: cursor - 1 - lineStart))
                lineStart = cursor
                continue
            }
            if wordEnd >= ns.length {
                let end = ns.length
                ranges.append(NSRange(location: lineStart, length: end - lineStart))
                lineStart = end
                cursor = end
                break
            }
            // Advance past the space.
            cursor = wordEnd + 1
        }
        if ranges.isEmpty {
            ranges.append(NSRange(location: 0, length: ns.length))
        }
        return ranges
    }
}

/// One wrapped visual line of a row (expression range and, when the row
/// has an answer, its independently wrapped answer range).
public struct ExportRowVisual: Equatable, Sendable {
    public let rowIndex: Int
    public let textRange: NSRange
    public let answerRange: NSRange?
    public let height: Double
    public let isContinuation: Bool

    public init(rowIndex: Int, textRange: NSRange, answerRange: NSRange?,
                height: Double, isContinuation: Bool) {
        self.rowIndex = rowIndex
        self.textRange = textRange
        self.answerRange = answerRange
        self.height = height
        self.isContinuation = isContinuation
    }
}

/// A visual line placed on a page (top-down page-local coordinates).
public struct ExportPlacedVisual: Equatable, Sendable {
    public let visual: ExportRowVisual
    /// The expression cell.
    public let frame: CGRect
    /// The answer cell (nil when the row has no answer on this visual).
    public let answerFrame: CGRect?

    public init(visual: ExportRowVisual, frame: CGRect, answerFrame: CGRect?) {
        self.visual = visual
        self.frame = frame
        self.answerFrame = answerFrame
    }
}

public struct ExportPage: Equatable, Sendable {
    public let index: Int
    public let visuals: [ExportPlacedVisual]
    /// The footer Total placement (only on the final page when shown).
    public let totalFrame: CGRect?

    public init(index: Int, visuals: [ExportPlacedVisual], totalFrame: CGRect?) {
        self.index = index
        self.visuals = visuals
        self.totalFrame = totalFrame
    }
}

public struct ExportDocumentLayout: Equatable, Sendable {
    public let pages: [ExportPage]
    public let pageSize: CGSize
    public let showsTotal: Bool
    public let gutterWidth: Double
    public let expressionX: Double
    public let expressionWidth: Double
    public let answerX: Double
    public let answerWidth: Double
    public let contentTop: Double

    public init(pages: [ExportPage], pageSize: CGSize, showsTotal: Bool,
                gutterWidth: Double, expressionX: Double, expressionWidth: Double,
                answerX: Double, answerWidth: Double, contentTop: Double) {
        self.pages = pages
        self.pageSize = pageSize
        self.showsTotal = showsTotal
        self.gutterWidth = gutterWidth
        self.expressionX = expressionX
        self.expressionWidth = expressionWidth
        self.answerX = answerX
        self.answerWidth = answerWidth
        self.contentTop = contentTop
    }
}

/// The deterministic pagination engine. Rows stay intact when they fit;
/// only a single row taller than the whole body area is fragmented
/// across pages. The Total appears once after the last exported row
/// and may move to the next page.
public enum ExportLayoutEngine {

    public static func layout(snapshot: ExportSnapshot,
                              metrics: ExportLayoutMetrics,
                              measure: (String) -> Double) -> ExportDocumentLayout {
        let page = metrics.pageSize
        let contentX = metrics.margins.left
        let contentWidth = max(page.width - metrics.margins.left - metrics.margins.right, 1)
        let gutter = snapshot.options.lineNumbers ? metrics.gutterWidth : 0
        let bodyX = contentX + gutter
        let bodyWidth = max(contentWidth - gutter, 1)
        let answerWidth = max(bodyWidth * metrics.answerFraction, 1)
        let expressionWidth = max(bodyWidth - answerWidth - metrics.columnGap, 1)
        let expressionX = bodyX
        let answerX = bodyX + expressionWidth + metrics.columnGap
        let headerHeight = min(metrics.headerHeight,
                               max(page.height - metrics.margins.top - metrics.margins.bottom, 1))
        let contentTop = metrics.margins.top + headerHeight
        let pageBottom = page.height - metrics.margins.bottom
        let bodyHeight = max(pageBottom - contentTop, 1)

        // 1) Wrap every row into visual lines.
        var visualsByRow: [[ExportRowVisual]] = []
        for (index, row) in snapshot.rows.enumerated() {
            let exprRanges = ExportTextWrapper.wrap(row.text,
                                                    maxWidth: expressionWidth,
                                                    measure: measure)
            let answerRanges = row.answer.map {
                ExportTextWrapper.wrap($0, maxWidth: answerWidth, measure: measure)
            } ?? []
            let count = max(exprRanges.count, answerRanges.count, 1)
            let bodyHeightForRow = rowLineHeight(row, metrics: metrics)
            var visuals: [ExportRowVisual] = []
            for k in 0..<count {
                let height = max(bodyHeightForRow, metrics.minimumRowHeight)
                visuals.append(ExportRowVisual(
                    rowIndex: index,
                    textRange: k < exprRanges.count ? exprRanges[k]
                        : NSRange(location: (row.text as NSString).length, length: 0),
                    answerRange: k < answerRanges.count ? answerRanges[k] : nil,
                    height: height,
                    isContinuation: k > 0))
            }
            visualsByRow.append(visuals)
        }

        // 2) Place them page by page.
        var pages: [ExportPage] = []
        var currentVisuals: [ExportPlacedVisual] = []
        var y = contentTop
        var pageIndex = 1

        func flushPage() {
            pages.append(ExportPage(index: pageIndex,
                                    visuals: currentVisuals,
                                    totalFrame: nil))
            currentVisuals = []
            pageIndex += 1
            y = contentTop
        }

        for visuals in visualsByRow {
            guard !visuals.isEmpty else { continue }
            let rowHeight = visuals.map(\.height).reduce(0, +)
                + metrics.visualSpacing * Double(max(visuals.count - 1, 0))
            let fitsOnOnePage = rowHeight <= bodyHeight
            if fitsOnOnePage, y > contentTop, y + rowHeight > pageBottom {
                flushPage()
            }
            for (k, visual) in visuals.enumerated() {
                if y > contentTop, y + visual.height > pageBottom {
                    flushPage()
                }
                let exprFrame = CGRect(x: expressionX, y: y,
                                       width: expressionWidth, height: visual.height)
                let answerFrame = visual.answerRange == nil ? nil
                    : CGRect(x: answerX, y: y, width: answerWidth, height: visual.height)
                currentVisuals.append(ExportPlacedVisual(visual: visual,
                                                         frame: exprFrame,
                                                         answerFrame: answerFrame))
                y += visual.height
                if k < visuals.count - 1 { y += metrics.visualSpacing }
            }
            y += metrics.rowSpacing
        }

        // 3) The Total: once, after the final exported row.
        var totalFrame: CGRect? = nil
        if snapshot.options.showTotal, snapshot.totalText != nil {
            let totalHeight = metrics.totalSpacingBefore + metrics.totalLineHeight
            if y > contentTop, y + totalHeight > pageBottom {
                flushPage()
            }
            totalFrame = CGRect(x: contentX, y: y + metrics.totalSpacingBefore,
                                width: contentWidth, height: metrics.totalLineHeight)
            y += totalHeight
        }
        if !currentVisuals.isEmpty || totalFrame != nil || pages.isEmpty {
            pages.append(ExportPage(index: pageIndex, visuals: currentVisuals,
                                    totalFrame: totalFrame))
        }
        return ExportDocumentLayout(pages: pages,
                                    pageSize: page,
                                    showsTotal: snapshot.options.showTotal
                                        && snapshot.totalText != nil,
                                    gutterWidth: gutter,
                                    expressionX: expressionX,
                                    expressionWidth: expressionWidth,
                                    answerX: answerX,
                                    answerWidth: answerWidth,
                                    contentTop: contentTop)
    }

    /// Visual-line height for a row (heading rows use the heading
    /// metric; every other row the expression metric; answers can only
    /// grow it through wrapping, never shrink it).
    static func rowLineHeight(_ row: ExportRow,
                              metrics: ExportLayoutMetrics) -> Double {
        switch row.kind {
        case .heading: return metrics.headingLineHeight
        case .blank: return metrics.expressionLineHeight
        case .expression, .comment, .total:
            return max(metrics.expressionLineHeight, metrics.answerLineHeight)
        }
    }
}
