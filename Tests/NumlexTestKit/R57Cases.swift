import Foundation
import NumlexCore

/// r57: standalone inline `total` rows — `total` sums the evaluated
/// values of ALL preceding logical lines and renders its answer
/// semibold with a gray rule above it.
///
/// Semantics under test: exact ASCII keyword (case-insensitive, outer
/// spaces/tabs), near-miss/prose/comment/heading rejection, env
/// precedence for an active variable/constant named `total`,
/// SECTION subtotals (r58: each total resets; blanks/headings never
/// reset; prior totals excluded; ordinary references contribute),
/// empty→0, evaluated-value precision (never
/// display strings or rounding overrides), overflow→quiet generic
/// error, ignored money/units/weather/date/error rows, token-derived
/// scalars, live tokens on totals, evaluate/resolve parity, stable
/// indices, previous-answer planning, Copy/menu eligibility, base-text
/// syntax, untouched auto-titling, and source guards for the footer
/// exclusion and the total-only weight/rule.

private let WM = "\u{FFFC}"

private func r57Sheet(_ content: String,
                      decimalPlaces: Int = 7,
                      constants: [UserConstant] = [],
                      weather: WeatherContext = .empty) -> [SheetLine] {
    var v: [String: Double] = [:]
    return evaluateSheet(content, variables: &v, rates: Rates(),
                         decimalPlaces: decimalPlaces,
                         constants: constants, weather: weather)
}

private func r57Resolve(_ content: String,
                        ids: [UUID],
                        refs: [AnswerReference] = [],
                        weather: WeatherContext = .empty)
-> (lines: [SheetLine], tokens: [TokenResolution]) {
    resolveSheet(content: content, lineIDs: ids, references: refs,
                 rates: Rates(), decimalPlaces: 7, weather: weather)
}

private func r57IDs(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

/// The unitless value of one row, or NaN when the row is not a plain
/// number (every inequality below then fails loudly — never a silent
/// pass through Optional promotion).
private func r57Number(_ lines: [SheetLine], _ i: Int) -> Double {
    if case .number(let v, nil) = lines[i].result { return v }
    return .nan
}

private func r57London(_ temp: Double) -> WeatherContext {
    WeatherContext(snapshots: ["london": WeatherSnapshot(
        queryKey: "london", displayQuery: "London", placeName: "London",
        country: "United Kingdom", latitude: 51.5074, longitude: -0.1278,
        temperatureCelsius: temp, fetchedAt: Date())])
}

public let r57Cases: [EngineCase] = [

    EngineCase("r57-exact-case-whitespace") {
        for cmd in ["total", "Total", "TOTAL", "  total  ", "\ttotal\t", " \t Total \t "] {
            let lines = r57Sheet("5\n\(cmd)")
            try expectEqual(r57Number(lines, 1), 5, "sums: '\(cmd)'")
            try expect(lines[1].isTotal, "flag: '\(cmd)'")
        }
    },

    EngineCase("r57-invalid-near-matches") {
        // Near-misses, prose, comments and headings never set the flag
        // (results stay exactly what the legacy pipeline produces).
        for line in ["subtotal", "totals", "total:", "total + 5",
                     "total recall", "my total", "  total x",
                     "// total", "# total", "total\u{FFFC}"] {
            let lines = r57Sheet("5\n\(line)")
            try expect(!lines[1].isTotal, "no flag: '\(line)'")
        }
        let comment = r57Sheet("5\n// total")
        if case .title = comment[1].result {} else {
            throw CaseFailure(message: "comment stays title", location: "r57")
        }
        let heading = r57Sheet("5\n# total")
        try expectEqual(heading[1].result, .blank, "heading stays blank")
    },

    EngineCase("r57-single-empty-total") {
        let first = r57Sheet("total")
        try expectEqual(r57Number(first, 0), 0, "first-line total is 0")
        try expect(first[0].isTotal, "first-line flag")
        let blanks = r57Sheet("\n\ntotal")
        try expectEqual(r57Number(blanks, 2), 0, "blanks ignored")
        try expect(blanks[2].isTotal, "flag after blanks")
    },

    EngineCase("r57-basic-cumulative") {
        // r58 sections: the second total sums only its own section.
        let lines = r57Sheet("10\n20\ntotal\n5\ntotal")
        try expectEqual(r57Number(lines, 2), 30, "first total")
        try expectEqual(r57Number(lines, 4), 5, "section since last total")
        try expectEqual(lines.map { $0.isTotal },
                        [false, false, true, false, true], "flags exact")
    },

    EngineCase("r57-source-above-only") {
        let lines = r57Sheet("total\n10\n20")
        try expectEqual(r57Number(lines, 0), 0, "nothing above")
        let later = r57Sheet("10\ntotal\n20\ntotal")
        try expectEqual(r57Number(later, 1), 10, "prefix only")
        try expectEqual(r57Number(later, 3), 20, "later total is its section")
    },

    EngineCase("r57-negatives-decimals-zero") {
        let lines = r57Sheet("-5\n2.5\n0\ntotal")
        try expectEqual(r57Number(lines, 3), -2.5, "signed sum")
        try expect(lines[3].isTotal, "flag")
    },

    EngineCase("r57-assignments-contribute") {
        let lines = r57Sheet("x = 10\nx + 5\ntotal")
        if case .variable(let name, let v) = lines[0].result {
            try expectEqual(name, "x", "assignment name")
            try expectEqual(v, 10, "assignment value")
        } else {
            throw CaseFailure(message: "row 0 is assignment", location: "r57")
        }
        try expectEqual(r57Number(lines, 1), 15, "derived row")
        // Assignment row (10) + derived row (15): each eligible row
        // contributes once.
        try expectEqual(r57Number(lines, 2), 25, "assignment + derived")
        let bare = r57Sheet("x = 10\ntotal")
        try expectEqual(r57Number(bare, 1), 10, "bare assignment contributes")
    },

    EngineCase("r57-constants-need-rows") {
        let fee = UserConstant(name: "fee", expression: "5")
        // A constant alone creates no row and contributes nothing.
        let lone = r57Sheet("total", constants: [fee])
        try expectEqual(r57Number(lone, 0), 0, "constant alone is 0")
        // A constant USED in a result row contributes through that row.
        let used = r57Sheet("fee + 1\ntotal", constants: [fee])
        try expectEqual(r57Number(used, 0), 6, "constant-driven row")
        try expectEqual(r57Number(used, 1), 6, "total of constant row")
    },

    EngineCase("r57-blanks-headings-no-reset") {
        let lines = r57Sheet("10\n\n# ledger\n// June\nplain prose\n20\ntotal")
        try expectEqual(r57Number(lines, 6), 30, "no reset anywhere")
        try expect(lines[6].isTotal, "flag")
    },

    EngineCase("r57-consecutive-totals") {
        // r58: the first total gives the section sum; the boundary
        // reset leaves the next section empty, so it totals 0.
        let lines = r57Sheet("10\ntotal\ntotal")
        try expectEqual(r57Number(lines, 1), 10, "first")
        try expectEqual(r57Number(lines, 2), 0, "second sees empty section")
        try expect(lines[1].isTotal && lines[2].isTotal, "both flagged")
    },

    EngineCase("r57-token-scalar-contributes") {
        // r58 sections: 10 / 20 / total(30) / bare-token(30) /
        // total(30) — the token row is an ordinary unitless result of
        // the NEW section and contributes normally there.
        let ids = r57IDs(5)
        let markerAt = 12 // "10\n20\ntotal\n" is 12 UTF-16 units
        let refs = [AnswerReference(sourceLineID: ids[2], labelLine: 3,
                                    location: markerAt)]
        let r = r57Resolve("10\n20\ntotal\n\(WM)\ntotal", ids: ids, refs: refs)
        try expectEqual(r57Number(r.lines, 2), 30, "command total")
        try expectEqual(r57Number(r.lines, 3), 30, "bare token of total")
        try expect(!r.lines[3].isTotal, "token row is not a total")
        try expectEqual(r57Number(r.lines, 4), 30, "token is the new section")
        try expect(r.lines[4].isTotal, "second total flagged")
        try expectEqual(r.tokens.count, 1, "one token")
        if case .active(let v, nil, _) = r.tokens[0].state {
            try expectEqual(v, 30, "token live on total")
        } else {
            throw CaseFailure(message: "token active on total", location: "r57")
        }
    },

    EngineCase("r57-token-on-total-live-change") {
        let ids = r57IDs(4)
        let markerAt = 12
        let refs = [AnswerReference(sourceLineID: ids[2], labelLine: 3,
                                    location: markerAt)]
        let before = r57Resolve("10\n20\ntotal\n\(WM)", ids: ids, refs: refs)
        try expectEqual(r57Number(before.lines, 2), 30, "before")
        // Editing the FIRST operand re-resolves the total and the
        // token follows with the same stable IDs (the marker moved
        // one unit right with the wider operand, so the sidecar
        // moves with it).
        let afterContent = "100\n20\ntotal\n\(WM)"
        let afterRefs = [AnswerReference(sourceLineID: ids[2], labelLine: 3,
                                         location: 13)]
        let after = r57Resolve(afterContent, ids: ids, refs: afterRefs)
        try expectEqual(r57Number(after.lines, 2), 120, "total follows edit")
        if case .active(let v, nil, _) = after.tokens[0].state {
            try expectEqual(v, 120, "token follows edit")
        } else {
            throw CaseFailure(message: "token live after edit", location: "r57")
        }
    },

    EngineCase("r57-total-deletion-breaks-token") {
        // The total line is gone but the sidecar still points at its
        // retired ID: the token breaks deterministically with the
        // remembered label while surviving rows keep their values.
        let live = UUID()
        let ids = r57IDs(3)
        let refs = [AnswerReference(sourceLineID: live, labelLine: 3,
                                    location: 6)]
        let r = r57Resolve("10\n20\n\(WM)", ids: ids, refs: refs)
        try expectEqual(r.tokens.count, 1, "one token")
        if case .broken(let line) = r.tokens[0].state {
            try expectEqual(line, 3, "remembered label")
        } else {
            throw CaseFailure(message: "token broken", location: "r57")
        }
        try expectEqual(r57Number(r.lines, 0), 10, "survivors intact")
        try expectEqual(r57Number(r.lines, 1), 20, "survivors intact")
    },

    EngineCase("r57-forward-ref-no-hang") {
        // A token above the total referencing the total below is a
        // forward reference: broken, never a hang.
        let ids = r57IDs(3)
        let refs = [AnswerReference(sourceLineID: ids[2], labelLine: 3,
                                    location: 0)]
        let r = r57Resolve("\(WM)\n10\ntotal", ids: ids, refs: refs)
        if case .broken = r.tokens[0].state {} else {
            throw CaseFailure(message: "forward ref broken", location: "r57")
        }
        try expectEqual(r57Number(r.lines, 2), 10, "total still resolves")
    },

    EngineCase("r57-previous-answer-selects-total") {
        let ids = r57IDs(4)
        let content = "10\n20\ntotal\n"
        let plan = PreviousAnswerPlan.plan(content: content, lineIDs: ids,
                                           caret: (content as NSString).length,
                                           op: "+", rates: Rates())
        guard let plan else {
            throw CaseFailure(message: "plan exists", location: "r57")
        }
        try expectEqual(plan.sourceLineIndex, 2, "total is the source")
        try expectEqual(plan.sourceLineID, ids[2], "stable ID")
    },

    EngineCase("r57-variable-name-precedence") {
        // An active variable named `total` wins over the command, so
        // existing notebooks keep working; `total = 5` is ordinary.
        let lines = r57Sheet("total = 5\ntotal")
        if case .variable(let name, let v) = lines[0].result {
            try expectEqual(name, "total", "assignment kept")
            try expectEqual(v, 5, "assigned value")
        } else {
            throw CaseFailure(message: "row 0 assigns total", location: "r57")
        }
        try expectEqual(r57Number(lines, 1), 5, "ordinary variable row")
        try expect(!lines[1].isTotal, "command suppressed")
        // Canonical casing: `TOTAL = 5` reserves every case variant.
        let upper = r57Sheet("TOTAL = 5\nTotal")
        try expect(!upper[1].isTotal, "cased collision suppressed")
    },

    EngineCase("r57-constant-name-precedence") {
        let c = UserConstant(name: "Total", expression: "7")
        let lines = r57Sheet("Total", constants: [c])
        try expectEqual(r57Number(lines, 0), 7, "constant row")
        try expect(!lines[0].isTotal, "constant suppresses command")
        let later = r57Sheet("10\ntotal", constants: [c])
        try expect(!later[1].isTotal, "no command anywhere")
        try expectEqual(r57Number(later, 1), 7, "ordinary constant row")
    },

    EngineCase("r57-ignored-kinds") {
        // Money, unit-bearing quantities, weather, dates and errors
        // never contribute; only the plain 10 does.
        let content = "$5\n10 km to meter\nJan 10 + 12 days\n1/0\n10\ntotal"
        let lines = r57Sheet(content, weather: r57London(20))
        try expectEqual(r57Number(lines, 5), 10, "only unitless rows")
        try expect(lines[5].isTotal, "flag")
        let withWeather = r57Sheet("weather in London\n10\ntotal",
                                   weather: r57London(20))
        if case .number(let wv, let wu) = withWeather[0].result {
            try expectEqual(wv, 20, "weather ready")
            try expectEqual(wu, WeatherQuery.celsiusUnitLabel, "weather unit")
        } else {
            throw CaseFailure(message: "weather row ready", location: "r57")
        }
        try expectEqual(r57Number(withWeather, 2), 10, "weather excluded")
        // (A bare `2 apples` keeps its legacy word-stripped scalar
        // reading and is intentionally not asserted here — only real
        // money rows are covered.)
        let named = r57Sheet("apple = 5$\n5 people \u{D7} apple\n10\ntotal")
        if case .money(let mv, _) = named[1].result {
            try expectEqual(mv, 25, "named money row")
        } else {
            throw CaseFailure(message: "money row stays money", location: "r57")
        }
        try expectEqual(r57Number(named, 3), 10, "named money excluded")
    },

    EngineCase("r57-overflow-quiet-error") {
        // 1e308 + 1e308 overflows Double (the tokenizer takes no
        // exponent literals, so the operands arrive via `^`): the
        // section total is the quiet generic error (never inf, never
        // a partial sum) and the flag stays off the invisible row —
        // but the boundary still resets (r58), so the next section
        // totals 0 instead of inheriting the poison.
        let lines = r57Sheet("10 ^ 308\n10 ^ 308\ntotal\ntotal")
        try expect(r57Number(lines, 0).isFinite, "operand finite")
        try expectEqual(r57Number(lines, 0), r57Number(lines, 1), "operands equal")
        if case .error(let msg) = lines[2].result {
            try expectEqual(msg, InlineTotal.overflowMessage, "generic")
        } else {
            throw CaseFailure(message: "row 2 errors", location: "r57")
        }
        try expect(!lines[2].isTotal, "no flag on error row")
        try expectEqual(r57Number(lines, 3), 0, "fresh section after overflow")
        try expect(lines[3].isTotal, "flag on recovered total")
    },

    EngineCase("r57-evaluated-precision") {
        // The aggregate uses evaluated values, never display strings
        // or per-row rounding overrides: 0.1 + 0.2 totals 0.3, and a
        // repeating decimal totals its evaluated (7dp) value exactly.
        let halves = r57Sheet("0.1\n0.2\ntotal")
        try expectEqual(r57Number(halves, 2), 0.3, "decimal sum")
        let third = r57Sheet("10/3\ntotal")
        try expect(!r57Number(third, 0).isNaN, "row evaluated")
        try expectEqual(r57Number(third, 0), r57Number(third, 1),
                        "total equals evaluated row value")
    },

    EngineCase("r57-evaluate-resolve-parity") {
        // Token-free sheets: evaluateSheet and resolveSheet agree on
        // every result, flag, index and length.
        let contents = [
            "10\n20\ntotal\n5\ntotal",
            "total",
            "x = 3\nx * 4\ntotal\ntotal",
            "$5\n10 km to meter\n8\ntotal",
            "TOTAL = 5\nTotal\n9\ntotal",
            "10 ^ 308\n10 ^ 308\ntotal",
        ]
        for content in contents {
            let a = r57Sheet(content)
            let r = r57Resolve(content, ids: r57IDs(content.components(separatedBy: "\n").count))
            try expectEqual(r.lines.count, a.count, "length: '\(content)'")
            for i in a.indices {
                try expectEqual(r.lines[i].result, a[i].result, "result \(i)")
                try expectEqual(r.lines[i].isTotal, a[i].isTotal, "flag \(i)")
                try expectEqual(r.lines[i].sourceLineIndex, i, "index \(i)")
            }
        }
    },

    EngineCase("r57-menu-copy-eligibility") {
        // A ready total is an ordinary unitless number on the shared
        // Copy/slider/Delete path: clipboard == visible, rounding on.
        let menu = AnswerDisplay.menu(for: .number(value: 30, unit: nil))
        try expectEqual(menu, AnswerDisplay.Menu(showsActions: true, showsRounding: true),
                        "full numeric menu")
        try expectEqual(AnswerDisplay.text(for: .number(value: 30, unit: nil),
                                           decimalPlaces: 7), "30", "copy text")
    },

    EngineCase("r57-syntax-base-text") {
        // The keyword keeps base text: no spans at all on a bare
        // command (and the classifier never strips or reformats it).
        for cmd in ["total", "TOTAL", "  total  "] {
            let spans = SyntaxClassifier.spans(for: cmd, rates: Rates(),
                                               decimalPlaces: 7)[0]
            try expect(spans.isEmpty, "no spans: '\(cmd)'")
        }
    },

    EngineCase("r57-autotitle-untouched") {
        // A leading total contributes no title (the evaluator sees no
        // result there without sheet context); the next calculable
        // line titles as before, and a total-only sheet keeps fallback.
        try expectEqual(Sheet.autoTitle(from: "total\n10 + 5", fallback: "Sheet"),
                        "10 + 5", "next line titles")
        try expectEqual(Sheet.autoTitle(from: "total", fallback: "Sheet"),
                        "Sheet", "total-only fallback")
    },

    EngineCase("r57-source-guards") {
        // The flag is derived-only: the view trusts evaluated metadata
        // (never source regex), the footer excludes total rows from its
        // unitless sum, and nothing about totals is persisted.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        func src(_ rel: String) throws -> String {
            let url = root.appendingPathComponent(rel).standardizedFileURL
            guard let s = try? String(contentsOf: url, encoding: .utf8) else {
                throw CaseFailure(message: "missing \(rel)", location: "R57Cases")
            }
            return s
        }
        let types = try src("Sources/NumlexCore/Engine/Types.swift")
        try expect(types.contains("isTotal: Bool = false"), "defaulted flag")
        let eval = try src("Sources/NumlexCore/Engine/Evaluator.swift")
        try expect(eval.contains("InlineTotal.isCommand"), "sheet-loop hook")
        let ref = try src("Sources/NumlexCore/Engine/ReferenceEvaluation.swift")
        try expect(ref.contains("InlineTotal.isCommand"), "resolve-loop hook")
        let view = try src("Sources/NumlexApp/Views/AnswerColumnView.swift")
        try expect(view.contains("line.isTotal"), "view trusts metadata")
        try expect(view.contains("Design.panelSeparator"), "neutral rule color")
        try expect(view.contains("weight: totalWeight"), "total-only weight")
        try expect(view.contains("guard !line.isTotal else { return nil }"),
                   "footer excludes totals")
        let sheet = try src("Sources/NumlexCore/Models/Sheet.swift")
        try expect(!sheet.contains("isTotal"), "never persisted")
    },
]
