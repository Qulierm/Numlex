import Foundation
import CoreGraphics
import CoreText

// MARK: - Print-safe color + palette

/// An opaque sRGB print color. Custom user colors keep their exact
/// canonical channels; fixed/base roles are resolved against the white
/// page by the app before they reach the renderer.
public struct ExportColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public static let black = ExportColor(red: 0, green: 0, blue: 0)
    public static let white = ExportColor(red: 1, green: 1, blue: 1)
    public static let gray = ExportColor(red: 0.45, green: 0.45, blue: 0.47)
    public static let lightGray = ExportColor(red: 0.82, green: 0.82, blue: 0.84)
}

/// The renderer's resolved palette. `highlightFills` is keyed by
/// `HighlightColor.rawValue`.
public struct ExportPalette: Equatable, Sendable {
    public var baseText: ExportColor
    public var number: ExportColor
    public var operatorGlyph: ExportColor
    public var variable: ExportColor
    public var conversion: ExportColor
    public var specifier: ExportColor
    public var label: ExportColor
    public var moneyMarker: ExportColor
    public var headingMarker: ExportColor
    public var headingBody: ExportColor
    public var comment: ExportColor
    public var tokenFill: ExportColor
    public var tokenFillInactive: ExportColor
    public var tokenText: ExportColor
    public var tokenTextInactive: ExportColor
    public var tokenBorder: ExportColor
    public var chromeText: ExportColor
    public var rule: ExportColor
    public var highlightFills: [String: ExportColor]

    public init(baseText: ExportColor = .black,
                number: ExportColor = .black,
                operatorGlyph: ExportColor = .black,
                variable: ExportColor = .black,
                conversion: ExportColor = .black,
                specifier: ExportColor = .black,
                label: ExportColor = .black,
                moneyMarker: ExportColor = .black,
                headingMarker: ExportColor = .gray,
                headingBody: ExportColor = .black,
                comment: ExportColor = .gray,
                tokenFill: ExportColor = ExportColor(red: 0.76, green: 0.86, blue: 1.0),
                tokenFillInactive: ExportColor = ExportColor(red: 0.88, green: 0.88, blue: 0.90),
                tokenText: ExportColor = ExportColor(red: 0.1, green: 0.1, blue: 0.1),
                tokenTextInactive: ExportColor = ExportColor(red: 0.42, green: 0.42, blue: 0.44),
                tokenBorder: ExportColor = ExportColor(red: 0.55, green: 0.63, blue: 0.74),
                chromeText: ExportColor = ExportColor(red: 0.35, green: 0.35, blue: 0.37),
                rule: ExportColor = ExportColor(red: 0.85, green: 0.85, blue: 0.87),
                highlightFills: [String: ExportColor] = [:]) {
        self.baseText = baseText
        self.number = number
        self.operatorGlyph = operatorGlyph
        self.variable = variable
        self.conversion = conversion
        self.specifier = specifier
        self.label = label
        self.moneyMarker = moneyMarker
        self.headingMarker = headingMarker
        self.headingBody = headingBody
        self.comment = comment
        self.tokenFill = tokenFill
        self.tokenFillInactive = tokenFillInactive
        self.tokenText = tokenText
        self.tokenTextInactive = tokenTextInactive
        self.tokenBorder = tokenBorder
        self.chromeText = chromeText
        self.rule = rule
        self.highlightFills = highlightFills
    }

    public func color(for role: SyntaxRole) -> ExportColor {
        switch role {
        case .number: return number
        case .operatorGlyph: return operatorGlyph
        case .variable: return variable
        case .conversion: return conversion
        case .specifier: return specifier
        case .label: return label
        case .moneyMarker: return moneyMarker
        case .hashMarker: return headingMarker
        case .hashBody: return headingBody
        case .tagMarker, .tagBody:
            return tokenText
        case .divider:
            return rule
        }
    }
}

// MARK: - Resolved fonts

public struct ExportFonts {
    public var expression: CTFont
    public var answer: CTFont
    public var semiboldAnswer: CTFont
    public var heading: CTFont
    public var title: CTFont
    public var chrome: CTFont
    public var token: CTFont

    public init(expression: CTFont, answer: CTFont, semiboldAnswer: CTFont,
                heading: CTFont, title: CTFont, chrome: CTFont, token: CTFont) {
        self.expression = expression
        self.answer = answer
        self.semiboldAnswer = semiboldAnswer
        self.heading = heading
        self.title = title
        self.chrome = chrome
        self.token = token
    }

    /// Derives the layout metrics from the real font metrics, keeping
    /// the layout and the drawing measured from the same fonts.
    public func metrics(pageSize: CGSize,
                        margins: ExportInsets = .standard) -> ExportLayoutMetrics {
        func lineHeight(_ font: CTFont) -> Double {
            Double(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
        }
        return ExportLayoutMetrics(
            expressionLineHeight: lineHeight(expression).rounded(.up),
            answerLineHeight: lineHeight(answer).rounded(.up),
            headingLineHeight: lineHeight(heading).rounded(.up),
            chromeLineHeight: lineHeight(chrome).rounded(.up),
            tokenLineHeight: lineHeight(token).rounded(.up) + 4,
            pageSize: pageSize,
            margins: margins)
    }

    /// The measurer the LAYOUT uses: the exact faces the renderer draws.
    public var measurer: ExportTextMeasurer {
        ExportTextMeasurer(
            plain: { ExportRenderedDocument.measure($0, font: self.expression) },
            token: { ExportRenderedDocument.measure($0, font: self.token) })
    }

    /// The EXACT expression-column measurer for one row: heading rows
    /// are measured with the bold heading face, everything else with the
    /// body face; token labels always with the token face.
    public func expressionMeasurer(row: ExportRow) -> ExportTextMeasurer {
        let font = row.kind == .heading ? heading : expression
        return ExportTextMeasurer(
            plain: { ExportRenderedDocument.measure($0, font: font) },
            token: { ExportRenderedDocument.measure($0, font: self.token) })
    }

    /// The EXACT answer-column measurer for one row: inline-total
    /// answers are semibold and measured that way.
    public func answerMeasurer(row: ExportRow) -> ExportTextMeasurer {
        let font = row.isInlineTotal ? semiboldAnswer : answer
        return .uniform { ExportRenderedDocument.measure($0, font: font) }
    }

    public var measurers: ExportMeasurers {
        ExportMeasurers(expression: { self.expressionMeasurer(row: $0) },
                        answer: { self.answerMeasurer(row: $0) })
    }

    /// Chrome widths for the footer-Total placement decision.
    public var chromeMeasurer: ExportChromeMeasurer {
        ExportChromeMeasurer(
            chrome: { ExportRenderedDocument.measure($0, font: self.chrome) },
            totalValue: { ExportRenderedDocument.measure($0, font: self.semiboldAnswer) })
    }
}

// MARK: - The renderer

/// The ONE deterministic renderer feeding both the PDF writer and the
/// AppKit print pipeline. It measures with CoreText, places with the
/// pure `ExportLayoutEngine`, and draws every page from the immutable
/// snapshot — it never reads a view, a viewport or the editor.
public struct ExportRenderedDocument {
    public let snapshot: ExportSnapshot
    public let fonts: ExportFonts
    public let palette: ExportPalette
    public let metrics: ExportLayoutMetrics
    public let layout: ExportDocumentLayout

    public init(snapshot: ExportSnapshot, fonts: ExportFonts,
                palette: ExportPalette,
                metrics: ExportLayoutMetrics? = nil) {
        self.snapshot = snapshot
        self.fonts = fonts
        self.palette = palette
        let resolved = metrics ?? fonts.metrics(pageSize: ExportLayoutMetrics.letter.pageSize)
        self.metrics = resolved
        self.layout = ExportLayoutEngine.layout(snapshot: snapshot,
                                                metrics: resolved,
                                                measurers: fonts.measurers,
                                                chrome: fonts.chromeMeasurer)
    }

    /// Single-line width of `text` in `font` (CoreText metrics).
    public static func measure(_ text: String, font: CTFont) -> Double {
        guard !text.isEmpty else { return 0 }
        let attr = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font
        ])
        let line = CTLineCreateWithAttributedString(attr)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        return CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
    }

    public var pageCount: Int { layout.pages.count }

    // MARK: PDF

    public func pdfData() -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            return data as Data
        }
        var mediaBox = CGRect(origin: .zero, size: layout.pageSize)
        let auxiliary: [CFString: Any] = [
            kCGPDFContextTitle: snapshot.sheetTitle,
            kCGPDFContextCreator: "Numlex",
            kCGPDFContextAuthor: "Numlex",
        ]
        guard let ctx = CGContext(consumer: consumer,
                                  mediaBox: &mediaBox,
                                  auxiliary as CFDictionary) else {
            return data as Data
        }
        for page in layout.pages {
            ctx.beginPDFPage(nil)
            draw(page: page, in: ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    public func writePDF(to url: URL) throws {
        let data = pdfData()
        try data.write(to: url, options: .atomic)
    }

    // MARK: Page drawing

    /// Draws one page into a context whose page-local coordinates are
    /// (0, 0, pageWidth, pageHeight) with the origin at the BOTTOM LEFT
    /// (PDF/AppKit default). Every top-down layout coordinate is
    /// converted here through the single `cgRect` helper, so text,
    /// capsules and fills can never disagree about Y.
    public func draw(page: ExportPage, in ctx: CGContext) {
        let size = layout.pageSize
        ctx.setFillColor(ExportColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        drawChrome(page: page, in: ctx)

        for placed in page.visuals {
            let row = snapshot.rows[placed.visual.rowIndex]
            // Persistent line highlight behind the full body width.
            if let highlight = row.highlight,
               let fill = palette.highlightFills[highlight.rawValue] {
                ctx.setFillColor(fill.cgColor)
                let top = placed.frame.minY
                let bottom = max(placed.answerFrame?.maxY ?? placed.frame.maxY,
                                 placed.frame.maxY)
                ctx.fill(cgRect(x: metrics.margins.left, top: top,
                                width: size.width - metrics.margins.left - metrics.margins.right,
                                height: max(bottom - top, 1)))
            }
            // Gutter: the ORIGINAL source number, only on the row's
            // first visual line.
            if snapshot.options.lineNumbers, !placed.visual.isContinuation {
                drawLine(text: "\(row.sourceLineNumber)",
                         font: fonts.chrome,
                         color: palette.chromeText,
                         x: metrics.margins.left + layout.gutterWidth - 8,
                         top: placed.frame.minY,
                         alignRightAt: metrics.margins.left + layout.gutterWidth - 8,
                         in: ctx)
            }
            if row.kind == .divider {
                drawDivider(placed: placed, in: ctx)
            } else {
                drawExpression(row: row, placed: placed, in: ctx)
                drawAnswer(row: row, placed: placed, in: ctx)
            }
        }

        if let totalFrame = page.totalFrame, let totalText = snapshot.totalText {
            drawTotal(totalText, frame: totalFrame, in: ctx)
        }
    }

    // MARK: Chrome

    private func drawChrome(page: ExportPage, in ctx: CGContext) {
        let size = layout.pageSize
        let top = metrics.margins.top
        let contentWidth = size.width - metrics.margins.left - metrics.margins.right
        let pageLabel = "\(page.index) / \(layout.pages.count)"
        let pageLabelWidth = min(ExportRenderedDocument.measure(pageLabel, font: fonts.chrome),
                                 contentWidth)
        // The title is bounded by the page label: it truncates with an
        // ellipsis rather than ever overprinting the label or a margin.
        let titleWidth = max(contentWidth - pageLabelWidth - 12, 0)
        let title = truncated(snapshot.sheetTitle, font: fonts.title,
                              maxWidth: titleWidth)
        drawLine(text: title,
                 font: fonts.title,
                 color: palette.baseText,
                 x: metrics.margins.left,
                 top: top,
                 in: ctx)
        drawLine(text: truncated(pageLabel, font: fonts.chrome, maxWidth: contentWidth),
                 font: fonts.chrome,
                 color: palette.chromeText,
                 x: size.width - metrics.margins.right,
                 top: top,
                 alignRightAt: size.width - metrics.margins.right,
                 in: ctx)
        ctx.setStrokeColor(palette.rule.cgColor)
        ctx.setLineWidth(0.5)
        let ruleTop = top + metrics.chromeLineHeight + 6
        ctx.stroke(cgRect(x: metrics.margins.left, top: ruleTop,
                          width: size.width - metrics.margins.left - metrics.margins.right,
                          height: 0.5))
    }

    private func drawTotal(_ text: String, frame: CGRect, in ctx: CGContext) {
        let label = snapshot.totalLabel
        let maxWidth = Double(frame.width)
        let labelWidth = ExportRenderedDocument.measure(label, font: fonts.chrome)
        if layout.totalLines >= 2 {
            // The combined width did not fit: label on its own line,
            // value on the next — both bounded by the content width.
            drawLine(text: truncated(label, font: fonts.chrome, maxWidth: maxWidth),
                     font: fonts.chrome,
                     color: palette.chromeText,
                     x: frame.minX,
                     top: frame.minY,
                     in: ctx)
            drawLine(text: truncated(text, font: fonts.semiboldAnswer, maxWidth: maxWidth),
                     font: fonts.semiboldAnswer,
                     color: palette.baseText,
                     x: frame.minX,
                     top: frame.minY + metrics.totalLineHeight,
                     in: ctx)
        } else {
            let valueMax = max(maxWidth - labelWidth - 10, 0)
            drawLine(text: label,
                     font: fonts.chrome,
                     color: palette.chromeText,
                     x: frame.minX,
                     top: frame.minY,
                     in: ctx)
            drawLine(text: truncated(text, font: fonts.semiboldAnswer, maxWidth: valueMax),
                     font: fonts.semiboldAnswer,
                     color: palette.baseText,
                     x: frame.minX + labelWidth + 10,
                     top: frame.minY,
                     in: ctx)
        }
    }

    /// Grapheme-safe ellipsis truncation: the returned string is never
    /// wider than `maxWidth` (a single over-wide grapheme degrades to
    /// the ellipsis alone, still bounded).
    private func truncated(_ text: String, font: CTFont, maxWidth: Double) -> String {
        guard maxWidth > 0 else { return "" }
        if ExportRenderedDocument.measure(text, font: font) <= maxWidth { return text }
        let ellipsis = "…"
        let characters = Array(text)
        var low = 0
        var high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            let candidate = String(characters.prefix(mid)) + ellipsis
            if ExportRenderedDocument.measure(candidate, font: font) <= maxWidth {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low == 0 ? ellipsis : String(characters.prefix(low)) + ellipsis
    }

    // MARK: Row cells

    private func drawExpression(row: ExportRow, placed: ExportPlacedVisual,
                                in ctx: CGContext) {
        ctx.saveGState()
        // Defensive cell clip: fragments are guaranteed to fit by the
        // layout, so this can never hide correctly wrapped content.
        ctx.clip(to: cgRect(frame: placed.frame))
        var x = Double(placed.frame.minX)
        var index = 0
        let segments = placed.visual.textSegments
        while index < segments.count {
            let segment = segments[index]
            if let tokenIndex = segment.tokenIndex {
                // Coalesce adjacent fragments of the SAME token into one
                // capsule (a token broken at a line end stays one element
                // per line).
                var text = segment.text
                let active = segment.active
                var j = index + 1
                while j < segments.count,
                      segments[j].tokenIndex == tokenIndex {
                    text += segments[j].text
                    j += 1
                }
                let labelWidth = ExportRenderedDocument.measure(text, font: fonts.token)
                let capsuleWidth = labelWidth + metrics.tokenHorizontalPadding
                let capsuleHeight = max(metrics.tokenLineHeight, 8)
                let capsuleTop = Double(placed.frame.minY)
                    + (Double(placed.frame.height) - capsuleHeight) / 2
                let rect = cgRect(x: x, top: capsuleTop,
                                  width: capsuleWidth, height: capsuleHeight)
                let path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5,
                                  transform: nil)
                ctx.setFillColor((active ? palette.tokenFill : palette.tokenFillInactive).cgColor)
                ctx.addPath(path)
                ctx.fillPath()
                if active {
                    ctx.setStrokeColor(palette.tokenBorder.cgColor)
                    ctx.setLineWidth(0.5)
                    ctx.addPath(path)
                    ctx.strokePath()
                }
                drawLine(text: text, font: fonts.token,
                         color: active ? palette.tokenText : palette.tokenTextInactive,
                         x: x + metrics.tokenHorizontalPadding / 2,
                         top: Double(placed.frame.minY),
                         width: capsuleWidth,
                         in: ctx)
                x += capsuleWidth
                index = j
            } else {
                let attributed = plainAttributedSegment(row: row, segment: segment)
                x += drawAttributed(attributed, x: x,
                                    top: Double(placed.frame.minY), in: ctx)
                index += 1
            }
        }
        ctx.restoreGState()
    }

    /// Package 7: a divider row draws one calm rule across the body
    /// width (never any text).
    private func drawDivider(placed: ExportPlacedVisual, in ctx: CGContext) {
        let midY = Double(placed.frame.midY)
        ctx.setStrokeColor(palette.rule.cgColor)
        ctx.setLineWidth(0.75)
        ctx.stroke(cgRect(x: Double(placed.frame.minX), top: midY,
                          width: Double(placed.frame.width)
                              + metrics.columnGap
                              + Double(placed.answerFrame?.width ?? 0),
                          height: 0.5))
    }

    private func drawAnswer(row: ExportRow, placed: ExportPlacedVisual,
                            in ctx: CGContext) {
        guard let answerRange = placed.visual.answerRange,
              let answerFrame = placed.answerFrame,
              let answer = row.answer else { return }
        let ns = answer as NSString
        guard answerRange.location <= ns.length,
              NSMaxRange(answerRange) <= ns.length else { return }
        let text = ns.substring(with: answerRange)
        let base = row.kind == .heading ? palette.headingBody : palette.baseText
        let color = row.isInlineTotal ? palette.baseText : base
        let font = row.isInlineTotal ? fonts.semiboldAnswer : fonts.answer
        ctx.saveGState()
        ctx.clip(to: cgRect(frame: answerFrame))
        drawLine(text: text, font: font, color: color,
                 x: Double(answerFrame.minX), top: Double(answerFrame.minY),
                 width: Double(answerFrame.width), in: ctx)
        ctx.restoreGState()
    }

    // MARK: Text building

    /// The renderer's final inline text for one row (token labels
    /// substituted for their U+FFFC markers) — exposed so tests can
    /// prove no replacement glyph and no stored snapshot value ever
    /// reaches the page.
    public func resolvedText(rowIndex: Int) -> String {
        guard snapshot.rows.indices.contains(rowIndex) else { return "" }
        return ExportLayoutEngine.resolvedText(row: snapshot.rows[rowIndex])
    }

    /// The attributed text of one plain segment: the row's base
    /// typography plus every syntax span intersecting the segment's
    /// source range. `segment.text` is authoritative (it carries the
    /// preserved/normalized whitespace the layout measured); token
    /// replacements are never re-colored.
    private func plainAttributedSegment(row: ExportRow,
                                        segment: ExportSegment) -> NSAttributedString {
        let source = NSMutableAttributedString(string: segment.text,
                                               attributes: baseAttributes(row: row))
        if snapshot.options.syntaxHighlighting, row.kind != .heading,
           segment.sourceRange.location != NSNotFound {
            for span in row.spans {
                let start = max(span.range.location - segment.sourceRange.location, 0)
                let end = min(NSMaxRange(span.range) - segment.sourceRange.location,
                              source.length)
                guard end > start else { continue }
                source.addAttribute(
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                    value: palette.color(for: span.role).cgColor,
                    range: NSRange(location: start, length: end - start))
            }
        }
        return source
    }

    private func baseAttributes(row: ExportRow) -> [NSAttributedString.Key: Any] {
        let font: CTFont
        let color: ExportColor
        switch row.kind {
        case .heading:
            font = fonts.heading
            color = snapshot.options.syntaxHighlighting ? palette.headingBody : palette.baseText
        case .comment:
            font = fonts.expression
            color = snapshot.options.syntaxHighlighting ? palette.comment : palette.baseText
        case .expression, .total, .blank, .divider:
            font = fonts.expression
            color = palette.baseText
        }
        return [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
    }

    /// Draws one attributed run at `x`, top-aligned at `top` (top-down),
    /// and returns its advance so the next segment continues inline.
    @discardableResult
    private func drawAttributed(_ attributed: NSAttributedString, x: Double,
                                top: Double, in ctx: CGContext) -> Double {
        guard attributed.length > 0 else { return 0 }
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let advance = Double(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: x, y: cgY(top: top, ascent: Double(ascent)))
        CTLineDraw(line, ctx)
        return advance
    }

    /// One plain line (chrome, gutter, answers, total) with optional
    /// right alignment. The line is never wrapped here (the layout
    /// already wrapped it); an optional `width` clips defensively.
    private func drawLine(text: String, font: CTFont, color: ExportColor,
                          x: Double, top: Double,
                          alignRightAt: Double? = nil,
                          width: Double? = nil,
                          in ctx: CGContext) {
        guard !text.isEmpty else { return }
        _ = width
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let advance = Double(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        var startX = x
        if let alignRightAt {
            startX = alignRightAt - advance
        }
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: startX, y: cgY(top: top, ascent: Double(ascent)))
        CTLineDraw(line, ctx)
    }

    // MARK: Coordinates

    /// Top-down Y -> baseline Y for text.
    private func cgY(top: Double, ascent: Double) -> Double {
        layout.pageSize.height - top - ascent
    }

    /// Top-down rect -> the context's bottom-up rect. THE single
    /// conversion used by every fill, capsule and clip.
    private func cgRect(x: Double, top: Double, width: Double,
                        height: Double) -> CGRect {
        CGRect(x: x, y: layout.pageSize.height - top - height,
               width: width, height: height)
    }

    private func cgRect(frame: CGRect) -> CGRect {
        cgRect(x: Double(frame.minX), top: Double(frame.minY),
               width: Double(frame.width), height: Double(frame.height))
    }
}
