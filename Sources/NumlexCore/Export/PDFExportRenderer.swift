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
        self.layout = ExportLayoutEngine.layout(
            snapshot: snapshot,
            metrics: resolved,
            measure: { text in
                ExportRenderedDocument.measure(text, font: fonts.expression)
            })
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
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return width
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
    /// (PDF/AppKit default).
    public func draw(page: ExportPage, in ctx: CGContext) {
        let size = layout.pageSize
        // White printable page.
        ctx.setFillColor(ExportColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        drawChrome(page: page, in: ctx)

        let bodyStart = layout.contentTop
        for placed in page.visuals {
            let row = snapshot.rows[placed.visual.rowIndex]
            // Persistent line highlight behind the full body width.
            if let highlight = row.highlight,
               let fill = palette.highlightFills[highlight.rawValue] {
                ctx.setFillColor(fill.cgColor)
                let top = placed.frame.minY
                let bottom = max(placed.answerFrame?.maxY ?? placed.frame.maxY,
                                 placed.frame.maxY)
                ctx.fill(rect(x: metrics.margins.left, top: top,
                              width: size.width - metrics.margins.left - metrics.margins.right,
                              height: max(bottom - top, 1), pageHeight: size.height))
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
                         pageHeight: size.height,
                         in: ctx)
            }
            drawExpression(row: row, placed: placed, pageHeight: size.height, in: ctx)
            drawAnswer(row: row, placed: placed, pageHeight: size.height, in: ctx)
        }

        if let totalFrame = page.totalFrame, let totalText = snapshot.totalText {
            drawTotal(totalText, frame: totalFrame, pageHeight: size.height, in: ctx)
        }
        _ = bodyStart
    }

    // MARK: Chrome

    private func drawChrome(page: ExportPage, in ctx: CGContext) {
        let size = layout.pageSize
        let top = metrics.margins.top
        drawLine(text: snapshot.sheetTitle,
                 font: fonts.title,
                 color: palette.baseText,
                 x: metrics.margins.left,
                 top: top,
                 pageHeight: size.height,
                 in: ctx)
        let pageLabel = "\(page.index) / \(layout.pages.count)"
        drawLine(text: pageLabel,
                 font: fonts.chrome,
                 color: palette.chromeText,
                 x: size.width - metrics.margins.right,
                 top: top,
                 alignRightAt: size.width - metrics.margins.right,
                 pageHeight: size.height,
                 in: ctx)
        // Hairline rule under the header.
        ctx.setStrokeColor(palette.rule.cgColor)
        ctx.setLineWidth(0.5)
        let ruleTop = top + metrics.chromeLineHeight + 6
        ctx.stroke(rect(x: metrics.margins.left, top: ruleTop,
                        width: size.width - metrics.margins.left - metrics.margins.right,
                        height: 0.5, pageHeight: size.height))
    }

    private func drawTotal(_ text: String, frame: CGRect,
                           pageHeight: Double, in ctx: CGContext) {
        let label = L10n.t("total", language: snapshot.language)
        drawLine(text: label,
                 font: fonts.chrome,
                 color: palette.chromeText,
                 x: frame.minX,
                 top: frame.minY,
                 pageHeight: pageHeight,
                 in: ctx)
        let labelWidth = ExportRenderedDocument.measure(label, font: fonts.chrome)
        drawLine(text: text,
                 font: fonts.semiboldAnswer,
                 color: palette.baseText,
                 x: frame.minX + labelWidth + 10,
                 top: frame.minY,
                 pageHeight: pageHeight,
                 in: ctx)
    }

    private func drawExpression(row: ExportRow, placed: ExportPlacedVisual,
                                pageHeight: Double, in ctx: CGContext) {
        let attributed = expressionText(row: row, range: placed.visual.textRange)
        guard attributed.length > 0 else { return }
        let width = max(Double(placed.frame.width), 1)
        drawAttributed(attributed, x: Double(placed.frame.minX),
                       top: Double(placed.frame.minY),
                       width: width, pageHeight: pageHeight, in: ctx)
    }

    private func drawAnswer(row: ExportRow, placed: ExportPlacedVisual,
                            pageHeight: Double, in ctx: CGContext) {
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
        drawLine(text: text, font: font, color: color,
                 x: Double(answerFrame.minX), top: Double(answerFrame.minY),
                 width: Double(answerFrame.width),
                 pageHeight: pageHeight, in: ctx)
    }

    // MARK: Text building

    /// Builds one visual line's attributed text: the shared syntax
    /// roles (only when highlighting is on), the `#` heading
    /// typography, and the inline token capsules replaced by their
    /// labels. The layout measured the raw text; token labels are wider
    /// than one U+FFFC, so the line's real width can exceed the layout
    /// measurement — drawing stays within the cell and clips at the
    /// answer column's edge (never overlapping it).
    public func expressionText(row: ExportRow, range: NSRange) -> NSAttributedString {
        let ns = row.text as NSString
        let clampedLocation = min(max(range.location, 0), ns.length)
        let clampedLength = min(max(range.length, 0), ns.length - clampedLocation)
        let rect = NSRange(location: clampedLocation, length: clampedLength)
        let source = NSMutableAttributedString(string: ns.substring(with: rect),
                                               attributes: baseAttributes(row: row))
        if snapshot.options.syntaxHighlighting {
            for span in row.spans {
                let spanRange = NSRange(location: span.range.location - clampedLocation,
                                        length: span.range.length)
                let start = max(spanRange.location, 0)
                let end = min(NSMaxRange(spanRange), source.length)
                guard end > start else { continue }
                // Heading typography owns its own colors.
                guard row.kind != .heading else { continue }
                source.addAttribute(
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                    value: palette.color(for: span.role).cgColor,
                    range: NSRange(location: start, length: end - start))
            }
        }
        // Inline tokens, replaced from LAST to FIRST so earlier offsets
        // stay valid; the replacement carries the token face and ink.
        let tokensInRange = row.tokens
            .filter { $0.offset >= rect.location && $0.offset < NSMaxRange(rect) }
            .sorted { $0.offset > $1.offset }
        for token in tokensInRange {
            let local = token.offset - rect.location
            guard local >= 0, local < source.length else { continue }
            let replacement = NSAttributedString(
                string: token.label,
                attributes: tokenAttributes(active: token.active))
            source.replaceCharacters(in: NSRange(location: local, length: 1),
                                     with: replacement)
        }
        return source
    }

    /// The renderer's final inline text for one row (token labels
    /// substituted for their U+FFFC markers) — exposed so tests can
    /// prove no replacement glyph and no stored snapshot value ever
    /// reaches the page.
    public func renderedText(rowIndex: Int) -> String {
        guard snapshot.rows.indices.contains(rowIndex) else { return "" }
        let row = snapshot.rows[rowIndex]
        let full = NSRange(location: 0, length: (row.text as NSString).length)
        return expressionText(row: row, range: full).string
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
        case .expression, .total, .blank:
            font = fonts.expression
            color = palette.baseText
        }
        return [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
    }

    /// Marks a replaced token label so the capsule pass finds exactly
    /// the runs the label replacement created (never a look-alike color).
    static let tokenRunAttribute = NSAttributedString.Key("NumlexExportToken")

    private func tokenAttributes(active: Bool) -> [NSAttributedString.Key: Any] {
        [
            NSAttributedString.Key(kCTFontAttributeName as String): fonts.token,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                (active ? palette.tokenText : palette.tokenTextInactive).cgColor,
            Self.tokenRunAttribute: active,
        ]
    }

    /// Draws one line of text, TOP-aligned at `top` (top-down). Text
    /// uses its own typographic ascent so mixed token fonts share a
    /// baseline; an optional right edge aligns the line's right side.
    @discardableResult
    private func drawAttributed(_ attributed: NSAttributedString, x: Double,
                                top: Double, width: Double,
                                pageHeight: Double, in ctx: CGContext) -> CTLine {
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let baseline = pageHeight - top - Double(ascent)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: x, y: baseline)
        // Inline token capsules behind the labels.
        drawTokenCapsules(attributed: attributed, line: line, x: x, top: top,
                          pageHeight: pageHeight, in: ctx)
        CTLineDraw(line, ctx)
        return line
    }

    private func drawTokenCapsules(attributed: NSAttributedString, line: CTLine,
                                   x: Double, top: Double,
                                   pageHeight: Double, in ctx: CGContext) {
        _ = pageHeight
        // Token runs are the replaced labels: find runs in the token
        // ink and draw their capsule boxes behind them.
        var cursor = 0
        while cursor < attributed.length {
            var effective = NSRange(location: 0, length: 0)
            let attrs = attributed.attributes(at: cursor, effectiveRange: &effective)
            if let active = attrs[Self.tokenRunAttribute] as? Bool {
                let start = CTLineGetOffsetForStringIndex(line, effective.location, nil)
                let end = CTLineGetOffsetForStringIndex(line, NSMaxRange(effective), nil)
                let rect = CGRect(x: x + Double(start) - 4,
                                  y: top + 2,
                                  width: max(Double(end - start) + 8, 4),
                                  height: max(metrics.tokenLineHeight - 4, 4))
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
            }
            cursor = NSMaxRange(effective)
        }
    }

    /// One plain line (chrome, gutter, answers, total) with optional
    /// right alignment at `alignRightAt`.
    private func drawLine(text: String, font: CTFont, color: ExportColor,
                          x: Double, top: Double,
                          alignRightAt: Double? = nil,
                          width: Double? = nil,
                          pageHeight: Double, in ctx: CGContext) {
        guard !text.isEmpty else { return }
        _ = width
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        var startX = x
        if let alignRightAt {
            startX = alignRightAt - lineWidth
        }
        var ascent: CGFloat = 0
        _ = CTLineGetTypographicBounds(line, &ascent, nil, nil)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: startX, y: pageHeight - top - Double(ascent))
        CTLineDraw(line, ctx)
    }

    // MARK: Coordinates

    /// Converts a top-down rect into the context's bottom-up origin.
    private func rect(x: Double, top: Double, width: Double,
                      height: Double, pageHeight: Double) -> CGRect {
        CGRect(x: x, y: pageHeight - top - height, width: width, height: height)
    }
}
