import Foundation
import CoreGraphics
import CoreText
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import NumlexCore

// MARK: - Package 7: shared sheet-line grammar (tags, dividers, headings)

private func p7number(_ line: SheetLine) -> Double? {
    if case .number(let v, _, _, _) = line.result { return v }
    if case .integer(let v, _) = line.result { return Double(v) }
    return nil
}

private func p7Fonts(size: Double = 12) -> ExportFonts {
    func font(_ name: String) -> CTFont {
        let desc = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: name as CFString,
            kCTFontSizeAttribute: size as CFNumber,
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(desc, size, nil)
    }
    return ExportFonts(expression: font("Helvetica"), answer: font("Helvetica"),
                       semiboldAnswer: font("Helvetica-Bold"), heading: font("Helvetica-Bold"),
                       title: font("Helvetica-Bold"), chrome: font("Helvetica"),
                       token: font("Menlo"))
}

private func p7DumpFixture(_ document: ExportRenderedDocument, name: String) {
    guard ProcessInfo.processInfo.environment["NUMLEX_EXPORT_FIXTURES"] != nil else { return }
    let dir = "/tmp/qa-out"
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    try? document.pdfData().write(to: URL(fileURLWithPath: "\(dir)/\(name).pdf"))
    let size = document.layout.pageSize
    let w = Int(size.width), h = Int(size.height)
    guard w > 0, h > 0, let page = document.layout.pages.first else { return }
    let buffer = UnsafeMutableRawPointer.allocate(byteCount: w * h * 4, alignment: 4)
    defer { buffer.deallocate() }
    guard let ctx = CGContext(data: buffer, width: w, height: h,
                              bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    document.draw(page: page, in: ctx)
    if let image = ctx.makeImage(),
       let dest = CGImageDestinationCreateWithURL(
           URL(fileURLWithPath: "\(dir)/\(name).png") as CFURL,
           UTType.png.identifier as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

private func exportProbeContext(_ content: String) -> ExportPresentationContext {
    ExportPresentationContext(
        sheetID: UUID(), sheetTitle: "Probe", content: content,
        lineIDs: content.components(separatedBy: "\n").map { _ in UUID() },
        references: [], answerDisplay: [], highlights: [],
        rates: Rates(), decimalPlaces: 7,
        now: Date(timeIntervalSince1970: 1_700_000_000),
        calendar: Calendar(identifier: .gregorian), constants: [],
        weather: .empty, geo: .empty, numberContext: .legacy,
        unitContext: .builtIns, preferences: .defaults,
        financial: .defaults, presentation: .defaults, language: .en)
}

private func p7Source(_ path: String) -> String {
    let fromFile = URL(fileURLWithPath: #file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    for root in [fromFile.path, FileManager.default.currentDirectoryPath] {
        let full = (root as NSString).appendingPathComponent(path)
        if let text = try? String(contentsOfFile: full, encoding: .utf8) { return text }
    }
    return ""
}

private func p7value(_ line: SheetLine) -> Double? {
    if let n = p7number(line) { return n }
    if case .variable(_, let v, _, _) = line.result { return v }
    return nil
}

private func p7rows(_ source: String) -> [SheetLine] {
    var vars: [String: Double] = [:]
    return evaluateSheet(source, variables: &vars, rates: Rates(), decimalPlaces: 7)
}

public let package7Cases: [EngineCase] = [

    EngineCase("p7-heading-requires-hash-space") {
        let rows = p7rows("# Head\n#food\n#\n# tagless\nis #tag")
        try expectEqual(rows.count, 5, "one row per line")
        try expectEqual(SheetLineAnalysis.parse("# Head").kind, .heading)
        // A tagged `#food` line is TAG-ONLY (quiet blank), never heading.
        let tagOnly = SheetLineAnalysis.parse("#food")
        try expectEqual(tagOnly.kind, .tagOnly)
        try expectEqual(tagOnly.tags.map(\.key), ["food"])
        try expectEqual(rows[1].result, .blank, "tag-only line is quiet")
        // A lone `#` is ordinary prose (skip), never a heading.
        try expectEqual(SheetLineAnalysis.parse("#").kind, .expression)
        try expectEqual(rows[2].result, .skip, "lone hash is prose")
        // `# ` heading body keeps its text.
        try expectEqual(SheetLineAnalysis.parse("# Head").headingBodySpan,
                        NSRange(location: 2, length: 4))
    },

    EngineCase("p7-tag-suffix-grammar") {
        // Multiple whitespace-separated tags at the end.
        let multi = SheetLineAnalysis.parse("2 + 3 #math #cash")
        try expectEqual(multi.kind, .expression)
        try expectEqual(multi.tags.map(\.key), ["math", "cash"])
        try expectEqual(multi.evaluationProjection, "2 + 3")
        try expectEqual(multi.tagSuffixSpan, NSRange(location: 6, length: 11))
        // Duplicates dedupe (first spelling wins).
        let dup = SheetLineAnalysis.parse("x = 1 #a #A")
        try expectEqual(dup.tags.map(\.key), ["a"])
        try expectEqual(dup.tags.map(\.spelling), ["a"])
        // `2 #food + 3` is NOT a tag suffix (trailing token is `3`).
        let notTag = SheetLineAnalysis.parse("2 #food + 3")
        try expect(notTag.tags.isEmpty, "non-terminal hash is not a tag")
        try expectEqual(notTag.evaluationProjection, "2 #food + 3")
        // Identifier rules: must start with a letter; letters, digits,
        // `_` and `-` after that.
        for bad in ["#1abc", "#", "#a b", "#-lead", "#\u{301}x"] {
            let parsed = SheetLineAnalysis.parse(bad)
            try expect(parsed.tags.isEmpty, "\(bad) is not a tag")
        }
        for good in ["#a", "#A_1", "#café", "#tag-name", "#tagName2"] {
            let parsed = SheetLineAnalysis.parse(good)
            try expectEqual(parsed.tags.count, 1, "\(good) is a tag")
        }
        // Unicode normalization + case-insensitive key, source spelling
        // preserved.
        let nfc = SheetLineAnalysis.parse("1 #café")
        try expectEqual(nfc.tags[0].key, "café")
        try expectEqual(nfc.tags[0].spelling, "café")
        // 64-grapheme bound.
        let long = String(repeating: "a", count: 65)
        try expect(SheetLineAnalysis.parse("1 #\(long)").tags.isEmpty,
                   "over-long identifier is not a tag")
        try expectEqual(SheetLineAnalysis.parse("1 #\(String(repeating: "a", count: 64))")
            .tags.count, 1)
        // Headings and comments never declare tags.
        try expect(SheetLineAnalysis.parse("# h #tag").tags.isEmpty, "heading no tags")
        try expect(SheetLineAnalysis.parse("// c #tag").tags.isEmpty, "comment no tags")
    },

    EngineCase("p7-tags-never-change-the-answer") {
        let rows = p7rows("base = 10\nbase + 5 #sum #report\ntotal of nothing")
        try expectEqual(rows[1].result, .number(value: 15, unit: nil,
                                                kind: .plain, fraction: nil),
                        "tagged expression evaluates its body")
        // A tagged declaration declares normally.
        try expectEqual(rows[0].result, .variable(name: "base", value: 10,
                                                  kind: .plain, fraction: nil))
        // Bare token lines with tags keep resolving (covered in resolve
        // tests); here at least the projection is the marker-only body.
        let marker = SheetLineAnalysis.parse("\u{FFFC} #link")
        try expectEqual(marker.evaluationProjection, "\u{FFFC}")
        try expectEqual(marker.tags.map(\.key), ["link"])
    },

    EngineCase("p7-divider-exactness-and-metadata") {
        try expectEqual(SheetLineAnalysis.parse("---").kind, .divider)
        try expectEqual(SheetLineAnalysis.parse("  ---  ").kind, .divider)
        try expectEqual(SheetLineAnalysis.parse("----").kind, .expression,
                        "four dashes are ordinary")
        try expectEqual(SheetLineAnalysis.parse("—").kind, .expression)
        let rows = p7rows("1 + 1\n---\n2 + 2")
        try expectEqual(rows[1].result, .blank, "divider has no answer")
        try expectEqual(rows[1].metadata, .divider, "divider metadata")
        try expect(SheetFooterTotal.aggregate(rows) == 6,
                   "divider contributes nothing; 1+1 + 2+2")
        // `----` is an ordinary visible row (skip for prose-like dashes).
        let four = p7rows("----")
        try expectEqual(four[0].metadata, .ordinary, "four dashes ordinary")
        // Divider spans for styling.
        try expectEqual(SheetLineAnalysis.parse("  ---  ").dividerSpan,
                        NSRange(location: 2, length: 3))
    },


    EngineCase("p7-subtotal-forms-and-percent") {
        let rows = p7rows("10\n20\nsubtotal\n30\nsubtotal")
        try expectEqual(rows[2].metadata, .subtotal, "subtotal metadata")
        try expect(rows[2].isTotal, "derived presentation")
        try expectEqual(p7number(rows[2]), 30, "section sum")
        try expectEqual(p7number(rows[4]), 30, "second section sum")
        // Percent forms apply to the RAW subtotal.
        try expectEqual(p7number(p7rows("100\nsubtotal + 15%")[1]), 115)
        try expectEqual(p7number(p7rows("100\nsubtotal - 10%")[1]), 90)
        // Outer whitespace and case tolerance.
        try expectEqual(p7number(p7rows("100\n  SUBTOTAL + 15%  ")[1]), 115)
        // Empty subtotal is 0.
        try expectEqual(p7number(p7rows("subtotal")[0]), 0)
        // Near-misses stay ordinary rows.
        for bad in ["subtotal + 5", "subtotal +", "subtotal extra", "subtotal + abc%"] {
            try expectEqual(p7rows("5\n\(bad)")[1].metadata, .ordinary,
                            "\(bad) is not a subtotal")
        }
    },

    EngineCase("p7-subtotal-boundaries") {
        // A `# ` heading and an exact `---` divider both reset.
        try expectEqual(p7number(p7rows("10\n# h\n20\nsubtotal")[3]), 20,
                        "heading boundary")
        try expectEqual(p7number(p7rows("10\n---\n20\nsubtotal")[3]), 20,
                        "divider boundary")
        // A legacy total is NOT a subtotal boundary (its own row is
        // excluded as derived).
        try expectEqual(p7number(p7rows("10\ntotal\n20\nsubtotal")[3]), 30,
                        "legacy total excluded, not a boundary")
        // A subtotal resets only ITS accumulator: the legacy total
        // still spans its own boundary (legacy total row excluded).
        try expectEqual(p7number(p7rows("10\nsubtotal\n20\ntotal")[3]), 30,
                        "legacy section spans the subtotal row")
    },

    EngineCase("p7-subtotal-eligibility-is-source-aware") {
        // Declarations excluded; usage rows, percent/fraction/multiplier,
        // exact integers and token-in-expression included; money, units,
        // booleans and errors excluded.
        let content = "x = 5\nx + 5\n$7\n3 kg\ntrue\n50%\n1/4\n0xFF\n2 + 3\nsubtotal"
        let rows = p7rows(content)
        // 10 (usage) + 0.5 + 0.25 + 255 + 5 = 270.75
        try expectEqual(p7number(rows[9]), 270.75, "eligibility set")
        // A bare-token-only row is excluded in resolveSheet.
        let ids = (0..<4).map { _ in UUID() }
        let markerAt = ("10\nsubtotal\n" as NSString).length
        let refs = [AnswerReference(sourceLineID: ids[1], labelLine: 2,
                                    location: markerAt)]
        let resolved = resolveSheet(content: "10\nsubtotal\n\u{FFFC}\nsubtotal",
                                    lineIDs: ids, references: refs,
                                    rates: Rates(), decimalPlaces: 7)
        try expectEqual(p7number(resolved.lines[1]), 10, "first subtotal")
        try expectEqual(p7number(resolved.lines[3]), 0, "bare token excluded")
        // A token INSIDE a genuine expression is eligible.
        let markerAt2 = ("5\nsubtotal\n" as NSString).length
        let refs2 = [AnswerReference(sourceLineID: ids[1], labelLine: 2,
                                     location: markerAt2)]
        let inExpr = resolveSheet(content: "5\nsubtotal\n\u{FFFC} + 1\nsubtotal",
                                  lineIDs: Array(ids.prefix(4)), references: refs2,
                                  rates: Rates(), decimalPlaces: 7)
        try expectEqual(p7number(inExpr.lines[2]), 6, "token expression value")
        try expectEqual(p7number(inExpr.lines[3]), 6, "token-in-expression counts")
    },

    EngineCase("p7-named-subtotal-and-shadowing") {
        let rows = p7rows("10\n20\nsum = subtotal")
        try expectEqual(rows[2].metadata, .subtotal, "named subtotal metadata")
        try expectEqual(p7number(rows[2]), 30, "named subtotal value")
        // The name is written to the environment as a plain scalar.
        let use = p7rows("10\n20\nsum = subtotal\nsum + 1")
        try expectEqual(p7number(use[3]), 31, "named value usable")
        // Percentage on the named form.
        try expectEqual(p7number(p7rows("100\nsum = subtotal + 15%")[1]), 115)
        // Constants are never mutated.
        let fee = UserConstant(name: "fee", expression: "5")
        var vars: [String: Double] = [:]
        let constantRows = evaluateSheet("10\nfee = subtotal", variables: &vars,
                                         rates: Rates(), decimalPlaces: 7,
                                         constants: [fee])
        if case .error(let msg) = constantRows[1].result {
            try expectEqual(msg, "Cannot assign to constant", "constant guarded")
        } else {
            throw CaseFailure(message: "constant assignment errors", location: "p7")
        }
        // An ACTIVE variable named `subtotal` suppresses the bare command
        // but not the named form.
        let shadow = p7rows("subtotal = 5\nsubtotal\nx = subtotal")
        try expectEqual(shadow[0].result, .variable(name: "subtotal", value: 5,
                                                    kind: .plain, fraction: nil),
                        "assignment wins")
        try expectEqual(shadow[1].metadata, .ordinary, "bare usage suppressed")
        try expectEqual(p7number(shadow[1]), 5, "bare usage value")
        try expectEqual(shadow[2].metadata, .subtotal, "named form still a command")
        try expectEqual(p7number(shadow[2]), 5, "named subtotal of the section")
    },

    EngineCase("p7-grand-total-semantics") {
        try expectEqual(p7number(p7rows("10\nsubtotal\n20\nsubtotal\ngrand total")[4]),
                        30, "grand sums successful subtotals")
        // Fewer than two subtotals: quiet generic error.
        let one = p7rows("10\nsubtotal\ngrand total")
        if case .error(let msg) = one[2].result {
            try expectEqual(msg, InlineTotal.overflowMessage, "quiet generic error")
        } else {
            throw CaseFailure(message: "one subtotal errors", location: "p7")
        }
        // A divider does not erase the grand list.
        try expectEqual(p7number(p7rows("10\nsubtotal\n---\n20\nsubtotal\ngrand total")[5]),
                        30, "divider keeps the grand list")
        // Named grand total writes the value.
        let named = p7rows("10\nsubtotal\n20\nsubtotal\ng = grand total\ng + 1")
        try expectEqual(named[4].metadata, .grandTotal, "grand metadata")
        try expectEqual(p7number(named[4]), 30, "grand value")
        try expectEqual(p7number(named[5]), 31, "named grand usable")
        // Legacy totals are not subtotal ROW values.
        let legacy = p7rows("10\ntotal\n20\nsubtotal\ngrand total")
        if case .error = legacy[4].result {
        } else {
            throw CaseFailure(message: "one real subtotal errors", location: "p7")
        }
    },

    EngineCase("p7-subtotal-tokenizable-and-footer-excluded") {
        // A subtotal row is an ordinary number for tokens.
        let ids = (0..<3).map { _ in UUID() }
        let markerAt = ("10\nsubtotal\n" as NSString).length
        let refs = [AnswerReference(sourceLineID: ids[1], labelLine: 2,
                                    location: markerAt)]
        let resolved = resolveSheet(content: "10\nsubtotal\n\u{FFFC}",
                                    lineIDs: ids, references: refs,
                                    rates: Rates(), decimalPlaces: 7)
        try expectEqual(resolved.tokens.count, 1, "token resolves subtotal row")
        if case .active(let v, nil, _) = resolved.tokens[0].state {
            try expectEqual(v, 10, "token value")
        } else {
            throw CaseFailure(message: "subtotal token active", location: "p7")
        }
        // Derived rows never double-count in the footer.
        let rows = p7rows("10\nsubtotal\ngrand total")
        try expect(SheetFooterTotal.aggregate(rows) == 10,
                   "footer counts the ordinary row only")
    },


    EngineCase("p7-subtotal-insertion-plans") {
        let ids = (0..<3).map { _ in UUID() }
        // Whitespace-only line -> command replaces the line.
        let blank = SubtotalInsertionPlan.plan(content: "5\n   \n6", lineIndex: 1,
                                               command: "subtotal",
                                               priorSubtotalCount: Int.max)
        try expectEqual(blank?.content, "5\nsubtotal\n6", "blank line filled")
        try expectEqual(blank?.edit.range, NSRange(location: 2, length: 3), "edit range")
        try expectEqual(blank?.caret, 10, "caret after the command")
        // Strict empty assignment -> named subtotal.
        let named = SubtotalInsertionPlan.plan(content: "5\nsum =  \n6", lineIndex: 1,
                                               command: "subtotal",
                                               priorSubtotalCount: Int.max)
        try expectEqual(named?.content, "5\nsum = subtotal\n6", "named form filled")
        // Anything else is rejected.
        for content in ["5\n7\n", "5\nx = 1\n", "5\nsum = 1\n", "5\n// c\n"] {
            try expect(SubtotalInsertionPlan.plan(content: content, lineIndex: 1,
                                                  command: "subtotal",
                                                  priorSubtotalCount: Int.max) == nil,
                       "rejected: \(content)")
        }
        // Grand total requires two prior subtotals.
        try expect(SubtotalInsertionPlan.plan(content: "subtotal\n   ",
                                              lineIndex: 1, command: "grand total",
                                              priorSubtotalCount: 1) == nil,
                   "grand needs two prior subtotals")
        try expect(SubtotalInsertionPlan.plan(content: "subtotal\nsubtotal\n   ",
                                              lineIndex: 2, command: "grand total",
                                              priorSubtotalCount: 2) != nil,
                   "grand accepted with two")
        // The reconciled line IDs survive and following references move.
        let content = "a = 1\n   \nb = 2"
        let plan = SubtotalInsertionPlan.plan(content: content, lineIndex: 1,
                                              command: "subtotal",
                                              priorSubtotalCount: Int.max)!
        let reconciled = LineIdentity.reconcile(oldContent: content,
                                                oldLineIDs: ids,
                                                oldReferences: [],
                                                newContent: plan.content,
                                                edit: plan.edit)
        try expectEqual(reconciled.lineIDs, ids, "line IDs preserved")
    },

    EngineCase("p7-convert-to-normal-plans") {
        let ids = (0..<2).map { _ in UUID() }
        let bare = SubtotalConversionPlan.plan(content: "10\n20\nsubtotal",
                                               lineIndex: 2, value: 30,
                                               context: .legacy)!
        try expectEqual(bare.content, "10\n20\n30.0", "bare converted")
        try expectEqual(bare.caret, 10, "caret at the literal end")
        let named = SubtotalConversionPlan.plan(content: "10\nsum = subtotal",
                                                lineIndex: 1, value: 10.5,
                                                context: .legacy)!
        try expectEqual(named.content, "10\nsum = 10.5", "named form keeps LHS")
        // Decimal-comma locales produce a retypeable literal.
        let comma = SubtotalConversionPlan.plan(content: "sum = subtotal",
                                                lineIndex: 0, value: 10.5,
                                                context: NumberFormatContext(
                                                    locale: Locale(identifier: "de_DE"),
                                                    decimalSeparator: ",",
                                                    groupingSeparator: ".",
                                                    argumentSeparator: ";",
                                                    displayGrouping: true,
                                                    compactNotation: false,
                                                    convertForeignOnPaste: false))!
        try expectEqual(comma.content, "sum = 10,5", "decimal comma literal")
        // Line count and stable IDs survive.
        let reconciled = LineIdentity.reconcile(oldContent: "10\n20\nsubtotal",
                                                oldLineIDs: ids + [UUID()],
                                                oldReferences: [],
                                                newContent: bare.content,
                                                edit: bare.edit)
        try expectEqual(reconciled.lineIDs.count, 3, "line count unchanged")
    },


    EngineCase("p7-tag-aggregates-see-tagged-rows-above") {
        let content = "10 #food\n20 #food #cash\n30 #travel\n"
            + "total of #food\naverage of #food\ncount of #food\nmedian of #food\n"
            + "count of #cash"
        let rows = p7rows(content)
        try expectEqual(p7number(rows[3]), 30, "total of tagged rows")
        try expectEqual(p7number(rows[4]), 15, "average")
        try expectEqual(p7number(rows[5]), 2, "count")
        try expectEqual(p7number(rows[6]), 15, "median of two")
        try expectEqual(p7number(rows[7]), 1, "each tag contributes once per row")
        try expectEqual(rows[3].metadata, .tagAggregate, "aggregate metadata")
        try expect(rows[3].isTotal, "derived presentation")
        // The query sees only rows STRICTLY above it.
        let below = p7rows("total of #food\n10 #food")
        try expectEqual(p7number(below[0]), 0, "rows below never count")
        // A divider ends the segment.
        let divided = p7rows("10 #food\n---\n20 #food\ntotal of #food")
        try expectEqual(p7number(divided[3]), 20, "divider resets the segment")
        // Non-contiguous tagged rows all count (blank/prose gaps).
        let gaps = p7rows("1 #a\nx = 5\nplain prose\n2 #a\ntotal of #a")
        try expectEqual(p7number(gaps[4]), 3, "gaps spanned; declarations excluded")
    },

    EngineCase("p7-tag-aggregate-grammar-and-empty") {
        // Empty total/count are 0; average/median are quiet errors.
        try expectEqual(p7number(p7rows("total of #none")[0]), 0)
        try expectEqual(p7number(p7rows("count of #none")[0]), 0)
        for kind in ["average", "median"] {
            let rows = p7rows("\(kind) of #none")
            if case .error(let msg) = rows[0].result {
                try expectEqual(msg, InlineTotal.overflowMessage, "\(kind) empty errors")
            } else {
                throw CaseFailure(message: "\(kind) of empty errors", location: "p7")
            }
        }
        // Strict grammar: multiple query tags, trailing garbage and
        // invalid identifiers reject.
        for bad in ["total of #a #b", "total of #a extra", "total of", "total #a",
                    "sum of #a", "total of #1bad"] {
            let rows = p7rows("5 #a\n\(bad)")
            try expect(rows[1].metadata != .tagAggregate, "\(bad) rejected")
        }
        // Eligibility: money/units/units rows are excluded.
        let mixed = p7rows("5 #m\n$7 #m\n3 kg #m\n2 #m\ntotal of #m")
        try expectEqual(p7number(mixed[4]), 7, "only eligible tagged rows")
        // Tokens inside expressions count; bare tokens do not.
        let ids = (0..<4).map { _ in UUID() }
        let markerAt = ("5 #a\n" as NSString).length
        let refs = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                    location: markerAt)]
        _ = markerAt
        let bare = resolveSheet(content: "5 #a\n\u{FFFC} #a\ncount of #a",
                                lineIDs: ids, references: refs,
                                rates: Rates(), decimalPlaces: 7)
        try expectEqual(p7number(bare.lines[2]), 1, "bare token excluded")
    },

    EngineCase("p7-tag-aggregates-tokenizable-and-export") {
        // A finite aggregate row is an ordinary number for tokens.
        let ids = (0..<4).map { _ in UUID() }
        let markerAt = ("5 #a\ntotal of #a\n" as NSString).length
        let refs = [AnswerReference(sourceLineID: ids[1], labelLine: 2,
                                    location: markerAt)]
        let resolved = resolveSheet(content: "5 #a\ntotal of #a\n\u{FFFC}",
                                    lineIDs: ids, references: refs,
                                    rates: Rates(), decimalPlaces: 7)
        try expectEqual(resolved.tokens.count, 1, "aggregate token resolves")
        if case .active(let v, nil, _) = resolved.tokens[0].state {
            try expectEqual(v, 5, "token value")
        } else {
            throw CaseFailure(message: "aggregate token active", location: "p7")
        }
        // Derived rows never feed later aggregates or the footer.
        let rows = p7rows("5 #a\ntotal of #a\ntotal of #a")
        try expectEqual(p7number(rows[2]), 5, "aggregate not re-consumed")
        try expect(SheetFooterTotal.aggregate(rows) == 5,
                   "footer excludes derived aggregates")
        // PDF export marks the row derived (total kind, no double count).
        var vars: [String: Double] = [:]
        let snapshot = ExportSnapshotBuilder.build(
            context: exportProbeContext("5 #a\ntotal of #a"),
            options: ExportOptions(showTotal: false))
        switch snapshot {
        case .success(let s):
            try expect(s.rows.count == 2, "two export rows")
            try expect(s.rows[1].isInlineTotal, "aggregate row derived in export")
        case .failure(let e):
            throw CaseFailure(message: "export build failed: \(e)", location: "p7")
        }
        _ = vars
    },


    EngineCase("p7-math-functions-count-median-stdev-rand") {
        try expectEqual(try evaluateExpression("count(1, 2, 3)", variables: [:]), 3)
        try expectEqual(try evaluateExpression("median(1, 2, 3)", variables: [:]), 2)
        try expectEqual(try evaluateExpression("median(1, 2, 3, 4)", variables: [:]), 2.5)
        // Sample (n-1) standard deviation of the classic dataset.
        let sd = try evaluateExpression("stdev(2, 4, 4, 4, 5, 5, 7, 9)", variables: [:])
        try expectClose(sd, 2.138089935299395, 1e-9)
        // Arity + domain strictness.
        for bad in ["stdev(1)", "median()", "count()", "rand(1)", "rand(5, 1)"] {
            do {
                _ = try evaluateExpression(bad, variables: [:])
                throw CaseFailure(message: "\(bad) must fail", location: "p7")
            } catch is CaseFailure {
                throw CaseFailure(message: "\(bad) must fail", location: "p7")
            } catch {
            }
        }
        // rand without a context is a strict domain failure.
        do {
            _ = try evaluateExpression("rand(1, 6)", variables: [:])
            throw CaseFailure(message: "rand needs entropy", location: "p7")
        } catch is CaseFailure {
            throw CaseFailure(message: "rand needs entropy", location: "p7")
        } catch {
        }
        // With a context the bounds are inclusive and unbiased-int.
        let ctx = RandomEvaluationContext(sheetID: UUID(),
                                          draw: { low, high in high })
        let drawn = try evaluateExpression("rand(1, 6)", variables: [:], random: ctx)
        try expectEqual(drawn, 6)
        let nested = try evaluateExpression("10 + rand(1, 6)", variables: [:], random: ctx)
        try expectEqual(nested, 16)
    },

    EngineCase("p7-statistics-natural-forms") {
        try expectEqual(p7number(p7rows("median of 1, 2, 3")[0]), 2)
        try expectEqual(p7number(p7rows("count of 1, 2, 3, 4")[0]), 4)
        // The phrase lane rounds at the CALLER's decimalPlaces (7 here).
        let rows = p7rows("standard deviation of 2, 4, 4, 4, 5, 5, 7, 9")
        try expectClose(p7number(rows[0]) ?? .nan, 2.1380899, 1e-9)
        let randomRows = p7rows("random number between 1 and 6")
        try expectEqual(randomRows[0].metadata, .dynamic, "random phrase is dynamic")
        // Decimal-comma lists use the semicolon separator.
        let de = NumberFormatContext(locale: Locale(identifier: "de_DE"),
                                     decimalSeparator: ",",
                                     groupingSeparator: ".",
                                     argumentSeparator: ";",
                                     displayGrouping: true,
                                     compactNotation: false,
                                     convertForeignOnPaste: false)
        var vars: [String: Double] = [:]
        let deRows = evaluateSheet("median of 1,5; 2,5; 3,5", variables: &vars,
                                   rates: Rates(), decimalPlaces: 7,
                                   context: de)
        try expectEqual(p7number(deRows[0]), 2.5, "decimal-comma median")
    },

    EngineCase("p7-rand-epoch-stability-and-dynamic-ban") {
        final class Counter: @unchecked Sendable { var n = 0 }
        let counter = Counter()
        let store = RandomSampleStore()
        let sheetID = UUID()
        let context = RandomEvaluationContext(
            sheetID: sheetID, store: store,
            draw: { low, high in
                counter.n += 1
                return low
            })
        let ids = (0..<3).map { _ in UUID() }
        let content = "rand(1, 100)\n\u{FFFC}"
        let markerAt = ("rand(1, 100)\n" as NSString).length
        let refs = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                    location: markerAt)]
        let first = resolveSheet(content: content, lineIDs: ids, references: refs,
                                 rates: Rates(), decimalPlaces: 7,
                                 random: context)
        try expectEqual(first.lines[0].metadata, .dynamic, "dynamic metadata")
        try expectEqual(p7number(first.lines[0]), 1, "drawn value")
        // A duplicated pass with the SAME store sees the same sample and
        // does not redraw.
        let second = resolveSheet(content: content, lineIDs: ids, references: refs,
                                  rates: Rates(), decimalPlaces: 7,
                                  random: RandomEvaluationContext(
                                      sheetID: sheetID, store: store,
                                      draw: { low, high in
                                          counter.n += 1
                                          return high
                                      }))
        try expectEqual(p7number(second.lines[0]), 1, "stable across passes")
        try expectEqual(counter.n, 1, "one draw per epoch")
        // A token referencing the dynamic row is broken.
        try expectEqual(second.tokens.count, 1, "token present")
        if case .broken = second.tokens[0].state {
        } else {
            throw CaseFailure(message: "dynamic token broken", location: "p7")
        }
        // Clearing the store starts a new epoch (a fresh draw).
        store.clear()
        let third = resolveSheet(content: content, lineIDs: ids, references: refs,
                                 rates: Rates(), decimalPlaces: 7,
                                 random: context)
        // The injected provider deterministically returns `low`, so a
        // fresh draw is proven by the counter, not by a different value.
        try expectEqual(p7number(third.lines[0]), 1, "fresh draw")
        try expectEqual(counter.n, 2, "one new draw after clear")
    },


    EngineCase("p7-footer-statistics-values") {
        let rows = p7rows("1\n2\n3\ntotal")
        try expectEqual(SheetFooterStatistics.compute(rows, statistic: .sum),
                        .value(6), "sum")
        try expectEqual(SheetFooterStatistics.compute(rows, statistic: .average),
                        .value(2), "average")
        try expectEqual(SheetFooterStatistics.compute(rows, statistic: .count),
                        .count(3), "count")
        try expectEqual(SheetFooterStatistics.compute(rows, statistic: .median),
                        .value(2), "median")
        // Even counts use the overflow-safe midpoint.
        let even = p7rows("1\n2\n3\n4")
        try expectEqual(SheetFooterStatistics.compute(even, statistic: .median),
                        .value(2.5), "even median")
        // Derived aggregate rows never contribute.
        let derived = p7rows("1\n2\nsubtotal\ngrand total")
        try expectEqual(SheetFooterStatistics.compute(derived, statistic: .count),
                        .count(2), "derived excluded")
        // Magnitude eligibility is preserved (money/units count).
        let broad = p7rows("$7\n3 kg")
        try expectEqual(SheetFooterStatistics.compute(broad, statistic: .sum),
                        .value(10), "magnitude sum")
        // Nothing eligible -> nil.
        try expect(SheetFooterStatistics.compute(p7rows("// c\n---"), statistic: .sum) == nil,
                   "no eligible rows")
    },

    EngineCase("p7-footer-setting-is-tolerant-and-global") {
        // Missing key decodes to .sum.
        let legacy = """
        {"decimalPlaces":7,"fontSizeKey":"tf","language":"en","sheetName":"Sheet","lineNumbers":true,"fontColor":"white"}
        """
        let decoded = try JSONDecoder().decode(AppSettings.self,
                                               from: Data(legacy.utf8))
        try expectEqual(decoded.footerStatistic, .sum, "missing -> sum")
        // Malformed value decodes to .sum.
        let malformed = """
        {"decimalPlaces":7,"fontSizeKey":"tf","language":"en","sheetName":"Sheet","lineNumbers":true,"fontColor":"white","footerStatistic":"bogus"}
        """
        let malformedDecoded = try JSONDecoder().decode(AppSettings.self,
                                                        from: Data(malformed.utf8))
        try expectEqual(malformedDecoded.footerStatistic, .sum, "malformed -> sum")
        // Round-trip keeps an explicit choice.
        var settings = AppSettings.defaults
        settings.footerStatistic = .median
        let data = try JSONEncoder().encode(settings)
        let round = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(round.footerStatistic, .median, "round-trip")
    },

    EngineCase("p7-footer-statistic-in-pdf") {
        let context = exportProbeContext("1\n2\n3\n4")
        var medianContext = context
        medianContext = ExportPresentationContext(
            sheetID: context.sheetID, sheetTitle: "Stats", content: context.content,
            lineIDs: context.lineIDs, references: [], answerDisplay: [],
            highlights: [], rates: Rates(), decimalPlaces: 7, now: context.now,
            calendar: context.calendar, constants: [], weather: .empty, geo: .empty,
            numberContext: .legacy, unitContext: .builtIns, preferences: .defaults,
            financial: .defaults, presentation: .defaults, language: .en,
            footerStatistic: .median)
        switch ExportSnapshotBuilder.build(context: medianContext,
                                           options: ExportOptions()) {
        case .success(let snapshot):
            try expectEqual(snapshot.totalText, "2.5", "median value")
            try expectEqual(snapshot.totalLabel, "Median", "median label")
        case .failure(let e):
            throw CaseFailure(message: "export failed: \(e)", location: "p7")
        }
        var countContext = medianContext
        countContext = ExportPresentationContext(
            sheetID: context.sheetID, sheetTitle: "Stats", content: context.content,
            lineIDs: context.lineIDs, references: [], answerDisplay: [],
            highlights: [], rates: Rates(), decimalPlaces: 7, now: context.now,
            calendar: context.calendar, constants: [], weather: .empty, geo: .empty,
            numberContext: .legacy, unitContext: .builtIns, preferences: .defaults,
            financial: .defaults, presentation: .defaults, language: .en,
            footerStatistic: .count)
        switch ExportSnapshotBuilder.build(context: countContext,
                                           options: ExportOptions()) {
        case .success(let snapshot):
            try expectEqual(snapshot.totalText, "4", "count value")
            try expectEqual(snapshot.totalLabel, "Count", "count label")
        case .failure(let e):
            throw CaseFailure(message: "export failed: \(e)", location: "p7")
        }
    },


    EngineCase("p7-pdf-fixture-tags-dividers-subtotals-footer") {
        // Headless PDF evidence for the Package 7 presentation: tags,
        // an exact divider, a tag aggregate, TWO successful subtotals
        // and a grand total (350) that must appear as a DRAWN answer,
        // plus the median footer statistic (with its localized label).
        let content = "# Ledger\nrevenue = 125000\ncosts = 73000\n"
            + "profit = revenue - costs #money\n---\n100 #food\n200 #food\n"
            + "total of #food\nsubtotal\n50\nsubtotal\ngrand total"
        let ids = content.components(separatedBy: "\n").map { _ in UUID() }
        // The grand total actually resolves (two prior subtotals).
        var checkVars: [String: Double] = [:]
        let checkRows = evaluateSheet(content, variables: &checkVars,
                                      rates: Rates(), decimalPlaces: 7)
        try expectEqual(p7number(checkRows[11]), 350, "grand total value")
        try expectEqual(checkRows[11].metadata, .grandTotal, "grand metadata")
        try expect(checkRows[11].isTotal, "grand derived presentation")
        let context = ExportPresentationContext(
            sheetID: UUID(), sheetTitle: "Package 7", content: content,
            lineIDs: ids, references: [], answerDisplay: [], highlights: [],
            rates: Rates(), decimalPlaces: 7,
            now: Date(timeIntervalSince1970: 1_700_000_000),
            calendar: Calendar(identifier: .gregorian), constants: [],
            weather: .empty, geo: .empty, numberContext: .legacy,
            unitContext: .builtIns, preferences: .defaults, financial: .defaults,
            presentation: .defaults, language: .en, footerStatistic: .median)
        let snapshot: ExportSnapshot
        switch ExportSnapshotBuilder.build(context: context, options: ExportOptions()) {
        case .success(let s): snapshot = s
        case .failure(let e):
            throw CaseFailure(message: "package 7 export failed: \(e)", location: "p7")
        }
        let doc = ExportRenderedDocument(snapshot: snapshot, fonts: p7Fonts(),
                                         palette: ExportPalette())
        p7DumpFixture(doc, name: "export-package7")
        try expect(doc.pageCount >= 1, "package 7 PDF renders")
        try expectEqual(snapshot.totalLabel, "Median", "median footer label")
        if let pdf = PDFDocument(data: doc.pdfData()) {
            let text = pdf.string ?? ""
            try expect(text.contains("profit = revenue - costs #money"),
                       "tags stay in the exported text")
            try expect(text.contains("total of #food"), "tag aggregate text")
            try expect(text.contains("350"), "grand total answer is drawn")
            try expect(text.contains("Median"), "footer statistic label")
        }
    },

    EngineCase("p7-classifier-tag-and-divider-spans") {
        let spans = SyntaxClassifier.spans(for: "2 + 3 #math #cash\n---\n# Head",
                                           rates: Rates(), decimalPlaces: 7)
        let tags = spans[0].filter { $0.role == .tagMarker || $0.role == .tagBody }
        try expectEqual(tags.count, 4, "two tags, marker + body each")
        try expectEqual(tags[0].role, .tagMarker)
        try expectEqual(tags[0].range, NSRange(location: 6, length: 1))
        try expectEqual(tags[1].role, .tagBody)
        try expectEqual(tags[1].range, NSRange(location: 7, length: 4))
        try expectEqual(spans[1].map(\.role), [.divider])
        try expectEqual(spans[1][0].range, NSRange(location: 0, length: 3))
        try expectEqual(spans[2].map(\.role), [.hashMarker, .hashBody])
        try expectEqual(spans[2][0].range, NSRange(location: 0, length: 2))
    },


    // MARK: - Task 9 acceptance: empties, dynamics, stability, menus

    EngineCase("p7-empty-answer-double-tap-dispatch") {
        let number: LineResult = .number(value: 1, unit: nil, kind: .plain, fraction: nil)
        let variable: LineResult = .variable(name: "x", value: 1)
        let money: LineResult = .money(value: 5, code: "USD")
        try expectEqual(AnswerDoubleTapPlan.action(for: number, sourceLine: "1 + 1", isDynamic: false), .mintToken, "number mints")
        try expectEqual(AnswerDoubleTapPlan.action(for: variable, sourceLine: "x = 1", isDynamic: false), .mintToken, "variable mints")
        try expectEqual(AnswerDoubleTapPlan.action(for: money, sourceLine: "$5", isDynamic: false), .mintToken, "money mints")
        try expectEqual(AnswerDoubleTapPlan.action(for: number, sourceLine: "rand(1, 6)", isDynamic: true), .inert, "dynamic never mints")
        try expectEqual(AnswerDoubleTapPlan.action(for: .blank, sourceLine: "   ", isDynamic: false), .insertSubtotal, "whitespace inserts")
        try expectEqual(AnswerDoubleTapPlan.action(for: .error(message: "Missing expression"), sourceLine: "total =", isDynamic: false), .insertSubtotal, "empty assignment inserts")
        try expectEqual(AnswerDoubleTapPlan.action(for: .blank, sourceLine: "# Title", isDynamic: false), .inert, "heading inert")
        try expectEqual(AnswerDoubleTapPlan.action(for: .blank, sourceLine: "// c", isDynamic: false), .inert, "comment inert")
        try expectEqual(AnswerDoubleTapPlan.action(for: .blank, sourceLine: "---", isDynamic: false), .inert, "divider inert")
        try expectEqual(AnswerDoubleTapPlan.action(for: .blank, sourceLine: "#tag", isDynamic: false), .inert, "tag-only inert")
        try expectEqual(AnswerDoubleTapPlan.action(for: .skip, sourceLine: "plain prose", isDynamic: false), .inert, "prose inert")
        try expectEqual(AnswerDoubleTapPlan.action(for: .error(message: "Invalid expression"), sourceLine: "1 +", isDynamic: false), .inert, "error inert")
        try expectEqual(AnswerDoubleTapPlan.action(for: .error(message: "Missing expression"), sourceLine: "x = 1", isDynamic: false), .inert, "non-empty assignment inert")
        // Predicate and planner agree on both classes.
        for line in ["   ", "\t", "total =", "x =  "] {
            try expect(SubtotalInsertionPlan.isEligibleTarget(line: line), "eligible: \(line)")
            try expect(SubtotalInsertionPlan.plan(content: "5\n\(line)\n6", lineIndex: 1,
                                                  command: "subtotal",
                                                  priorSubtotalCount: Int.max) != nil,
                       "planned: \(line)")
        }
        for line in ["# Title", "// c", "---", "#tag", "plain prose", "1 +", "x = 1"] {
            try expect(!SubtotalInsertionPlan.isEligibleTarget(line: line), "inert: \(line)")
            try expect(SubtotalInsertionPlan.plan(content: "5\n\(line)\n6", lineIndex: 1,
                                                  command: "subtotal",
                                                  priorSubtotalCount: Int.max) == nil,
                       "rejected: \(line)")
        }
        // UI wiring: the catcher uses the shared plan and the empty path
        // is connected in the owner.
        let view = p7Source("Sources/NumlexApp/Views/AnswerColumnView.swift")
        try expect(view.contains("AnswerDoubleTapPlan.action("), "catcher uses the shared plan")
        try expect(view.contains("isDynamic: line.isDynamic"), "catcher passes the taint")
        try expect(p7Source("Sources/NumlexApp/Views/ContentView.swift")
                    .contains("onEmptyAnswerDoubleTap"), "empty path wired")
    },

    EngineCase("p7-dynamic-token-plan-refused") {
        let ids = [UUID()]
        let selection = NSRange(location: 0, length: 0)
        try expect(AnswerTokenInsertion.plan(content: "1", lineIDs: ids, references: [],
                                             sourceLineIndex: 0, selection: selection,
                                             sourceIsDynamic: true) == nil,
                   "dynamic source refuses the token plan")
        try expect(AnswerTokenInsertion.plan(content: "1", lineIDs: ids, references: [],
                                             sourceLineIndex: 0, selection: selection,
                                             sourceIsDynamic: false) != nil,
                   "ordinary source still plans")
        // The resolver marks the executed rand row and a referenced token
        // becomes broken (never a stale value).
        let ctx = RandomEvaluationContext(sheetID: UUID(), draw: { _, high in high })
        let content = "rand(1, 6)\n5\n\u{FFFC}"
        let contentIDs = (0..<3).map { _ in UUID() }
        let markerAt = ("rand(1, 6)\n5\n" as NSString).length
        let refs = [AnswerReference(sourceLineID: contentIDs[0], labelLine: 1,
                                    location: markerAt)]
        let resolved = resolveSheet(content: content, lineIDs: contentIDs, references: refs,
                                    rates: Rates(), decimalPlaces: 7, random: ctx)
        try expect(resolved.lines[0].isDynamic, "executed rand row dynamic")
        try expect(!resolved.lines[1].isDynamic, "ordinary row not dynamic")
        try expectEqual(resolved.tokens.count, 1, "token present")
        if case .broken = resolved.tokens[0].state {
        } else {
            throw CaseFailure(message: "dynamic source token is broken", location: "p7")
        }
    },

    EngineCase("p7-rand-registry-every-route") {
        // Free expression, whitespace before `(`.
        let free = RandomEvaluationContext(sheetID: UUID(), draw: { _, high in high })
        try expectEqual(try evaluateExpression("10 + rand (1, 6)", variables: [:],
                                               random: free), 16)
        // Single-identifier assignment route + name taint.
        let assign = RandomEvaluationContext(sheetID: UUID(), draw: { _, high in high })
        var av: [String: Double] = [:]
        let assigned = evaluateSheet("x = rand(1, 6)\nx + 1", variables: &av,
                                     rates: Rates(), decimalPlaces: 7, random: assign)
        try expectEqual(p7value(assigned[0]), 6, "assigned rand value")
        try expect(assigned[0].isDynamic, "assignment row dynamic")
        try expectEqual(p7number(assigned[1]), 7, "name value propagates")
        try expect(assigned[1].isDynamic, "referencing row dynamic")
        // Natural multiword assignment.
        let natural = RandomEvaluationContext(sheetID: UUID(), draw: { _, high in high })
        var nv: [String: Double] = [:]
        let naturalRows = evaluateSheet("total revenue = rand(1, 6)\ntotal revenue + 1",
                                        variables: &nv, rates: Rates(),
                                        decimalPlaces: 7, random: natural)
        try expectEqual(p7value(naturalRows[0]), 6, "natural assignment rand")
        try expectEqual(p7number(naturalRows[1]), 7, "natural name propagates")
        // Multiple calls draw multiple samples ONCE per epoch.
        let store = RandomSampleStore()
        var draws = 0
        let multi = RandomEvaluationContext(sheetID: UUID(), store: store,
                                            draw: { _, high in draws += 1; return high })
        var mv: [String: Double] = [:]
        let multiRows = evaluateSheet("rand(1, 6) + rand(1, 6)", variables: &mv,
                                      rates: Rates(), decimalPlaces: 7, random: multi)
        try expectEqual(p7number(multiRows[0]), 12, "two draws summed")
        try expectEqual(draws, 2, "one draw per call")
        var mv2: [String: Double] = [:]
        _ = evaluateSheet("rand(1, 6) + rand(1, 6)", variables: &mv2,
                          rates: Rates(), decimalPlaces: 7, random: multi)
        try expectEqual(draws, 2, "duplicated pass reuses samples")
        // Decimal-comma argument separator.
        let de = NumberFormatContext(locale: Locale(identifier: "de_DE"),
                                     decimalSeparator: ",",
                                     groupingSeparator: ".",
                                     argumentSeparator: ";",
                                     displayGrouping: true,
                                     compactNotation: false,
                                     convertForeignOnPaste: false)
        let deCtx = RandomEvaluationContext(sheetID: UUID(), draw: { _, high in high })
        try expectEqual(try evaluateExpression("rand(1; 6)", variables: [:],
                                               context: de, random: deCtx), 6)
        // Token expression + rand through the shared strict core.
        let tokenCtx = RandomEvaluationContext(sheetID: UUID(), draw: { _, high in high })
        let ids = [UUID(), UUID()]
        let tokenRefs = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                         location: 2)]
        let tokenRows = resolveSheet(content: "5\n\u{FFFC} + rand (1, 6)",
                                     lineIDs: ids, references: tokenRefs,
                                     rates: Rates(), decimalPlaces: 7, random: tokenCtx)
        try expectEqual(p7number(tokenRows.lines[1]), 11, "token + rand")
        try expect(tokenRows.lines[1].isDynamic, "token rand row dynamic")
    },

    EngineCase("p7-dynamic-detection-execution-aware") {
        // A lazy unselected branch never draws and never taints.
        let lazyStore = RandomSampleStore()
        var lazyDraws = 0
        let lazy = RandomEvaluationContext(sheetID: UUID(), store: lazyStore,
                                           draw: { _, high in lazyDraws += 1; return high })
        var lv: [String: Double] = [:]
        let lazyRows = evaluateSheet("if false then rand(1, 6) else 5", variables: &lv,
                                     rates: Rates(), decimalPlaces: 7, random: lazy)
        try expectEqual(p7number(lazyRows[0]), 5, "unselected branch value")
        try expect(!lazyRows[0].isDynamic, "unexecuted rand never taints")
        try expectEqual(lazyDraws, 0, "unexecuted rand never draws")
        // The selected branch draws and taints.
        let taken = RandomEvaluationContext(sheetID: UUID(), draw: { _, high in high })
        var tv: [String: Double] = [:]
        let takenRows = evaluateSheet("if true then rand(1, 6) else 5", variables: &tv,
                                      rates: Rates(), decimalPlaces: 7, random: taken)
        try expectEqual(p7number(takenRows[0]), 6, "selected branch value")
        try expect(takenRows[0].isDynamic, "executed rand taints")
        // Lexical decoys are not dynamic: comments and malformed text.
        let decoyStore = RandomSampleStore()
        var decoyDraws = 0
        let decoy = RandomEvaluationContext(sheetID: UUID(), store: decoyStore,
                                            draw: { _, high in decoyDraws += 1; return high })
        var dv: [String: Double] = [:]
        let decoyRows = evaluateSheet("// rand(1, 6)\nrand(1, 6", variables: &dv,
                                      rates: Rates(), decimalPlaces: 7, random: decoy)
        try expect(!decoyRows[0].isDynamic, "comment mentioning rand is inert")
        try expect(!decoyRows[1].isDynamic, "malformed rand is not dynamic")
        try expectEqual(decoyDraws, 0, "decoys never draw")
        // Derived rows carry the taint orthogonally to their kind.
        let derivedCtx = RandomEvaluationContext(sheetID: UUID(), draw: { _, high in high })
        var rv: [String: Double] = [:]
        let derived = evaluateSheet("rand(1, 6)\nsubtotal\n5\nsubtotal\ngrand total",
                                    variables: &rv, rates: Rates(),
                                    decimalPlaces: 7, random: derivedCtx)
        try expectEqual(derived[1].metadata, .subtotal, "subtotal kind")
        try expect(derived[1].isDynamic, "subtotal is dynamic")
        try expectEqual(derived[4].metadata, .grandTotal, "grand kind")
        try expect(derived[4].isDynamic, "grand total is dynamic")
        // Named derived assignment propagates to later references.
        let namedCtx = RandomEvaluationContext(sheetID: UUID(), draw: { _, high in high })
        var nv: [String: Double] = [:]
        let namedRows = evaluateSheet("rand(1, 6)\ns = subtotal\ns + 1",
                                      variables: &nv, rates: Rates(),
                                      decimalPlaces: 7, random: namedCtx)
        try expect(namedRows[1].isDynamic, "named subtotal dynamic")
        try expect(namedRows[2].isDynamic, "name reference tainted")
        // Tag aggregate fed by a dynamic tagged row is dynamic.
        let tagCtx = RandomEvaluationContext(sheetID: UUID(), draw: { _, high in high })
        var gv: [String: Double] = [:]
        let tagRows = evaluateSheet("rand(1, 6) #x\ntotal of #x", variables: &gv,
                                    rates: Rates(), decimalPlaces: 7, random: tagCtx)
        try expectEqual(tagRows[1].metadata, .tagAggregate, "tag kind")
        try expect(tagRows[1].isDynamic, "tag aggregate dynamic")
    },

    EngineCase("p7-random-stability-and-conversion") {
        let store = RandomSampleStore()
        var draws = 0
        let ctx = RandomEvaluationContext(sheetID: UUID(), store: store,
                                          draw: { _, high in draws += 1; return high })
        let ids = [UUID(), UUID()]
        let content = "rand(1, 6)\nsubtotal"
        func pass() -> (lines: [SheetLine], tokens: [TokenResolution]) {
            resolveSheet(content: content, lineIDs: ids, references: [],
                         rates: Rates(), decimalPlaces: 7, random: ctx)
        }
        let first = pass()
        try expectEqual(p7number(first.lines[0]), 6, "displayed sample")
        // Scroll/hover/format/footer-menu/export passes reuse the epoch.
        for _ in 0..<4 { _ = pass() }
        try expectEqual(draws, 1, "duplicated display passes never redraw")
        // Footer menu changes are pure UI state.
        try expect(FooterStatisticMenu.isChecked(.sum, current: .sum), "footer menu pure")
        try expectEqual(draws, 1, "footer menu change never redraws")
        // Export freezes the CURRENT epoch: building a snapshot with the
        // same context neither redraws nor changes the value.
        let exportContext = ExportPresentationContext(
            sheetID: UUID(), sheetTitle: "Freeze", content: content,
            lineIDs: ids, references: [], answerDisplay: [], highlights: [],
            rates: Rates(), decimalPlaces: 7,
            now: Date(timeIntervalSince1970: 1_700_000_000),
            calendar: Calendar(identifier: .gregorian), constants: [],
            weather: .empty, geo: .empty, numberContext: .legacy,
            unitContext: .builtIns, preferences: .defaults, financial: .defaults,
            presentation: .defaults, language: .en, random: ctx)
        _ = ExportSnapshotBuilder.build(context: exportContext, options: ExportOptions())
        _ = ExportSnapshotBuilder.build(context: exportContext, options: ExportOptions())
        try expectEqual(draws, 1, "export never redraws")
        // Conversion freezes the DISPLAYED value without a redraw.
        let displayed = p7number(first.lines[1]) ?? .nan
        try expectEqual(displayed, 6, "displayed subtotal")
        guard let plan = SubtotalConversionPlan.plan(content: content, lineIndex: 1,
                                                     value: displayed,
                                                     context: .legacy) else {
            throw CaseFailure(message: "conversion planned", location: "p7")
        }
        try expectEqual(plan.content, "rand(1, 6)\n6.0", "converted to displayed value")
        try expectEqual(draws, 1, "conversion never redraws")
        // A content edit / Recalculate clears the store: the next pass
        // draws a fresh epoch.
        store.clear()
        _ = pass()
        try expectEqual(draws, 2, "clear starts a new epoch")
    },

    EngineCase("p7-projection-offsets-preserve-markers") {
        let analysis = SheetLineAnalysis.parse("  \u{FFFC} + 1 #tag")
        try expectEqual(analysis.evaluationProjection, "\u{FFFC} + 1", "tag stripped")
        try expectEqual(analysis.projectionOffset, 2, "leading whitespace offset")
        try expectEqual(analysis.tags.count, 1, "tag parsed")
        // Leading tabs/spaces plus a tag: the marker sidecar still maps.
        let ids = (0..<3).map { _ in UUID() }
        let content = "10\n\t \u{FFFC} + 1 #tag\n20"
        let markerAt = ("10\n\t " as NSString).length
        let refs = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                    location: markerAt)]
        let resolved = resolveSheet(content: content, lineIDs: ids, references: refs,
                                    rates: Rates(), decimalPlaces: 7)
        try expectEqual(p7number(resolved.lines[1]), 11, "marker resolved to 10")
        try expectEqual(resolved.tokens.count, 1, "one token")
        try expectEqual(resolved.tokens[0].location, markerAt, "token location unmoved")
        if case .active(let v, _, _) = resolved.tokens[0].state {
            try expectEqual(v, 10, "active value")
        } else {
            throw CaseFailure(message: "token active", location: "p7")
        }
        // Multiple markers in one tagged row keep their coordinates.
        let ids2 = (0..<3).map { _ in UUID() }
        let content2 = "5\n7\n  \u{FFFC} + \u{FFFC} #sum"
        let m1 = ("5\n7\n  " as NSString).length
        let m2 = m1 + ("\u{FFFC} + " as NSString).length
        let refs2 = [AnswerReference(sourceLineID: ids2[0], labelLine: 1, location: m1),
                     AnswerReference(sourceLineID: ids2[1], labelLine: 2, location: m2)]
        let resolved2 = resolveSheet(content: content2, lineIDs: ids2, references: refs2,
                                     rates: Rates(), decimalPlaces: 7)
        try expectEqual(p7number(resolved2.lines[2]), 12, "both markers resolve")
        try expectEqual(resolved2.tokens.count, 2, "two tokens")
        // A marker row with a tag still contributes to its tag aggregate.
        let ids3 = [UUID(), UUID(), UUID()]
        let content3 = "5\n \u{FFFC} + 1 #a\ntotal of #a"
        let mA = ("5\n " as NSString).length
        let refs3 = [AnswerReference(sourceLineID: ids3[0], labelLine: 1, location: mA)]
        let resolved3 = resolveSheet(content: content3, lineIDs: ids3, references: refs3,
                                     rates: Rates(), decimalPlaces: 7)
        try expectEqual(p7number(resolved3.lines[2]), 6,
                        "tagged marker expression contributes to its tag aggregate")
        // Syntax spans keep original UTF-16 coordinates.
        let spans = SyntaxClassifier.spans(for: "  \u{FFFC} + 1 #tag",
                                           rates: Rates(), decimalPlaces: 7)
        let tagSpans = spans[0].filter { $0.role == .tagMarker || $0.role == .tagBody }
        try expectEqual(tagSpans.first?.range, NSRange(location: 8, length: 1),
                        "tag marker span in original coordinates")
        try expectEqual(tagSpans.last?.range, NSRange(location: 9, length: 3),
                        "tag body span in original coordinates")
    },

    EngineCase("p7-nfc-tag-validation-and-lookup") {
        let composed = SheetLineAnalysis.parse("1 #café")
        let decomposed = SheetLineAnalysis.parse("1 #cafe\u{0301}")
        try expectEqual(composed.tags.count, 1, "composed tag valid")
        try expectEqual(decomposed.tags.count, 1, "decomposed tag valid")
        try expectEqual(composed.tags[0].key, decomposed.tags[0].key,
                        "NFC keys equal")
        try expectEqual(decomposed.tags[0].spelling, "cafe\u{0301}",
                        "original spelling preserved")
        try expectEqual(decomposed.tags[0].span, NSRange(location: 2, length: 6),
                        "original span preserved")
        try expectEqual(decomposed.tags[0].nameSpan, NSRange(location: 3, length: 5),
                        "original name span preserved")
        // Composed and decomposed spellings query the same aggregate.
        let first = p7rows("1 #cafe\u{0301}\ntotal of #café")
        try expectEqual(p7number(first[1]), 1, "decomposed tag, composed query")
        let second = p7rows("2 #café\ntotal of #cafe\u{0301}")
        try expectEqual(p7number(second[1]), 2, "composed tag, decomposed query")
    },

    EngineCase("p7-statistics-numerical-stability") {
        // The shared midpoint never overflows for opposite extremes.
        try expectEqual(StatisticsFunctions.midpoint(-1e308, 1e308), 0,
                        "midpoint of finite extremes")
        try expectEqual(StatisticsFunctions.median([-1e308, 1e308]), 0,
                        "median of finite extremes")
        let footer = p7rows("0 - 10^308\n10^308")
        try expectEqual(SheetFooterStatistics.compute(footer, statistic: .median),
                        .value(0), "footer median uses the safe midpoint")
        // The stable average is reused by tag aggregates.
        try expectEqual(StatisticsFunctions.average([1e308, 1e308]), 1e308,
                        "average of huge same-sign values")
        let tagAvg = p7rows("10^308 #a\n10^308 #a\naverage of #a")
        try expectEqual(p7number(tagAvg[2]), 1e308, "tag average stable")
        // Scaled two-pass stdev stays finite for huge finite spreads.
        let sd = StatisticsFunctions.stdev([-1e308, 1e308])
        try expect(sd?.isFinite == true, "stdev finite for opposite extremes")
        try expectClose(sd ?? .nan, 1.4142135623730951e308, 1e300)
        let near = StatisticsFunctions.stdev([1e308, 1e308.nextUp])
        try expect(near?.isFinite == true, "stdev finite near the top")
        try expect((near ?? 0) > 0, "non-zero near-top spread")
        // Ordinary corpus.
        try expectClose(StatisticsFunctions.stdev([2, 4, 4, 4, 5, 5, 7, 9]) ?? .nan,
                        2.138089935299395, 1e-12)
        // The phrase lane accepts expressions/variables through the
        // shared parser and never strips neutral words.
        var vars: [String: Double] = [:]
        let phrase = evaluateSheet("x = 3\nstandard deviation of x, 5, 7",
                                   variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(p7number(phrase[1]), 2, "variable list entry")
        let exprList = p7rows("median of 1 + 1, 5 - 1, 3")
        try expectEqual(p7number(exprList[0]), 3, "expression list entries")
        let neutral = p7rows("median of 1 and 2")
        if case .error = neutral[0].result {
        } else {
            throw CaseFailure(message: "neutral words rejected", location: "p7")
        }
        // Caller decimalPlaces drives rounding (no hardcoded 10).
        var tenVars: [String: Double] = [:]
        let ten = evaluateSheet("standard deviation of 2, 4, 4, 4, 5, 5, 7, 9",
                                variables: &tenVars, rates: Rates(), decimalPlaces: 10)
        try expectClose(p7number(ten[0]) ?? .nan, 2.1380899353, 1e-9)
    },

    EngineCase("p7-menu-contracts-and-isTotal") {
        try expectEqual(FooterStatisticMenu.order, [.sum, .average, .count, .median],
                        "footer menu order")
        try expect(FooterStatisticMenu.isChecked(.median, current: .median),
                   "checked entry")
        try expect(!FooterStatisticMenu.isChecked(.sum, current: .median),
                   "single checked entry")
        let view = p7Source("Sources/NumlexApp/Views/AnswerColumnView.swift")
        try expect(view.contains("FooterStatisticMenu.order"),
                   "footer menu built from the shared order")
        try expect(!view.contains("menu.addItem(NSMenuItem.separator())\n            menu.addItem(item(L10n.t(\"convertToNormalLine\""),
                   "convert never starts with a separator")
        if let at = view.range(of: "menu.addItem(item(L10n.t(\"convertToNormalLine\"") {
            let tail = String(view[at.lowerBound...]).prefix(240)
            try expect(tail.contains("menu.addItem(.separator())"),
                       "separator follows the convert item")
        } else {
            throw CaseFailure(message: "convert item present", location: "p7")
        }
        // `isTotal` is precise: every derived aggregate row carries it
        // (successful or not), including tag aggregates and errors.
        let rows = p7rows("1\nsubtotal\ngrand total\ntotal of #x")
        try expect(rows[1].isTotal && rows[1].metadata == .subtotal, "subtotal isTotal")
        try expect(rows[2].isTotal && rows[2].metadata == .grandTotal, "grand isTotal")
        try expect(rows[3].isTotal && rows[3].metadata == .tagAggregate,
                   "tag aggregate isTotal")
        let errorGrand = p7rows("subtotal\ngrand total")
        try expect(errorGrand[1].isTotal && errorGrand[1].metadata == .grandTotal,
                   "unsuccessful grand is still a derived row")
    },

    EngineCase("p7-app-random-context-parity") {
        let model = p7Source("Sources/NumlexApp/AppModel.swift")
        let occurrences = model.components(separatedBy: "random: randomContext(for: sheet.id)")
            .count - 1
        try expect(occurrences >= 4,
                   "all auxiliary evaluates thread the current store")
        try expect(model.contains("randomStores[removedID] = nil"),
                   "removed sheet stores deleted")
        try expect(model.contains("randomStores[sheets[0].id] = nil"),
                   "replaced sole sheet store deleted")
        let content = p7Source("Sources/NumlexApp/Views/ContentView.swift")
        try expect(content.contains("random: model.currentRandomContext"),
                   "export/display share the epoch")
        let plan = p7Source("Sources/NumlexCore/Models/AnswerTokenInsertion.swift")
        try expect(plan.contains("sourceIsDynamic"), "token plan guards dynamic sources")
    },

    EngineCase("p7-weather-scan-ignores-tag-suffix") {
        // A trailing tag must never become part of a place name.
        let queries = WeatherQuery.scanQueries(in: "weather in Paris #travel")
        try expectEqual(queries.count, 1)
        try expect(queries[0].display.lowercased().contains("paris"),
                   "place name stays Paris")
        try expect(!queries[0].display.contains("#"),
                   "no tag hash in the place name")
    },
]
