import Foundation
import NumlexCore

// MARK: - r83: advanced percentages
//
// One semantic numeric model (plain / percent / fraction / multiplier)
// rides the results, the typed engine, the environment and the answer
// tokens; the phrase grammar (of / on / off, reverse bases, named
// percentages, conversions, ratios) is strict and keyword-aware:
//
// - Percent-ish magnitudes: percent literals (`15%`), multiplier
//   literals (`1.5x`) and fractions (`2/3`, `2/10 as fraction`) join
//   the `of` / `on` / `off` slots; plain numbers do not (`500 of 200`
//   stays the legacy bounded-infix error). A 100% change doubles or
//   halves.
// - Semantic kinds survive the pipeline: `10% + 20%` is 30% (raw-ratio
//   percent mode), `200 + 10%` stays the legacy contextual 220,
//   assignments and environment entries keep their kind, and the
//   answer renders/copies the locale-aware `40%` / `1/5` / `1.5x`
//   string (per-answer rounding applies to the numeric component of a
//   percent/multiplier; fractions round nothing).
// - The TERMINAL spaced `%` converts the whole preceding division
//   (`20/200 %` = 10%); `20/200%` keeps the legacy postfix reading
//   (10) and `50 %` stays the legacy `50%` (0.5). The canonicalizer
//   preserves that semantic space and nothing else.
// - Money participates as an operand where the form allows; dividing
//   mixed currencies errors instead of converting; booleans, units and
//   dates never enter the phrase grammar.
// - Tokens: percent/fraction/multiplier answers mint kinded tokens
//   (`20%`, `1/5`, `1.5x`) that behave contextually in expressions
//   (`200 + TOKEN` = 224 when TOKEN = 20%) and in the phrase forms.

private let M83 = "\u{FFFC}"

/// One evaluated sheet through the same API the app uses.
private func r83Lines(_ content: String) -> [SheetLine] {
    var v: [String: Double] = [:]
    return evaluateSheet(content, variables: &v, rates: Rates(), decimalPlaces: 7)
}

private func r83Fail(_ what: String, _ got: Any?) -> CaseFailure {
    CaseFailure(message: "\(what): got \(String(describing: got))", location: "R83Cases")
}

/// A number answer with the expected value AND semantic kind.
private func r83Close(_ a: Double, _ b: Double) -> Bool {
    abs(a - b) <= max(1e-9, 1e-9 * max(abs(a), abs(b)))
}

private func r83IsKinded(_ r: LineResult, _ v: Double, _ kind: NumericKind,
                         _ what: String) throws {
    guard case .number(let n, let u, let k, _) = r, r83Close(n, v), u == nil else {
        throw r83Fail("\(what): expected \(v) \(kind)", r)
    }
    try expectEqual(k, kind, "\(what) kind")
}

/// A number answer of ANY kind (a phrase value line can be plain).
private func r83IsNumber(_ r: LineResult, _ v: Double, _ what: String) throws {
    guard case .number(let n, let u, _, _) = r, r83Close(n, v), u == nil else {
        throw r83Fail("\(what): expected \(v)", r)
    }
}

/// A money answer with the expected value and currency code.
private func r83IsMoney(_ r: LineResult, _ v: Double, _ code: String, _ what: String) throws {
    guard case .money(let n, let c) = r, r83Close(n, v), c == code else {
        throw r83Fail("\(what): expected \(v) \(code)", r)
    }
}

private func r83IsFraction(_ r: LineResult, _ num: Int64, _ den: Int64,
                           _ what: String) throws {
    guard case .number(_, nil, let k, let f) = r, k == .fraction,
          let f, f.numerator == num, f.denominator == den else {
        throw r83Fail("\(what): expected \(num)/\(den) fraction", r)
    }
}

public let r83Cases: [EngineCase] = [
    // MARK: of / on / off

    EngineCase("r83-of-percent-and-fraction-magnitudes") {
        let lines = r83Lines("15% of 490\n2/3 of 600\n1.5x of 20")
        try r83IsNumber(lines[0].result, 73.5, "15% of 490")
        try r83IsNumber(lines[1].result, 400, "2/3 of 600")
        try r83IsNumber(lines[2].result, 30, "1.5x of 20")
    },

    EngineCase("r83-on-off-change-magnitudes") {
        let lines = r83Lines("15% on 200\n30% off 200\n100% on 10\n100% off 20\n1.5x on 20\n1.5x off 20")
        try r83IsNumber(lines[0].result, 230, "15% on 200")
        try r83IsNumber(lines[1].result, 140, "30% off 200")
        try r83IsNumber(lines[2].result, 20, "100% on 10 doubles")
        try r83IsNumber(lines[3].result, 0, "100% off 20 halves to zero")
        try r83IsNumber(lines[4].result, 50, "1.5x on 20")
        try r83IsNumber(lines[5].result, -10, "1.5x off 20")
    },

    EngineCase("r83-of-plain-left-stays-legacy-error") {
        let lines = r83Lines("500 of 200\n2 of 3")
        guard case .error = lines[0].result else {
            throw r83Fail("500 of 200 must fail (plain is not a magnitude)", lines[0].result)
        }
        guard case .error = lines[1].result else {
            throw r83Fail("2 of 3 must fail (a bare literal is not a fraction)", lines[1].result)
        }
    },

    EngineCase("r83-of-on-off-money-operands") {
        let lines = r83Lines("20% of $500\n15% off $100\n15% on $100")
        try r83IsMoney(lines[0].result, 100, "USD", "20% of $500")
        try r83IsMoney(lines[1].result, 85, "USD", "15% off $100")
        try r83IsMoney(lines[2].result, 115, "USD", "15% on $100")
    },

    // MARK: reverse bases

    EngineCase("r83-reverse-base") {
        let lines = r83Lines("100 is 50% of what\n100 is 20% off what\n100 is 25% on what")
        try r83IsNumber(lines[0].result, 200, "100 is 50% of what")
        try r83IsNumber(lines[1].result, 125, "100 is 20% off what")
        try r83IsNumber(lines[2].result, 80, "100 is 25% on what")
    },

    EngineCase("r83-reverse-base-money") {
        let lines = r83Lines("$100 is 50% of what")
        try r83IsMoney(lines[0].result, 200, "USD", "$100 is 50% of what")
    },

    // MARK: named percentages

    EngineCase("r83-what-percent-phrases") {
        let lines = r83Lines("50 is what % of 200\n140 is what % off 200\n230 is what % on 200")
        try r83IsKinded(lines[0].result, 0.25, .percent, "50 is what % of 200")
        try r83IsKinded(lines[1].result, 0.30, .percent, "140 is what % off 200")
        try r83IsKinded(lines[2].result, 0.15, .percent, "230 is what % on 200")
    },

    EngineCase("r83-as-a-percent-of") {
        let lines = r83Lines("100 as a % of 800\n100 as % of 800")
        try r83IsKinded(lines[0].result, 0.125, .percent, "100 as a % of 800")
        try r83IsKinded(lines[1].result, 0.125, .percent, "100 as % of 800")
    },

    EngineCase("r83-change-phrases") {
        let lines = r83Lines("100 to 130 is what %\n100 to 130 as %\n130 to 100 as %")
        try r83IsKinded(lines[0].result, 0.30, .percent, "100 to 130 is what %")
        try r83IsKinded(lines[1].result, 0.30, .percent, "100 to 130 as %")
        try expectClose(lines[2].result.fractionValue.map { _ in 0 } ?? 0, 0, 1e-12, "")
        // (100 - 130) / 130 = -23.08%: the change is relative to the original value.
        if case .number(let v, _, let k, _) = lines[2].result, k == .percent {
            try expectClose(v, -30.0 / 130.0, 1e-12, "130 to 100 as %")
        } else {
            throw r83Fail("130 to 100 as % must be a percent", lines[2].result)
        }
    },

    EngineCase("r83-mixed-currencies-error") {
        let lines = r83Lines("$50 is what % of 200\n$50 is what % of €200")
        guard case .error = lines[0].result else {
            throw r83Fail("money vs plain division must error", lines[0].result)
        }
        guard case .error = lines[1].result else {
            throw r83Fail("mixed currencies must error", lines[1].result)
        }
    },

    // MARK: conversions and ratios

    EngineCase("r83-as-percent-conversion") {
        let lines = r83Lines("0.25 as %\n0.25 as a %\n0.25 as percent\n0.25 as percentage")
        for (i, l) in lines.enumerated() {
            try r83IsKinded(l.result, 0.25, .percent, "0.25 conversion form \(i)")
        }
    },

    EngineCase("r83-as-fraction") {
        let lines = r83Lines("50% as fraction\n2/10 as fraction\n0.25 as a fraction")
        try r83IsFraction(lines[0].result, 1, 2, "50% as fraction")
        try r83IsFraction(lines[1].result, 1, 5, "2/10 as fraction")
        try r83IsFraction(lines[2].result, 1, 4, "0.25 as a fraction")
        try expectClose(lines[1].result.fractionValue?.value ?? 0, 0.2, 1e-12, "2/10 value")
    },

    EngineCase("r83-conversion-rejects-wrong-kind") {
        // A money operand is rejected by every conversion form
        // (currency is never coerced to a ratio).
        let lines = r83Lines("$0.25 as %\n€0.25 as fraction")
        guard case .error = lines[0].result else {
            throw r83Fail("$0.25 as % must fail (currency)", lines[0].result)
        }
        guard case .error = lines[1].result else {
            throw r83Fail("€0.25 as fraction must fail (currency)", lines[1].result)
        }
    },

    EngineCase("r83-multiplier-aliases") {
        let lines = r83Lines("20 as x of 5\n20 as multiple of 5\n20 as multiplier of 5\n10 to 15 as x\n10 to 15 as multiplier")
        try r83IsKinded(lines[0].result, 4, .multiplier, "20 as x of 5")
        try r83IsKinded(lines[1].result, 4, .multiplier, "20 as multiple of 5")
        try r83IsKinded(lines[2].result, 4, .multiplier, "20 as multiplier of 5")
        try r83IsKinded(lines[3].result, 1.5, .multiplier, "10 to 15 as x")
        try r83IsKinded(lines[4].result, 1.5, .multiplier, "10 to 15 as multiplier")
    },

    EngineCase("r83-ratio-phrases") {
        let lines = r83Lines("20% is 500, what is 750\nif 500 is 20%, what is 750")
        try r83IsKinded(lines[0].result, 0.30, .percent, "20% is 500, what is 750")
        try r83IsKinded(lines[1].result, 0.30, .percent, "if 500 is 20%, what is 750")
    },

    // MARK: terminal spaced-% conversion

    EngineCase("r83-terminal-spaced-percent") {
        let lines = r83Lines("20/200 %\n2/3 %")
        try r83IsKinded(lines[0].result, 0.1, .percent, "20/200 %")
        try r83IsKinded(lines[1].result, 2.0 / 3.0, .percent, "2/3 %")
    },

    EngineCase("r83-postfix-percent-untouched") {
        // `20/200%` keeps the LEGACY postfix reading (percent binds to
        // the last number: 20 ÷ (200/100) = 10, plain), and `50 %`
        // stays the legacy pure percent 0.5.
        let lines = r83Lines("20/200%\n50 %")
        try r83IsKinded(lines[0].result, 10, .plain, "20/200% postfix stays 10")
        try r83IsKinded(lines[1].result, 0.5, .percent, "50 % stays 50%")
    },

    // MARK: semantic kinds in expressions

    EngineCase("r83-percent-mode-additive") {
        let lines = r83Lines("10% + 20%\n30% + 0.4\n100% + 2 + 30%")
        try r83IsKinded(lines[0].result, 0.30, .percent, "10% + 20% = 30%")
        try r83IsKinded(lines[1].result, 0.70, .percent, "30% + 0.4 = 70%")
        try r83IsKinded(lines[2].result, 3.30, .percent, "100% + 2 + 30% = 330%")
    },

    EngineCase("r83-contextual-legacy-preserved") {
        let lines = r83Lines("200 + 10%\n100 + 10%\n200 + 10% - 5%")
        try r83IsKinded(lines[0].result, 220, .plain, "200 + 10% = 220")
        try r83IsKinded(lines[1].result, 110, .plain, "100 + 10% = 110")
        try r83IsKinded(lines[2].result, 209, .plain, "200 + 10% - 5% = 209 (compounding)")
    },

    EngineCase("r83-multiplier-in-expressions") {
        let lines = r83Lines("1.5x\n200 * 1.5x")
        try r83IsKinded(lines[0].result, 1.5, .multiplier, "1.5x literal")
        try r83IsKinded(lines[1].result, 300, .plain, "200 * 1.5x = 300")
    },

    EngineCase("r83-kind-propagates-through-variables") {
        let lines = r83Lines("x = 10% + 20%\n200 + x\nx + 5%\n200 * x")
        guard case .variable(_, let xv, let xk, _) = lines[0].result else {
            throw r83Fail("x = 30% must assign a kinded scalar", lines[0].result)
        }
        try expectEqual(xv, 0.3, "x value")
        try expectEqual(xk, NumericKind.percent, "x kind")
        try r83IsKinded(lines[1].result, 260, .plain, "200 + x contextual (x = 30%)")
        try r83IsKinded(lines[2].result, 0.35, .percent, "x + 5% = 35%")
        try r83IsKinded(lines[3].result, 60, .plain, "200 * x = 60")
    },

    EngineCase("r83-assignment-phrase-right-hand-sides") {
        // (p/q instead of x: an active variable named `x` would shadow
        // the multiplier suffix, and `1.5x` is then 1.5 times x.)
        let lines = r83Lines("p = 20% of 500\ny = 20/200 %\nz = 1.5x\n200 + y")
        guard case .variable(_, let xv, let xk, _) = lines[0].result else {
            throw r83Fail("p = 20% of 500", lines[0].result)
        }
        try expectEqual(xv, 100, "p value")
        try expectEqual(xk, NumericKind.plain, "p kind")
        guard case .variable(_, let yv, let yk, _) = lines[1].result else {
            throw r83Fail("y = 20/200 %", lines[1].result)
        }
        try expectEqual(yv, 0.1, "y value")
        try expectEqual(yk, NumericKind.percent, "y kind (spaced conversion)")
        guard case .variable(_, let zv, let zk, _) = lines[2].result else {
            throw r83Fail("z = 1.5x", lines[2].result)
        }
        try expectEqual(zv, 1.5, "z value")
        try expectEqual(zk, NumericKind.multiplier, "z kind")
        try r83IsKinded(lines[3].result, 220, .plain, "200 + y (y = 10%)")
    },

    // MARK: display / copy / menu

    EngineCase("r83-kindledisplay-strings") {
        let lines = r83Lines("10% + 20%\n2/10 as fraction\n10 to 15 as x\n0.25 as %")
        try expectEqual(AnswerDisplay.text(for: lines[0].result, decimalPlaces: 2),
                        "30%", "percent copy")
        try expectEqual(AnswerDisplay.text(for: lines[1].result, decimalPlaces: 2),
                        "1/5", "fraction copy is the rational itself")
        try expectEqual(AnswerDisplay.text(for: lines[2].result, decimalPlaces: 2),
                        "1.5x", "multiplier copy")
        try expectEqual(AnswerDisplay.text(for: lines[3].result, decimalPlaces: 2),
                        "25%", "conversion copy")
        // Per-answer rounding applies to the percent component.
        try expectEqual(AnswerDisplay.text(for: lines[0].result, decimalPlaces: 0),
                        "30%", "percent rounds its component")
        let oneThird = r83Lines("1/3 as %")
        try expectEqual(AnswerDisplay.text(for: oneThird[0].result, decimalPlaces: 1),
                        "33.3%", "one third of a percent at 1dp")
        // Fractions never take a rounding override.
        if AnswerDisplay.menu(for: lines[1].result)?.showsRounding != false {
            throw r83Fail("fraction menu must offer no rounding", nil)
        }
        if AnswerDisplay.menu(for: lines[0].result)?.showsRounding != true {
            throw r83Fail("percent menu must offer rounding", nil)
        }
    },

    // MARK: tokens

    EngineCase("r83-token-percent-contextual") {
        let u0 = UUID(), u1 = UUID()
        let content = "10% + 10%\n200 + \(M83)"
        let (lines, tokens) = resolveSheet(
            content: content, lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 16)],
            rates: Rates(), decimalPlaces: 7)
        guard case .activeKinded(_, _, let kind, _, let display) = tokens[0].state else {
            throw r83Fail("percent token state", tokens[0].state)
        }
        try expectEqual(kind, NumericKind.percent, "token kind")
        try expectEqual(display, "20%", "token display")
        try r83IsKinded(lines[1].result, 240, .plain, "200 + TOKEN is contextual (20% = +40)")
    },

    EngineCase("r83-token-percent-mode") {
        let u0 = UUID(), u1 = UUID()
        let content = "10% + 10%\n\(M83) + \(M83)"
        let (lines, _) = resolveSheet(
            content: content, lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10),
                        AnswerReference(sourceLineID: u0, labelLine: 2, location: 14)],
            rates: Rates(), decimalPlaces: 7)
        try r83IsKinded(lines[1].result, 0.40, .percent, "TOKEN + TOKEN = 40%")
    },

    EngineCase("r83-token-phrase-operands") {
        let u0 = UUID(), u1 = UUID()
        let content = "10% + 10%\n\(M83) of 200"
        let (lines, _) = resolveSheet(
            content: content, lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10)],
            rates: Rates(), decimalPlaces: 7)
        try r83IsNumber(lines[1].result, 40, "TOKEN of 200 (TOKEN = 20%)")
    },

    EngineCase("r83-token-fraction-and-multiplier") {
        let u0 = UUID(), u1 = UUID(), u2 = UUID(), u3 = UUID()
        let content = "2/10 as fraction\n10 to 15 as x\n\(M83) of 200\n\(M83) of 20"
        let (lines, tokens) = resolveSheet(
            content: content, lineIDs: [u0, u1, u2, u3],
            references: [AnswerReference(sourceLineID: u0, labelLine: 3, location: 31),
                        AnswerReference(sourceLineID: u1, labelLine: 4, location: 40)],
            rates: Rates(), decimalPlaces: 7)
        guard case .activeKinded(_, _, .fraction, let f, let d) = tokens[0].state,
              let f, f.numerator == 1, f.denominator == 5 else {
            throw r83Fail("fraction token state", tokens[0].state)
        }
        try expectEqual(d, "1/5", "fraction display")
        guard case .activeKinded(_, _, .multiplier, _, let md) = tokens[1].state else {
            throw r83Fail("multiplier token state", tokens[1].state)
        }
        try expectEqual(md, "1.5x", "multiplier display")
        try r83IsNumber(lines[2].result, 40, "fraction token: 1/5 of 200")
        try r83IsNumber(lines[3].result, 30, "multiplier token: 1.5x of 20")
    },

    // MARK: formatting

    EngineCase("r83-spaced-operator-operands") {
        // The canonicalizer spaces binary operators (`2 / 10`); the
        // phrase grammar must read the spaced division as ONE operand.
        let lines = r83Lines("2 / 10 as fraction\n1 / 5 of 600\n1.5x on 20")
        try expectEqual(AnswerDisplay.text(for: lines[0].result, decimalPlaces: 7),
                        "1/5", "spaced division as fraction")
        try r83IsNumber(lines[1].result, 120, "1 / 5 of 600")
        try r83IsNumber(lines[2].result, 50, "1.5x on 20")
    },

    EngineCase("r83-canonical-percent-space") {
        // The canonicalizer spaces binary operators (`20 / 200`); the
        // semantic space of the terminal conversion survives, while
        // every other space before % keeps the legacy collapse and the
        // postfix reading stays glued.
        try expectEqual(NotebookFormatting.canonicalMathText("20/200 %"),
                        "20 / 200 %", "terminal spaced % preserved")
        try expectEqual(NotebookFormatting.canonicalMathText("20 / 200 %"),
                        "20 / 200 %", "normalized, space preserved")
        try expectEqual(NotebookFormatting.canonicalMathText("20/200%"),
                        "20 / 200%", "postfix % stays glued")
        try expectEqual(NotebookFormatting.canonicalMathText("50 %"),
                        "50%", "bare literal keeps the legacy collapse")
        // Idempotent both ways.
        let once = NotebookFormatting.canonicalMathText("20/200 %")
        try expectEqual(NotebookFormatting.canonicalMathText(once), once, "idempotent")
    },

    EngineCase("r83-canonical-x-suffix-glued") {
        try expectEqual(NotebookFormatting.canonicalMathText("1.5x"), "1.5x", "x suffix glued")
        try expectEqual(NotebookFormatting.canonicalMathText("1.5 x"), "1.5 x",
                        "spaced x stays a variable, not a suffix")
    },

    // MARK: syntax roles

    EngineCase("r83-syntax-phrase-roles") {
        // Operands take the number role; the live phrase keywords take
        // the specifier role.
        let s = SyntaxClassifier.spans(for: "15% of 490", rates: Rates(), decimalPlaces: 7)[0]
        try expect(s.contains { $0.role == .specifier }, "of takes the specifier role")
        try expect(s.contains { $0.role == .number }, "operands take the number role")

        let s2 = SyntaxClassifier.spans(for: "100 is 50% of what", rates: Rates(), decimalPlaces: 7)[0]
        let spec = s2.filter { $0.role == .specifier }.map { $0.range }
        // `is` (3), `of` (2), `what` (4) — the live phrase keywords.
        try expectEqual(spec,
                        [NSRange(location: 4, length: 2),
                         NSRange(location: 11, length: 2),
                         NSRange(location: 14, length: 4)],
                        "is/of/what take the specifier role")
        let nums = s2.filter { $0.role == .number }.map { $0.range }
        // Literal operands (the `%` glyph itself stays base, like the
        // boolean palette leaves its operators).
        try expectEqual(nums,
                        [NSRange(location: 0, length: 3),
                         NSRange(location: 7, length: 2)],
                        "operands keep the number role")
    },

    EngineCase("r83-syntax-keyword-shadowing") {
        // An active variable named `of` kills the of-form: the line
        // evaluates through the expression route and `of` keeps its
        // VARIABLE role, not the specifier one.
        let doc = "of = 5\n10% of 500"
        let lines = r83Lines(doc)
        // The `of` INFIX operator outranks the variable reading: with a
        // percent left side `10% of 500` is the bounded percent infix
        // (0.1 x 500) even while `of` is an active variable name.
        try r83IsNumber(lines[1].result, 50, "10% of 500 keeps the infix reading")
        let spans = SyntaxClassifier.spans(for: doc, rates: Rates(), decimalPlaces: 7)[1]
        try expect(!spans.contains { $0.role == .specifier },
                   "shadowed keyword is not a specifier")
        try expect(spans.contains { $0.role == .variable },
                   "shadowed keyword keeps the variable role")
    },

    // MARK: numeric-world integration

    EngineCase("r83-totals-and-previous-answer") {
        let lines = r83Lines("15% of 490\n100\ntotal")
        // The inline total sums the plain value of the percent-kind
        // line like any number of its section.
        try r83IsNumber(lines[2].result, 173.5, "total after 73.5 + 100")
        // A phrase value line stays a plain NUMBER answer: it feeds
        // totals and the previous-answer plan exactly like any number.
        if lines[0].result.numericKind != NumericKind.plain && lines[0].result.rawNumericValue != 73.5 {
            throw r83Fail("phrase value line must stay a plain number answer", lines[0].result)
        }
    },

    EngineCase("r83-dangling-phrases-fail") {
        // A phrase missing its value operand fails safely — never a
        // word-stripped fallback value.
        let lines = r83Lines("50 is what % of\n100 as a % of")
        guard case .error = lines[0].result else {
            throw r83Fail("dangling what-%-of must fail", lines[0].result)
        }
        guard case .error = lines[1].result else {
            throw r83Fail("dangling as-a-%-of must fail", lines[1].result)
        }
    },

    EngineCase("r83-strictness-booleans-and-prose") {
        // Boolean syntax wins over phrases (the boolean stage runs
        // first); the phrase then reports its strict outcome.
        let lines = r83Lines("flag = true\ntrue and 15% of 100")
        guard case .boolean = lines[0].result else {
            throw r83Fail("flag = true", lines[0].result)
        }
        guard case .error = lines[1].result else {
            throw r83Fail("boolean syntax on a phrase line must fail", lines[1].result)
        }
        // Prose never becomes math: a stray keyword in an operand
        // position breaks the form and the line stays an error.
        let prose = r83Lines("15% of fish")
        guard case .error = prose[0].result else {
            throw r83Fail("15% of fish must fail (prose operand)", prose[0].result)
        }
    },
]
