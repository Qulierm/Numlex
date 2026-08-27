import Foundation
import NumlexCore

/// Named money assignments, typed time rates, typed variable reuse and
/// the hardened natural highlighting — the r17 regression suite.
///
/// Engine cases run the real top-down pipeline (`evaluateSheet`,
/// `resolveSheet` for tokens); syntax cases run the classifier on
/// EVERY character prefix and deletion suffix of the user lines;
/// formatting cases pin byte identity of natural lines on every tick.

private let M = "\u{FFFC}"

private func aRates() -> Rates {
    Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1, "RUB": 90, "JPY": 150])
}

private func aSheet(_ lines: [String], rates: Rates = aRates()) -> [SheetLine] {
    var vars: [String: Double] = [:]
    return evaluateSheet(lines.joined(separator: "\n"),
                         variables: &vars, rates: rates, decimalPlaces: 7)
}

private func isMoney(_ r: LineResult, v: Double, code: String) -> Bool {
    if case .money(let x, let c) = r { return x == v && c == code }
    return false
}

private func isError(_ r: LineResult) -> Bool {
    if case .error = r { return true }
    return false
}

private func isNumber(_ r: LineResult) -> Bool {
    if case .number = r { return true }
    return false
}

private let fourLines: [String] = [
    "monthly rent = $2.5k",
    "phone bill = 45$",
    "food = $50 per day × 30 days.",
    "contractor = $85 / hr × 8 hrs.",
]

public let moneyAssignmentCases: [EngineCase] = [
    EngineCase("assign-four-lines") { try bodyFourLines() },
    EngineCase("assign-reuse-multiply") { try bodyReuse() },
    EngineCase("assign-same-currency-add") { try bodySameCurrency() },
    EngineCase("assign-contextual-percent") { try bodyContextualPercent() },
    EngineCase("assign-mixed-currency-error") { try bodyMixedCurrency() },
    EngineCase("assign-markers-postfix-compact") { try bodyMarkers() },
    EngineCase("assign-rate-per-day") { try bodyPerDay() },
    EngineCase("assign-rate-slash-singular-plural") { try bodyRateWords() },
    EngineCase("assign-rate-uncancelled-error") { try bodyUncancelled() },
    EngineCase("assign-zero-and-mismatch") { try bodyZero() },
    EngineCase("assign-invalid-lhs") { try bodyInvalidLHS() },
    EngineCase("assign-longest-name") { try bodyLongest() },
    EngineCase("assign-before-declaration-error") { try bodyBeforeDecl() },
    EngineCase("assign-huge-finite-overflow") { try bodyHuge() },
    EngineCase("assign-malformed-no-fallback") { try bodyNoFallback() },
    EngineCase("assign-single-id-money-reuse") { try bodySingleIdReuse() },
    EngineCase("assign-multiword-scalar") { try bodyMultiwordScalar() },
    EngineCase("assign-iso-annotation") { try bodyISO() },
    EngineCase("assign-named-conversion-eur") { try bodyNamedConversion() },
    EngineCase("assign-token-from-assignment") { try bodyToken() },
    EngineCase("syntax-assign-intended-spans") { try bodySpans() },
    EngineCase("syntax-reference-name-green") { try bodyRefSpans() },
    EngineCase("syntax-prefix-stress") { try bodyPrefixStress() },
    EngineCase("syntax-sanitize-defensive") { try bodySanitize() },
    EngineCase("format-assign-byte-identity") { try bodyFormatIdentity() },
    EngineCase("format-caret-map-identity") { try bodyCaretMap() },
]

// MARK: - Engine bodies

private func bodyFourLines() throws {
    let lines = aSheet(fourLines)
    try expectEqual(lines.count, 4, "one row per line")
    if isMoney(lines[0].result, v: 2500, code: "USD") {
        try expectEqual(formatMoney(2500, code: "USD"), "$2,500.00", "display")
    } else { try expect(false, "monthly rent = $2.5k → .money(2500, USD)") }
    if isMoney(lines[1].result, v: 45, code: "USD") {
        try expectEqual(formatMoney(45, code: "USD"), "$45.00", "display")
    } else { try expect(false, "phone bill = 45$ → .money(45, USD)") }
    if isMoney(lines[2].result, v: 1500, code: "USD") {
        try expectEqual(formatMoney(1500, code: "USD"), "$1,500.00", "display")
    } else { try expect(false, "food rate line → .money(1500, USD)") }
    if isMoney(lines[3].result, v: 680, code: "USD") {
        try expectEqual(formatMoney(680, code: "USD"), "$680.00", "display")
    } else { try expect(false, "contractor rate line → .money(680, USD)") }
}

private func bodyReuse() throws {
    let lines = aSheet(fourLines + ["monthly rent × 12"])
    try expect(isMoney(lines[4].result, v: 30000, code: "USD"),
               "monthly rent × 12 → $30,000.00")
    if case .money = lines[4].result {
        try expectEqual(formatMoney(30000, code: "USD"), "$30,000.00", "display")
    }
}

private func bodySameCurrency() throws {
    let lines = aSheet(fourLines + ["monthly rent + phone bill"])
    try expect(isMoney(lines[4].result, v: 2545, code: "USD"),
               "same-currency add → $2,545.00")
}

private func bodyContextualPercent() throws {
    let lines = aSheet(fourLines + ["monthly rent + 5%"])
    try expect(isMoney(lines[4].result, v: 2625, code: "USD"),
               "contextual % on named money → $2,625.00")
}

private func bodyMixedCurrency() throws {
    let lines = aSheet(["a = $10", "b = €20", "a + b", "a + 5"])
    try expect(isError(lines[2].result), "mixed currencies are a hidden error")
    try expect(!isNumber(lines[2].result), "mixed currency line is never .number")
    try expect(isMoney(lines[3].result, v: 15, code: "USD"), "a + 5 → $15.00")
}

private func bodyMarkers() throws {
    let lines = aSheet(["x = 45$", "y = $2.5k", "z = 2.5k$", "w = CA$50"])
    try expect(isMoney(lines[0].result, v: 45, code: "USD"), "postfix $")
    try expect(isMoney(lines[1].result, v: 2500, code: "USD"), "prefix $ + k")
    try expect(isMoney(lines[2].result, v: 2500, code: "USD"), "k before postfix $")
    try expect(isMoney(lines[3].result, v: 50, code: "CAD"), "CA$")
    let bad = aSheet(["m = 5$3", "n = $$10"])
    try expect(isError(bad[0].result), "5$3 is not a marker (hidden error)")
    try expect(isError(bad[1].result), "doubled $$ is not a marker")
}

private func bodyPerDay() throws {
    let lines = aSheet(["a = $24 per day × 12 hrs", "b = $5 per day × 2 days"])
    try expect(isMoney(lines[0].result, v: 12, code: "USD"),
               "$24 per day × 12 hrs = $12 (exact catalog factors)")
    try expect(isMoney(lines[1].result, v: 10, code: "USD"),
               "$5 per day × 2 days = $10")
}

private func bodyRateWords() throws {
    let lines = aSheet([
        "a = $10 / hr × 8 hours",
        "b = $1 / hr × 90 mins",
        "c = $12 / week × 2 weeks",
        "d = $2 per hour × 3 hours",
    ])
    try expect(isMoney(lines[0].result, v: 80, code: "USD"), "/ hr × hours")
    try expect(isMoney(lines[1].result, v: 1.5, code: "USD"), "/ hr × 90 mins = 1.5")
    try expect(isMoney(lines[2].result, v: 24, code: "USD"), "/ week × weeks")
    try expect(isMoney(lines[3].result, v: 6, code: "USD"), "per hour × hours")
}

private func bodyUncancelled() throws {
    let lines = aSheet(["x = $2.5k per day", "y = $85 / hr", "z = $5 per"])
    try expect(isError(lines[0].result), "uncancelled per-day rate is an error")
    try expect(isError(lines[1].result), "uncancelled /hr rate is an error")
    try expect(isError(lines[2].result), "dangling per is an error")
    let bare = aSheet(["$5 per day"])
    try expect(isError(bare[0].result), "$5 per day is not a number")
}

private func bodyZero() throws {
    let lines = aSheet([
        "x = $0 per day × 5 days",
        "y = $100 per day × 0 days",
        "z = $10 per day × 5 days × 3 hrs",
    ])
    try expect(isMoney(lines[0].result, v: 0, code: "USD"), "zero numerator → $0")
    try expect(isMoney(lines[1].result, v: 0, code: "USD"), "zero duration → $0")
    try expect(isError(lines[2].result), "one rate vs two durations is an error")
}

private func bodyInvalidLHS() throws {
    let lines = aSheet([
        "123 = $5",
        "monthly rent = $5 = 3",
        "a b c d e f g = $5",
        "= $5",
        "monthly rent! = $5",
    ])
    for (i, sl) in lines.enumerated() {
        let r = sl.result
        try expect(isError(r), "invalid LHS #\(i) is a hidden error")
        try expect(!isNumber(r), "invalid LHS #\(i) never becomes a number")
    }
}

private func bodyLongest() throws {
    let lines = aSheet(["rent = $100", "monthly rent = $2.5k",
                        "rent × 2", "monthly rent × 2"])
    try expect(isMoney(lines[2].result, v: 200, code: "USD"),
               "short name not stolen by the longer one")
    try expect(isMoney(lines[3].result, v: 5000, code: "USD"),
               "longest boundary match wins")
}

private func bodyBeforeDecl() throws {
    let lines = aSheet(["monthly rent × 12", "monthly rent = $2.5k",
                        "monthly rent × 12"])
    try expect(isError(lines[0].result), "reference before declaration is an error")
    try expect(!isNumber(lines[0].result),
               "pre-declaration reference never falls back to a number")
    try expect(isMoney(lines[1].result, v: 2500, code: "USD"), "declaration")
    try expect(isMoney(lines[2].result, v: 30000, code: "USD"), "after declaration")
}

private func bodyHuge() throws {
    let lines = aSheet([
        "big = $10^154 × 10^154",
        "big2 = $10^160 × 10^160",
    ])
    if case .money(let v, _) = lines[0].result {
        try expect(v.isFinite, "finite huge money value")
        try expect(!formatMoney(v, code: "USD").isEmpty, "display renders")
    } else {
        try expect(false, "10^308 is a finite money value")
    }
    try expect(isError(lines[1].result), "overflow to Infinity is a hidden error")
}

private func bodyNoFallback() throws {
    let lines = aSheet(["x = $5 +", "y = $", "food = $50 per",
                        "phone bill = 45$5", "a b c = $"])
    for (i, sl) in lines.enumerated() {
        let r = sl.result
        try expect(isError(r), "malformed #\(i) is a hidden error")
        try expect(!isNumber(r), "malformed #\(i) never falls back to a number")
    }
}

private func bodySingleIdReuse() throws {
    let lines = aSheet(["x = $5", "x × 12", "x + 5"])
    try expect(isMoney(lines[0].result, v: 5, code: "USD"), "single-id money assign")
    try expect(isMoney(lines[1].result, v: 60, code: "USD"), "single-id money reuse")
    try expect(isMoney(lines[2].result, v: 10, code: "USD"), "money + scalar")
}

private func bodyMultiwordScalar() throws {
    let lines = aSheet(["a b = 5 + 3", "a b × 2", "a b"])
    if case .variable(let name, let v) = lines[0].result {
        try expectEqual(name, "a b", "multiword scalar name")
        try expectEqual(v, 8, "a b = 8")
    } else { try expect(false, "a b = 5 + 3 is a variable assignment") }
    if case .number(let v, let u) = lines[1].result {
        try expectEqual(v, 16, "a b × 2 = 16")
        try expect(u == nil, "unitless result")
    } else { try expect(false, "a b × 2 is a number") }
    try expect(!isError(lines[2].result), "bare declared name is not an error")
}

private func bodyISO() throws {
    let lines = aSheet(["t = 100 USD", "u = 50 EUR", "t + 5"])
    try expect(isMoney(lines[0].result, v: 100, code: "USD"), "100 USD")
    try expect(isMoney(lines[1].result, v: 50, code: "EUR"), "50 EUR")
    try expect(isMoney(lines[2].result, v: 105, code: "USD"), "ISO name reuse")
}

private func bodyNamedConversion() throws {
    let lines = aSheet(["monthly rent = $100", "monthly rent in EUR",
                        "monthly rent to EUR"])
    if case .number(let v, let u) = lines[1].result {
        try expectClose(v, 110, 1e-9, "100 USD × 1.1 = 110 EUR")
        try expectEqual(u ?? "", "EUR", "unit EUR")
    } else { try expect(false, "named money in EUR converts via rates") }
    if case .number(let v, let u) = lines[2].result {
        try expectClose(v, 110, 1e-9, "legacy `to` keyword")
        try expectEqual(u ?? "", "EUR", "unit EUR")
    } else { try expect(false, "named money to EUR converts via rates") }
}

private func bodyToken() throws {
    let src = "monthly rent = $2.5k"
    let mDoc = (src as NSString).length + 1
    let ids = [UUID(), UUID()]
    let content = src + "\n" + M + " × 12"
    let refs = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                location: mDoc)]
    let (lines, _) = resolveSheet(content: content, lineIDs: ids,
                                  references: refs, rates: aRates(), decimalPlaces: 7)
    if case .number(let v, let u) = lines[1].result {
        try expectClose(v, 30000, 1e-9, "token from assignment × 12")
        try expectEqual(u ?? "", "USD", "currency carried")
    } else if case .money(let v, let c) = lines[1].result {
        try expectClose(v, 30000, 1e-9, "token from assignment × 12")
        try expectEqual(c, "USD", "currency carried")
    } else { try expect(false, "token × 12 line") }
    let content2 = src + "\n" + M + " in EUR"
    let (lines2, _) = resolveSheet(content: content2, lineIDs: ids,
                                   references: refs, rates: aRates(), decimalPlaces: 7)
    if case .number(let v, let u) = lines2[1].result {
        try expectClose(v, 2750, 1e-6, "2500 × 1.1 = 2750 EUR")
        try expectEqual(u ?? "", "EUR", "unit EUR")
        try expectEqual(formatQuantity(v, unit: u, decimalPlaces: 7),
                        "€2,750.00", "money display")
    } else { try expect(false, "token in EUR line") }
    let src3 = "monthly rent = $3k"
    let content3 = src3 + "\n" + M + " in EUR"
    let refs3 = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                 location: (src3 as NSString).length + 1)]
    let (lines3, _) = resolveSheet(content: content3, lineIDs: ids,
                                   references: refs3, rates: aRates(), decimalPlaces: 7)
    if case .number(let v, _) = lines3[1].result {
        try expectClose(v, 3300, 1e-6, "edited source updates the token")
    } else { try expect(false, "edited source token line") }
    // Broken: the reference's source line id matches no line.
    let src4 = "phone bill = 45$"
    let content4 = src4 + "\n" + M + " × 12"
    let deadRefs = [AnswerReference(sourceLineID: UUID(), labelLine: 1,
                                    location: (src4 as NSString).length + 1)]
    let (lines4, tokens) = resolveSheet(content: content4, lineIDs: ids,
                                        references: deadRefs, rates: aRates(), decimalPlaces: 7)
    try expect(!isNumber(lines4[1].result), "broken source never shows a value")
    if let t = tokens.first {
        if case .broken = t.state {
            // expected
        } else {
            try expect(false, "token state must be broken")
        }
    }
}

// MARK: - Syntax bodies

private func bodySpans() throws {
    let spans = SyntaxClassifier.spans(for: fourLines.joined(separator: "\n"),
                                       rates: aRates(), decimalPlaces: 7)
    try expectEqual(spans.count, 4, "one span list per line")
    // Line 0: `monthly rent = $2.5k`
    let l0 = spans[0]
    try expectEqual(l0.filter { $0.role == .variable }.map { $0.range },
                    [NSRange(location: 0, length: 12)], "whole LHS green")
    try expectEqual(l0.filter { $0.role == .moneyMarker }.map { $0.range },
                    [NSRange(location: 15, length: 1)], "purple $")
    try expectEqual(l0.filter { $0.role == .number }.map { $0.range },
                    [NSRange(location: 16, length: 4)], "cyan 2.5k")
    // Line 1: `phone bill = 45$`
    let l1 = spans[1]
    try expectEqual(l1.filter { $0.role == .variable }.map { $0.range },
                    [NSRange(location: 0, length: 10)], "whole LHS green")
    try expectEqual(l1.filter { $0.role == .number }.map { $0.range },
                    [NSRange(location: 13, length: 2)], "cyan 45")
    try expectEqual(l1.filter { $0.role == .moneyMarker }.map { $0.range },
                    [NSRange(location: 15, length: 1)], "purple postfix $")
    // Line 2: `food = $50 per day × 30 days.`
    let l2 = spans[2]
    try expectEqual(l2.filter { $0.role == .variable }.map { $0.range },
                    [NSRange(location: 0, length: 4)], "food green")
    try expectEqual(l2.filter { $0.role == .moneyMarker }.map { $0.range },
                    [NSRange(location: 7, length: 1)], "purple $")
    try expectEqual(l2.filter { $0.role == .number }.map { $0.range },
                    [NSRange(location: 8, length: 2), NSRange(location: 21, length: 2)],
                    "cyan 50 and 30")
    // Time UNIT aliases are conversion content; `per` keeps its own
    // specifier role in the natural context (base-colored by default).
    try expectEqual(l2.filter { $0.role == .conversion }.map { $0.range },
                    [NSRange(location: 15, length: 3), NSRange(location: 24, length: 4)],
                    "day / days conversion color")
    var covered = Set<Int>()
    for sp in l2 {
        for u in sp.range.location..<NSMaxRange(sp.range) { covered.insert(u) }
    }
    covered = covered.filter { $0 < 29 }
    try expect(!covered.contains(28), "terminal dot stays base")
    // r21: × and `per` carry their own roles (operatorGlyph / specifier)
    // and are base-colored by default — the default look is unchanged.
    try expect(covered.contains(19), "× keeps its operator role")
    try expect(covered.contains(11) && covered.contains(12) && covered.contains(13),
               "`per` keeps its specifier role in a natural money context")
    // Line 3: `contractor = $85 / hr × 8 hrs.`
    let l3 = spans[3]
    try expectEqual(l3.filter { $0.role == .variable }.map { $0.range },
                    [NSRange(location: 0, length: 10)], "contractor green")
    try expectEqual(l3.filter { $0.role == .moneyMarker }.map { $0.range },
                    [NSRange(location: 13, length: 1)], "purple $")
    try expectEqual(l3.filter { $0.role == .number }.map { $0.range },
                    [NSRange(location: 14, length: 2), NSRange(location: 24, length: 1)],
                    "cyan 85 and 8")
    try expectEqual(l3.filter { $0.role == .conversion }.map { $0.range },
                    [NSRange(location: 19, length: 2), NSRange(location: 26, length: 3)],
                    "hr / hrs conversion color")
}

private func bodyRefSpans() throws {
    let spans = SyntaxClassifier.spans(
        for: "monthly rent = $2.5k\nphone bill = 45$\nmonthly rent × 12\nmonthly rent + phone bill",
        rates: aRates(), decimalPlaces: 7)
    let l1 = spans[2]
    try expectEqual(l1.filter { $0.role == .variable }.map { $0.range },
                    [NSRange(location: 0, length: 12)], "declared name green in reuse")
    try expectEqual(l1.filter { $0.role == .number }.map { $0.range },
                    [NSRange(location: 15, length: 2)], "cyan 12")
    let l2 = spans[3]
    try expectEqual(l2.filter { $0.role == .variable }.map { $0.range },
                    [NSRange(location: 0, length: 12), NSRange(location: 15, length: 10)],
                    "both names green")
}

private func assertSpansValid(_ line: String, _ spans: [SyntaxSpan]) throws {
    let len = (line as NSString).length
    var previousEnd = -1
    for s in spans {
        try expect(s.range.location >= 0 && s.range.length > 0
            && NSMaxRange(s.range) <= len,
            "span \(s.range) within line of \(len)")
        try expect(s.range.location >= previousEnd,
                   "spans sorted and non-overlapping: \(s.range)")
        previousEnd = NSMaxRange(s.range)
    }
}

private func bodyPrefixStress() throws {
    var total = 0
    for line in fourLines {
        let chars = Array(line)
        for n in 0...chars.count {
            let prefix = String(chars[0..<n])
            let spans = SyntaxClassifier.spans(for: prefix,
                                               rates: aRates(), decimalPlaces: 7)
            try expectEqual(spans.count, 1, "one row for the single line")
            try assertSpansValid(prefix, spans[0])
            total += 1
        }
        for n in 0..<chars.count {
            let suffix = String(chars[n...])
            let spans = SyntaxClassifier.spans(for: suffix,
                                               rates: aRates(), decimalPlaces: 7)
            try expectEqual(spans.count, 1, "one row for the single line")
            try assertSpansValid(suffix, spans[0])
            total += 1
        }
    }
    try expect(total == fourLines.reduce(0) { $0 + $1.count * 2 + 1 },
               "every prefix and suffix classified")
    // Emoji / prose / answer-marker adjacency: never an exception, and
    // every span stays inside the line.
    let tricky = [
        "the 🏠 rent is $5",
        "🏠 monthly rent = $2.5k",
        "$5" + M + " + 3",
        M + " monthly rent = $2.5k",
        "monthly rent = $2.5k" + M,
        "a long bounded line with $1,234,567.89 and per day words and a terminal dot.",
    ]
    for line in tricky {
        let spans = SyntaxClassifier.spans(for: line,
                                           rates: aRates(), decimalPlaces: 7)
        try expectEqual(spans.count, 1, "one row")
        try assertSpansValid(line, spans[0])
    }
}

private func bodySanitize() throws {
    let len = 10
    let bad: [SyntaxSpan] = [
        SyntaxSpan(role: .number, range: NSRange(location: NSNotFound, length: 2)),
        SyntaxSpan(role: .number, range: NSRange(location: 0, length: 0)),
        SyntaxSpan(role: .number, range: NSRange(location: 8, length: 5)),
        SyntaxSpan(role: .number, range: NSRange(location: -1, length: 3)),
        SyntaxSpan(role: .variable, range: NSRange(location: 2, length: 4)),
        SyntaxSpan(role: .number, range: NSRange(location: 2, length: 2)),
        SyntaxSpan(role: .conversion, range: NSRange(location: 5, length: 3)),
        SyntaxSpan(role: .moneyMarker, range: NSRange(location: 7, length: 1)),
    ]
    let out = SyntaxClassifier.sanitize(bad, lineLength: len)
    var previousEnd = -1
    for s in out {
        try expect(s.range.location >= 0 && s.range.length > 0
            && NSMaxRange(s.range) <= len, "sanitized span valid: \(s.range)")
        try expect(s.range.location >= previousEnd, "sanitized disjoint")
        previousEnd = NSMaxRange(s.range)
    }
    try expect(out.contains { $0.role == .variable
        && $0.range == NSRange(location: 2, length: 4) }, "longer span wins")
    try expect(!out.contains { $0.role == .number
        && $0.range == NSRange(location: 2, length: 2) }, "shorter overlap dropped")
}

// MARK: - Formatting bodies

private func bodyFormatIdentity() throws {
    let doc = fourLines.joined(separator: "\n")
        + "\nmonthly rent = $"
        + "\nfood = $50 per"
        + "\ncontractor = $85 / hr × 8 hrs"
        + "\nphone bill = 45$"
        + "\n1 + 2"
    let canonical = NotebookFormatting.canonicalDocument(doc)
    try expectEqual(canonical, doc, "natural lines byte-identical, 1+2 already canonical")
    let doc2 = "1+2\nmonthly rent = $2.5k"
    let canonical2 = NotebookFormatting.canonicalDocument(doc2)
    try expectEqual(canonical2, "1 + 2\nmonthly rent = $2.5k",
                    "legacy normalized, money untouched")
    try expectEqual(NotebookFormatting.isMathematical("food = $50 per"), false,
                    "natural error line is not mathematical")
    try expectEqual(NotebookFormatting.isMathematical("monthly rent = $"), false,
                    "incomplete marker prefix is not mathematical")
    try expectEqual(NotebookFormatting.isMathematical("1 + 2"), true,
                    "plain math stays mathematical")
}

private func bodyCaretMap() throws {
    // Identity document: the map exists and is well-formed (the app only
    // applies maps when the document actually changed, but the shape
    // must still be sound).
    let doc = fourLines.joined(separator: "\n")
    let canonical = NotebookFormatting.canonicalDocument(doc)
    try expectEqual(canonical, doc, "identity document")
    let map = NotebookFormatting.mapDocument(from: doc, to: canonical)
    let n = (doc as NSString).length
    try expectEqual(map.count, n + 1, "map length")
    try expectEqual(map.first ?? -1, 0, "map starts at 0")
    try expectEqual(map.last ?? -1, n, "map ends at the document end")
    for (prev, cur) in zip(map, map.dropFirst()) where cur < prev {
        try expect(false, "map monotone at \(cur)")
    }
    // Changed document: `1+2` normalizes, the money line stays put —
    // the caret right after `+` lands after the canonical `+`.
    let from = "1+2\nmonthly rent = $2.5k"
    let to = "1 + 2\nmonthly rent = $2.5k"
    let map2 = NotebookFormatting.mapDocument(from: from, to: to)
    try expectEqual(map2.count, (from as NSString).length + 1, "map2 length")
    try expectEqual(Array(map2[0...3]), [0, 1, 3, 5],
                    "caret map across the normalized first line")
}
