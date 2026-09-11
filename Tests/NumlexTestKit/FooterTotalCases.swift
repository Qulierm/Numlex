import Foundation
import NumlexCore

/// The persistent bottom-panel Total (`SheetFooterTotal`) — the footer
/// contract, distinct from the inline `total` command.
///
/// Coverage: dimension-agnostic magnitudes (unitless, physical units,
/// weather, durations, currency-code units, money), named scalars and
/// exact integers, percent/multiplier/fraction canonical values,
/// token-derived and duplicate rows counting once, inline total rows
/// excluded, the non-scalar exclusions (boolean/date/location/DMS/
/// broken/error/blank/skip/title), negatives and zero, "no eligible
/// rows => nil" vs "eligible rows summing to zero => 0", non-finite
/// defensive exclusion and deterministic overflow, conversion output
/// magnitudes, unchanged inline `total` semantics, and the source
/// wiring (the view delegates to the core API and no longer encodes
/// eligibility itself).

private let WM = "\u{FFFC}"

// MARK: - Local helpers

private func footerSource(_ rel: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

private func footerSheet(_ content: String,
                         rates: Rates = Rates(),
                         constants: [UserConstant] = [],
                         weather: WeatherContext = .empty,
                         decimalPlaces: Int = 7) -> [SheetLine] {
    var v: [String: Double] = [:]
    return evaluateSheet(content, variables: &v, rates: rates,
                         decimalPlaces: decimalPlaces,
                         constants: constants, weather: weather)
}

/// The unitless value of one row, or NaN when the row is not a plain
/// number (every inequality below then fails loudly).
private func footerNumber(_ lines: [SheetLine], _ i: Int) -> Double {
    if case .number(let v, nil, _, _) = lines[i].result { return v }
    return .nan
}

private func footerLine(_ result: LineResult, isTotal: Bool = false) -> SheetLine {
    SheetLine(sourceLineIndex: 0, result: result, isTotal: isTotal)
}

private func footerLondon(_ temp: Double = 18.5) -> WeatherContext {
    WeatherContext(snapshots: ["london": WeatherSnapshot(
        queryKey: "london", displayQuery: "London", placeName: "London",
        country: "United Kingdom", latitude: 51.5074, longitude: -0.1278,
        temperatureCelsius: temp, fetchedAt: Date())])
}

public let footerTotalCases: [EngineCase] = [

    // MARK: - Dimension-agnostic magnitudes

    EngineCase("footer-unit-and-money-magnitudes") {
        // The approved contract example: `2 kg`, `$3` and `4 EUR` are
        // summed by MAGNITUDE, with no unit conversion and no suffix.
        let lines = footerSheet("2 kg\n$3\n4 EUR")
        try expectEqual(SheetFooterTotal.eligibleRowCount(lines), 3, "all three eligible")
        try expectClose(SheetFooterTotal.aggregate(lines) ?? .nan, 9, 1e-12,
                        "2 kg + $3 + 4 EUR = 9")
        // Row order never matters for a fold of magnitudes.
        let reversed = Array(lines.reversed())
        try expectClose(SheetFooterTotal.aggregate(reversed) ?? .nan, 9, 1e-12,
                        "order-independent")
        // Units stay untouched by the aggregate: the rows still display
        // their own units.
        if case .number(_, let unit, _, _) = lines[0].result {
            try expectEqual(unit ?? "<none>", "kg", "kg unit preserved")
        } else {
            throw CaseFailure(message: "2 kg must stay a number", location: "FooterTotal")
        }
        if case .money(let v, let code) = lines[1].result {
            try expectClose(v, 3, 1e-12, "money value")
            try expectEqual(code, "USD", "USD code")
        } else {
            throw CaseFailure(message: "$3 must stay money", location: "FooterTotal")
        }
        // And the aggregate is one plain unitless number.
        try expectEqual(SheetFooterTotal.aggregate(lines.map {
            footerLine($0.result, isTotal: $0.isTotal)
        }).map { $0.isFinite } ?? false, true, "plain finite Double")
    },

    EngineCase("footer-named-scalars-and-exact-integers") {
        let lines = footerSheet("apple = 5\napple + 3\n0x1F\nhex = 0xFF\nhex + 1")
        try expect(SheetFooterTotal.eligibleRowCount(lines) == lines.count,
                   "every row eligible (got \(SheetFooterTotal.eligibleRowCount(lines)))")
        // 5 (variable) + 8 (ordinary) + 31 (.integer) + 255 (.variableInt)
        // + 256 (ordinary exact) = 555.
        try expectClose(SheetFooterTotal.aggregate(lines) ?? .nan, 555, 1e-12,
                        "named scalars and exact integers all contribute")
        if case .variableInt(_, let v, let radix) = lines[3].result {
            try expectEqual(v, 255, "hex assignment exact value")
            try expectEqual(radix, 16, "hex radix")
        } else {
            throw CaseFailure(message: "hex assignment must be variableInt",
                              location: "FooterTotal")
        }
        if case .integer(let v, _) = lines[2].result {
            try expectEqual(v, 31, "0x1F exact value")
        } else {
            throw CaseFailure(message: "0x1F must be an exact integer",
                              location: "FooterTotal")
        }
    },

    EngineCase("footer-kinds-canonical-values") {
        // Percent keeps its ratio, multiplier its factor, fraction its
        // numeric value — never the display string.
        let lines = footerSheet("25%\n1.5x\n3/8\n40% of 200")
        try expectClose(SheetFooterTotal.contribution(of: lines[0]) ?? .nan, 0.25, 1e-12,
                        "25% contributes 0.25")
        try expectClose(SheetFooterTotal.contribution(of: lines[1]) ?? .nan, 1.5, 1e-12,
                        "1.5x contributes 1.5")
        try expectClose(SheetFooterTotal.contribution(of: lines[2]) ?? .nan, 0.375, 1e-12,
                        "3/8 contributes its numeric value")
        try expectClose(SheetFooterTotal.contribution(of: lines[3]) ?? .nan, 80, 1e-12,
                        "40% of 200 contributes 80")
        try expectClose(SheetFooterTotal.aggregate(lines) ?? .nan, 82.125, 1e-12,
                        "canonical sum 82.125")
        // The kinds are presentation metadata only: each contribution
        // equals the raw evaluated value.
        for (i, line) in lines.enumerated() {
            guard case .number(let v, _, _, _) = line.result else {
                throw CaseFailure(message: "row \(i) must be a number", location: "FooterTotal")
            }
            try expectClose(SheetFooterTotal.contribution(of: line) ?? .nan, v, 1e-12,
                            "row \(i) contributes its raw value")
        }
    },

    EngineCase("footer-weather-contributes-its-magnitude") {
        // Weather is a unit-bearing temperature: excluded from the
        // inline section sum, but a real scalar for the footer.
        let lines = footerSheet("weather in London\n10", weather: footerLondon(18.5))
        try expectEqual(lines[0].result, .number(value: 18.5, unit: "C°"), "ready weather")
        try expectClose(SheetFooterTotal.contribution(of: lines[0]) ?? .nan, 18.5, 1e-12,
                        "weather contributes 18.5")
        try expect(InlineTotal.contribution(of: lines[0].result, isTotalRow: false) == nil,
                   "inline section total still excludes weather", "inline")
        try expectClose(SheetFooterTotal.aggregate(lines) ?? .nan, 28.5, 1e-12,
                        "footer = 18.5 + 10")
    },

    EngineCase("footer-conversion-output-magnitude") {
        // A conversion row contributes the magnitude it OUTPUTS.
        let lines = footerSheet("10 km to meter\n1 hour to minutes\n3\n")
        try expect(SheetFooterTotal.eligibleRowCount(lines) == 3,
                   "three eligible rows (trailing blank ignored)")
        // 10000 m + 60 min + 3 = 10063 (no cross-dimension conversion).
        try expectClose(SheetFooterTotal.aggregate(lines) ?? .nan, 10063, 1e-12,
                        "conversion outputs summed by magnitude")
        // Money conversion contributes the converted (output) value.
        let money = footerSheet("$100 to EUR",
                                rates: Rates(base: "USD", rates: ["USD": 1, "EUR": 0.9]))
        // The evaluator presents the converted amount as its output
        // magnitude (currency-code unit or a money row — both eligible).
        switch money[0].result {
        case .money(let mv, let code):
            try expectEqual(code, "EUR", "converted currency code")
            try expectClose(SheetFooterTotal.contribution(of: money[0]) ?? .nan, mv, 1e-12,
                            "money conversion contributes its output magnitude")
        case .number(let mv, let unit, _, _):
            try expectEqual(unit ?? "<none>", "EUR", "converted currency unit")
            try expectClose(SheetFooterTotal.contribution(of: money[0]) ?? .nan, mv, 1e-12,
                            "currency conversion contributes its output magnitude")
        default:
            throw CaseFailure(message: "expected a currency conversion, got \(money[0].result)",
                              location: "FooterTotal")
        }
        try expectClose(SheetFooterTotal.contribution(of: money[0]) ?? .nan, 90, 1e-12,
                        "$100 to EUR @0.9 contributes 90")
    },

    // MARK: - Counting rules

    EngineCase("footer-tokens-and-duplicates-count-once-per-row") {
        let u0 = UUID(), u1 = UUID(), u2 = UUID()
        let content = "7\n" + WM + "\n" + WM
        let (lines, _) = resolveSheet(
            content: content, lineIDs: [u0, u1, u2],
            references: [
                AnswerReference(sourceLineID: u0, labelLine: 1, location: 2),
                AnswerReference(sourceLineID: u0, labelLine: 1, location: 4)
            ],
            rates: Rates(), decimalPlaces: 7, weather: .empty)
        try expectEqual(lines.count, 3, "three rows")
        try expectEqual(lines[1].result, .number(value: 7, unit: nil), "first token row")
        try expectEqual(lines[2].result, .number(value: 7, unit: nil), "second token row")
        // Rows are counted, never dependency-DAG deduplicated: the
        // source row plus each referring row contribute once.
        try expectEqual(SheetFooterTotal.eligibleRowCount(lines), 3, "three eligible rows")
        try expectClose(SheetFooterTotal.aggregate(lines) ?? .nan, 21, 1e-12,
                        "7 + 7 + 7 (row-counted, not deduplicated)")
    },

    EngineCase("footer-inline-total-rows-excluded") {
        let lines = footerSheet("10\n5\ntotal\n5\ntotal")
        try expect(lines[2].isTotal, "first total flagged")
        try expect(lines[4].isTotal, "second total flagged")
        try expect(SheetFooterTotal.contribution(of: lines[2]) == nil,
                   "derived total row never contributes", "footer")
        try expect(SheetFooterTotal.contribution(of: lines[4]) == nil,
                   "second total row never contributes", "footer")
        // The ordinary 10 and 5 count; the two total rows do not.
        try expectEqual(SheetFooterTotal.eligibleRowCount(lines), 3, "three eligible rows")
        try expectClose(SheetFooterTotal.aggregate(lines) ?? .nan, 20, 1e-12,
                        "footer counts 10 + 5 + 5 and excludes both total rows")
        // Explicit isTotal flag on an otherwise numeric row is enough.
        let flagged = [footerLine(.number(value: 4, unit: nil, kind: .plain, fraction: nil),
                                  isTotal: true)]
        try expect(SheetFooterTotal.aggregate(flagged) == nil,
                   "a lone total row leaves no footer total", "footer")
    },

    // MARK: - Exclusions

    EngineCase("footer-excludes-non-scalar-results") {
        let excluded: [LineResult] = [
            .blank,
            .skip,
            .title("Groceries"),
            .boolean(value: true),
            .date(year: 2026, month: 5, day: 5, showYear: false),
            .location(name: "Paris", country: "France",
                      coordinate: GeoCoordinate(latitude: 48.8566, longitude: 2.3522)),
            .dms(DMSTools.fromDecimal(156.75)!),
            .brokenToken(line: 3),
            .error(message: "Invalid expression")
        ]
        for result in excluded {
            try expect(SheetFooterTotal.contribution(of: footerLine(result)) == nil,
                       "\(result) must not contribute", "footer")
        }
        try expect(SheetFooterTotal.aggregate(excluded.map { footerLine($0) }) == nil,
                   "no eligible rows anywhere -> nil", "footer")
        // Evaluated equivalents from real sheets stay excluded too.
        let sheet = footerSheet("2 < 3\nMay 5 + 43 days\n1/0\n\n")
        for line in sheet {
            try expect(SheetFooterTotal.contribution(of: line) == nil,
                       "evaluated \(line.result) must not contribute", "footer")
        }
        try expect(SheetFooterTotal.aggregate(sheet) == nil,
                   "non-scalar sheet has no footer total", "footer")
    },

    EngineCase("footer-negative-zero-and-empty") {
        // Negatives and zero are ordinary scalar rows.
        let lines = footerSheet("-5\n0\n5\n-2 kg")
        try expectEqual(SheetFooterTotal.eligibleRowCount(lines), 4, "all four eligible")
        try expectClose(SheetFooterTotal.aggregate(lines) ?? .nan, -2, 1e-12,
                        "-5 + 0 + 5 + (-2) = -2")
        // Eligible rows summing to zero -> 0, never nil.
        let zero = footerSheet("5\n-5")
        try expectEqual(SheetFooterTotal.eligibleRowCount(zero), 2, "two eligible")
        let zeroTotal = SheetFooterTotal.aggregate(zero)
        try expect(zeroTotal != nil, "zero total is NOT nil", "footer")
        try expectEqual(zeroTotal ?? .nan, 0, "exact zero")
        // A lone zero is an eligible row.
        let single = footerSheet("0")
        try expectEqual(SheetFooterTotal.aggregate(single) ?? .nan, 0, "0 sheet totals 0")
        // No eligible rows -> nil (nothing to display).
        try expect(SheetFooterTotal.aggregate([]) == nil, "empty sheet -> nil", "footer")
        let blanks = footerSheet("\n\n")
        try expect(SheetFooterTotal.eligibleRowCount(blanks) == 0, "blank rows ineligible")
        try expect(SheetFooterTotal.aggregate(blanks) == nil, "blank-only sheet -> nil", "footer")
    },

    // MARK: - Non-finite / overflow

    EngineCase("footer-nonfinite-excluded-and-overflow-deterministic") {
        // A non-finite evaluator value makes its row ineligible rather
        // than poisoning the aggregate (defensive: the engine
        // boundaries reject non-finite results anyway).
        for bad in [Double.infinity, -Double.infinity, Double.nan] {
            let row = footerLine(.number(value: bad, unit: nil, kind: .plain, fraction: nil))
            try expect(SheetFooterTotal.contribution(of: row) == nil,
                       "\(bad) is ineligible", "footer")
        }
        try expect(SheetFooterTotal.contribution(of:
            footerLine(.money(value: .nan, code: "USD"))) == nil,
            "non-finite money ineligible", "footer")
        // Finite inputs can still overflow: the fold is left-to-right
        // and deterministic, and the shared formatter renders ±∞
        // safely instead of the app trapping.
        let overflow = [
            footerLine(.number(value: 1e308, unit: nil, kind: .plain, fraction: nil)),
            footerLine(.number(value: 1e308, unit: nil, kind: .plain, fraction: nil))
        ]
        let sum = SheetFooterTotal.aggregate(overflow)
        try expect(sum?.isInfinite == true, "overflowing sum is infinite, not trapped")
        try expectEqual(sum ?? 0, .infinity, "deterministic +∞")
        try expectEqual(formatDisplayValue(sum ?? 0, decimalPlaces: 7), "+∞",
                        "footer-formatted overflow stays safe")
        // One huge and one ordinary row: same deterministic order.
        let near = [
            footerLine(.number(value: 1e308, unit: nil, kind: .plain, fraction: nil)),
            footerLine(.number(value: 5e22, unit: nil, kind: .plain, fraction: nil))
        ]
        // 5e22 sits below the 1e308 ULP, so the fold is exactly 1e308:
        // deterministic and finite, never trapped.
        try expectClose(SheetFooterTotal.aggregate(near) ?? .nan, 1e308, 1e292,
                        "near-overflow finite sum")
        try expect(SheetFooterTotal.aggregate(near)?.isFinite == true,
                   "near-overflow sum stays finite")
    },

    // MARK: - Inline total semantics unchanged

    EngineCase("footer-inline-total-semantics-unchanged") {
        // Money, unit-bearing quantities, dates and errors stay OUT of
        // the inline section sum — only the unitless 10 counts there.
        let lines = footerSheet("$5\n10 km to meter\nJan 10 + 12 days\n1/0\n10\ntotal")
        try expect(lines[5].isTotal, "total row flagged")
        try expectEqual(footerNumber(lines, 5), 10, "inline section total is still 10")
        // The footer has its own, broader contract: money + conversion
        // output + unitless (totals excluded) = 5 + 10000 + 10.
        try expectEqual(SheetFooterTotal.eligibleRowCount(lines), 3, "three eligible rows")
        try expectClose(SheetFooterTotal.aggregate(lines) ?? .nan, 10015, 1e-12,
                        "footer = 5 + 10000 + 10")
        // Section scoping still resets after each total command.
        let sectioned = footerSheet("1\n2\ntotal\n3\ntotal")
        try expectEqual(footerNumber(sectioned, 2), 3, "first section 1 + 2")
        try expectEqual(footerNumber(sectioned, 4), 3, "second section 3")
        try expectClose(SheetFooterTotal.aggregate(sectioned) ?? .nan, 6, 1e-12,
                        "footer keeps summing the whole sheet (1 + 2 + 3)")
    },

    // MARK: - Source wiring

    EngineCase("footer-source-wiring-delegates-to-core") {
        guard let view = footerSource("Sources/NumlexApp/Views/AnswerColumnView.swift") else {
            throw CaseFailure(message: "missing AnswerColumnView.swift", location: "FooterTotal")
        }
        try expect(view.contains("SheetFooterTotal.aggregate(rows)"),
                   "the footer delegates to the core aggregate", "wiring")
        // The view no longer encodes eligibility: no unit filter, no
        // result-type switch in the summary property.
        try expect(!view.contains("u == nil"), "no unitless-only filter in the view", "wiring")
        try expect(!view.contains("let numeric = rows.compactMap"),
                   "the old per-type compactMap filter is gone", "wiring")
        try expect(!view.contains("line.result, u == nil"),
                   "no result-type eligibility test in the view", "wiring")
        try expect(!view.contains("isTotal else { return nil }"),
                   "total-row exclusion now lives in the core contract", "wiring")
        // Footer geometry/gate/formatting untouched.
        try expect(view.contains("if showTotalBar, let s = summary {"),
                   "the showTotalBar gate is unchanged", "wiring")
        try expect(view.contains("formatDisplayValue(sum, decimalPlaces: decimalPlaces"),
                   "the shared formatter still renders the value", "wiring")
        guard let core = footerSource("Sources/NumlexCore/Engine/SheetFooterTotal.swift") else {
            throw CaseFailure(message: "missing SheetFooterTotal.swift", location: "FooterTotal")
        }
        try expect(core.contains("public static func aggregate(_ lines: [SheetLine]) -> Double?"),
                   "public aggregate API exists", "wiring")
        try expect(core.contains("public static func eligibleRowCount(_ lines: [SheetLine]) -> Int"),
                   "public row-count API exists", "wiring")
        try expect(core.contains("isTotalRow: line.isTotal"),
                   "the core owns the inline-total row exclusion", "wiring")
    }
]
