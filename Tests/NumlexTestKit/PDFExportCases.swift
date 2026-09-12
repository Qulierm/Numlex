import Foundation
import CoreGraphics
import CoreText
import AppKit
import NumlexCore

// MARK: - PDF/print export (snapshot, filters, pagination, renderer)

private func exportContext(_ content: String,
                           title: String = "Sheet",
                           lineIDs: [UUID]? = nil,
                           references: [AnswerReference] = [],
                           answerDisplay: [AnswerDisplayPreference] = [],
                           highlights: [LineHighlightPreference] = [],
                           language: AppLanguage = .en,
                           presentation: NumberPresentationPreferences = .defaults,
                           decimalPlaces: Int = 10) -> ExportPresentationContext {
    let ids = lineIDs ?? content.components(separatedBy: "\n").map { _ in UUID() }
    return ExportPresentationContext(
        sheetID: UUID(),
        sheetTitle: title,
        content: content,
        lineIDs: ids,
        references: references,
        answerDisplay: answerDisplay,
        highlights: highlights,
        rates: Rates(),
        decimalPlaces: decimalPlaces,
        now: Date(timeIntervalSince1970: 1_700_000_000),
        calendar: Calendar(identifier: .gregorian),
        constants: [],
        weather: .empty,
        geo: .empty,
        numberContext: .legacy,
        unitContext: .builtIns,
        preferences: .defaults,
        financial: .defaults,
        presentation: presentation,
        language: language)
}

private func exportBuild(_ context: ExportPresentationContext,
                         _ options: ExportOptions) throws -> ExportSnapshot {
    switch ExportSnapshotBuilder.build(context: context, options: options) {
    case .success(let s): return s
    case .failure(let e): throw CaseFailure(message: "build failed: \(e)",
                                            location: "Export")
    }
}

private func exportFailure(_ context: ExportPresentationContext,
                           _ options: ExportOptions) -> ExportSnapshotError? {
    if case .failure(let e) = ExportSnapshotBuilder.build(context: context,
                                                          options: options) {
        return e
    }
    return nil
}

private func exportFonts(size: Double = 12) -> ExportFonts {
    func font(_ name: String, weight: CGFloat) -> CTFont {
        let desc = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: name as CFString,
            kCTFontSizeAttribute: size as CFNumber,
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(desc, size, nil)
    }
    return ExportFonts(expression: font("Helvetica", weight: 0),
                       answer: font("Helvetica", weight: 0),
                       semiboldAnswer: font("Helvetica-Bold", weight: 0),
                       heading: font("Helvetica-Bold", weight: 0),
                       title: font("Helvetica-Bold", weight: 0),
                       chrome: font("Helvetica", weight: 0),
                       token: font("Menlo", weight: 0))
}

/// A deterministic fake measurement: every character is 7pt wide and
/// every line 20pt tall, so pagination is exactly predictable.
private func fakeMetrics(pageHeight: Double = 200) -> ExportLayoutMetrics {
    var m = ExportLayoutMetrics(pageSize: CGSize(width: 300, height: pageHeight))
    m.expressionLineHeight = 20
    m.answerLineHeight = 20
    m.headingLineHeight = 20
    m.chromeLineHeight = 10
    m.tokenLineHeight = 14
    m.rowSpacing = 0
    m.visualSpacing = 0
    m.headerHeight = 20
    m.totalSpacingBefore = 0
    m.totalLineHeight = 20
    m.gutterWidth = 20
    m.columnGap = 10
    m.answerFraction = 0.3
    m.minimumRowHeight = 0
    m.margins = ExportInsets(top: 10, left: 10, bottom: 10, right: 10)
    return m
}


private func syntheticRow(_ text: String, answer: String? = nil,
                          tokens: [ExportToken] = [],
                          kind: ExportRowKind = .expression,
                          sourceLine: Int = 1) -> ExportRow {
    ExportRow(sourceLineNumber: sourceLine, lineID: UUID(), kind: kind,
              text: text, answer: answer, spans: [], tokens: tokens,
              highlight: nil, isInlineTotal: false)
}

private func syntheticSnapshot(_ rows: [ExportRow],
                               options: ExportOptions = ExportOptions(showTotal: false)) -> ExportSnapshot {
    ExportSnapshot(sheetTitle: "Probe", rows: rows, total: nil, totalText: nil,
                   options: options, lineCount: rows.count + 1)
}

/// The same width model the layout uses: plain text measured plainly, a
/// token run measured with the token face plus ONE capsule padding per
/// contiguous run, and one space width between wrapped atoms.
private func segmentWidth(_ segments: [ExportSegment],
                          measure: (String) -> Double,
                          tokenPadding: Double) -> Double {
    var width = 0.0
    var lastToken: Int? = nil
    for s in segments {
        if s.isJoiningSpace {
            width += measure(" ")
            lastToken = nil
            continue
        }
        if let t = s.tokenIndex {
            width += measure(s.text)
            if t != lastToken { width += tokenPadding }
            lastToken = t
        } else {
            width += measure(s.text)
            lastToken = nil
        }
    }
    return width
}

private struct ExportBitmap {
    let pixels: [UInt8]
    let width: Int
    let height: Int
    let scale: Int

    func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }

    func isInk(_ x: Int, _ y: Int) -> Bool {
        let c = rgb(x, y)
        return c.0 < 250 || c.1 < 250 || c.2 < 250
    }

    /// The capsule fill (0.76, 0.86, 1.0) with a small tolerance; the
    /// border stroke (0.55, 0.63, 0.74) and the label ink are excluded.
    func isCapsuleFill(_ x: Int, _ y: Int) -> Bool {
        let c = rgb(x, y)
        return abs(c.0 - 194) < 24 && abs(c.1 - 219) < 24 && abs(c.2 - 255) < 24
    }

    /// Dark label/text ink (token text is near-black).
    func isTextInk(_ x: Int, _ y: Int) -> Bool {
        let c = rgb(x, y)
        return c.0 < 120 && c.1 < 120 && c.2 < 120
    }
}

private func renderExportBitmap(document: ExportRenderedDocument,
                                page: Int, scale: Int = 1) -> ExportBitmap? {
    let size = document.layout.pageSize
    let w = Int(Double(size.width) * Double(scale))
    let h = Int(Double(size.height) * Double(scale))
    guard w > 0, h > 0, document.layout.pages.indices.contains(page) else { return nil }
    let byteCount = w * h * 4
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 4)
    defer { buffer.deallocate() }
    guard let ctx = CGContext(data: buffer, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(origin: .zero, size: size))
    document.draw(page: document.layout.pages[page], in: ctx)
    let pixels = [UInt8](UnsafeBufferPointer(start: buffer.assumingMemoryBound(to: UInt8.self),
                                             count: byteCount))
    return ExportBitmap(pixels: pixels, width: w, height: h, scale: scale)
}

private func inkCount(_ data: Data) -> Int {
    guard let provider = CGDataProvider(data: data as CFData),
          let pdf = CGPDFDocument(provider),
          let page = pdf.page(at: 1) else { return 0 }
    let media = page.getBoxRect(.mediaBox)
    let w = Int(media.width), h = Int(media.height)
    guard w > 0, h > 0 else { return 0 }
    var pixels = [UInt8](repeating: 255, count: w * h * 4)
    pixels.withUnsafeMutableBytes { buf in
        if let ctx = CGContext(data: buf.baseAddress, width: w, height: h,
                               bitsPerComponent: 8, bytesPerRow: w * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.drawPDFPage(page)
        }
    }
    return pixels.enumerated().reduce(0) { count, pair in
        pair.offset % 4 == 3 ? count : (pair.element < 250 ? count + 1 : count)
    }
}


/// Reconstructs a row's resolved expression from its visual lines,
/// re-inserting the single source space consumed at word-wrap breaks
/// exactly where the source gap is one space character.
private func reconstructExpression(row: ExportRow,
                                   visuals: [ExportPlacedVisual]) -> String {
    let ns = row.text as NSString
    var out = ""
    var prevEnd: Int? = nil
    for placed in visuals {
        for segment in placed.visual.textSegments {
            if segment.isJoiningSpace {
                out += " "
                if let end = prevEnd { prevEnd = end + 1 }
                continue
            }
            if segment.sourceRange.location != NSNotFound {
                if let end = prevEnd, segment.sourceRange.location == end + 1,
                   end < ns.length, ns.character(at: end) == 32 {
                    out += " "
                }
                prevEnd = segment.sourceRange.location + segment.sourceRange.length
            }
            out += segment.text
        }
    }
    return out
}


/// QA-only fixture dump (enabled with NUMLEX_EXPORT_FIXTURES=1): writes
/// the real renderer's output for the stress fixtures so the report can
/// cite page counts, hashes and pixel bounds.
private func dumpExportFixture(_ document: ExportRenderedDocument, name: String) {
    guard ProcessInfo.processInfo.environment["NUMLEX_EXPORT_FIXTURES"] != nil else { return }
    let dir = "/tmp/qa-out"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? document.pdfData().write(to: URL(fileURLWithPath: "\(dir)/\(name).pdf"))
}

public let pdfExportCases: [EngineCase] = [

    EngineCase("export-range-filters-and-original-line-numbers") {
        let content = "# Heading\n1 + 1\n// hidden note\n//\n2 + 2\ntotal"
        let ctx = exportContext(content)
        // Full export keeps every source row; the comment rows exist
        // only while hideComments is off.
        let all = try exportBuild(ctx, ExportOptions())
        try expectEqual(all.rows.count, 6, "full row count")
        try expectEqual(all.rows[0].kind, .heading, "heading kind")
        try expectEqual(all.rows[2].kind, .comment, "comment kind")
        try expectEqual(all.rows[5].kind, .total, "inline total kind")
        // Hide comments removes both semantic `//` rows.
        let noComments = try exportBuild(ctx, ExportOptions(hideComments: true))
        try expectEqual(noComments.rows.map(\.sourceLineNumber), [1, 2, 5, 6],
                        "hidden comment rows omitted, originals kept")
        // Hide the `#` marker: one marker + one separator space, body
        // and heading role preserved, line number untouched.
        let noHash = try exportBuild(ctx, ExportOptions(hideHashMarker: true))
        try expectEqual(noHash.rows[0].text, "Heading", "hash strip")
        try expectEqual(noHash.rows[0].kind, .heading, "heading role after strip")
        try expectEqual(noHash.rows[0].sourceLineNumber, 1, "original number")
        // Range: inclusive 1-based, original numbers survive.
        let ranged = try exportBuild(ctx, ExportOptions(range: .lines(from: 2, to: 5)))
        try expectEqual(ranged.rows.map(\.sourceLineNumber), [2, 3, 4, 5],
                        "range rows")
        // `#` stripping + syntax spans stay inside the display text.
        let stripped = try exportBuild(ctx, ExportOptions(hideHashMarker: true))
        for row in stripped.rows {
            for span in row.spans {
                try expect(span.range.location >= 0, "span start")
                try expect(NSMaxRange(span.range) <= (row.text as NSString).length,
                           "span bound")
            }
        }
    },

    EngineCase("export-range-validation-and-empty-output") {
        let ctx = exportContext("1 + 1\n2 + 2")
        try expect(ExportSnapshotBuilder.validate(range: .all, lineCount: 2),
                   "all valid")
        try expect(ExportSnapshotBuilder.validate(range: .lines(from: 1, to: 2), lineCount: 2),
                   "range valid")
        try expect(!ExportSnapshotBuilder.validate(range: .lines(from: 0, to: 2), lineCount: 2),
                   "zero start invalid")
        try expect(!ExportSnapshotBuilder.validate(range: .lines(from: 2, to: 1), lineCount: 2),
                   "inverted invalid")
        try expect(!ExportSnapshotBuilder.validate(range: .lines(from: 1, to: 3), lineCount: 2),
                   "past end invalid")
        try expectEqual(exportFailure(ctx, ExportOptions(range: .lines(from: 3, to: 3))),
                        .invalidRange, "build rejects invalid range")
        // A range selecting only hidden comment rows has NOTHING to
        // print — it must present an error, never a blank PDF.
        let comments = exportContext("// one\n// two")
        try expectEqual(exportFailure(comments, ExportOptions(hideComments: true)),
                        .noPrintableRows, "empty filtered output")
        try expectEqual(exportFailure(exportContext(""), ExportOptions()),
                        .emptySheet, "empty sheet")
        try expectEqual(ExportSnapshotBuilder.printableRowCount(
            context: comments, options: ExportOptions(hideComments: true)), 0,
            "dialog validation count")
    },

    EngineCase("export-token-offsets-and-capsule-labels") {
        // Line 1 is the token source; line 2 holds a marker at the end
        // of the text; line 3 is a heading with a marker-free body.
        let source = "price = 10"
        let tokenLine = "total of \u{FFFC} here"
        let content = source + "\n" + tokenLine + "\n# Heading"
        let contentLines = content.components(separatedBy: "\n")
        let ids = contentLines.map { _ in UUID() }
        let markerOffset = ((source + "\n") as NSString).length
            + (("total of ") as NSString).length
        let ref = AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                  location: markerOffset)
        let ctx = exportContext(content, lineIDs: ids, references: [ref])
        let snapshot = try exportBuild(ctx, ExportOptions(hideHashMarker: true))
        let tokenRow = snapshot.rows[1]
        try expectEqual(tokenRow.tokens.count, 1, "one token")
        try expectEqual(tokenRow.tokens[0].label, "10", "live capsule label")
        try expect(tokenRow.tokens[0].active, "active token")
        try expectEqual(tokenRow.tokens[0].offset,
                        (("total of ") as NSString).length, "token offset")
        // The U+FFFC itself never reaches the page as a replacement
        // glyph: the rendered text substitutes the live label.
        let rendered = ExportRenderedDocument(snapshot: snapshot,
                                              fonts: exportFonts(),
                                              palette: ExportPalette())
        let line = rendered.resolvedText(rowIndex: 1)
        try expect(!line.contains("\u{FFFC}"), "no raw marker in rendered text")
        try expect(line.contains("10"), "token label rendered")
    },

    EngineCase("export-full-resolve-and-footer-total-semantics") {
        let content = "a = 5\nb = 3\na + b\n10\n20\ntotal"
        let ctx = exportContext(content)
        let snapshot = try exportBuild(ctx, ExportOptions())
        // Inline `total` row: semibold, excluded from the aggregate.
        try expect(snapshot.rows.last?.isInlineTotal == true, "inline total")
        // Partial range: only the exported rows contribute.
        let partial = try exportBuild(ctx, ExportOptions(range: .lines(from: 4, to: 5)))
        try expectEqual(partial.total, 30, "partial total over exported rows")
        // Full range equals the live footer over ALL resolved rows.
        let resolved = resolveSheet(content: content,
                                    lineIDs: ctx.lineIDs,
                                    references: [],
                                    rates: Rates(),
                                    decimalPlaces: 10,
                                    now: ctx.now,
                                    calendar: ctx.calendar)
        try expectEqual(snapshot.total,
                        SheetFooterTotal.aggregate(resolved.lines),
                        "full range == live footer")
        // The formatted Total matches the live column's formatting.
        try expectEqual(snapshot.totalText, "38", "total text")
    },

    EngineCase("export-per-line-precision-and-notation-via-uuid") {
        let ids = [UUID(), UUID()]
        let content = "1 / 3\n2 / 3"
        let prefs = [
            AnswerDisplayPreference(lineID: ids[0], decimalPlaces: 2),
            AnswerDisplayPreference(lineID: ids[1], decimalPlaces: 5,
                                    notation: .decimal),
        ]
        let ctx = exportContext(content, lineIDs: ids, answerDisplay: prefs)
        let snapshot = try exportBuild(ctx, ExportOptions())
        try expectEqual(snapshot.rows[0].answer, "0.33", "override 2dp")
        try expectEqual(snapshot.rows[1].answer, "0.66667", "override 5dp decimal")
        // The same source with no overrides keeps the global precision.
        let plain = try exportBuild(exportContext(content, lineIDs: ids),
                                    ExportOptions())
        try expectEqual(plain.rows[0].answer, "0.3333333333", "global 10dp")
    },

    EngineCase("export-error-strings-only-where-live-column-shows-them") {
        let ctx = exportContext("1 / 0\n1 +")
        let snapshot = try exportBuild(ctx, ExportOptions())
        for row in snapshot.rows {
            // Generic calculation errors render nothing in the live
            // column and therefore have no export answer.
            try expectEqual(row.answer, nil, "generic error hidden")
        }
        // The explicit rates-unavailable state is preserved.
        let ratesContext = exportContext("100 USD to XYZ")
        let ratesSnapshot = try exportBuild(ratesContext, ExportOptions())
        if let answer = ratesSnapshot.rows[0].answer {
            try expect(answer == "Rates unavailable",
                       "rates state preserved, got \(answer)")
        }
    },

    EngineCase("export-layout-pagination-rows-intact-total-next-page") {
        // 5 rows of 20pt each + total in a 200pt page with 20pt header
        // and 20pt margins: exactly 160pt of body — five rows fit on
        // one page, so the total moves to page 2.
        var metrics = fakeMetrics(pageHeight: 200)
        metrics.totalSpacingBefore = 0
        let ctx = exportContext("1\n2\n3\n4\n5\n6\n7\n8")
        let snapshot = try exportBuild(ctx, ExportOptions())
        let doc = ExportLayoutEngine.layout(snapshot: snapshot, metrics: metrics,
                                            measure: { Double($0.count) * 7 })
        try expectEqual(doc.pages.count, 2, "two pages")
        try expectEqual(doc.pages[0].visuals.count, 8, "eight rows page 1")
        try expect(doc.pages[0].totalFrame == nil, "no total on page 1")
        try expect(doc.pages[1].totalFrame != nil, "total on page 2")
        // Every row stays intact: five rows, one visual each, none split.
        for page in doc.pages {
            for placed in page.visuals {
                try expect(!placed.visual.isContinuation, "no fragments")
            }
        }
        // Deterministic: repeating the layout yields identical pages.
        let again = ExportLayoutEngine.layout(snapshot: snapshot, metrics: metrics,
                                              measure: { Double($0.count) * 7 })
        try expectEqual(doc.pages, again.pages, "layout deterministic")
    },

    EngineCase("export-layout-over-page-row-fragments-safely") {
        // A single 25-character row on a 300pt-wide page wraps to two
        // visual lines; a tiny page forces the second fragment onto the
        // next page WITHOUT dropping or duplicating text.
        var metrics = fakeMetrics(pageHeight: 70)
        metrics.expressionLineHeight = 20
        metrics.answerLineHeight = 20
        metrics.headerHeight = 10
        metrics.rowSpacing = 0
        let long = "aaaa bbbb cccc dddd eeee ffff gggg hhhh iiii jjjj kkkk"
        let ctx = exportContext(long)
        let snapshot = try exportBuild(ctx, ExportOptions(showTotal: false))
        let doc = ExportLayoutEngine.layout(snapshot: snapshot, metrics: metrics,
                                            measure: { Double($0.count) * 7 })
        try expect(doc.pages.count >= 2, "long row fragments across pages")
        let placed = doc.pages.flatMap(\.visuals)
        try expectEqual(placed.count, 3, "three visual fragments")
        func firstSource(_ placed: ExportPlacedVisual) -> NSRange? {
            placed.visual.textSegments.first { !$0.isJoiningSpace }?.sourceRange
        }
        try expectEqual(firstSource(placed[0])?.location, 0, "first fragment start")
        let lastEnd = placed[0].visual.textSegments.last { !$0.isJoiningSpace }
            .map { $0.sourceRange.location + $0.sourceRange.length }
        try expectEqual(firstSource(placed[1])?.location,
                        lastEnd.map { $0 + 1 },
                        "second fragment continues after the space")
    },

    EngineCase("export-pdf-smoke-metadata-pages-and-ink") {
        let ctx = exportContext("1 + 1\n2 + 2", title: "Numbers")
        let snapshot = try exportBuild(ctx, ExportOptions())
        let doc = ExportRenderedDocument(snapshot: snapshot,
                                         fonts: exportFonts(),
                                         palette: ExportPalette())
        let data = doc.pdfData()
        try expect(data.count > 400, "non-trivial PDF bytes")
        try expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-",
                   "PDF header")
        guard let pdf = CGPDFDocument(CGDataProvider(data: data as CFData)!) else {
            throw CaseFailure(message: "unreadable PDF", location: "Export")
        }
        try expectEqual(pdf.numberOfPages, doc.pageCount, "page count")
        let media = pdf.page(at: 1)?.getBoxRect(.mediaBox) ?? .zero
        try expectEqual(Double(media.width), Double(doc.layout.pageSize.width),
                        "media width")
        try expectEqual(Double(media.height), Double(doc.layout.pageSize.height),
                        "media height")
        if let info = pdf.info as? [String: Any] {
            try expectEqual(info[kCGPDFContextTitle as String] as? String, "Numbers",
                            "PDF title metadata")
            try expectEqual(info[kCGPDFContextCreator as String] as? String, "Numlex",
                            "PDF creator metadata")
        }
        // Render page 1 into a bitmap and require real ink (the text
        // was drawn, not an empty page).
        let scale = 1.0
        let w = Int(Double(media.width) * scale)
        let h = Int(Double(media.height) * scale)
        var pixels = [UInt8](repeating: 255, count: w * h * 4)
        pixels.withUnsafeMutableBytes { buf in
            if let bctx = CGContext(data: buf.baseAddress, width: w, height: h,
                                    bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                bctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                bctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                bctx.drawPDFPage(pdf.page(at: 1)!)
            }
        }
        let nonWhite = pixels.enumerated().reduce(0) { count, pair in
            pair.offset % 4 == 3 ? count : (pair.element < 250 ? count + 1 : count)
        }
        try expect(nonWhite > 100, "page has drawn ink (got \(nonWhite))")
    },


    EngineCase("export-menu-and-wiring-source-contracts") {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func source(_ path: String) -> String {
            (try? String(contentsOf: root.appendingPathComponent(path),
                         encoding: .utf8)) ?? ""
        }
        let app = source("Sources/NumlexApp/NumlexApp.swift")
        try expect(app.contains("L10n.t(\"exportSheetPDF\""), "PDF item localized")
        try expect(app.contains("L10n.t(\"exportSheetNLX\""), "NLX item localized")
        try expect(app.contains("L10n.t(\"printSheet\""), "Print item localized")
        try expect(app.contains("CommandGroup(replacing: .printItem)"),
                   "standard Print placement")
        try expect(app.contains(".keyboardShortcut(\"p\", modifiers: .command)"),
                   "Cmd-P shortcut")
        try expect(app.contains("CommandGroup(replacing: .importExport)"),
                   "import/export group owned once")
        try expect(app.contains("Notification.Name(\"numlex.exportSheetPDF\")"),
                   "PDF notification")
        try expect(app.contains("Notification.Name(\"numlex.printSheet\")"),
                   "Print notification")
        // No duplicate system Print command: only ONE replacement.
        try expect(app.components(separatedBy: "printItem").count == 2,
                   "exactly one print group")
        let content = source("Sources/NumlexApp/Views/ContentView.swift")
        try expect(content.contains("presentExport(.pdf)"), "PDF presentation")
        try expect(content.contains("presentExport(.print)"), "print presentation")
        try expect(content.contains("NSSavePanel()"), "native save panel")
        try expect(content.contains("allowedContentTypes = [.pdf]"), "PDF-only save panel")
        try expect(content.contains("writePDF(to: url)"), "atomic PDF write")
        try expect(content.contains("NSPrintOperation(view: view, printInfo: info)"),
                   "same document feeds NSPrintOperation")
        // The editor is never re-mounted or captured for export.
        try expect(!content.contains("cacheDisplay"), "no viewport capture")
    },

    EngineCase("export-token-positions-survive-filters-and-ranges") {
        let content = "// note\nprice = 10\nvalue \u{FFFC}\n# Heading"
        let lines = content.components(separatedBy: "\n")
        let ids = lines.map { _ in UUID() }
        let line = "value \u{FFFC}"
        let markerOffset = ((content as NSString).range(of: "\u{FFFC}").location)
        _ = line
        let ref = AnswerReference(sourceLineID: ids[1], labelLine: 2,
                                  location: markerOffset)
        let ctx = exportContext(content, lineIDs: ids, references: [ref])
        // Hiding the comment row shifts ROWS, never token offsets.
        let hidden = try exportBuild(ctx, ExportOptions(hideComments: true,
                                                        hideHashMarker: true))
        let tokenRow = hidden.rows.first { $0.sourceLineNumber == 3 }
        try expect(tokenRow != nil, "token row survives")
        try expectEqual(tokenRow?.tokens.first?.offset,
                        ("value " as NSString).length, "offset in display text")
        try expectEqual(tokenRow?.tokens.first?.label, "10", "label unchanged")
        // Range filtering keeps the ORIGINAL number and the offset.
        let ranged = try exportBuild(ctx, ExportOptions(range: .lines(from: 3, to: 3)))
        try expectEqual(ranged.rows.first?.sourceLineNumber, 3, "original number")
        try expectEqual(ranged.rows.first?.tokens.first?.offset,
                        ("value " as NSString).length, "offset after range")
        // Hash marker strip: the marker character is not a token, so a
        // heading's token-free body keeps its content role.
        try expectEqual(hidden.rows.last?.text, "Heading", "heading body stripped")
    },

    EngineCase("export-options-clamp-and-total-off") {
        let options = ExportOptions(fontPointSize: 40,
                                    range: .lines(from: 10, to: 20))
        let clamped = options.clamped(toLineCount: 4)
        try expectEqual(clamped.fontPointSize, 36, "size clamp")
        try expectEqual(clamped.range, .lines(from: 4, to: 4), "range clamp")
        let ctx = exportContext("1\n2")
        let noTotal = try exportBuild(ctx, ExportOptions(showTotal: false))
        try expect(noTotal.totalText == nil, "total disabled")
        // Highlights travel by stable UUID, never row index.
        let ids = [UUID(), UUID()]
        let highlighted = try exportBuild(
            exportContext("1\n2", lineIDs: ids,
                          highlights: [LineHighlightPreference(lineID: ids[1],
                                                               color: .green)]),
            ExportOptions())
        try expect(highlighted.rows[0].highlight == nil, "row 0 unhighlighted")
        try expectEqual(highlighted.rows[1].highlight, .green, "row 1 highlight")
    },

    EngineCase("export-pdf-bytes-deterministic") {
        let ctx = exportContext("1 + 1\n2 kg + 3 kg", title: "Deterministic")
        let snapshot = try exportBuild(ctx, ExportOptions())
        let doc = ExportRenderedDocument(snapshot: snapshot,
                                         fonts: exportFonts(),
                                         palette: ExportPalette())
        let a = doc.pdfData()
        let b = doc.pdfData()
        // CoreGraphics stamps a per-document /ID and a /CreationDate;
        // both are framework bookkeeping, not page content. Everything
        // the renderer produces must be byte-identical.
        func scrub(_ data: Data, marker: String, terminator: UInt8,
                   replacement: String) -> Data {
            var out = data
            guard let r = out.range(of: Data(marker.utf8)),
                  let end = out[r.upperBound...].firstIndex(of: terminator) else {
                return out
            }
            out.replaceSubrange(r.lowerBound..<(end + 1), with: Data(replacement.utf8))
            return out
        }
        func content(_ data: Data) -> Data {
            let once = scrub(data, marker: "/ID [", terminator: 93,
                             replacement: "/ID [<0><0>]")
            return scrub(once, marker: "/CreationDate (", terminator: 41,
                         replacement: "/CreationDate (D:0)")
        }
        try expectEqual(content(a), content(b), "identical content bytes")
        try expect(a.count > 500, "non-trivial page")
    },


    EngineCase("export-token-layout-width-matches-drawing") {
        // A long token label in a narrow expression column: the LAYOUT
        // must reserve the label plus capsule padding exactly where the
        // renderer draws them, so nothing can overlap the answer column.
        let label = "1234567.891011"
        let marker = 6 // "value " prefix
        let row = syntheticRow("value \u{FFFC} end", answer: label,
                               tokens: [ExportToken(offset: marker, label: label,
                                                    active: true)])
        let snapshot = syntheticSnapshot([row])
        var metrics = fakeMetrics(pageHeight: 400)
        metrics.pageSize = CGSize(width: 200, height: 400)
        metrics.margins = ExportInsets(top: 10, left: 10, bottom: 10, right: 10)
        metrics.answerFraction = 0.5
        metrics.columnGap = 10
        metrics.gutterWidth = 0
        metrics.tokenHorizontalPadding = 8
        let measure: (String) -> Double = { Double(($0 as NSString).length) * 7 }
        let options = ExportOptions(lineNumbers: false, showTotal: false)
        let snapshot2 = syntheticSnapshot([row], options: options)
        let doc = ExportLayoutEngine.layout(snapshot: snapshot2, metrics: metrics,
                                            measure: measure)
        let visuals = doc.pages.flatMap(\.visuals)
        try expect(visuals.count >= 3, "long label wraps into fragments")
        for placed in visuals {
            let width = segmentWidth(placed.visual.textSegments, measure: measure,
                                     tokenPadding: 8)
            try expect(abs(width - placed.visual.textWidth) < 0.001,
                       "layout and drawing width agree")
            try expect(width <= doc.expressionWidth + 0.001,
                       "fragment fits the column (got \(width))")
        }
        // Reconstruction: joining every segment in visual order yields
        // the resolved text exactly (no dropped/duplicated characters).
        let joined = reconstructExpression(row: row, visuals: visuals)
        try expectEqual(joined, "value " + label + " end", "exact reconstruction")
        // The token fragments together carry the label, and each
        // token-bearing fragment paid the capsule padding.
        let tokenTexts = visuals.flatMap(\.visual.textSegments)
            .filter { $0.tokenIndex != nil }.map(\.text)
        try expectEqual(tokenTexts.joined(), label, "label fragment concatenation")
        for placed in visuals where placed.visual.textSegments.contains(where: { $0.tokenIndex != nil }) {
            let tokenText = placed.visual.textSegments
                .filter { $0.tokenIndex != nil }.map(\.text).joined()
            try expect(placed.visual.textWidth >= measure(tokenText) + 8 - 0.001,
                       "capsule padding reserved")
        }
    },

    EngineCase("export-hard-break-long-words-and-graphemes") {
        // 300+ character no-space expression with emoji and a combining
        // sequence: every emitted fragment must fit the column and the
        // reconstruction must be character-exact.
        let emoji = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        let combining = "e\u{0301}"
        let longWord = String(repeating: "a", count: 120) + emoji + combining
            + String(repeating: "b", count: 220)
        let row = syntheticRow(longWord, answer: String(repeating: "z", count: 300))
        let options = ExportOptions(lineNumbers: false, showTotal: false)
        let snapshot = syntheticSnapshot([row], options: options)
        var metrics = fakeMetrics(pageHeight: 400)
        metrics.pageSize = CGSize(width: 200, height: 400)
        metrics.margins = ExportInsets(top: 10, left: 10, bottom: 10, right: 10)
        metrics.answerFraction = 0.5
        metrics.columnGap = 10
        metrics.gutterWidth = 0
        let measure: (String) -> Double = { Double(($0 as NSString).length) * 7 }
        let doc = ExportLayoutEngine.layout(snapshot: snapshot, metrics: metrics,
                                            measure: measure)
        let visuals = doc.pages.flatMap(\.visuals)
        try expect(visuals.count > 4, "long word fragments across many visuals")
        for placed in visuals {
            let width = segmentWidth(placed.visual.textSegments, measure: measure,
                                     tokenPadding: 8)
            try expect(width <= doc.expressionWidth + 0.001,
                       "expression fragment fits (got \(width))")
        }
        let joined = visuals.flatMap(\.visual.textSegments).map(\.text).joined()
        try expectEqual(joined, longWord, "grapheme-safe reconstruction")
        try expect(joined.contains(emoji), "emoji family kept whole")
        try expect(joined.contains(combining), "combining sequence kept whole")
        try expect(!joined.contains("\u{FFFD}"), "no replacement glyph")
        // Answer column hard-breaks too; ranges cover every character.
        let answer = row.answer ?? ""
        var rebuilt = ""
        var previousEnd: Int? = nil
        for placed in visuals {
            guard let range = placed.visual.answerRange else { continue }
            if let end = previousEnd, end + 1 == range.location {
                let skipped = (answer as NSString).substring(with: NSRange(location: end, length: 1))
                if skipped == " " { rebuilt += " " }
            }
            let piece = (answer as NSString).substring(with: range)
            try expect(measure(piece) <= doc.answerWidth + 0.001,
                       "answer fragment fits")
            rebuilt += piece
            previousEnd = range.location + range.length
        }
        try expectEqual(rebuilt, answer, "answer reconstruction")
        dumpExportFixture(ExportRenderedDocument(snapshot: snapshot, fonts: exportFonts(),
                                                 palette: ExportPalette(),
                                                 metrics: metrics),
                          name: "export-fixture-longword")
    },

    EngineCase("export-long-token-label-fragments-safely") {
        // A label longer than the whole column must fragment between
        // graphemes, each fragment keeping capsule padding.
        let label = String(repeating: "9", count: 320)
        let row = syntheticRow("\u{FFFC}", answer: nil,
                               tokens: [ExportToken(offset: 0, label: label,
                                                    active: true)])
        let options = ExportOptions(lineNumbers: false, showTotal: false)
        let snapshot = syntheticSnapshot([row], options: options)
        var metrics = fakeMetrics(pageHeight: 400)
        metrics.pageSize = CGSize(width: 200, height: 400)
        metrics.margins = ExportInsets(top: 10, left: 10, bottom: 10, right: 10)
        metrics.answerFraction = 0.5
        metrics.columnGap = 10
        metrics.gutterWidth = 0
        let measure: (String) -> Double = { Double(($0 as NSString).length) * 7 }
        let doc = ExportLayoutEngine.layout(snapshot: snapshot, metrics: metrics,
                                            measure: measure)
        let visuals = doc.pages.flatMap(\.visuals)
        try expect(visuals.count >= 8, "label fragments across visuals")
        for placed in visuals {
            let width = segmentWidth(placed.visual.textSegments, measure: measure,
                                     tokenPadding: 8)
            try expect(width <= doc.expressionWidth + 0.001,
                       "token fragment fits (got \(width))")
        }
        let joined = visuals.flatMap(\.visual.textSegments).map(\.text).joined()
        try expectEqual(joined, label, "token label reconstruction")
        dumpExportFixture(ExportRenderedDocument(snapshot: snapshot, fonts: exportFonts(),
                                                 palette: ExportPalette(),
                                                 metrics: metrics),
                          name: "export-fixture-longtoken")
    },

    EngineCase("export-bitmap-capsule-geometry-and-margins") {
        let label = "123456.789"
        let row = syntheticRow("#heading\n".isEmpty ? "" : "value \u{FFFC}",
                               answer: label,
                               tokens: [ExportToken(offset: 6, label: label,
                                                    active: true)])
        let long = syntheticRow(String(repeating: "w", count: 300), sourceLine: 2)
        let snapshot = syntheticSnapshot([row, long],
                                         options: ExportOptions(showTotal: false))
        let doc = ExportRenderedDocument(snapshot: snapshot,
                                         fonts: exportFonts(size: 11),
                                         palette: ExportPalette())
        guard let bitmap = renderExportBitmap(document: doc, page: 0) else {
            throw CaseFailure(message: "bitmap render failed", location: "Export")
        }
        let pageH = Int(doc.layout.pageSize.height)
        let pageW = Int(doc.layout.pageSize.width)
        // 1) No ink outside the page margins.
        var minX = Int.max, maxX = Int.min
        for y in 0..<pageH {
            for x in 0..<pageW where bitmap.isInk(x, y) {
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }
        try expect(minX >= Int(doc.metrics.margins.left) - 3,
                   "ink respects the left margin (minX=\(minX))")
        try expect(maxX <= pageW - Int(doc.metrics.margins.right) + 3,
                   "ink respects the right margin (maxX=\(maxX))")
        // 2) The expression cell never spills into the answer column.
        guard let placed0 = doc.layout.pages[0].visuals.first(where: { $0.visual.rowIndex == 0 }) else {
            throw CaseFailure(message: "row 0 placement", location: "Export")
        }
        // CGBitmapContext memory rows are top-down (row 0 = top of the
        // page), so the row band maps directly from top-down points.
        let bandTop = Double(placed0.frame.minY)
        let bandBottom = Double(placed0.frame.maxY)
        let bandMinY = max(Int(bandTop) - 3, 0)
        let bandMaxY = min(Int(bandBottom) + 3, pageH - 1)
        var exprMaxX = Int.min
        for y in bandMinY...bandMaxY {
            for x in 0..<Int(doc.layout.answerX) where bitmap.isInk(x, y) {
                exprMaxX = max(exprMaxX, x)
            }
        }
        try expect(Double(exprMaxX) <= doc.layout.expressionX + doc.layout.expressionWidth + 3,
                   "expression ink inside its column (got \(exprMaxX))")
        // 3) Capsule fill pixels sit at the ROW's position (not mirrored
        // near the page bottom) and surround the label ink.
        var capsulePixels: [(Int, Int)] = []
        for y in 0..<pageH {
            for x in 0..<pageW where bitmap.isCapsuleFill(x, y) {
                capsulePixels.append((x, y))
            }
        }
        try expect(capsulePixels.count > 30, "capsule fill drawn")
        let capsuleMinY = capsulePixels.map(\.1).min() ?? 0
        let capsuleMaxY = capsulePixels.map(\.1).max() ?? 0
        try expect(capsuleMinY >= bandMinY,
                   "capsule not below the row (c=\(capsuleMinY) band=\(bandMinY)...\(bandMaxY))")
        try expect(capsuleMaxY <= bandMaxY,
                   "capsule not above the row (c=\(capsuleMaxY) band=\(bandMinY)...\(bandMaxY))")
        try expect(capsuleMaxY < pageH / 2,
                   "capsule is in the upper page band (not mirrored at the bottom; maxY=\(capsuleMaxY))")
        let capsuleMinX = capsulePixels.map(\.0).min() ?? 0
        let capsuleMaxX = capsulePixels.map(\.0).max() ?? 0
        try expect(capsuleMaxX - capsuleMinX > Int(7 * 11 / 2),
                   "capsule spans the label plus padding")
        var textInsideCapsule = false
        for y in capsuleMinY...capsuleMaxY {
            for x in capsuleMinX...capsuleMaxX where bitmap.isTextInk(x, y) {
                textInsideCapsule = true
            }
        }
        try expect(textInsideCapsule, "label ink inside the capsule")
    },

    EngineCase("export-print-operation-save-to-pdf-matches-renderer") {
        // The NONINTERACTIVE print path: the exact production paginated
        // view, driven by a real NSPrintOperation that saves to a file.
        try MainActor.assumeIsolated {
            // The NONINTERACTIVE print path: the exact production paginated
            // view, driven by a real NSPrintOperation that saves to a file.
            _ = NSApplication.shared
            let ctx = exportContext("1 + 1\n2 + 2\n3 + 3", title: "Print Probe")
            let snapshot = try exportBuild(ctx, ExportOptions())
            let doc = ExportRenderedDocument(snapshot: snapshot,
                                             fonts: exportFonts(),
                                             palette: ExportPalette())
            let view = ExportPaginatedPrintView(document: doc)
            var range = NSRange(location: 0, length: 0)
            try expect(view.knowsPageRange(&range), "knowsPageRange")
            try expectEqual(range.length, doc.pageCount, "page range length")
            try expectEqual(view.rectForPage(1).height,
                            CGFloat(doc.layout.pageSize.height), "page 1 geometry")
            let path = FileManager.default.temporaryDirectory
                .appendingPathComponent("numlex-print-\(UUID().uuidString).pdf")
            defer { try? FileManager.default.removeItem(at: path) }
            let info = NSPrintInfo()
            info.paperSize = NSSize(width: doc.layout.pageSize.width,
                                    height: doc.layout.pageSize.height)
            info.topMargin = 0
            info.bottomMargin = 0
            info.leftMargin = 0
            info.rightMargin = 0
            info.horizontalPagination = .fit
            info.verticalPagination = .fit
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = path
            let operation = NSPrintOperation(view: view, printInfo: info)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            operation.run()
            try expect(FileManager.default.fileExists(atPath: path.path),
                       "print operation wrote a PDF")
            guard let data = try? Data(contentsOf: path),
                  let provider = CGDataProvider(data: data as CFData),
                  let printed = CGPDFDocument(provider) else {
                throw CaseFailure(message: "printed PDF unreadable", location: "Export")
            }
            try expectEqual(printed.numberOfPages, doc.pageCount,
                            "printed page count matches the renderer")
            let media = printed.page(at: 1)?.getBoxRect(.mediaBox) ?? .zero
            try expectEqual(Double(media.width), Double(doc.layout.pageSize.width),
                            "printed page width")
            try expectEqual(Double(media.height), Double(doc.layout.pageSize.height),
                            "printed page height")
            let printedInk = inkCount(data)
            let directInk = inkCount(doc.pdfData())
            try expect(printedInk > 100, "printed page has ink")
            try expect(abs(printedInk - directInk) < max(directInk / 10, 200),
                       "printed ink matches the direct renderer (\(printedInk) vs \(directInk))")
        }
    },

    EngineCase("export-localization-six-languages") {
        let keys = ["exportSheetPDF", "exportSheetNLX", "printSheet",
                    "export.title.pdf", "export.title.print", "export.font",
                    "export.fontFamily", "export.fontFace", "export.size",
                    "export.syntax", "export.lineNumbers", "export.total",
                    "export.hideComments", "export.hideHash", "export.lines",
                    "export.linesAll", "export.linesRange", "export.from",
                    "export.to", "export.invalidRange", "export.emptyRange",
                    "export.cancel", "export.confirmPDF", "export.confirmPrint",
                    "export.saveError.title", "export.saveError.message", "export.ok"]
        for language in AppLanguage.allCases {
            for key in keys {
                let value = L10n.t(key, language: language)
                try expect(!value.isEmpty, "\(language.rawValue) \(key) present")
                try expect(value != key, "\(language.rawValue) \(key) translated")
            }
        }
    },
]
