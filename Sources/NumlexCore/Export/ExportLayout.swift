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
    /// Total horizontal capsule padding around one token label. The
    /// LAYOUT reserves this width and the renderer draws it, so the two
    /// can never disagree.
    public var tokenHorizontalPadding: Double
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
                tokenHorizontalPadding: Double = 8,
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
        self.tokenHorizontalPadding = tokenHorizontalPadding
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

/// The measured width of one text atom: plain source text is measured
/// with the exact face it is drawn with (body, heading, semibold answer
/// or chrome), a token label with the token face.
public struct ExportTextMeasurer {
    public var plain: (String) -> Double
    public var token: (String) -> Double

    public init(plain: @escaping (String) -> Double,
                token: @escaping (String) -> Double) {
        self.plain = plain
        self.token = token
    }

    /// One measurement for both kinds (tests, uniform faces).
    public static func uniform(_ measure: @escaping (String) -> Double) -> ExportTextMeasurer {
        ExportTextMeasurer(plain: measure, token: measure)
    }
}

/// Per-row exact measurers. The expression column of a heading row is
/// measured with the heading face, and an inline-total answer with the
/// semibold face — the same faces the renderer draws, so a bold glyph
/// can never overrun its column.
public struct ExportMeasurers {
    public var expression: (ExportRow) -> ExportTextMeasurer
    public var answer: (ExportRow) -> ExportTextMeasurer

    public init(expression: @escaping (ExportRow) -> ExportTextMeasurer,
                answer: @escaping (ExportRow) -> ExportTextMeasurer) {
        self.expression = expression
        self.answer = answer
    }

    public static func uniform(_ measurer: ExportTextMeasurer) -> ExportMeasurers {
        ExportMeasurers(expression: { _ in measurer }, answer: { _ in measurer })
    }
}

/// Chrome text widths used only to bound the footer Total placement.
public struct ExportChromeMeasurer {
    public var chrome: (String) -> Double
    public var totalValue: (String) -> Double

    public init(chrome: @escaping (String) -> Double,
                totalValue: @escaping (String) -> Double) {
        self.chrome = chrome
        self.totalValue = totalValue
    }
}

/// One drawable segment of a resolved visual line. `sourceRange` is the
/// exact range in the row's display text; token labels carry the
/// marker's range (length 1) but draw the resolved label. Concatenating
/// the segments of every visual line in order reconstructs the resolved
/// text exactly — including every whitespace character (normalized to a
/// single space per source whitespace character) and token labels.
public struct ExportSegment: Equatable, Sendable {
    public let sourceRange: NSRange
    public let text: String
    /// Index into `ExportRow.tokens` for a substituted token label.
    public let tokenIndex: Int?
    public let active: Bool

    public init(sourceRange: NSRange, text: String, tokenIndex: Int? = nil,
                active: Bool = false) {
        self.sourceRange = sourceRange
        self.text = text
        self.tokenIndex = tokenIndex
        self.active = active
    }
}

/// One wrapped visual line of a row: resolved expression segments plus,
/// independently wrapped, the answer range (plain text).
public struct ExportRowVisual: Equatable, Sendable {
    public let rowIndex: Int
    public let textSegments: [ExportSegment]
    public let answerRange: NSRange?
    public let height: Double
    public let isContinuation: Bool
    /// The measured width of the resolved expression segments,
    /// including token capsule padding. Guaranteed <= the expression
    /// column width except for a single grapheme wider than the column.
    public let textWidth: Double

    public init(rowIndex: Int, textSegments: [ExportSegment],
                answerRange: NSRange?, height: Double, isContinuation: Bool,
                textWidth: Double) {
        self.rowIndex = rowIndex
        self.textSegments = textSegments
        self.answerRange = answerRange
        self.height = height
        self.isContinuation = isContinuation
        self.textWidth = textWidth
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
    /// 1 (label and value on one line) or 2 (the value wrapped onto its
    /// own line because the combined width exceeds the content width).
    public let totalLines: Int

    public init(pages: [ExportPage], pageSize: CGSize, showsTotal: Bool,
                gutterWidth: Double, expressionX: Double, expressionWidth: Double,
                answerX: Double, answerWidth: Double, contentTop: Double,
                totalLines: Int = 1) {
        self.pages = pages
        self.pageSize = pageSize
        self.showsTotal = showsTotal
        self.gutterWidth = gutterWidth
        self.expressionX = expressionX
        self.expressionWidth = expressionWidth
        self.answerX = answerX
        self.answerWidth = answerWidth
        self.contentTop = contentTop
        self.totalLines = totalLines
    }
}

// MARK: - Text wrapping

/// Grapheme-safe text breaking, shared by layout and tests. A word wider
/// than its column is split between EXTENDED GRAPHEME CLUSTERS (never a
/// UTF-16 surrogate pair or a composed sequence), so every fragment is
/// measurable and drawable without clipping.
public enum ExportTextWrapper {
    /// Extended grapheme clusters of a string (Swift `Character`s are
    /// exactly the composed sequences Foundation would keep together).
    public static func graphemes(_ text: String) -> [String] {
        text.map(String.init)
    }

    /// True for a whitespace UTF-16 unit (spaces, tabs, NBSP and the
    /// other Unicode space separators).
    public static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = UnicodeScalar(unit) else { return false }
        return CharacterSet.whitespaces.contains(scalar)
    }

    /// The source text with every whitespace CHARACTER normalized to a
    /// single space (tabs/NBSP/Unicode spaces stay visible; their count
    /// is preserved one-for-one).
    public static func normalizedWhitespace(_ text: String) -> String {
        String(text.map { $0.isWhitespace ? Character(" ") : $0 })
    }

    /// Breaks one over-wide run of text into consecutive ranges whose
    /// measured width is <= `maxWidth`. A single grapheme wider than the
    /// column is emitted alone (it cannot be split further); callers
    /// still clip defensively.
    public static func graphemeRanges(_ text: String, maxWidth: Double,
                                      measure: (String) -> Double) -> [NSRange] {
        let ns = text as NSString
        guard ns.length > 0, maxWidth > 0 else {
            return ns.length > 0 ? [NSRange(location: 0, length: ns.length)] : []
        }
        var ranges: [NSRange] = []
        var start = 0
        var currentWidth = 0.0
        let characters = Array(text)
        var offsets: [Int] = [0]
        for ch in characters {
            offsets.append(offsets[offsets.count - 1] + (String(ch) as NSString).length)
        }
        for (i, ch) in characters.enumerated() {
            let chWidth = measure(String(ch))
            if currentWidth > 0, currentWidth + chWidth > maxWidth {
                ranges.append(NSRange(location: start, length: offsets[i] - start))
                start = offsets[i]
                currentWidth = 0
            }
            currentWidth += chWidth
        }
        if start < ns.length {
            ranges.append(NSRange(location: start, length: ns.length - start))
        }
        return ranges
    }

    /// GREEDY wrapping with contiguous ranges: as many words (and the
    /// whitespace runs between them) as fit are packed onto each line;
    /// only a run wider than the whole column is hard-broken between
    /// grapheme clusters. The returned ranges tile the whole text in
    /// order, so concatenating their substrings reproduces the source
    /// exactly and no character is dropped or duplicated.
    public static func wrap(_ text: String,
                            maxWidth: Double,
                            measure: (String) -> Double) -> [NSRange] {
        let ns = text as NSString
        guard ns.length > 0 else { return [] }
        var ranges: [NSRange] = []
        var lineStart = 0
        var lineEnd = 0
        var lineWidth = 0.0
        var open = false

        func flush() {
            guard open else { return }
            ranges.append(NSRange(location: lineStart, length: lineEnd - lineStart))
            open = false
            lineWidth = 0
        }

        var cursor = 0
        while cursor < ns.length {
            let start = cursor
            let whitespace = isWhitespace(ns.character(at: cursor))
            while cursor < ns.length,
                  isWhitespace(ns.character(at: cursor)) == whitespace {
                cursor += 1
            }
            let tokenRange = NSRange(location: start, length: cursor - start)
            let token = ns.substring(with: tokenRange)
            let tokenWidth = measure(token)
            if tokenWidth <= maxWidth || maxWidth <= 0 {
                if open, lineWidth + tokenWidth > maxWidth {
                    flush()
                }
                if !open {
                    lineStart = tokenRange.location
                    open = true
                }
                lineEnd = NSMaxRange(tokenRange)
                lineWidth += tokenWidth
            } else {
                // Over-wide run: break it between graphemes, packing the
                // pieces greedily.
                let pieces = graphemeRanges(token, maxWidth: maxWidth, measure: measure)
                for piece in pieces {
                    let pieceRange = NSRange(location: tokenRange.location + piece.location,
                                             length: piece.length)
                    let pieceWidth = measure(ns.substring(with: pieceRange))
                    if open, lineWidth + pieceWidth > maxWidth {
                        flush()
                    }
                    if !open {
                        lineStart = pieceRange.location
                        open = true
                    }
                    lineEnd = NSMaxRange(pieceRange)
                    lineWidth += pieceWidth
                }
            }
        }
        flush()
        return ranges
    }
}

// MARK: - Atom building

/// One grapheme cell used by the hard-break pass: the drawable unit and
/// the source segment it came from.
private struct ExportGraphemeCell {
    let unit: String
    let segment: ExportSegment
    /// Absolute UTF-16 offset of this unit's first character in the
    /// row's display text (token labels keep their marker offset).
    let sourceOffset: Int
}

/// An unbreakable layout atom: one word or one whitespace run of the
/// display text, resolved into drawable runs (plain substrings, token
/// labels, exact whitespace) with its exact measured width.
struct ExportAtom: Equatable {
    let segments: [ExportSegment]
    let width: Double
    /// True when the atom is a fragment produced by a grapheme break.
    let isFragment: Bool
}

enum ExportAtomFactory {
    /// Resolves one row's display text into word and whitespace atoms,
    /// then hard-breaks every atom wider than the column grapheme-safely.
    /// The returned atoms, in order, cover the text contiguously.
    static func atoms(row: ExportRow, maxWidth: Double,
                      measurer: ExportTextMeasurer,
                      tokenPadding: Double) -> [ExportAtom] {
        let ns = row.text as NSString
        let tokensByOffset = Dictionary(uniqueKeysWithValues:
            row.tokens.enumerated().map { ($0.element.offset, $0.offset) })
        var atoms: [ExportAtom] = []
        var cursor = 0
        while cursor < ns.length {
            let start = cursor
            let whitespace = ExportTextWrapper.isWhitespace(ns.character(at: cursor))
            if whitespace {
                while cursor < ns.length,
                      ExportTextWrapper.isWhitespace(ns.character(at: cursor)) {
                    cursor += 1
                }
                let range = NSRange(location: start, length: cursor - start)
                let text = ExportTextWrapper.normalizedWhitespace(
                    ns.substring(with: range))
                atoms.append(ExportAtom(
                    segments: [ExportSegment(sourceRange: range, text: text)],
                    width: measurer.plain(text),
                    isFragment: false))
                continue
            }
            while cursor < ns.length,
                  !ExportTextWrapper.isWhitespace(ns.character(at: cursor)) {
                cursor += 1
            }
            let wordEnd = cursor
            var segments: [ExportSegment] = []
            var p = start
            while p < wordEnd {
                if ns.character(at: p) == answerTokenMarkerUTF16,
                   let tokenIndex = tokensByOffset[p] {
                    let token = row.tokens[tokenIndex]
                    segments.append(ExportSegment(
                        sourceRange: NSRange(location: p, length: 1),
                        text: token.label,
                        tokenIndex: tokenIndex,
                        active: token.active))
                    p += 1
                } else {
                    var plainEnd = p + 1
                    while plainEnd < wordEnd,
                          ns.character(at: plainEnd) != answerTokenMarkerUTF16 {
                        plainEnd += 1
                    }
                    // Never split a plain run at an orphan marker.
                    if plainEnd < wordEnd, tokensByOffset[plainEnd] == nil {
                        plainEnd += 1
                    }
                    segments.append(ExportSegment(
                        sourceRange: NSRange(location: p, length: plainEnd - p),
                        text: ns.substring(with: NSRange(location: p,
                                                         length: plainEnd - p))))
                    p = plainEnd
                }
            }
            atoms.append(makeAtom(segments: segments, measurer: measurer,
                                  tokenPadding: tokenPadding, isFragment: false))
        }
        // Hard-break over-wide atoms.
        var broken: [ExportAtom] = []
        for atom in atoms {
            if atom.width <= maxWidth || maxWidth <= 0 || atom.segments.isEmpty {
                broken.append(atom)
            } else {
                broken.append(contentsOf: breakAtom(atom, maxWidth: maxWidth,
                                                    measurer: measurer,
                                                    tokenPadding: tokenPadding))
            }
        }
        return broken
    }

    static func makeAtom(segments: [ExportSegment],
                         measurer: ExportTextMeasurer, tokenPadding: Double,
                         isFragment: Bool) -> ExportAtom {
        var width = 0.0
        var tokenCount = 0
        for s in segments {
            if s.tokenIndex != nil {
                width += measurer.token(s.text)
                tokenCount += 1
            } else {
                width += measurer.plain(s.text)
            }
        }
        width += tokenPadding * Double(max(tokenCount, 0))
        return ExportAtom(segments: segments, width: width, isFragment: isFragment)
    }

    /// Splits an atom between grapheme clusters, preserving run
    /// identity (a plain run stays plain; a token label fragment keeps
    /// its token index and its capsule padding).
    static func breakAtom(_ atom: ExportAtom, maxWidth: Double,
                          measurer: ExportTextMeasurer,
                          tokenPadding: Double) -> [ExportAtom] {
        var cells: [ExportGraphemeCell] = []
        for segment in atom.segments {
            var offset = segment.sourceRange.location
            for unit in ExportTextWrapper.graphemes(segment.text) {
                cells.append(ExportGraphemeCell(
                    unit: unit, segment: segment,
                    sourceOffset: segment.tokenIndex != nil
                        ? segment.sourceRange.location : offset))
                if segment.tokenIndex == nil {
                    offset += (unit as NSString).length
                }
            }
        }
        guard !cells.isEmpty else { return [atom] }
        var fragments: [ExportAtom] = []
        var current: [ExportGraphemeCell] = []
        var currentWidth = 0.0
        // Capsule padding is charged ONCE per contiguous token run in a
        // fragment (exactly how makeAtom measures the grouped run).
        var lastTokenIndex: Int? = nil
        for cell in cells {
            let tokenIndex = cell.segment.tokenIndex
            var w = tokenIndex != nil ? measurer.token(cell.unit)
                                      : measurer.plain(cell.unit)
            if let tokenIndex, tokenIndex != lastTokenIndex {
                w += tokenPadding
            }
            if !current.isEmpty, currentWidth + w > maxWidth {
                fragments.append(makeFragment(current, measurer: measurer,
                                              tokenPadding: tokenPadding))
                current = []
                currentWidth = 0
                lastTokenIndex = nil
                if let tokenIndex, tokenIndex != lastTokenIndex {
                    w = measurer.token(cell.unit) + tokenPadding
                }
            }
            current.append(cell)
            currentWidth += w
            lastTokenIndex = tokenIndex
        }
        if !current.isEmpty {
            fragments.append(makeFragment(current, measurer: measurer,
                                          tokenPadding: tokenPadding))
        }
        return fragments.isEmpty ? [atom] : fragments
    }

    /// Re-groups consecutive cells sharing a source segment (same token
    /// index or same plain range) into drawable runs, so a fragmented
    /// token keeps its capsule identity and plain text stays whole.
    private static func makeFragment(_ cells: [ExportGraphemeCell],
                                     measurer: ExportTextMeasurer,
                                     tokenPadding: Double) -> ExportAtom {
        var segments: [ExportSegment] = []
        var i = 0
        while i < cells.count {
            let source = cells[i].segment
            var text = cells[i].unit
            var j = i + 1
            while j < cells.count,
                  cells[j].segment.tokenIndex == source.tokenIndex,
                  cells[j].segment.sourceRange == source.sourceRange,
                  cells[j].segment.active == source.active {
                text += cells[j].unit
                j += 1
            }
            // A plain fragment carries its OWN source range (so syntax
            // spans map exactly); a token fragment keeps the marker.
            let range: NSRange
            if source.tokenIndex != nil {
                range = source.sourceRange
            } else {
                let startOffset = cells[i].sourceOffset
                let last = cells[j - 1]
                let endOffset = last.sourceOffset + (last.unit as NSString).length
                range = NSRange(location: startOffset, length: endOffset - startOffset)
            }
            segments.append(ExportSegment(sourceRange: range, text: text,
                                          tokenIndex: source.tokenIndex,
                                          active: source.active))
            i = j
        }
        return makeAtom(segments: segments, measurer: measurer,
                        tokenPadding: tokenPadding, isFragment: true)
    }
}

/// The deterministic pagination engine. Rows stay intact when they fit;
/// only a single row taller than the whole body area is fragmented
/// across pages. The Total appears once after the last exported row
/// and may move to the next page.
public enum ExportLayoutEngine {

    /// Convenience for callers with one uniform measurement (tests).
    public static func layout(snapshot: ExportSnapshot,
                              metrics: ExportLayoutMetrics,
                              measure: @escaping (String) -> Double) -> ExportDocumentLayout {
        layout(snapshot: snapshot, metrics: metrics,
               measurers: .uniform(.uniform(measure)), chrome: nil)
    }

    public static func layout(snapshot: ExportSnapshot,
                              metrics: ExportLayoutMetrics,
                              measurer: ExportTextMeasurer) -> ExportDocumentLayout {
        layout(snapshot: snapshot, metrics: metrics,
               measurers: .uniform(measurer), chrome: nil)
    }

    public static func layout(snapshot: ExportSnapshot,
                              metrics: ExportLayoutMetrics,
                              measurers: ExportMeasurers,
                              chrome: ExportChromeMeasurer? = nil) -> ExportDocumentLayout {
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

        // 1) Resolve + wrap every row into visual lines with the row's
        // EXACT faces (headings bold, inline totals semibold).
        var visualsByRow: [[ExportRowVisual]] = []
        for (index, row) in snapshot.rows.enumerated() {
            let expressionMeasurer = measurers.expression(row)
            let atoms = ExportAtomFactory.atoms(
                row: row, maxWidth: expressionWidth, measurer: expressionMeasurer,
                tokenPadding: metrics.tokenHorizontalPadding)
            let lines = wrapAtoms(atoms, maxWidth: expressionWidth)
            let answerMeasurer = measurers.answer(row)
            let answerRanges = row.answer.map {
                ExportTextWrapper.wrap($0, maxWidth: answerWidth,
                                       measure: answerMeasurer.plain)
            } ?? []
            let count = max(lines.count, answerRanges.count, 1)
            let bodyHeightForRow = rowLineHeight(row, metrics: metrics)
            var visuals: [ExportRowVisual] = []
            for k in 0..<count {
                let height = max(bodyHeightForRow, metrics.minimumRowHeight)
                let segments = k < lines.count ? lines[k].segments : []
                visuals.append(ExportRowVisual(
                    rowIndex: index,
                    textSegments: segments,
                    answerRange: k < answerRanges.count ? answerRanges[k] : nil,
                    height: height,
                    isContinuation: k > 0,
                    textWidth: k < lines.count ? lines[k].width : 0))
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

        // 3) The Total: once, after the final exported row. A combined
        // label+value wider than the content area wraps the value onto
        // its own line (the layout reserves the extra height here).
        var totalFrame: CGRect? = nil
        var totalLines = 1
        if snapshot.options.showTotal, let totalText = snapshot.totalText {
            let label = L10n.t("total", language: snapshot.language)
            if let chrome {
                let combined = chrome.chrome(label) + 10 + chrome.totalValue(totalText)
                if combined > contentWidth { totalLines = 2 }
            }
            let totalHeight = metrics.totalSpacingBefore
                + metrics.totalLineHeight * Double(totalLines)
            if y > contentTop, y + totalHeight > pageBottom {
                flushPage()
            }
            totalFrame = CGRect(x: contentX, y: y + metrics.totalSpacingBefore,
                                width: contentWidth,
                                height: metrics.totalLineHeight * Double(totalLines))
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
                                    contentTop: contentTop,
                                    totalLines: totalLines)
    }

    struct WrappedLine: Equatable {
        let segments: [ExportSegment]
        let width: Double
    }

    /// Greedy atom wrapping. Atoms (words and whitespace runs) are
    /// placed in order with no synthesized separators; a break happens
    /// only when the next atom would exceed the column. Every produced
    /// line's measured width is <= the column except for a single
    /// grapheme wider than the column itself.
    static func wrapAtoms(_ atoms: [ExportAtom], maxWidth: Double) -> [WrappedLine] {
        guard !atoms.isEmpty else { return [] }
        var lines: [WrappedLine] = []
        var current: [ExportAtom] = []
        var currentWidth = 0.0
        func emit() {
            guard !current.isEmpty else { return }
            var segments: [ExportSegment] = []
            var width = 0.0
            for atom in current {
                segments.append(contentsOf: atom.segments)
                width += atom.width
            }
            lines.append(WrappedLine(segments: segments, width: width))
            current = []
            currentWidth = 0
        }
        for atom in atoms {
            if !current.isEmpty, currentWidth + atom.width > maxWidth {
                emit()
            }
            current.append(atom)
            currentWidth += atom.width
        }
        emit()
        return lines
    }

    /// Visual-line height for a row (heading rows use the heading
    /// metric; every other row the expression metric; answers can only
    /// grow it through wrapping, never shrink it).
    static func rowLineHeight(_ row: ExportRow,
                              metrics: ExportLayoutMetrics) -> Double {
        switch row.kind {
        case .heading: return max(metrics.headingLineHeight, metrics.tokenLineHeight)
        case .blank: return metrics.expressionLineHeight
        case .expression, .comment, .total:
            return max(max(metrics.expressionLineHeight, metrics.answerLineHeight),
                       metrics.tokenLineHeight)
        }
    }

    /// The FULL resolved text of one row: token labels substituted for
    /// their markers and every whitespace character normalized to one
    /// space (the exact text the emitted segments reconstruct).
    public static func resolvedText(row: ExportRow) -> String {
        var out = ""
        let ns = row.text as NSString
        let tokensByOffset = Dictionary(uniqueKeysWithValues:
            row.tokens.enumerated().map { ($0.element.offset, $0.offset) })
        var p = 0
        while p < ns.length {
            if ns.character(at: p) == answerTokenMarkerUTF16,
               let tokenIndex = tokensByOffset[p] {
                out += row.tokens[tokenIndex].label
                p += 1
            } else {
                let unit = ns.substring(with: NSRange(location: p, length: 1))
                out += ExportTextWrapper.normalizedWhitespace(unit)
                p += 1
            }
        }
        return out
    }
}
