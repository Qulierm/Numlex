import Foundation
import NumlexCore

// MARK: - r19: configurable input helpers (operators, grouping, previous answer)

private let M19 = "\u{FFFC}"

private func r19Rates() -> Rates {
    Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1])
}

private func expect19(_ cond: Bool, _ msg: String) throws {
    if !cond { throw CaseFailure(message: msg, location: "R19Cases") }
}

private func pref(pad: Bool = true, star: Bool = true, tick: Bool = false,
                  quick: Bool = true, group: Bool = true, prev: Bool = true) -> InputPreferences {
    InputPreferences(padOperators: pad, replaceAsterisk: star, replaceBacktick: tick,
                     quickOperators: quick, groupNumbers: group, insertPreviousAnswer: prev)
}

private func line19(_ text: String, _ p: InputPreferences, rates: Rates = r19Rates()) -> (text: String, map: [Int])? {
    InputFormatting.formatLine(text, prefs: p, rates: rates)
}

private func doc19(_ text: String, _ p: InputPreferences, rates: Rates = r19Rates()) -> (text: String, map: [Int]) {
    InputFormatting.formatDocument(text, prefs: p, rates: rates)
}

/// Monotone, boundary-correct caret map: one entry per insertion point,
/// non-decreasing, start/end pinned, length = UTF-16 length + 1.
private func checkMap19(_ name: String, _ map: [Int], fromLen: Int, toLen: Int) throws {
    try expect19(map.count == fromLen + 1, "\(name): map count \(map.count) != \(fromLen) + 1")
    try expect19(map.first == 0, "\(name): map starts at \(map.first ?? -1)")
    try expect19(map.last == toLen, "\(name): map ends at \(map.last ?? -1), expected \(toLen)")
    for i in 1..<map.count where map[i] < map[i - 1] {
        throw CaseFailure(message: "\(name): map not monotone at \(i)", location: "R19Cases")
    }
}

public let r19OperatorCases: [EngineCase] = [
    EngineCase("r19-op-pad-on") {
        let p = pref()
        try expectEqual(line19("1+1", p)?.text, "1 + 1", "pad inserts spaces")
        try expect19(line19("1 + 1", p) == nil, "already canonical is a fixed point")
        let (t, m) = line19("1+1", p)!
        try checkMap19("1+1", m, fromLen: 3, toLen: 5)
        // Caret right after the typed `+` (position 2) lands after the operator.
        try expectEqual(m[2], 3, "caret after + lands after +")
        // A typed `*` becomes the visible multiplication with padding.
        try expectEqual(line19("3*3", p)?.text, "3 × 3", "star becomes × with padding")
    },
    EngineCase("r19-op-pad-off-keeps-whitespace") {
        let p = pref(pad: false)
        try expect19(line19("1+1", p) == nil, "pad off: 1+1 stays literal")
        try expect19(line19("1  +  1", p) == nil, "pad off: typed spaces preserved")
        // Glyph replacement still runs with pad off.
        try expectEqual(line19("3*3", p)?.text, "3×3", "pad off: star becomes ×, no spacing")
        // Star off + pad on: `*` survives but still gets padded.
        let p2 = pref(star: false)
        try expectEqual(line19("3*3", p2)?.text, "3 * 3", "star off: * kept and padded")
        // Star off + pad off: fully literal.
        try expect19(line19("3*3", pref(pad: false, star: false)) == nil, "star off + pad off: literal")
    },
    EngineCase("r19-op-backtick") {
        let on = pref(tick: true)
        try expectEqual(line19("5`5", on)?.text, "5 + 5", "backtick becomes +")
        let off = pref()
        try expect19(line19("5`5", off) == nil, "backtick off: literal (line errors)")
        var v = [String: Double]()
        let r = evalLine("5 + 5", variables: &v, rates: r19Rates(), decimalPlaces: 7)
        if case .number(let x, _) = r { try expect19(x == 10, "transformed backtick line evaluates") }
        else { throw CaseFailure(message: "backtick line result \(r)", location: "R19Cases") }
    },
    EngineCase("r19-op-quick-operators") {
        let p = pref()
        try expectEqual(line19("5p5", p)?.text, "5 + 5", "p -> +")
        try expectEqual(line19("5m5", p)?.text, "5 - 5", "m -> -")
        try expectEqual(line19("5x5", p)?.text, "5 × 5", "x -> ×")
        try expectEqual(line19("5d5", p)?.text, "5 ÷ 5", "d -> ÷")
        // Decimals are allowed on both sides.
        try expectEqual(line19("2.5m3.5", p)?.text, "2.5 - 3.5", "decimal operands")
        // Completed-only: missing an operand side never fires.
        try expect19(line19("5m", p) == nil, "trailing 5m stays (magnitude)")
        try expect19(line19("2.5k", p) == nil, "2.5k stays (compact)")
        try expect19(line19("10Mb", p) == nil, "10Mb stays (uppercase)")
        // Identifiers are protected.
        try expect19(line19("a5d3", p) == nil, "identifier a5d3 untouched")
        try expect19(line19("x12p4y", p) == nil, "identifier with digits untouched")
        // Quick off: literal, and the line errors (no answer).
        let off = pref(quick: false)
        try expect19(line19("5p5", off) == nil, "quick off: 5p5 literal")
    },
    EngineCase("r19-op-quick-fixed-point-and-eval") {
        let p = pref()
        // Every transformed result is a fixed point of the whole pass.
        for (src, want) in [("5p5", "5 + 5"), ("5m5", "5 - 5"), ("5x5", "5 × 5"), ("5d5", "5 ÷ 5")] {
            let once = line19(src, p)
            try expectEqual(once?.text, want, "transform \(src)")
            try expect19(line19(want, p) == nil, "fixed point for \(want)")
        }
        var v = [String: Double]()
        let cases: [(String, Double)] = [("5 + 5", 10), ("5 - 5", 0), ("5 × 5", 25), ("5 ÷ 5", 1)]
        for (line, want) in cases {
            let r = evalLine(line, variables: &v, rates: r19Rates(), decimalPlaces: 7)
            if case .number(let x, let u) = r, u == nil {
                try expectClose(x, want, 1e-9, "eval \(line)")
            } else {
                throw CaseFailure(message: "eval \(line) -> \(r)", location: "R19Cases")
            }
        }
    },
]

public let r19GroupCases: [EngineCase] = [
    EngineCase("r19-group-basic") {
        let p = pref()
        try expectEqual(line19("10000", p)?.text, "10,000", "10000 -> 10,000")
        try expect19(line19("999", p) == nil, "999 stays (three digits)")
        try expectEqual(line19("12345.678", p)?.text, "12,345.678", "fraction untouched")
        try expectEqual(line19("10000 + 1", p)?.text, "10,000 + 1", "math line groups")
        // The transformed result stays a fixed point.
        try expect19(line19("10,000", p) == nil, "already grouped is a fixed point")
        // In-progress grouped tokens normalize.
        try expectEqual(line19("1,0000", p)?.text, "10,000", "in-progress 1,0000 -> 10,000")
    },
    EngineCase("r19-group-contexts") {
        let p = pref()
        try expectEqual(line19("$10000", p)?.text, "$10,000", "money literal groups")
        try expectEqual(line19("1234k", p)?.text, "1,234k", "compact suffix keeps grouping")
        try expect19(line19("x1234", p) == nil, "identifier tail not grouped")
        try expect19(line19("1e1234", p) == nil, "exponent digits not grouped")
        try expect19(line19(".1234", p) == nil, "fractional run not grouped")
        try expect19(line19("2.5", p) == nil, "small decimals untouched")
        // Prose error lines are never rewritten by grouping.
                // The evaluator treats a lone digit in prose as the number, so
        // the integer part groups consistently with the answer display.
        try expectEqual(line19("I need 12345 items", p)?.text, "I need 12,345 items", "prose number part groups")
        // Grouping off: literal digits stay.
        let off = pref(group: false)
        try expect19(line19("10000", off) == nil, "group off: literal")
    },
    EngineCase("r19-group-caret-map") {
        let p = pref()
        // Typing `0` to reach 10000: the caret at the END must map to
        // the end of `10,000` (incremental 999 -> 1,000 -> 10,000).
        let (t, m) = line19("10000", p)!
        try expectEqual(t, "10,000", "text")
        try checkMap19("10000", m, fromLen: 5, toLen: 6)
        try expectEqual(m[5], 6, "end caret stays at the end")
        try expectEqual(m[1], 1, "caret after the first digit stays put")
        // The comma appears AFTER a caret sitting at its insertion point.
        try expectEqual(m[2], 3, "caret right of the comma shifts once")
    },
    EngineCase("r19-group-document-map") {
        let p = pref()
        let src = "10000\nabc\n2+2"
        let (text, map) = doc19(src, p)
        try expectEqual(text, "10,000\nabc\n2 + 2", "per-line passes compose")
        let slen = (src as NSString).length
        let tlen = (text as NSString).length
        try checkMap19("doc", map, fromLen: slen, toLen: tlen)
        // Newline boundaries land on newlines.
        let nsT = text as NSString
        for p19 in 0..<slen where (src as NSString).character(at: p19) == 0x0A {
            let q = map[p19]
            try expect19(q < nsT.length && nsT.character(at: q) == 0x0A,
                         "newline at \(p19) maps to a newline (got \(q))")
        }
    },
]

public let r19PrevAnswerCases: [EngineCase] = [
    EngineCase("r19-prev-answer-plan-basics") {
        let ids = [UUID(), UUID(), UUID()]
        let content = "5 + 5\n\n"
        let plan = PreviousAnswerPlan.plan(content: content, lineIDs: ids, caret: 6, op: "+", rates: r19Rates())
        try expect19(plan != nil, "plans after a number line")
        try expectEqual(plan?.sourceLineIndex, 0, "source is the number line")
        try expectEqual(plan?.sourceLineID, ids[0], "stable line ID")
        try expectEqual(plan?.insertionLocation, 6, "caret position")
        // Whitespace-only caret line still plans (indentation preserved).
        let indented = "5 + 5\n  "
        let p2 = PreviousAnswerPlan.plan(content: indented, lineIDs: ids, caret: 8, op: "-", rates: r19Rates())
        try expect19(p2 != nil, "indented blank line plans")
        // A caret line with content never plans.
        let filled = "5 + 5\nx"
        try expect19(PreviousAnswerPlan.plan(content: filled, lineIDs: ids, caret: 7, op: "+", rates: r19Rates()) == nil,
                     "non-blank caret line never plans")
    },
    EngineCase("r19-prev-answer-eligibility") {
        let ids = (0..<8).map { _ in UUID() }
        func planAfter(_ src: String, _ op: Character = "+") -> Int? {
            let content = src + "\n"
            let p = PreviousAnswerPlan.plan(content: content, lineIDs: ids,
                                            caret: (src as NSString).length + 1, op: op, rates: r19Rates())
            return p?.sourceLineIndex
        }
        try expectEqual(planAfter("42"), 0, "plain number eligible")
        try expectEqual(planAfter("$500"), 0, "money eligible")
        try expectEqual(planAfter("price = 1250"), 0, "variable eligible")
        try expectEqual(planAfter("10 km to meter"), 0, "number with unit eligible")
        try expectEqual(planAfter("May 5 + 12 days"), nil, "date not eligible")
                try expectEqual(planAfter("abc 123"), 0, "evaluates to a number -> eligible")
        try expectEqual(planAfter("x12p4y"), nil, "true error line not eligible")
        try expectEqual(planAfter(M19), nil, "token line not eligible")
        // Nearest answerable line wins over older ones.
        let both = "abc 123\n10 km to meter\n77"
        try expectEqual(planAfter(both), 2, "nearest eligible line")
        // Operator gate: only the accepted operator set fires.
        let c = "5 + 5\n"
        for op in PreviousAnswerPlan.operators {
            try expect19(PreviousAnswerPlan.plan(content: c, lineIDs: ids, caret: 6, op: op, rates: r19Rates()) != nil,
                         "operator \(op) accepted")
        }
        try expect19(PreviousAnswerPlan.plan(content: c, lineIDs: ids, caret: 6, op: "q", rates: r19Rates()) == nil,
                     "q not an operator")
        try expect19(PreviousAnswerPlan.plan(content: c, lineIDs: ids, caret: 6, op: "=", rates: r19Rates()) == nil,
                     "= not an operator")
    },
]

public let r19IdentityCases: [EngineCase] = [
    EngineCase("r19-identity-format-map-remaps-marker") {
        // A marker on line 2 while line 1 gets grouped: the EXACT map
        // must carry the marker one position right.
        let ids = [UUID(), UUID()]
        let old = "1000\n" + M19 + " + 5"
        let ids2 = [UUID(), UUID()]
        _ = ids
        let oldRefs = [AnswerReference(sourceLineID: ids2[0], labelLine: 1, location: 5)]
        var env = [String: Double]()
        _ = evalLine(old, variables: &env, rates: r19Rates(), decimalPlaces: 7)
        // The user types `0` at the end of line 1 (range (4,0), "0").
        let intermediate = "10000\n" + M19 + " + 5"
        let (final, map) = doc19(intermediate, pref())
        try expectEqual(final, "10,000\n" + M19 + " + 5", "grouped document")
        let edit = NotebookEdit(range: NSRange(location: 4, length: 0), replacement: "0", formatMap: map)
        let (newIDs, refs) = LineIdentity.reconcile(
            oldContent: old, oldLineIDs: ids2, oldReferences: oldRefs,
            newContent: final, edit: edit)
        try expectEqual(refs.count, 1, "token survives")
        try expectEqual(refs.first?.location, 7, "marker remapped past the comma")
        try expectEqual(newIDs.count, 2, "line IDs preserved")
        // Without the exact map, the legacy inference must still work:
        let editNoMap = NotebookEdit(range: NSRange(location: 4, length: 0), replacement: "0")
        let (_, refsLegacy) = LineIdentity.reconcile(
            oldContent: old, oldLineIDs: ids2, oldReferences: oldRefs,
            newContent: final, edit: editNoMap)
        try expectEqual(refsLegacy.first?.location, 7, "legacy inference agrees")
    },
    EngineCase("r19-identity-marker-paste-with-format-map") {
        // Pasting a token onto a line that then gets padded: the paste
        // map (edit.formatMap) must place the marker at the final spot.
        let ids = [UUID(), UUID()]
        let oldRefs = [AnswerReference(sourceLineID: ids[0], labelLine: 1, location: 5)]
        let old = "1000\n" + M19 + " + 5"
        let intermediate = "10000\n" + M19 + " + 5"
        let (final, map) = doc19(intermediate, pref())
        let edit = NotebookEdit(range: NSRange(location: 4, length: 0), replacement: "0", formatMap: map)
        let (_, refs) = LineIdentity.reconcile(
            oldContent: old, oldLineIDs: ids, oldReferences: oldRefs,
            newContent: final, edit: edit)
        try expectEqual(refs.first?.location, 7, "paste path uses the exact map")
    },
]

public let r19SettingsCases: [EngineCase] = [
    EngineCase("r19-settings-legacy-store-decode") {
        // A pre-r19 store: no `input` key at all.
        let legacy = """
        {"sheets":[],"selectedIndex":0,"version":1,
         "settings":{"decimalPlaces":10,"fontSizeKey":"tf","language":"en",
                     "sheetName":"Sheet","lineNumbers":true,"fontColor":"white"}}
        """
        let payload = try JSONDecoder().decode(StorePayload.self, from: legacy.data(using: .utf8)!)
        try expectEqual(payload.settings.input, InputPreferences.defaults, "missing input -> defaults")
        // A full r19 store round-trips every key.
        var settings = AppSettings.defaults
        settings.input = pref(pad: false, star: false, tick: true, quick: false, group: false, prev: false)
        let full = try JSONEncoder().encode(AppSettings.self == AppSettings.self ? settings : settings)
        let back = try JSONDecoder().decode(AppSettings.self, from: full)
        try expectEqual(back.input, settings.input, "full input round-trips")
        // A partially written input object falls back key-by-key.
        let partial = """
        {"decimalPlaces":7,"fontSizeKey":"tf","language":"en","sheetName":"Sheet",
         "lineNumbers":false,"fontColor":"white","input":{"quickOperators":false}}
        """
        let p = try JSONDecoder().decode(AppSettings.self, from: partial.data(using: .utf8)!)
        try expectEqual(p.input.quickOperators, false, "present key wins")
        try expectEqual(p.input.padOperators, true, "missing key -> default")
        try expectEqual(p.input.groupNumbers, true, "missing key 2 -> default")
        try expectEqual(StorePayload.currentVersion, 2, "store version bumped")
    },
    EngineCase("r19-legacy-parity-migration-pass") {
        // The one-time v1 migration MUST reproduce the pre-r19
        // canonicalization exactly (no quick operators, no grouping).
        let samples = [
            "3*3", "1+1", "price = 1250", "price * 1.2", "10 km to meter",
            "May 5 + 12 days", "10000", "$3k earnings / 5 people", "1,0000 + 2",
            "# Demo", "I have 5 apples", "food $50 per day * 30 days",
            M19 + " in eur", "100 USD",
        ]
        for s in samples {
            let legacyText = NotebookFormatting.canonicalDocument(s)
            let migrated = doc19(s, .legacy).text
            try expectEqual(migrated, legacyText, "migration parity for '\(s)'")
        }
        // And the migration map is a valid caret map.
        for s in samples {
            let (text, map) = doc19(s, .legacy)
            try checkMap19("migration \(s)", map, fromLen: (s as NSString).length, toLen: (text as NSString).length)
        }
    },
    EngineCase("r19-natural-lines-stay-stable") {
        let p = pref()
        // User's live lines must come back byte-identical (fixed point).
        let stable = [
            "food $50 per day × 30 days",
            "contractor = $85 / hr × 8 hrs",
            "monthly rent = $2.5k",
            "phone bill = $45",
            M19 + " in eur",
            "May 5 + 12 days",
            "lunch was $55 + 20% tip",
            "# Demo",
            "",
        ]
        for line in stable {
            try expect19(line19(line, p) == nil, "stable: '\(line)'")
        }
        // A token+money mix line stays canonical.
        try expect19(line19(M19 + " + materials $240", p) == nil, "token+money stable")
        // The r18 prose results still evaluate after the pass.
        let (t1, _) = line19("food $50 per day*30 days", p)!
        try expectEqual(t1, "food $50 per day × 30 days", "prose multiplication canonicalized")
        var v = [String: Double]()
        let r1 = evalLine(t1, variables: &v, rates: r19Rates(), decimalPlaces: 7)
        try expect19(PreviousAnswerPlan.isAnswerable(r1!), "prose money line answerable")
        let (t2, _) = line19("$680.00+materials $240", p)!
        try expectEqual(t2, "$680.00 + materials $240", "money addition canonicalized")
    },
]
