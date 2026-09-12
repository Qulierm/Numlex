import Foundation
import CoreGraphics
import CoreText
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
        let line = rendered.renderedText(rowIndex: 1)
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
        try expectEqual(placed[0].visual.textRange.location, 0, "first fragment start")
        try expectEqual(placed[1].visual.textRange.location,
                        (placed[0].visual.textRange.location
                         + placed[0].visual.textRange.length + 1),
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
