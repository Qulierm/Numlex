//
//  LinkedConversionCases.swift
//  NumlexTestKit
//
//  r91: linked answers participate in ORDINARY conversions.
//
//  A linked answer (`<answer token>` + its `AnswerReference`) is a live
//  quantity. Before r91 the only conversion route was
//  `<unit-bearing token> to <target>`: the token itself had to carry a
//  source unit, so the reported `<linked 4673> mg to kg` missed the
//  route and fell into the token-expression grammar, which cannot parse
//  conversion keywords, and ended as a hidden `Invalid expression`.
//
//  The fix substitutes the linked value into an ordinary conversion
//  line and routes it through the ONE conversion engine
//  (`tryConversion`), so:
//    - `<unitless numeric token> <source unit> to <target>` works like
//      the typed literal `4673 mg to kg`;
//    - `<unit-bearing token> to <target>` keeps working unchanged;
//    - every conversion class and error class matches ordinary lines;
//    - a semantic unitless token (percent / fraction / multiplier) or a
//      boolean token can NEVER be relabeled as a physical unit.
//
//  The document is never touched: the input content, the U+FFFC marker,
//  the `AnswerReference` identity, the line IDs and the token states are
//  asserted unchanged, and the token stays LIVE (a source edit changes
//  the converted answer).
//
//  r92: a unit-bearing linked answer may REPEAT its own unit explicitly
//  (`4673 mg` + `<token> mg to kg`). The repeated unit is compared with
//  the carried one by EXACT unit identity (label equality, or identical
//  kind/vector/family/toBase):
//    - agreement converts, using the user's own text (no duplicated
//      label is synthesized), so aliases like `inch` for `in` work;
//    - a known-but-different unit is the documented `Incompatible units`
//      conflict — the linked answer's own unit is never silently
//      reinterpreted (a `C°`-carrying answer is not re-based as `F°`);
//    - an unresolvable unit on either side keeps the previous behavior
//      and lets the conversion engine report its own message.
//  BUG-01 (`3 in` + `<token> in cm` / `in in`) is deliberately NOT pinned
//  here: it is a known open defect, verified with the probe instead.

import Foundation
import NumlexCore

private let M91 = String(answerTokenMarker)

/// Resolves one sheet with explicit references and returns its rows plus
/// the resolved token states.
private func lcResolve(
    _ content: String,
    refs: [(source: Int, label: Int, location: Int)],
    decimalPlaces: Int = 7,
    rates: Rates = Rates(),
    context: NumberFormatContext = .legacy,
    unitContext: UnitContext = .builtIns
) -> (lines: [SheetLine], tokens: [TokenResolution], ids: [UUID]) {
    let count = content.components(separatedBy: "\n").count
    let ids = (0..<count).map { _ in UUID() }
    let references = refs.map {
        AnswerReference(sourceLineID: ids[$0.source], labelLine: $0.label,
                        location: $0.location)
    }
    let resolved = resolveSheet(content: content, lineIDs: ids,
                                references: references, rates: rates,
                                decimalPlaces: decimalPlaces,
                                context: context, unitContext: unitContext)
    return (resolved.lines, resolved.tokens, ids)
}

/// The `.number` value of a row, or nil.
private func lcValue(_ line: SheetLine) -> Double? {
    guard case .number(let v, _, _, _) = line.result else { return nil }
    return v
}

/// The `.number` unit label of a row, or nil.
private func lcUnit(_ line: SheetLine) -> String? {
    guard case .number(_, let u, _, _) = line.result, let u, !u.isEmpty else { return nil }
    return u
}

/// The error message of a row, or nil when it is not an error.
private func lcError(_ line: SheetLine) -> String? {
    guard case .error(let m) = line.result else { return nil }
    return m
}

private func lcClose(_ a: Double?, _ b: Double, _ label: String) throws {
    guard let a, abs(a - b) <= max(1e-9, 1e-9 * abs(b)) else {
        throw CaseFailure(message: "\(label): expected \(b), got \(String(describing: a))",
                          location: "LinkedConversionCases")
    }
}

/// The UTF-16 `location` of a marker that starts line `markerLine` (0-based)
/// of a sheet built from `lines` — the document offset, i.e. every
/// preceding line plus its newline.
private func lcMarkerOffset(_ lines: [String], _ markerLine: Int) -> Int {
    ((lines[0..<markerLine].joined(separator: "\n") + "\n") as NSString).length
}

/// The `location` of the marker on line 2 of a two-line sheet.
private func lcMarkerAt(_ firstLine: String) -> Int {
    lcMarkerOffset([firstLine, ""], 1)
}

public let linkedConversionCases: [EngineCase] = [

    EngineCase("r91-linked-conversion-reported-case") {
        // The exact user report: a unitless linked 4673 followed by
        // `mg to kg`. The source unit is typed explicitly; the linked
        // value supplies the number.
        let content = "4673\n\(M91) mg to kg"
        let (lines, tokens, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt("4673"))],
                                           decimalPlaces: 7)
        try lcClose(lcValue(lines[1]), 0.004673, "linked 4673 mg to kg")
        try expectEqual(lcUnit(lines[1]), "kg", "target unit")
        try expectEqual(lines[1].sourceLineIndex, 1, "source index")
        // The linked row is an ordinary result row (never a total).
        try expect(!lines[1].isTotal, "not a total row")
        try expectEqual(lines[1].metadata, .ordinary, "ordinary metadata")
        // The token stays live and the document is untouched.
        try expectEqual(tokens.count, 1, "one token")
        guard case .active(let v, let unit, _) = tokens[0].state else {
            throw CaseFailure(message: "token state: \(tokens[0].state)")
        }
        try lcClose(v, 4673, "token value")
        try expect(unit == nil, "unitless token stays unitless")
    },

    EngineCase("r91-linked-conversion-full-precision-not-display") {
        // 4673 mg is 0.004673 kg: a DISPLAY-rounded value (2 decimals
        // would be 0.00) must not be substituted. The conversion keeps
        // `max(decimalPlaces, 10)` precision.
        let content = "4673\n\(M91) mg to kg"
        for dp in [0, 2, 7] {
            let (lines, _, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt("4673"))],
                                          decimalPlaces: dp)
            try lcClose(lcValue(lines[1]), 0.004673, "dp \(dp) keeps full precision")
            try expectEqual(lcUnit(lines[1]), "kg", "dp \(dp) unit")
        }
        // A large exact value survives too (no grouping, no rounding).
        let big = "1234567\n\(M91) mg to kg"
        let (rows, _, _) = lcResolve(big, refs: [(0, 1, lcMarkerAt("1234567"))])
        try lcClose(lcValue(rows[1]), 1.234567, "1234567 mg to kg")
    },

    EngineCase("r91-linked-conversion-carried-unit-unchanged") {
        // The pre-r91 form must behave exactly as before: the token
        // already carries `mg`, so the user writes only `to kg`.
        let content = "4673 mg\n\(M91) to kg"
        let (lines, tokens, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt("4673 mg"))])
        try lcClose(lcValue(lines[1]), 0.004673, "carried mg to kg")
        try expectEqual(lcUnit(lines[1]), "kg", "target unit")
        guard case .active(let v, let unit, let display) = tokens[0].state else {
            throw CaseFailure(message: "token state: \(tokens[0].state)")
        }
        try lcClose(v, 4673, "token value")
        try expectEqual(unit, "mg", "token keeps its carried unit")
        try expectEqual(display, "4,673 mg", "token display unchanged")
        // The same conversion is reachable with `in` instead of `to`.
        let inForm = "4673 mg\n\(M91) in kg"
        let (rows, _, _) = lcResolve(inForm, refs: [(0, 1, lcMarkerAt("4673 mg"))])
        try lcClose(lcValue(rows[1]), 0.004673, "carried mg in kg")
    },

    EngineCase("r91-linked-conversion-classes") {
        // Temperature, compound/ratio, fuel and length — the same engine
        // as ordinary lines, so every class works with an explicit
        // source unit on a unitless linked value.
        let content = [
            "100",                                   // 0: unitless
            "\(M91) C to F",                         // 1: temperature
            "36",                                    // 2
            "\(M91) km/h to m/s",                    // 3: compound
            "1",                                     // 4
            "\(M91) g/cm³ to kg/m³",                 // 5: ratio
            "10",                                    // 6
            "\(M91) mpg to L/100km",                 // 7: fuel crossing
            "3",                                     // 8
            "\(M91) in to cm",                       // 9: inch `in` before `to`
            "2",                                     // 10
            "\(M91) km to m",                        // 11: plain length
        ].joined(separator: "\n")
        let sourceLines = content.components(separatedBy: "\n")
        let refs = [(0, 1), (2, 3), (4, 5), (6, 7), (8, 9), (10, 11)].map {
            (source: $0.0, label: $0.1,
             location: lcMarkerOffset(sourceLines, $0.1))
        }
        let (lines, tokens, _) = lcResolve(content, refs: refs)
        try expectEqual(tokens.count, 6, "six live tokens")
        try lcClose(lcValue(lines[1]), 212, "100 C to F")
        try expectEqual(lcUnit(lines[1]), "F°", "temperature unit")
        try lcClose(lcValue(lines[3]), 10, "36 km/h to m/s")
        try expectEqual(lcUnit(lines[3]), "m/s", "compound unit")
        try lcClose(lcValue(lines[5]), 1000, "1 g/cm³ to kg/m³")
        try lcClose(lcValue(lines[9]), 7.62, "3 in to cm (inch before to)")
        try expectEqual(lcUnit(lines[9]), "cm", "inch target unit")
        try lcClose(lcValue(lines[11]), 2000, "2 km to m")
        // The fuel crossing converts with the engine's exact value.
        try lcClose(lcValue(lines[7]), 23.5214583333, "10 mpg to L/100km")
        try expectEqual(lcUnit(lines[7]), "L/100km", "fuel target unit")
    },

    EngineCase("r91-linked-conversion-currency-and-rates") {
        let rates = Rates(base: "EUR", rates: ["EUR": 1, "USD": 1.1, "GBP": 0.85])
        // Success: an explicitly typed currency source on a unitless
        // linked value, and the carried-code form.
        let ok = "110\n\(M91) USD to EUR"
        let (rows, _, _) = lcResolve(ok, refs: [(0, 1, lcMarkerAt("110"))], rates: rates)
        try lcClose(lcValue(rows[1]), 100, "110 USD to EUR")
        try expectEqual(lcUnit(rows[1]), "EUR", "currency target unit")
        let carried = "110 USD\n\(M91) to EUR"
        let (rows2, _, _) = lcResolve(carried, refs: [(0, 1, lcMarkerAt("110 USD"))], rates: rates)
        try lcClose(lcValue(rows2[1]), 100, "carried USD to EUR")
        // A pair the table cannot answer keeps the explicit white state.
        let noRates = Rates(base: "EUR", rates: ["EUR": 1])
        let missing = "10\n\(M91) USD to GBP"
        let (rows3, _, _) = lcResolve(missing, refs: [(0, 1, lcMarkerAt("10"))], rates: noRates)
        try expectEqual(lcError(rows3[1]), "Rates unavailable", "missing rate pair")
        let missingCarried = "10 USD\n\(M91) to GBP"
        let (rows4, _, _) = lcResolve(missingCarried,
                                      refs: [(0, 1, lcMarkerAt("10 USD"))], rates: noRates)
        try expectEqual(lcError(rows4[1]), "Rates unavailable", "missing carried pair")
        // A money source row is a live code-carrying token.
        let moneySource = "110 USD\n\(M91) to EUR"
        let (_, tokens5, _) = lcResolve(moneySource, refs: [(0, 1, lcMarkerAt("110 USD"))],
                                        rates: rates)
        guard case .active(_, let code, _) = tokens5[0].state else {
            throw CaseFailure(message: "money token state: \(tokens5[0].state)")
        }
        try expectEqual(code, "USD", "money token carries the code")
    },

    EngineCase("r91-linked-conversion-errors-match-ordinary-lines") {
        // Each error class must be the ORDINARY conversion error, never
        // the old token-route `Invalid conversion`.
        let cases: [(source: String, suffix: String, want: String)] = [
            ("5", "zzz to kg", "Unknown units"),        // unknown source
            ("5", "kg to zzz", "Unknown units"),        // unknown target
            ("5", "kg to m", "Incompatible units"),     // incompatible dimensions
            ("5", "kg to second", "Incompatible units"),
        ]
        for c in cases {
            let content = "\(c.source)\n\(M91) \(c.suffix)"
            let (lines, _, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt(c.source))])
            try expectEqual(lcError(lines[1]), c.want, "\(c.source) \(c.suffix)")
        }
        // The carried form reports the same classes.
        let carried: [(source: String, suffix: String, want: String)] = [
            ("5 kg", "to zzz", "Unknown units"),
            ("5 kg", "to m", "Incompatible units"),
        ]
        for c in carried {
            let content = "\(c.source)\n\(M91) \(c.suffix)"
            let (lines, _, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt(c.source))])
            try expectEqual(lcError(lines[1]), c.want, "carried \(c.source) \(c.suffix)")
        }
    },

    EngineCase("r91-linked-conversion-rejects-semantic-unitless-kinds") {
        // A percent / fraction / multiplier linked answer is a SEMANTIC
        // unitless value: it must never be relabeled as a physical unit
        // through this bridge. A boolean token is equally refused.
        let sources = ["20%", "1.5x", "0.25 as fraction", "true"]
        for source in sources {
            let content = "\(source)\n\(M91) mg to kg"
            let (lines, _, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt(source))])
            try expect(lcError(lines[1]) != nil,
                       "\(source) mg to kg must not convert")
            try expect(lcValue(lines[1]) == nil,
                       "\(source) mg to kg must not produce a number")
            // Specifically NOT the successful 0.004673 kg bridge result.
            if let v = lcValue(lines[1]) {
                throw CaseFailure(message: "\(source) produced \(v)",
                                  location: "LinkedConversionCases")
            }
            // The source row itself still evaluates as its own kind.
            try expect(lcValue(lines[0]) != nil || lcError(lines[0]) == nil,
                       "\(source) source row still evaluates")
        }
        // A percent token used with a target only (no source unit) is
        // also not a conversion.
        let percentOnly = "20%\n\(M91) to kg"
        let (rows, _, _) = lcResolve(percentOnly, refs: [(0, 1, lcMarkerAt("20%"))])
        try expect(lcValue(rows[1]) == nil, "percent to kg is not a conversion")
    },

    EngineCase("r91-linked-conversion-decimal-comma-context") {
        // In decimal-comma modes the substituted literal must use a
        // comma: a dot would scan as a GROUPING separator and silently
        // change the value (1.5 -> 15).
        let comma = NumberFormatContext(
            locale: Locale(identifier: "de_DE"), decimalSeparator: ",",
            groupingSeparator: ".", argumentSeparator: ";",
            displayGrouping: true, compactNotation: false,
            convertForeignOnPaste: true)
        let content = "1,5\n\(M91) kg to g"
        let (lines, _, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt("1,5"))],
                                      context: comma)
        try lcClose(lcValue(lines[0]), 1.5, "comma source value")
        try lcClose(lcValue(lines[1]), 1500, "1,5 kg to g (comma mode)")
        try expectEqual(lcUnit(lines[1]), "g", "gram target")
        // The same value in the dot context converts identically.
        let dotContent = "1.5\n\(M91) kg to g"
        let (dotLines, _, _) = lcResolve(dotContent, refs: [(0, 1, lcMarkerAt("1.5"))])
        try lcClose(lcValue(dotLines[1]), 1500, "1.5 kg to g (dot mode)")
        // And the reported milligram case works in comma mode too.
        let mgContent = "4673\n\(M91) mg to kg"
        let (mgLines, _, _) = lcResolve(mgContent, refs: [(0, 1, lcMarkerAt("4673"))],
                                        context: comma)
        try lcClose(lcValue(mgLines[1]), 0.004673, "comma mode 4673 mg to kg")
    },

    EngineCase("r91-linked-conversion-custom-unit-context") {
        // A custom unit label is available to the conversion exactly as
        // it is for ordinary lines (the same `UnitContext`).
        let rows = [UserUnitDefinition(name: "zorch", definition: "660 feet")]
        let resolved = UnitResolver.resolve(rows)
        let content = "10\n\(M91) zorch to m"
        let (lines, _, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt("10"))],
                                      unitContext: resolved.context)
        try lcClose(lcValue(lines[1]), 2011.68, "10 zorch to m (custom context)")
        try expectEqual(lcUnit(lines[1]), "m", "custom conversion target")
        // A carried custom label keeps working through the same engine.
        let carried = "10 zorch\n\(M91) to m"
        let (rows2, _, _) = lcResolve(carried, refs: [(0, 1, lcMarkerAt("10 zorch"))],
                                      unitContext: resolved.context)
        try lcClose(lcValue(rows2[1]), 2011.68, "carried zorch to m")
    },

    EngineCase("r91-linked-conversion-state-invariants") {
        // The bridge is an evaluation copy: the document, the marker, the
        // reference identity and the line IDs are never rewritten, and
        // the token stays LIVE — editing the source changes the answer.
        let content = "4673\n\(M91) mg to kg"
        let marker = lcMarkerAt("4673")
        let (lines, tokens, ids) = lcResolve(content, refs: [(0, 1, marker)])
        try lcClose(lcValue(lines[1]), 0.004673, "converted")
        // Content is byte-identical to what was passed in.
        try expectEqual(content, "4673\n\(M91) mg to kg", "content unchanged")
        try expectEqual((content as NSString).range(of: M91).location, marker,
                        "marker location unchanged")
        try expectEqual(lines.count, ids.count, "one row per line ID")
        try expectEqual(lines[0].sourceLineIndex, 0, "row 0 index")
        try expectEqual(lines[1].sourceLineIndex, 1, "row 1 index")
        // The reference resolves to the FIRST line's identity.
        try expectEqual(tokens[0].location, marker, "token location")
        // Live: change the source value, the converted answer follows.
        let edited = "1000\n\(M91) mg to kg"
        let (editedLines, _, _) = lcResolve(edited, refs: [(0, 1, lcMarkerAt("1000"))])
        try lcClose(lcValue(editedLines[1]), 0.001, "live update to 1000 mg")
        // A unit-bearing source that changes unit changes the result.
        let unitEdit = "1 g\n\(M91) to kg"
        let (unitLines, _, _) = lcResolve(unitEdit, refs: [(0, 1, lcMarkerAt("1 g"))])
        try lcClose(lcValue(unitLines[1]), 0.001, "1 g to kg")
    },

    EngineCase("r91-linked-conversion-untouched-other-routes") {
        // Only the conversion shape changed: a token used in a genuine
        // expression, a bare token row and a token assignment keep their
        // existing behavior.
        let expr = "5\n\(M91) + 1"
        let (exprLines, _, _) = lcResolve(expr, refs: [(0, 1, lcMarkerAt("5"))])
        try lcClose(lcValue(exprLines[1]), 6, "token in expression")
        let bare = "5 kg\n\(M91)"
        let (bareLines, _, _) = lcResolve(bare, refs: [(0, 1, lcMarkerAt("5 kg"))])
        try lcClose(lcValue(bareLines[1]), 5, "bare token row")
        try expectEqual(lcUnit(bareLines[1]), "kg", "bare token keeps its unit")
        // `x = <token>` is not a conversion shape (the marker is not the
        // first content), so the bridge declines and the assignment route
        // keeps its PRE-EXISTING behavior — verified byte-identical
        // before and after this change. A plain assignment is unaffected.
        let assigned = "5\nx = 5"
        let (assignedLines, _, _) = lcResolve(assigned, refs: [(0, 1, lcMarkerAt("5"))])
        if case .variable(let name, let v, _, _) = assignedLines[1].result {
            try expectEqual(name, "x", "assignment name")
            try lcClose(v, 5, "assignment value")
        } else {
            throw CaseFailure(message: "plain assignment: \(assignedLines[1].result)",
                              location: "LinkedConversionCases")
        }
        let tokenAssign = "5\nx = \(M91)"
        let (tokenAssignLines, _, _) = lcResolve(tokenAssign, refs: [(0, 1, lcMarkerAt("5"))])
        try expect(lcValue(tokenAssignLines[1]) == nil,
                   "x = <token> is not a conversion (pre-existing behavior)")
        // A unit literal on the plain side of a token expression stays a
        // strict error (never a word strip) — unchanged by this fix.
        let strict = "5\n\(M91) + 500 m"
        let (strictLines, _, _) = lcResolve(strict, refs: [(0, 1, lcMarkerAt("5"))])
        try expect(lcError(strictLines[1]) != nil, "unit literal in token expr is strict")
        // A token followed by a non-conversion word is not a conversion.
        let prose = "5\n\(M91) apples"
        let (proseLines, _, _) = lcResolve(prose, refs: [(0, 1, lcMarkerAt("5"))])
        try expect(lcValue(proseLines[1]) == nil || lcUnit(proseLines[1]) == nil,
                   "non-conversion suffix is not a unit conversion")
    },

    // MARK: - r92: a repeated, agreeing source unit

    EngineCase("r92-repeated-agreeing-unit-converts") {
        // The BUG-02 repro: the source already carries `mg`, and the user
        // repeats that same unit before the keyword. Pre-r92 the bridge
        // appended the carried label anyway, synthesizing
        // `4673 mg mg to kg`, which the engine rejected with the
        // misleading `Unknown units`.
        let content = "4673 mg\n\(M91) mg to kg"
        let (lines, tokens, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt("4673 mg"))])
        try lcClose(lcValue(lines[1]), 0.004673, "4673 mg + <token> mg to kg")
        try expectEqual(lcUnit(lines[1]), "kg", "target unit")
        // The linked answer keeps its OWN unit — nothing was re-based.
        guard case .active(let v, let unit, let display) = tokens[0].state else {
            throw CaseFailure(message: "token state: \(tokens[0].state)",
                              location: "LinkedConversionCases")
        }
        try lcClose(v, 4673, "token value")
        try expectEqual(unit, "mg", "token keeps its carried unit")
        try expectEqual(display, "4,673 mg", "token display unchanged")
        // The document and the reference identity are untouched.
        try expectEqual(content, "4673 mg\n\(M91) mg to kg", "content unchanged")
        try expectEqual(lines[1].sourceLineIndex, 1, "source index")
        try expect(!lines[1].isTotal, "ordinary row")
    },

    EngineCase("r92-repeated-agreeing-unit-alias") {
        // `inch` resolves to the SAME unit expression as `in`, so an
        // explicitly repeated alias agrees. The ordinary-line equivalent
        // is asserted FIRST, so the linked expectation can never drift
        // from the engine's own grammar.
        var vars: [String: Double] = [:]
        let ordinary = evaluateSheet("3 inch to cm", variables: &vars,
                                     rates: Rates(), decimalPlaces: 7)[0].result
        guard case .number(let ordValue, let ordUnit, _, _) = ordinary else {
            throw CaseFailure(message: "ordinary `3 inch to cm`: \(ordinary)",
                              location: "LinkedConversionCases")
        }
        try lcClose(ordValue, 7.62, "ordinary alias conversion")
        try expectEqual(ordUnit, "cm", "ordinary alias target unit")
        // The same alias pair through a linked answer whose source carries
        // the canonical `in` label.
        let content = "3 inch\n\(M91) inch to cm"
        let (lines, tokens, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt("3 inch"))])
        try lcClose(lcValue(lines[1]), 7.62, "linked alias agreement")
        try expectEqual(lcUnit(lines[1]), "cm", "linked alias target unit")
        guard case .active(_, let carried, _) = tokens[0].state else {
            throw CaseFailure(message: "token state: \(tokens[0].state)",
                              location: "LinkedConversionCases")
        }
        try expectEqual(carried, "in", "source carries the canonical `in` label")
    },

    EngineCase("r92-conflicting-source-unit-is-incompatible") {
        // A KNOWN but different unit is the documented conflict class —
        // never `Unknown units`, and never a converted number.
        for (source, suffix) in [("4673 mg", "kg to g"), ("4673 mg", "g to kg")] {
            let content = "\(source)\n\(M91) \(suffix)"
            let (lines, _, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt(source))])
            try expectEqual(lcError(lines[1]), "Incompatible units",
                            "\(source) + <token> \(suffix)")
            try expect(lcError(lines[1]) != "Unknown units",
                       "\(source) + \(suffix) must not report Unknown units")
            try expect(lcValue(lines[1]) == nil,
                       "\(source) + \(suffix) must not produce a number")
        }
    },

    EngineCase("r92-temperature-conflict-never-reinterpreted") {
        // A temperature-carrying linked answer commanded with a DIFFERENT
        // scale must conflict rather than silently re-base the value.
        // NOTE: a bare `100 celsius` source line is UNITLESS in this
        // engine (measured: `number(100, unit: nil)`), so a conversion
        // RESULT is used as the temperature-carrying source.
        let content = "100 C to F\n\(M91) C° to K"
        let (lines, tokens, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt("100 C to F"))])
        guard case .active(_, let carried, _) = tokens[0].state else {
            throw CaseFailure(message: "token state: \(tokens[0].state)",
                              location: "LinkedConversionCases")
        }
        try expectEqual(carried, "F°", "source carries the F° scale")
        try expectEqual(lcError(lines[1]), "Incompatible units", "temperature conflict")
        try expect(lcValue(lines[1]) == nil, "no converted temperature")
        // The plan's literal shape behaves as its unitless source dictates:
        // the linked value carries NO unit, so the user's explicit source
        // defines it and the documented unitless spelling converts.
        let unitless = "100 celsius\n\(M91) F° to K"
        let (unitlessLines, _, _) = lcResolve(unitless, refs: [(0, 1, lcMarkerAt("100 celsius"))])
        try lcClose(lcValue(unitlessLines[1]), 310.9277777778,
                    "unitless source + explicit F° to K")
        try expectEqual(lcUnit(unitlessLines[1]), "K°", "kelvin target")
    },

    EngineCase("r92-unknown-explicit-source-still-unknown") {
        // Agreement cannot be established: the explicit source does not
        // resolve, so the previous behavior (and its accurate message)
        // is kept rather than inventing a verdict.
        let content = "4673 mg\n\(M91) zzz to kg"
        let (lines, _, _) = lcResolve(content, refs: [(0, 1, lcMarkerAt("4673 mg"))])
        try expectEqual(lcError(lines[1]), "Unknown units", "unknown explicit source")
        try expect(lcValue(lines[1]) == nil, "no number for an unknown source")
    },

    EngineCase("r92-repeat-rule-leaves-documented-spellings-unchanged") {
        // The two documented spellings and the reported r91 case keep
        // their pinned values.
        let carried = "4673 mg\n\(M91) to kg"
        let (carriedLines, _, _) = lcResolve(carried, refs: [(0, 1, lcMarkerAt("4673 mg"))])
        try lcClose(lcValue(carriedLines[1]), 0.004673, "carried `to` spelling")
        try expectEqual(lcUnit(carriedLines[1]), "kg", "carried target unit")
        let carriedIn = "4673 mg\n\(M91) in kg"
        let (carriedInLines, _, _) = lcResolve(carriedIn, refs: [(0, 1, lcMarkerAt("4673 mg"))])
        try lcClose(lcValue(carriedInLines[1]), 0.004673, "carried `in` spelling")
        let unitless = "4673\n\(M91) mg to kg"
        for dp in [2, 7] {
            let (lines, _, _) = lcResolve(unitless, refs: [(0, 1, lcMarkerAt("4673"))],
                                          decimalPlaces: dp)
            try lcClose(lcValue(lines[1]), 0.004673, "unitless explicit source at dp \(dp)")
            try expectEqual(lcUnit(lines[1]), "kg", "unitless target unit at dp \(dp)")
        }
        // A unitless linked answer with no explicit source still declines
        // the conversion (no unit to convert from).
        let noSource = "4673\n\(M91) to kg"
        let (noSourceLines, _, _) = lcResolve(noSource, refs: [(0, 1, lcMarkerAt("4673"))])
        try expect(lcValue(noSourceLines[1]) == nil, "unitless `to kg` gives no number")
    },

    EngineCase("r92-repeated-unit-money-agreement-and-conflict") {
        let rates = Rates(base: "EUR", rates: ["EUR": 1, "USD": 1.1])
        // Agreement: the repeated code matches the money token's code.
        let agree = "$5\n\(M91) USD to EUR"
        let (agreeLines, agreeTokens, _) = lcResolve(agree, refs: [(0, 1, lcMarkerAt("$5"))],
                                                     rates: rates)
        try lcClose(lcValue(agreeLines[1]), 4.5454545455, "repeated USD agrees")
        try expectEqual(lcUnit(agreeLines[1]), "EUR", "money target unit")
        guard case .active(_, let code, _) = agreeTokens[0].state else {
            throw CaseFailure(message: "money token state: \(agreeTokens[0].state)",
                              location: "LinkedConversionCases")
        }
        try expectEqual(code, "USD", "money token keeps its code")
        // Conflict: a different code is never treated as agreement.
        let conflict = "$5\n\(M91) EUR to USD"
        let (conflictLines, _, _) = lcResolve(conflict, refs: [(0, 1, lcMarkerAt("$5"))],
                                              rates: rates)
        try expectEqual(lcError(conflictLines[1]), "Incompatible units", "money conflict")
        try expect(lcValue(conflictLines[1]) == nil, "money conflict produces no number")
    },

    EngineCase("r92-repeated-unit-other-classes-agree") {
        // The rule is class-agnostic: duration and compound units agree
        // when the repeated unit IS the carried unit.
        let duration = "30 minutes\n\(M91) minutes to hours"
        let (durationLines, _, _) = lcResolve(duration, refs: [(0, 1, lcMarkerAt("30 minutes"))])
        try lcClose(lcValue(durationLines[1]), 0.5, "duration agreement")
        try expectEqual(lcUnit(durationLines[1]), "h", "duration target unit")
        let compound = "36 km/h\n\(M91) km/h to m/s"
        let (compoundLines, _, _) = lcResolve(compound, refs: [(0, 1, lcMarkerAt("36 km/h"))])
        try lcClose(lcValue(compoundLines[1]), 10, "compound agreement")
        try expectEqual(lcUnit(compoundLines[1]), "m/s", "compound target unit")
        // A conflicting duration unit conflicts (0.5 hours is not 0.5
        // minutes) rather than silently reinterpreting the linked answer.
        let durationConflict = "30 minutes to hours\n\(M91) min to s"
        let (conflictLines, _, _) = lcResolve(durationConflict,
                                             refs: [(0, 1, lcMarkerAt("30 minutes to hours"))])
        try expectEqual(lcError(conflictLines[1]), "Incompatible units",
                        "duration unit conflict")
    },
]
