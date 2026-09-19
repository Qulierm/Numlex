import Foundation
import NumlexCore

/// Bounded inline totals (the `total last N` command family).
///
/// `total last N` sums the eligible values found in the N immediately
/// PRECEDING LOGICAL source rows of the current legacy section (never
/// crossing the nearest prior legacy total, `# ` heading or exact `---`
/// divider), then resets that section exactly like bare `total`.
///
/// Semantics under test:
/// - `N` counts logical lines, never eligible results: blank, comment,
///   prose, error, money/unit, bare-token and derived aggregate rows
///   each occupy one slot and contribute nothing.
/// - The window is section-scoped; the command itself never occupies a
///   slot of the section it closes, and both forms reset the section
///   (history included) afterwards.
/// - Parsing is strict (ASCII `1...Int.max`, no signs/decimals/overflow/
///   trailing garbage) and both forms are suppressed by an active
///   variable or constant named `total`.
/// - Overflow and dynamic taint come from the SELECTED slots only.
/// - evaluateSheet and resolveSheet agree byte-for-byte.

private func tlSheet(_ content: String,
                     decimalPlaces: Int = 7,
                     constants: [UserConstant] = []) -> [SheetLine] {
    var v: [String: Double] = [:]
    return evaluateSheet(content, variables: &v, rates: Rates(),
                         decimalPlaces: decimalPlaces, constants: constants)
}

private func tlIDs(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

private func tlResolve(_ content: String,
                       ids: [UUID]? = nil,
                       refs: [AnswerReference] = []) -> [SheetLine] {
    let n = content.components(separatedBy: "\n").count
    return resolveSheet(content: content, lineIDs: ids ?? tlIDs(n), references: refs,
                        rates: Rates(), decimalPlaces: 7).lines
}

/// The unitless value of one row, or NaN when the row is not a plain
/// number (every inequality below then fails loudly — never a silent
/// pass through Optional promotion).
private func tlNumber(_ lines: [SheetLine], _ i: Int) -> Double {
    if case .number(let v, nil, _, _) = lines[i].result { return v }
    return .nan
}

private func tlError(_ lines: [SheetLine], _ i: Int) -> String? {
    if case .error(let message) = lines[i].result { return message }
    return nil
}

/// An overflowing aggregate is the deterministic quiet generic error —
/// never a fabricated zero, never a flagged total row.
private func tlExpectOverflow(_ lines: [SheetLine], _ i: Int) throws {
    guard let message = tlError(lines, i) else {
        throw CaseFailure(message: "row \(i) is not an error: \(lines[i].result)",
                          location: "TotalLastCases")
    }
    try expectEqual(message, InlineTotal.overflowMessage, "quiet generic error")
    try expect(!lines[i].isTotal, "an overflowing window is never a total row")
    try expectEqual(lines[i].metadata, .ordinary, "overflow keeps ordinary metadata")
}

/// evaluateSheet/resolveSheet agree on every result, flag, metadata,
/// source index and dynamic taint of one token-free sheet.
private func tlParity(_ content: String) throws {
    let a = tlSheet(content)
    let b = tlResolve(content)
    try expectEqual(b.count, a.count, "length: '\(content)'")
    for i in a.indices {
        try expectEqual(b[i].result, a[i].result, "result \(i): '\(content)'")
        try expectEqual(b[i].isTotal, a[i].isTotal, "flag \(i): '\(content)'")
        try expectEqual(b[i].metadata, a[i].metadata, "metadata \(i): '\(content)'")
        try expectEqual(b[i].isDynamic, a[i].isDynamic, "dynamic \(i): '\(content)'")
        try expectEqual(b[i].sourceLineIndex, i, "index \(i): '\(content)'")
    }
}

public let totalLastCases: [EngineCase] = [

    EngineCase("total-last-basic-window") {
        let lines = tlSheet("1\n2\n3\ntotal last 2")
        try expectEqual(tlNumber(lines, 3), 5, "sum of the two rows above")
        try expect(lines[3].isTotal, "derived presentation flag")
        try expectEqual(lines[3].metadata, .legacyTotal, "legacy total metadata")
        try expectEqual(lines[3].sourceLineIndex, 3, "source index preserved")
        // The window is exactly N rows: N-1 and N+1 differ.
        try expectEqual(tlNumber(tlSheet("1\n2\n3\ntotal last 1"), 3), 3, "last one row")
        try expectEqual(tlNumber(tlSheet("1\n2\n3\n4\ntotal last 3"), 4), 9, "last three rows")
        // The command row itself is never one of its own slots.
        try expectEqual(tlNumber(tlSheet("1\n2\n3\ntotal last 3"), 3), 6, "no self-inclusion")
        try tlParity("1\n2\n3\ntotal last 2")
    },

    EngineCase("total-last-grammar-case-and-separators") {
        for content in ["1\n2\ntotal last 2",
                        "1\n2\nTOTAL LAST 2",
                        "1\n2\n  total last 2  ",
                        "1\n2\n\ttotal last 2\t",
                        "1\n2\ntotal\tlast\t2",
                        "1\n2\nToTaL   LaSt   2"] {
            let lines = tlSheet(content)
            try expectEqual(tlNumber(lines, 2), 3, "value: '\(content)'")
            try expectEqual(lines[2].metadata, .legacyTotal, "metadata: '\(content)'")
            try expect(lines[2].isTotal, "flag: '\(content)'")
        }
        // The tag-stripped projection keeps the command intact.
        let tagged = tlSheet("1\n2\ntotal last 2 #cash")
        try expectEqual(tlNumber(tagged, 2), 3, "tagged command value")
        try expectEqual(tagged[2].metadata, .legacyTotal, "tagged command metadata")
    },

    EngineCase("total-last-window-larger-than-section") {
        // A leading command has an empty section: 0 with the flag on.
        let leading = tlSheet("total last 3")
        try expectEqual(tlNumber(leading, 0), 0, "leading limited total")
        try expect(leading[0].isTotal, "leading limited total flagged")
        // Leading blanks are slots of an empty section: still 0.
        try expectEqual(tlNumber(tlSheet("\n\ntotal last 3"), 2), 0, "empty section")
        // A window larger than the section sums the whole section.
        try expectEqual(tlNumber(tlSheet("1\n2\ntotal last 99"), 2), 3, "clamped window")
        try expectEqual(tlNumber(tlSheet("total last 9223372036854775807"), 0), 0,
                        "Int.max window")
        // A prior boundary hides everything above it from the window.
        try expectEqual(tlNumber(tlSheet("1\n2\ntotal\n3\ntotal last 5"), 4), 3,
                        "prior total is a boundary")
        try tlParity("1\n2\ntotal last 99")
    },

    EngineCase("total-last-counts-logical-lines-not-results") {
        // Blanks, prose, comments, errors, money and units each occupy
        // exactly one slot while contributing nothing.
        try expectEqual(tlNumber(tlSheet("10\n20\n\nplain prose\n$5\ntotal last 4"), 5), 20,
                        "blank + prose + money consume slots")
        try expectEqual(tlNumber(tlSheet("1\n2\n\n\ntotal last 4"), 4), 3, "blank slots")
        try expectEqual(tlNumber(tlSheet("1\n// June\n2\n//\ntotal last 3"), 4), 2,
                        "comment slots")
        try expectEqual(tlNumber(tlSheet("5\n1 +\ntotal last 2"), 2), 5, "error slot")
        try expectEqual(tlNumber(tlSheet("1\n2\n3 kg\ntotal last 2"), 3), 2, "unit slot")
        try expectEqual(tlNumber(tlSheet("1\n2\n3 kg\ntotal last 1"), 3), 0,
                        "a unit row alone contributes nothing")
        try expectEqual(tlNumber(tlSheet("1\n2\n$5\ntotal last 1"), 3), 0,
                        "a money row alone contributes nothing")
        try expectEqual(tlNumber(tlSheet("1\n2\ntrue\ntotal last 1"), 3), 0,
                        "a boolean row alone contributes nothing")
        // Derived aggregate rows take a slot and contribute nothing.
        try expectEqual(tlNumber(tlSheet("10\nsubtotal\n20\nsubtotal\ngrand total\ntotal last 3"), 5),
                        20, "subtotal/grand rows are slots")
        try expectEqual(tlNumber(tlSheet("1 #a\n2 #a\ntotal of #a\ntotal last 2"), 3), 2,
                        "tag aggregate row is a slot")
        try tlParity("10\n20\n\nplain prose\n$5\ntotal last 4")
    },

    EngineCase("total-last-section-boundaries") {
        // A `# ` heading clears the history: rows above it are invisible.
        try expectEqual(tlNumber(tlSheet("10\n20\n# ledger\n30\ntotal last 3"), 4), 30,
                        "heading boundary")
        try expectEqual(tlNumber(tlSheet("10\n20\n# ledger\ntotal last 5"), 3), 0,
                        "empty section after a heading")
        // An exact `---` divider is a boundary; `----` is not.
        try expectEqual(tlNumber(tlSheet("10\n20\n---\ntotal last 5"), 3), 0, "divider boundary")
        try expectEqual(tlNumber(tlSheet("10\n20\n----\ntotal last 2"), 3), 20,
                        "`----` is an ordinary row, not a boundary")
        // A prior total of EITHER form is a legacy boundary.
        try expectEqual(tlNumber(tlSheet("10\n20\ntotal\ntotal last 5"), 3), 0,
                        "prior bare total")
        try expectEqual(tlNumber(tlSheet("1\n2\ntotal last 2\n3\ntotal last 5"), 4), 3,
                        "prior limited total")
        try expectEqual(tlNumber(tlSheet("1\n2\ntotal last 2\n# h\n3\ntotal last 5"), 5), 3,
                        "heading after a limited total")
        // `subtotal` / `grand total` are NOT legacy boundaries: their own
        // rows take a slot, the eligible rows above stay visible.
        try expectEqual(tlNumber(tlSheet("10\nsubtotal\n20\ntotal last 2"), 3), 20,
                        "subtotal is no boundary")
        try expectEqual(tlNumber(tlSheet("10\nsubtotal\n20\ntotal last 1"), 3), 20,
                        "the row right above")
        try tlParity("10\n20\n# ledger\n30\ntotal last 3")
    },

    EngineCase("total-last-resets-the-section") {
        let twice = tlSheet("1\n2\ntotal last 2\ntotal last 2")
        try expectEqual(tlNumber(twice, 2), 3, "first window")
        try expectEqual(tlNumber(twice, 3), 0, "history cleared by the first command")
        try expect(twice[3].isTotal, "the second command is still a total row")
        let bareThen = tlSheet("1\n2\ntotal last 2\ntotal")
        try expectEqual(tlNumber(bareThen, 3), 0, "a following bare total starts empty")
        let limitedThen = tlSheet("1\n2\ntotal\n3\ntotal last 1")
        try expectEqual(tlNumber(limitedThen, 2), 3, "bare total first")
        try expectEqual(tlNumber(limitedThen, 4), 3, "limited total after it")
        // Only rows AFTER the reset are visible to a later window.
        let after = tlSheet("1\n2\ntotal last 2\n3\n4\ntotal last 3")
        try expectEqual(tlNumber(after, 5), 7, "post-reset rows only")
        try expectEqual(tlNumber(tlSheet("1\n2\ntotal last 2\n3\ntotal last 5"), 4), 3,
                        "window cannot reach above the reset")
        try tlParity("1\n2\ntotal last 2\ntotal last 2")
    },

    EngineCase("total-last-strict-rejects-as-ordinary-rows") {
        let rejected = ["total last 0",
                        "total last -1",
                        "total last +1",
                        "total last 1.5",
                        "total last 1,5",
                        "total last 1e3",
                        "total last 1_0",
                        "total last",
                        "total 2",
                        "total last 2 extra",
                        "total last 2 3",
                        "total last ٣",
                        "total last ٥",
                        "total last 9223372036854775808",
                        "totallast 2",
                        "totals last 2"]
        for bad in rejected {
            let lines = tlSheet("5\n\(bad)\ntotal")
            try expect(!lines[1].isTotal, "'\(bad)' is not a total row")
            try expectEqual(lines[1].metadata, .ordinary, "'\(bad)' metadata stays ordinary")
            // Rejection means ordinary non-command input: it evaluates
            // and contributes exactly like the keyword-neutral twin and
            // never resets the section.
            let neutral = "zzz" + bad.dropFirst("total".count)
            let twin = tlSheet("5\n\(neutral)\ntotal")
            try expectEqual(lines[1].result, twin[1].result,
                            "'\(bad)' evaluates like ordinary input")
            try expectEqual(lines[2].result, twin[2].result, "'\(bad)' never resets")
            try expect(lines[2].isTotal, "'\(bad)' leaves the next bare total intact")
        }
        // The accepted boundary of the grammar: the largest usable
        // count and a padded one still parse.
        try expectEqual(tlNumber(tlSheet("1\n2\ntotal last 007"), 2), 3, "leading zeros")
    },

    EngineCase("total-last-shadowed-by-variable-and-constant") {
        // An ACTIVE variable named `total` suppresses BOTH forms.
        let shadow = tlSheet("total = 5\n1\n2\ntotal last 2\ntotal")
        try expectEqual(shadow[0].metadata, .ordinary, "the assignment is ordinary")
        try expect(!shadow[3].isTotal, "the limited form is suppressed")
        try expectEqual(shadow[3].metadata, .ordinary, "limited form stays ordinary")
        try expect(!shadow[4].isTotal, "the bare form stays suppressed")
        try expectEqual(tlNumber(tlSheet("total = 5\ntotal + 1"), 1), 6,
                        "the variable itself still evaluates")
        // A global constant named `total` shadows both forms too.
        let constant = tlSheet("1\n2\ntotal last 2\ntotal",
                               constants: [UserConstant(name: "total", expression: "7")])
        try expect(!constant[2].isTotal, "constant shadows the limited form")
        try expectEqual(constant[2].metadata, .ordinary, "constant-shadowed metadata")
        try expect(!constant[3].isTotal, "constant shadows the bare form")
        // With no active entry both forms are commands again.
        let free = tlSheet("1\n2\ntotal last 2\ntotal last 1")
        try expect(free[2].isTotal && free[3].isTotal, "both forms recognized")
        try expectEqual(tlNumber(free, 3), 0, "the second command sees a reset section")
    },

    EngineCase("total-last-leaves-bare-total-unchanged") {
        // Bare `total` still sums the WHOLE current section.
        try expectEqual(tlNumber(tlSheet("1\n2\n3\n4\ntotal"), 4), 10, "bare total")
        try expectEqual(tlNumber(tlSheet("1\n2\ntotal last 1\n3\ntotal"), 4), 3,
                        "bare total after a limited one")
        try expectEqual(tlNumber(tlSheet("1\n2\ntotal\n3\ntotal last 1"), 4), 3,
                        "limited total after a bare one")
        try expectEqual(tlNumber(tlSheet("1\n2\n3\ntotal last 3\n4\ntotal"), 5), 4,
                        "bare total sees only the post-command rows")
        // Subtotal and grand total keep their own accumulators.
        let mixed = tlSheet("10\nsubtotal\n20\nsubtotal\ntotal last 1\ngrand total")
        try expectEqual(tlNumber(mixed, 1), 10, "first subtotal")
        try expectEqual(tlNumber(mixed, 3), 20, "second subtotal")
        try expectEqual(tlNumber(mixed, 4), 0, "limited window sees only the subtotal row")
        try expectEqual(mixed[4].metadata, .legacyTotal, "limited total metadata")
        try expectEqual(mixed[5].metadata, .grandTotal, "grand total survives")
        try expectEqual(tlNumber(mixed, 5), 30, "grand list untouched by the limited reset")
        try tlParity("10\nsubtotal\n20\nsubtotal\ntotal last 1\ngrand total")
    },

    EngineCase("total-last-eligibility-is-source-aware") {
        // The same source-aware eligibility as `subtotal`: declarations,
        // money, units and booleans are excluded; scalar usage rows,
        // percent/fraction/base literals and token expressions included.
        let content = "x = 5\nx + 5\n$7\n3 kg\ntrue\n50%\n1/4\n0xFF\n2 + 3"
        // 10 + 0.5 + 0.25 + 255 + 5 = 270.75 over the whole section.
        try expectEqual(tlNumber(tlSheet("\(content)\ntotal last 9"), 9), 270.75,
                        "eligibility over the whole section")
        try expectEqual(tlNumber(tlSheet("\(content)\ntotal last 3"), 9), 260.25,
                        "eligibility inside the window (0.25 + 255 + 5)")
        try expectEqual(tlNumber(tlSheet("\(content)\ntotal last 2"), 9), 260,
                        "255 + 5")
        try expectEqual(tlNumber(tlSheet("\(content)\ntotal last 10"), 9), 270.75,
                        "a window larger than the section")
        try tlParity("\(content)\ntotal last 3")
    },

    EngineCase("total-last-evaluate-resolve-parity") {
        for content in ["1\n2\ntotal last 2",
                        "total last 3",
                        "1\n2\ntotal last 2\ntotal",
                        "x = 1\nx + 1\ntotal last 2",
                        "10\n# h\n20\ntotal last 5",
                        "10\n20\n---\n30\ntotal last 3",
                        "1\n2\n$5\n3 kg\n1 +\ntotal last 5",
                        "1\n2\ntotal last 2 #cash",
                        "10 ^ 308\n10 ^ 308\n1\n2\ntotal last 2",
                        "1\n2\n10 ^ 308\n10 ^ 308\ntotal last 2"] {
            try tlParity(content)
        }
    },

    EngineCase("total-last-token-window-and-bare-token-slot") {
        let ids = tlIDs(4)
        let markerAt = ("10\ntotal last 1\n" as NSString).length
        let refs = [AnswerReference(sourceLineID: ids[1], labelLine: 2,
                                    location: markerAt)]
        // A token in a genuine expression inside the selected window
        // contributes like any other eligible row.
        let inExpr = tlResolve("10\ntotal last 1\n\u{FFFC} + 1\ntotal last 2",
                               ids: ids, refs: refs)
        try expectEqual(tlNumber(inExpr, 1), 10, "limited total above the token")
        try expectEqual(tlNumber(inExpr, 2), 11, "token expression value")
        try expectEqual(tlNumber(inExpr, 3), 11, "token expression inside the window")
        // A bare-token-only row takes its slot and contributes nothing.
        let bare = tlResolve("10\ntotal last 1\n\u{FFFC}\ntotal last 2",
                             ids: ids, refs: refs)
        try expectEqual(tlNumber(bare, 2), 10, "the bare token still resolves")
        try expectEqual(tlNumber(bare, 3), 0, "the bare token slot contributes nothing")
        // A token minted ON a limited total row keeps showing its value.
        let onTotal = tlResolve(
            "1\n2\ntotal last 2\n\u{FFFC}",
            ids: ids,
            refs: [AnswerReference(sourceLineID: ids[2], labelLine: 3,
                                   location: ("1\n2\ntotal last 2\n" as NSString).length)])
        try expectEqual(tlNumber(onTotal, 2), 3, "the minted source row")
        try expectEqual(tlNumber(onTotal, 3), 3, "token on a limited total")
    },

    EngineCase("total-last-metadata-answer-and-footer-exclusion") {
        let lines = tlSheet("1\n2\ntotal last 2")
        try expect(lines[2].isTotal, "presentation flag")
        try expectEqual(lines[2].metadata, .legacyTotal, "legacy total metadata")
        try expect(lines[2].metadata.isDerived, "derived row")
        // The answer is a plain unitless `.number` (Copy, slider, tokens).
        if case .number(let v, nil, _, _) = lines[2].result {
            try expectEqual(v, 3, "plain unitless number")
        } else {
            throw CaseFailure(message: "limited total is not a plain number: \(lines[2].result)",
                              location: "TotalLastCases")
        }
        // The bottom Total panel never double-counts it.
        try expect(SheetFooterTotal.contribution(of: lines[2].result,
                                                isTotalRow: lines[2].isTotal) == nil,
                   "footer excludes the limited total")
        try expectEqual(SheetFooterStatistics.contributions(lines), [1, 2],
                        "footer contributions")
        try expectEqual(SheetFooterStatistics.compute(lines, statistic: .sum), .value(3),
                        "footer sum ignores the total row")
        try expectEqual(SheetFooterStatistics.compute(lines, statistic: .count), .count(2),
                        "footer count ignores the total row")
    },

    EngineCase("total-last-selected-window-dynamic-taint") {
        // A dynamic row OUTSIDE the window never taints it.
        let outside = tlSheet("rand(1, 6)\n5\ntotal last 1")
        try expectEqual(tlNumber(outside, 2), 5, "window value")
        try expect(outside[0].isDynamic, "the rand row is dynamic")
        try expect(!outside[2].isDynamic, "a dynamic row outside the window is inert")
        // A dynamic row INSIDE the window taints the limited total.
        let inside = tlSheet("5\nrand(1, 6)\ntotal last 1")
        try expect(inside[2].isDynamic, "dynamic row inside the window taints")
        try expectEqual(inside[2].metadata, .legacyTotal, "metadata is still a legacy total")
        try expect(tlNumber(inside, 2).isFinite, "the value is still a real number")
        // A dynamic but INELIGIBLE slot (a declaration) never taints.
        let ineligible = tlSheet("5\nx = rand(1, 6)\ntotal last 1")
        try expect(ineligible[1].isDynamic, "the declaration row is dynamic")
        try expect(!ineligible[2].isDynamic, "an ineligible dynamic slot never taints")
        try expectEqual(tlNumber(ineligible, 2), 0, "the declaration contributes nothing")
        // Bare-total taint behavior is unchanged.
        let bare = tlSheet("rand(1, 6)\n5\ntotal")
        try expect(bare[2].isDynamic, "bare total is still tainted by the whole section")
        let bareClean = tlSheet("5\nrand(1, 6)\ntotal last 2\n7\ntotal")
        try expectEqual(tlNumber(bareClean, 4), 7, "post-reset bare total")
        try expect(!bareClean[4].isDynamic, "the taint was consumed by the reset")
    },

    EngineCase("total-last-selected-window-overflow") {
        // Overflow INSIDE the window: quiet generic error, no flag, and
        // the section still resets.
        let inside = tlSheet("1\n2\n10 ^ 308\n10 ^ 308\ntotal last 2\ntotal")
        try tlExpectOverflow(inside, 4)
        try expectEqual(tlNumber(inside, 5), 0, "reset after an overflowed window")
        // Overflow while summing the window itself.
        try tlExpectOverflow(tlSheet("10 ^ 308\n10 ^ 308\ntotal last 2"), 2)
        // The bare total of the same poisoned section still errors.
        try tlExpectOverflow(tlSheet("10 ^ 308\n10 ^ 308\ntotal"), 2)
        // Overflow OUTSIDE the window never poisons it.
        try expectEqual(tlNumber(tlSheet("10 ^ 308\n10 ^ 308\n1\n2\ntotal last 2"), 4), 3,
                        "clean window after a poisoned section")
        // A window that reaches back into the overflowing rows still
        // errors: the window, not the section, decides.
        try tlExpectOverflow(tlSheet("10 ^ 308\n10 ^ 308\n1\n2\ntotal last 4"), 4)
        try tlParity("10 ^ 308\n10 ^ 308\n1\n2\ntotal last 2")
    },

    EngineCase("total-last-base-text-classification") {
        // The command is an ordinary expression row for the structural
        // classifier: the keyword stays base text and paints exactly
        // like its keyword-neutral twin. The semibold answer + gray rule
        // come from the derived metadata, never from a syntax role.
        try expectEqual(SheetLineAnalysis.parse("total last 3").kind, .expression,
                        "expression kind")
        let command = SyntaxClassifier.spans(for: "total last 3", rates: Rates(),
                                             decimalPlaces: 7)[0]
        let twin = SyntaxClassifier.spans(for: "zzz last 3", rates: Rates(),
                                          decimalPlaces: 7)[0]
        try expectEqual(command.map(\.role), twin.map(\.role), "no special syntax role")
        try expect(!command.contains { NSLocationInRange(0, $0.range) },
                   "the keyword itself is never painted")
        try expectEqual(SyntaxClassifier.spans(for: "total", rates: Rates(),
                                               decimalPlaces: 7)[0], [],
                        "bare total stays base text")
    },
]
