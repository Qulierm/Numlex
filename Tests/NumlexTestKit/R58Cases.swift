import Foundation
import NumlexCore

/// r58: user correction making `total` a SECTION subtotal, centering
/// the total divider on the true midpoint between answer ink centers,
/// and centering wrapped gutter line numbers in their logical block.
///
/// Task 1 semantics under test: each recognized total returns its
/// section sum (rows since the preceding total, or sheet start) and
/// resets; consecutive totals give the sum once then 0; blanks,
/// headings, prose and errors never reset; an overflow errors its own
/// section and still resets; a `total` variable/constant keeps
/// precedence (ordinary row, never a boundary, never a reset).
/// evaluateSheet/resolveSheet parity holds through the shared hook.

private let WM58 = "￼"

private func r58Sheet(_ content: String,
                      decimalPlaces: Int = 7,
                      constants: [UserConstant] = [],
                      weather: WeatherContext = .empty) -> [SheetLine] {
    var v: [String: Double] = [:]
    return evaluateSheet(content, variables: &v, rates: Rates(),
                         decimalPlaces: decimalPlaces,
                         constants: constants, weather: weather)
}

private func r58Resolve(_ content: String,
                        ids: [UUID],
                        refs: [AnswerReference] = [],
                        weather: WeatherContext = .empty)
-> (lines: [SheetLine], tokens: [TokenResolution]) {
    resolveSheet(content: content, lineIDs: ids, references: refs,
                 rates: Rates(), decimalPlaces: 7, weather: weather)
}

private func r58IDs(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

/// The unitless value of one row, or NaN when the row is not a plain
/// number (every inequality below then fails loudly — never a silent
/// pass through Optional promotion).
private func r58Number(_ lines: [SheetLine], _ i: Int) -> Double {
    if case .number(let v, nil) = lines[i].result { return v }
    return .nan
}

/// evaluateSheet/resolveSheet agree on every result, flag and index
/// for one token-free sheet (parity through the shared section hook).
private func r58Parity(_ content: String) throws {
    let a = r58Sheet(content)
    let n = content.components(separatedBy: "\n").count
    let r = r58Resolve(content, ids: r58IDs(n))
    try expectEqual(r.lines.count, a.count, "length: '\(content)'")
    for i in a.indices {
        try expectEqual(r.lines[i].result, a[i].result, "result \(i)")
        try expectEqual(r.lines[i].isTotal, a[i].isTotal, "flag \(i)")
        try expectEqual(r.lines[i].sourceLineIndex, i, "index \(i)")
    }
}

public let r58Cases: [EngineCase] = [

    EngineCase("r58-screenshot-sections") {
        // The exact user screenshot: 8348/2=4174, 492/6=82, first
        // section 4256; 549/2=274.5, 298+3=301, second section 575.5
        // (NOT the cumulative 4831.5).
        let content = "8348 / 2\n492 / 6\ntotal\n549 / 2\n298 + 3\ntotal"
        let lines = r58Sheet(content)
        try expectEqual(r58Number(lines, 0), 4174, "8348/2")
        try expectEqual(r58Number(lines, 1), 82, "492/6")
        try expectEqual(r58Number(lines, 2), 4256, "first section")
        try expectEqual(r58Number(lines, 3), 274.5, "549/2")
        try expectEqual(r58Number(lines, 4), 301, "298+3")
        try expectEqual(r58Number(lines, 5), 575.5, "second section")
        try expectEqual(lines.map { $0.isTotal },
                        [false, false, true, false, false, true], "flags")
        try r58Parity(content)
    },

    EngineCase("r58-sections-independent") {
        // Three sections accumulate independently: 1+2=3, 10+20=30,
        // 100=100.
        let content = "1\n2\ntotal\n10\n20\ntotal\n100\ntotal"
        let lines = r58Sheet(content)
        try expectEqual(r58Number(lines, 2), 3, "section one")
        try expectEqual(r58Number(lines, 5), 30, "section two")
        try expectEqual(r58Number(lines, 7), 100, "section three")
        try r58Parity(content)
    },

    EngineCase("r58-consecutive-totals-zero") {
        // First total gives the section sum; each following boundary
        // resets an already-empty section, so they total 0.
        let lines = r58Sheet("5\ntotal\ntotal\ntotal")
        try expectEqual(r58Number(lines, 1), 5, "section sum once")
        try expectEqual(r58Number(lines, 2), 0, "empty section")
        try expectEqual(r58Number(lines, 3), 0, "still empty")
        try expect(lines[1].isTotal && lines[2].isTotal && lines[3].isTotal,
                   "all flagged")
    },

    EngineCase("r58-leading-total") {
        // A leading total has no section yet: 0 with the flag on; the
        // rows after it form the first real section.
        let lines = r58Sheet("total\n5\ntotal")
        try expectEqual(r58Number(lines, 0), 0, "leading is 0")
        try expect(lines[0].isTotal, "leading flagged")
        try expectEqual(r58Number(lines, 2), 5, "first section")
        let pair = r58Sheet("total\ntotal")
        try expectEqual(r58Number(pair, 0), 0, "first 0")
        try expectEqual(r58Number(pair, 1), 0, "second 0")
    },

    EngineCase("r58-gaps-never-reset") {
        // Blanks, headings, titles and prose neither contribute nor
        // reset: the section spans them, but the boundary still cuts.
        let content = "10\n\n# ledger\n// June\nplain prose\ntotal\n\n20\ntotal"
        let lines = r58Sheet(content)
        try expectEqual(r58Number(lines, 5), 10, "gaps spanned")
        try expectEqual(r58Number(lines, 8), 20, "boundary cuts")
        try expect(lines[5].isTotal && lines[8].isTotal, "flags")
        try r58Parity(content)
    },

    EngineCase("r58-overflow-is-boundary") {
        // An overflowing section errors (quiet generic message, no
        // flag) yet still resets: the next section totals normally
        // with no partial carry.
        let content = "10 ^ 308\n10 ^ 308\ntotal\n5\ntotal"
        let lines = r58Sheet(content)
        if case .error(let msg) = lines[2].result {
            try expectEqual(msg, InlineTotal.overflowMessage, "generic")
        } else {
            throw CaseFailure(message: "section total errors", location: "r58")
        }
        try expect(!lines[2].isTotal, "no flag on error row")
        try expectEqual(r58Number(lines, 3), 5, "operand row")
        try expectEqual(r58Number(lines, 4), 5, "fresh section, no carry")
        try expect(lines[4].isTotal, "recovered flag")
        try r58Parity(content)
    },

    EngineCase("r58-token-row-new-section") {
        // A total referenced by a later ordinary token row contributes
        // through THAT row in its own section: 10 / total(10) /
        // bare-token(10) / total(10).
        // "10\ntotal\n" is 9 UTF-16 units, so the bare marker on
        // line 2 sits at document offset 9.
        let ids = r58IDs(4)
        let refs = [AnswerReference(sourceLineID: ids[1], labelLine: 2,
                                    location: 9)]
        let r = r58Resolve("10\ntotal\n\(WM58)\ntotal", ids: ids, refs: refs)
        try expectEqual(r58Number(r.lines, 1), 10, "section total")
        try expectEqual(r58Number(r.lines, 2), 10, "token row value")
        try expect(!r.lines[2].isTotal, "token row not a total")
        try expectEqual(r58Number(r.lines, 3), 10, "token is the section")
        try expect(r.lines[3].isTotal, "second total flagged")
        if case .active(let v, nil, _) = r.tokens[0].state {
            try expectEqual(v, 10, "token live on section total")
        } else {
            throw CaseFailure(message: "token active", location: "r58")
        }
    },

    EngineCase("r58-variable-precedence-no-reset") {
        // An active variable named `total` keeps precedence: the
        // assignment is an ordinary contributing row (never a
        // boundary), and later bare `total` lines stay ordinary too —
        // no flag anywhere, no reset anywhere.
        let lines = r58Sheet("total = 5\n3\ntotal")
        if case .variable(let name, let v) = lines[0].result {
            try expectEqual(name, "total", "assignment kept")
            try expectEqual(v, 5, "assigned value")
        } else {
            throw CaseFailure(message: "row 0 assigns", location: "r58")
        }
        try expectEqual(r58Number(lines, 1), 3, "ordinary row")
        // The bare `total` line reads the variable (5) instead of
        // summing: precedence turns every candidate into an ordinary
        // row, so no boundary and no flag exist anywhere.
        try expectEqual(r58Number(lines, 2), 5, "variable read, not a sum")
        try expect(!lines[2].isTotal, "command suppressed")
        // Global constant variant: no command exists at all, so the
        // would-be totals are plain constant rows in one stream.
        let c = UserConstant(name: "Total", expression: "7")
        let clines = r58Sheet("3\ntotal\n4\ntotal", constants: [c])
        try expectEqual(r58Number(clines, 1), 7, "constant row one")
        try expectEqual(r58Number(clines, 3), 7, "constant row two")
        try expect(!clines.contains(where: { $0.isTotal }), "no flags at all")
    },

    // MARK: - Task 2: centered total divider geometry

    EngineCase("r58-divider-midpoint-exact") {
        // On-grid midpoints are bit-exact and equidistant: no
        // closer-to-upper bias from any row-top pin.
        for scale: CGFloat in [1, 2, 3] {
            let y = TotalDivider.midpoint(previousCenter: 100, totalCenter: 200,
                                          displayScale: scale)
            try expectEqual(y, 150, "exact center, scale \(scale)")
            try expectEqual(150 - 100, 200 - 150, "equidistant")
        }
    },

    EngineCase("r58-divider-snapping-bound") {
        // Off-grid midpoints round (never floor/ceil) to the device
        // pixel grid: the snapped line stays within half a physical
        // pixel of the true midpoint at every scale.
        let pairs: [(CGFloat, CGFloat)] = [(100.3, 200.7), (0, 33.333),
                                            (517.25, 599.75), (10, 11)]
        for scale: CGFloat in [1, 2, 3] {
            for (a, b) in pairs {
                let exact = (a + b) / 2
                let y = TotalDivider.midpoint(previousCenter: a, totalCenter: b,
                                              displayScale: scale)
                // Snapped to the pixel grid...
                try expectEqual(y * scale, (y * scale).rounded(), "on grid")
                // ...within half a physical pixel of exact.
                try expect(abs(y - exact) * scale <= 0.5001,
                           "centered \(a)/\(b) @\(scale)x")
            }
        }
    },

    EngineCase("r58-divider-answer-centers") {
        // Centers derive from the same baseline + cap-height rule the
        // rows render with: single rows sit on the TextKit baseline,
        // wrapped rows center their ink across the block, and differing
        // weights/fonts move only their own row's center.
        let asc: CGFloat = 16
        let nat: CGFloat = 22
        let capR: CGFloat = 14
        let capS: CGFloat = 14
        // Single 32pt row at top 100: baseline rule, regular weight.
        let singleBase = AnswerBaseline.baseline(rowTop: 100, rowHeight: 32,
                                                 fragmentCount: 1, ascender: asc,
                                                 naturalHeight: nat, capHeight: capR)
        let singleCenter = TotalDivider.answerInkCenter(rowTop: 100,
                                                        baselineOffset: singleBase - 100,
                                                        capHeight: capR)
        try expectEqual(singleCenter, singleBase - capR / 2, "single ink")
        // Wrapped 3-fragment block (top 200, height 96): ink centered.
        let wrapBase = AnswerBaseline.baseline(rowTop: 200, rowHeight: 96,
                                               fragmentCount: 3, ascender: asc,
                                               naturalHeight: nat, capHeight: capS)
        let wrapCenter = TotalDivider.answerInkCenter(rowTop: 200,
                                                      baselineOffset: wrapBase - 200,
                                                      capHeight: capS)
        try expectEqual(wrapCenter, 248, "block mid 200 + 96/2")
        // A larger semibold cap height lifts only the total's center.
        let bigCenter = TotalDivider.answerInkCenter(rowTop: 200,
                                                     baselineOffset: wrapBase - 200,
                                                     capHeight: 18)
        try expectEqual(bigCenter, wrapCenter - 2, "cap-height delta")
        // Midpoint composes: equal distance before snapping.
        let mid = TotalDivider.midpoint(previousCenter: singleCenter,
                                        totalCenter: wrapCenter, displayScale: 2)
        let exact = (singleCenter + wrapCenter) / 2
        try expect(abs(mid - exact) * 2 <= 0.5001, "composed centered")
    },

    EngineCase("r58-divider-visibility") {
        // The predicate mirrors what the column actually renders:
        // ordinary numbers (plain, unit-bearing, weather), variables,
        // money, dates and inactive-token labels are anchors; blanks,
        // skips, titles and quiet generic errors are not.
        let visible: [LineResult] = [
            .number(value: 3, unit: nil),
            .number(value: 3, unit: "meter"),
            .number(value: 20, unit: WeatherQuery.celsiusUnitLabel),
            .variable(name: "x", value: 3),
            .money(value: 3, code: "USD"),
            .date(year: 2026, month: 1, day: 2, showYear: false),
            .brokenToken(line: 4),
            .error(message: WeatherQuery.unavailableMessage),
            .error(message: "Rates unavailable"),
        ]
        for r in visible { try expect(TotalDivider.isVisibleAnswer(r), "seen \(r)") }
        let hidden: [LineResult] = [
            .blank, .skip, .title("June"),
            .error(message: "Invalid expression"),
            .error(message: InlineTotal.overflowMessage),
        ]
        for r in hidden { try expect(!TotalDivider.isVisibleAnswer(r), "gap \(r)") }
    },

    EngineCase("r58-divider-previous-visible") {
        // The scan skips gaps, stops at the section boundary, and
        // reports nil at the sheet start.
        func row(_ result: LineResult, total: Bool = false) -> SheetLine {
            SheetLine(sourceLineIndex: 0, result: result, isTotal: total)
        }
        let lines = [
            row(.number(value: 10, unit: nil)),
            row(.blank), row(.title("t")), row(.skip),
            row(.error(message: "Invalid expression")),
            row(.number(value: 30, unit: nil), total: true),
        ]
        try expectEqual(TotalDivider.previousVisibleIndex(totalIndex: 5, lines: lines),
                        0, "skips the gap")
        // A prior total is the boundary, never an anchor — even when
        // it is the immediately preceding row.
        let consecutive = [
            row(.number(value: 10, unit: nil)),
            row(.number(value: 10, unit: nil), total: true),
            row(.number(value: 0, unit: nil), total: true),
        ]
        try expectEqual(TotalDivider.previousVisibleIndex(totalIndex: 2, lines: consecutive),
                        nil, "boundary stops scan")
        // Leading total: nothing above.
        try expectEqual(TotalDivider.previousVisibleIndex(totalIndex: 0, lines: consecutive),
                        nil, "sheet start")
        // Money/date anchors count even though they never contribute.
        let mixed = [
            row(.money(value: 5, code: "USD")),
            row(.number(value: 7, unit: nil), total: true),
        ]
        try expectEqual(TotalDivider.previousVisibleIndex(totalIndex: 1, lines: mixed),
                        0, "money anchors")
    },

    EngineCase("r58-divider-fallback") {
        // No previous visible answer: one own-row-height above the
        // total's center — exactly the total row's top edge.
        try expectEqual(TotalDivider.fallback(totalCenter: 100, totalRowHeight: 32),
                        84, "row top")
        try expectEqual(TotalDivider.fallback(totalCenter: 100, totalRowHeight: 0),
                        99.5, "degenerate height clamps")
    },

    EngineCase("r58-divider-source-guards") {
        // The row-top pin is gone; the column places dividers through
        // the pure midpoint helper over metadata + metrics.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func src(_ rel: String) throws -> String {
            let url = root.appendingPathComponent(rel).standardizedFileURL
            guard let s = try? String(contentsOf: url, encoding: .utf8) else {
                throw CaseFailure(message: "missing \(rel)", location: "R58Cases")
            }
            return s
        }
        let view = try src("Sources/NumlexApp/Views/AnswerColumnView.swift")
        try expect(!view.contains(".overlay(alignment: .top)"),
                   "row-top rule gone")
        try expect(view.contains("TotalDivider.midpoint"), "midpoint helper")
        try expect(view.contains("TotalDivider.previousVisibleIndex"), "section scan")
        try expect(view.contains("TotalDivider.fallback"), "fallback")
        try expect(view.contains("Design.panelSeparator"), "neutral rule kept")
        let layout = try src("Sources/NumlexCore/Engine/Layout.swift")
        try expect(layout.contains("public enum TotalDivider"), "core helper")
    },

    // MARK: - Task 3: wrapped gutter line numbers

    EngineCase("r58-gutter-single-unchanged") {
        // 0/1 fragments keep the caret-aligned rule exactly: the
        // helper reproduces the legacy composition (row-box baseline
        // via CaretGeometry, ink via the text cap, number on that
        // center with its own cap) AND hand arithmetic.
        let rowTop: CGFloat = 64
        let rowHeight: CGFloat = 32
        let asc: CGFloat = 15.2
        let nat: CGFloat = 21.5
        let textCap: CGFloat = 13.8
        let numCap: CGFloat = 7.9
        for count in [0, 1] {
            let got = GutterGeometry.numberBaseline(
                fragmentCount: count, rowTop: rowTop, rowHeight: rowHeight,
                blockTop: 1000, blockHeight: 9000,
                ascender: asc, naturalHeight: nat,
                textCapHeight: textCap, numberCapHeight: numCap)
            let legacyBase = CaretGeometry.baseline(
                rowTop: rowTop, rowHeight: rowHeight,
                ascender: asc, naturalHeight: nat)
            let legacy = CaretGeometry.inkCenter(baseline: legacyBase,
                                                 capHeight: textCap) + numCap / 2
            try expectEqual(got, legacy, "legacy composition \(count)")
            let hand = rowTop + (rowHeight - nat) + asc - textCap / 2 + numCap / 2
            try expectClose(got, hand, 0.0001, "hand arithmetic \(count)")
        }
    },

    EngineCase("r58-gutter-wrapped-center") {
        // 2+ fragments center the number ink on the exact logical
        // block midpoint; the row-box inputs are ignored entirely.
        let numCap: CGFloat = 7.9
        for count in [2, 3, 5] {
            let got = GutterGeometry.numberBaseline(
                fragmentCount: count, rowTop: 11, rowHeight: 22,
                blockTop: 100, blockHeight: 90,
                ascender: 1, naturalHeight: 2,
                textCapHeight: 3, numberCapHeight: numCap)
            try expectEqual(got, 145 + numCap / 2, "block mid \(count)")
            // The standalone wrapped entry the editor ships agrees.
            try expectEqual(GutterGeometry.wrappedNumberBaseline(
                blockTop: 100, blockHeight: 90, numberCapHeight: numCap),
                got, "editor entry agrees")
        }
    },

    EngineCase("r58-gutter-fonts-origin") {
        // Tall blocks, nonzero origins and distinct cap metrics compose
        // with no empirical offset: baseline = mid + numberCap/2.
        let base = GutterGeometry.wrappedNumberBaseline(
            blockTop: 517.25, blockHeight: 213.5, numberCapHeight: 8.25)
        try expectClose(base, 517.25 + 106.75 + 4.125, 0.0001, "tall block")
        let viaFull = GutterGeometry.numberBaseline(
            fragmentCount: 4, rowTop: 0, rowHeight: 0,
            blockTop: 517.25, blockHeight: 213.5,
            ascender: 0, naturalHeight: 0,
            textCapHeight: 0, numberCapHeight: 8.25)
        try expectEqual(viaFull, base, "full == wrapped entry")
    },

    EngineCase("r58-gutter-source-guards") {
        // The editor counts real TextKit fragments per logical range
        // and routes wrapped lines through the block helper; the
        // legacy single-line baseline path stays inline and intact.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func src(_ rel: String) throws -> String {
            let url = root.appendingPathComponent(rel).standardizedFileURL
            guard let s = try? String(contentsOf: url, encoding: .utf8) else {
                throw CaseFailure(message: "missing \(rel)", location: "R58Cases")
            }
            return s
        }
        let editor = try src("Sources/NumlexApp/Editor/NotebookEditor.swift")
        try expect(editor.contains("enumerateLineFragments(forGlyphRange:"),
                   "real fragment count")
        try expect(editor.contains("GutterGeometry.wrappedNumberBaseline"),
                   "block helper wired")
        try expect(editor.contains("rowFragCounts[i] >= 2"), "wrap threshold")
        try expect(editor.contains("CaretGeometry.baseline("),
                   "legacy path intact")
        let caret = try src("Sources/NumlexCore/Models/CaretGeometry.swift")
        try expect(caret.contains("public enum GutterGeometry"), "core helper")
    },

]
