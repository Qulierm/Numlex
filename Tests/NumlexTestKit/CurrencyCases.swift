import Foundation
import NumlexCore

/// ISO money literals are ASCII-case-insensitive and a line may combine
/// currencies with additive/subtractive arithmetic: the FIRST money
/// operand anchors the result and every other operand converts through
/// the supplied rate table. Currency ×/÷ currency never silently squares
/// a currency; a missing pair is the explicit `Rates unavailable` state.
///
/// Coverage: the shared case-insensitive scanner (all supported codes,
/// boundaries, ranges, regional amounts), single-code formatting,
/// cross-currency add/subtract (order, 3+ operands, parentheses, unary,
/// symbols + ISO, grouping/compact), legacy scalar/percent behavior,
/// missing rates, deterministic named anchors, assignments, the source
/// guard for currency ×/÷, and the highlighter's case-insensitive
/// `.moneyMarker` ranges.

private let WM = "\u{FFFC}"

// MARK: - Local helpers

private func currencySource(_ rel: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let url = root.appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

/// The deterministic cross-currency table used by these cases:
/// 1 EUR = 1.1 USD (so 1 USD = 1/1.1 EUR).
private func currencyRates() -> Rates {
    Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1])
}

private func currencyResults(_ content: String,
                             rates: Rates = currencyRates(),
                             decimalPlaces: Int = 10) -> [LineResult] {
    var v: [String: Double] = [:]
    return evaluateSheet(content, variables: &v, rates: rates,
                         decimalPlaces: decimalPlaces).map(\.result)
}

private func currencyMoney(_ content: String,
                           rates: Rates = currencyRates(),
                           decimalPlaces: Int = 10) -> (value: Double, code: String)? {
    if case .money(let v, let c) = currencyResults(content, rates: rates,
                                                   decimalPlaces: decimalPlaces)[0] {
        return (v, c)
    }
    return nil
}

public let currencyCases: [EngineCase] = [

    // MARK: - Task 2: case-insensitive ISO recognition

    EngineCase("currency-lowercase-iso-is-money") {
        guard let m = currencyMoney("500 usd") else {
            throw CaseFailure(message: "500 usd must be money",
                              location: "CurrencyCases")
        }
        try expectClose(m.value, 500, 1e-9, "value")
        try expectEqual(m.code, "USD", "canonical uppercase code")
        // Empty rates: no conversion is needed for a single code.
        guard let bare = currencyMoney("500 usd", rates: Rates()) else {
            throw CaseFailure(message: "500 usd must work with empty rates",
                              location: "CurrencyCases")
        }
        try expectClose(bare.value, 500, 1e-9, "no rates needed")
        // The display is the normal USD money formatting.
        try expectEqual(CurrencyPresentation.formatMoney(500, code: bare.code), "$500.00",
                        "renders $500.00")
    },

    EngineCase("currency-mixed-case-iso-is-money") {
        for spelling in ["usd", "Usd", "uSd", "USD"] {
            guard let m = currencyMoney("500 \(spelling)") else {
                throw CaseFailure(message: "500 \(spelling) must be money",
                                  location: "CurrencyCases")
            }
            try expectClose(m.value, 500, 1e-9, "value for \(spelling)")
            try expectEqual(m.code, "USD", "canonical for \(spelling)")
        }
        if case .money(let v, let c) = currencyResults("12.5 eur")[0] {
            try expectClose(v, 12.5, 1e-9, "decimal amount")
            try expectEqual(c, "EUR", "EUR code")
        } else {
            throw CaseFailure(message: "12.5 eur must be money", location: "CurrencyCases")
        }
    },

    EngineCase("currency-all-supported-codes-case-insensitive") {
        // Every supported fiat code normalizes from any ASCII casing and
        // evaluates as money (no rates needed for a single code).
        try expect(FiatCurrencies.codes.count >= 166, "the supported table is complete")
        var checked = 0
        for code in FiatCurrencies.codes {
            // A lowercase spelling that is already an existing
            // NON-currency unit label keeps its unit reading (`cup`),
            // so those codes are asserted uppercase-only below.
            let lowerResolves = UnitCatalog.resolveExpression(code.lowercased())
            var lowerIsNonCurrencyUnit = false
            if let p = lowerResolves, case .currency = p.unit.kind {} else if lowerResolves != nil {
                lowerIsNonCurrencyUnit = true
            }
            if lowerIsNonCurrencyUnit {
                let upper = "250 \(code)"
                guard let m = currencyMoney(upper, rates: Rates()) else {
                    throw CaseFailure(message: "uppercase \(upper) must stay money",
                                      location: "CurrencyCases")
                }
                try expectEqual(m.code, code, "uppercase \(code) stays money")
                continue
            }
            for spelling in [code.lowercased(), code, code.prefix(1) + code.dropFirst().lowercased()] {
                checked += 1
                let line = "250 \(spelling)"
                guard let m = currencyMoney(line, rates: Rates()) else {
                    throw CaseFailure(message: "\(line) must be money",
                                      location: "CurrencyCases")
                }
                try expectEqual(m.code, code, "canonical code for \(spelling)")
                try expectClose(m.value, 250, 1e-9, "value for \(spelling)")
                let occ = CurrencyAnnotations.occurrences(in: line)
                try expectEqual(occ.count, 1, "one occurrence for \(spelling)")
                try expectEqual(occ.first?.code, code, "scanner code for \(spelling)")
                try expectEqual(occ.first?.shape, .isoCode, "ISO shape for \(spelling)")
                try expectEqual(occ.first?.range.location, 4, "exact range start")
                try expectEqual(occ.first?.range.length, 3, "exact range length")
            }
        }
        try expect(checked >= 160, "case-insensitivity checked \(checked) spellings")
    },

    EngineCase("currency-scanner-boundaries-and-invalid-codes") {
        // Invalid three-letter tokens are never money.
        for line in ["500 xyz", "500 abc", "100 us", "100 usdd"] {
            let codes = CurrencyAnnotations.occurrences(in: line).map(\.code)
            try expect(codes.isEmpty, "\(line) carries no currency (got \(codes))",
                       "boundary")
        }
        // Identifiers/prose are never annotated.
        for line in ["usd", "usd wallet", "the usd is strong", "myusd 5", "500usd"] {
            let codes = CurrencyAnnotations.occurrences(in: line).map(\.code)
            try expect(codes.isEmpty, "\(line) carries no currency (got \(codes))",
                       "boundary")
        }
        // A real amount annotation is required: a bare code after a
        // letter or a code with no amount stays money-free.
        try expect(CurrencyAnnotations.occurrences(in: "500 usd").count == 1, "amount + code")
        try expect(CurrencyAnnotations.occurrences(in: "usd 500").isEmpty,
                   "prefix ISO is not part of the grammar")
        // Multiple annotations on one line, source order preserved.
        let multi = CurrencyAnnotations.occurrences(in: "500 usd - 300 eur")
        try expectEqual(multi.map(\.code), ["USD", "EUR"], "source order")
        try expect(multi[0].range.location < multi[1].range.location, "ordered ranges")
        // Symbol markers and ISO codes coexist.
        let both = CurrencyAnnotations.occurrences(in: "$500 - 300 eur")
        try expectEqual(both.map(\.shape), [.symbolMarker, .isoCode], "mixed shapes")
        try expectEqual(both.map(\.code), ["USD", "EUR"], "mixed codes")
        // Regional amounts: decimal comma and narrow-space grouping.
        try expectEqual(CurrencyAnnotations.occurrences(in: "500,50 eur").first?.code, "EUR",
                        "decimal comma")
        try expectEqual(CurrencyAnnotations.occurrences(in: "1\u{202F}000 eur").first?.code,
                        "EUR", "narrow-space grouping")
        // UTF-16 safety: the reported ranges slice the exact code text.
        let line = "500 usd - 300 eur"
        let ns = line as NSString
        for o in CurrencyAnnotations.occurrences(in: line) {
            let text = ns.substring(with: o.range)
            try expectEqual(text.uppercased(), o.code, "range slices the code")
        }
        // Incomplete input never produces a partial annotation.
        for line in ["500 u", "500 ", "500 us"] {
            try expect(CurrencyAnnotations.occurrences(in: line).isEmpty,
                       "incomplete '\(line)' has no occurrence")
        }
    },

    EngineCase("currency-symbol-and-iso-same-code") {
        // `$500 + 100 usd` is one currency written two ways: no
        // conversion, no rates required.
        guard let m = currencyMoney("$500 + 100 usd", rates: Rates()) else {
            throw CaseFailure(message: "$500 + 100 usd must be money",
                              location: "CurrencyCases")
        }
        try expectClose(m.value, 600, 1e-9, "600 USD")
        try expectEqual(m.code, "USD", "USD kept")
    },

    // MARK: - Task 3: additive/subtractive cross-currency arithmetic

    EngineCase("currency-user-sample-500-usd-minus-300-eur") {
        // 1 EUR = 1.1 USD, so 300 EUR = 272.7272... USD:
        // 500 - 300/1.1 = 227.2727272727...
        guard let m = currencyMoney("500 usd - 300 eur") else {
            throw CaseFailure(message: "the user sample must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(m.value, 227.2727272727, 1e-9, "500 - 300/1.1")
        try expectEqual(m.code, "USD", "first operand anchors USD")
        // Addition is the natural counterpart.
        guard let plus = currencyMoney("500 usd + 300 eur") else {
            throw CaseFailure(message: "addition must evaluate", location: "CurrencyCases")
        }
        try expectClose(plus.value, 772.7272727273, 1e-9, "500 + 300/1.1")
        try expectEqual(plus.code, "USD", "USD anchor")
    },

    EngineCase("currency-anchor-is-first-operand") {
        // Reversed order anchors EUR: 500 USD = 550 EUR, so
        // 300 - 550 = -250 EUR.
        guard let m = currencyMoney("300 eur - 500 usd") else {
            throw CaseFailure(message: "reversed order must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(m.value, -250, 1e-9, "300 - 500×1.1")
        try expectEqual(m.code, "EUR", "first operand anchors EUR")
        // The same pair under a different table gives a different result
        // (the rates snapshot is the only conversion source).
        let other = Rates(base: "USD", rates: ["USD": 1, "EUR": 0.8])
        guard let two = currencyMoney("500 usd - 300 eur", rates: other) else {
            throw CaseFailure(message: "alternate table must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(two.value, 500 - 300 / 0.8, 1e-9, "300 EUR = 375 USD")
    },

    EngineCase("currency-three-operands-left-to-right") {
        // USD-based table: entries are units of each code per 1 USD, so
        // 1 GBP = 1/0.714285… = 1.4 USD (matches `$500 - 300 eur`).
        let rates = Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1, "GBP": 1 / 1.4])
        // 100 + 200/1.1×1.1... anchor USD: 200 EUR = 181.8181...,
        // 50 GBP = 70 USD → 100 + 181.8181 − 70 = 211.8181...
        guard let m = currencyMoney("100 usd + 200 eur - 50 gbp", rates: rates) else {
            throw CaseFailure(message: "three-currency line must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(m.value, 100 + 200 / 1.1 - 50 * 1.4, 1e-9, "left-to-right")
        try expectEqual(m.code, "USD", "USD anchor")
        // Parenthesized subexpression and a unary sign stay deterministic.
        guard let p = currencyMoney("(500 usd - 300 eur) + 100 usd", rates: rates) else {
            throw CaseFailure(message: "parenthesized sum must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(p.value, 500 - 300 / 1.1 + 100, 1e-9, "parens")
        guard let u = currencyMoney("-500 usd + 300 eur", rates: rates) else {
            throw CaseFailure(message: "unary sign must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(u.value, -500 + 300 / 1.1, 1e-9, "unary minus")
        guard let inner = currencyMoney("2 × (500 usd - 300 eur)", rates: rates) else {
            throw CaseFailure(message: "scalar × parenthesized money",
                              location: "CurrencyCases")
        }
        try expectClose(inner.value, 2 * (500 - 300 / 1.1), 1e-9, "scalar multiply")
    },

    EngineCase("currency-symbols-and-iso-mix") {
        guard let a = currencyMoney("$500 - 300 eur") else {
            throw CaseFailure(message: "$500 - 300 eur must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(a.value, 500 - 300 / 1.1, 1e-9, "symbol + ISO")
        try expectEqual(a.code, "USD", "$ anchors USD")
        guard let b = currencyMoney("500 usd - €300") else {
            throw CaseFailure(message: "500 usd - €300 must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(b.value, 500 - 300 / 1.1, 1e-9, "ISO + symbol")
        try expectEqual(b.code, "USD", "ISO anchors USD")
        guard let c = currencyMoney("€300 - $500") else {
            throw CaseFailure(message: "€300 - $500 must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(c.value, 300 - 500 * 1.1, 1e-9, "EUR anchor arithmetic")
        try expectEqual(c.code, "EUR", "first symbol anchors EUR")
    },

    EngineCase("currency-grouped-compact-and-regional-amounts") {
        // Grouped digits, compact suffix and a negative operand all go
        // through the shared amount grammar (no display parsing).
        guard let m = currencyMoney("$3,400 - 1,000 eur") else {
            throw CaseFailure(message: "grouped amounts must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(m.value, 3400 - 1000 / 1.1, 1e-9, "grouped")
        guard let k = currencyMoney("$2.5K + 1,000 usd") else {
            throw CaseFailure(message: "compact + grouped amounts must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(k.value, 2500 + 1000, 1e-9, "compact + grouped, same code")
        // Decimal comma (regional input context) reads the comma as the
        // decimal separator; the default context keeps reading it as
        // grouping (500,50 → 50050).
        let commaContext = NumberFormatContext(
            locale: Locale(identifier: "de_DE"), decimalSeparator: ",",
            groupingSeparator: ".", argumentSeparator: ";",
            displayGrouping: true, compactNotation: false,
            convertForeignOnPaste: true)
        var cv: [String: Double] = [:]
        let comma = evaluateSheet("500,50 eur + 100 usd", variables: &cv,
                                  rates: currencyRates(), decimalPlaces: 10,
                                  context: commaContext)[0].result
        if case .money(let v, let c) = comma {
            // EUR is the first operand here, so the anchor is EUR and
            // 100 USD becomes 110 EUR.
            try expectClose(v, 500.5 + 100 * 1.1, 1e-9, "decimal comma")
            try expectEqual(c, "EUR", "EUR anchor")
        } else {
            throw CaseFailure(message: "decimal-comma amount must evaluate, got \(comma)",
                              location: "CurrencyCases")
        }
    },

    EngineCase("currency-scalar-and-percent-legacy-semantics") {
        // Unannotated scalars keep the legacy money semantics.
        guard let a = currencyMoney("500 usd - 20") else {
            throw CaseFailure(message: "scalar subtraction must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(a.value, 480, 1e-9, "500 usd - 20 = 480 USD")
        try expectEqual(a.code, "USD", "USD kept")
        guard let b = currencyMoney("500 usd - 10%") else {
            throw CaseFailure(message: "contextual percent must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(b.value, 450, 1e-9, "500 usd - 10% = 450 USD")
        guard let c = currencyMoney("$200 + $50") else {
            throw CaseFailure(message: "same-symbol sum must evaluate",
                              location: "CurrencyCases")
        }
        try expectClose(c.value, 250, 1e-9, "same currency unchanged")
        // Money × scalar and money ÷ scalar stay legal, single currency.
        guard let d = currencyMoney("$500 × 2") else {
            throw CaseFailure(message: "money × scalar", location: "CurrencyCases")
        }
        try expectClose(d.value, 1000, 1e-9, "money × scalar")
        guard let e = currencyMoney("500 usd / 4") else {
            throw CaseFailure(message: "money ÷ scalar", location: "CurrencyCases")
        }
        try expectClose(e.value, 125, 1e-9, "money ÷ scalar")
    },

    EngineCase("currency-missing-rates-is-explicit") {
        // No table: a cross-currency sum is the explicit state, never a
        // numeric fallback and never a partial sum.
        let empty = Rates()
        for line in ["500 usd - 300 eur", "$500 - €300", "100 gbp + 5 eur"] {
            let r = currencyResults(line, rates: empty)[0]
            try expectEqual(r, .error(message: "Rates unavailable"),
                            "\(line) needs rates (got \(r))")
        }
        // A table missing one leg behaves the same way.
        let partial = Rates(base: "USD", rates: ["USD": 1])
        try expectEqual(currencyResults("500 usd - 300 eur", rates: partial)[0],
                        .error(message: "Rates unavailable"), "missing EUR leg")
        // Same currency never needs a rate table.
        try expectClose(currencyMoney("500 usd - 300 usd", rates: empty)?.value ?? .nan,
                        200, 1e-9, "same code needs no rates")
        // And the pure policy helper agrees.
        try expect(CurrencyArithmetic.factor(from: "EUR", to: "USD", rates: empty) == nil,
                   "nil factor without a rate")
        try expectEqual(CurrencyArithmetic.factor(from: "USD", to: "USD", rates: empty), 1,
                        "identity factor")
    },

    EngineCase("currency-multiply-divide-currency-rejected") {
        // No cross-currency product/quotient: never a silent USD².
        for line in ["2 usd × 3 eur", "10 usd / 2 eur", "10 $ / €2", "2 usd ^ 2 eur"] {
            let r = currencyResults(line)[0]
            guard case .error = r else {
                throw CaseFailure(message: "\(line) must be rejected, got \(r)",
                                  location: "CurrencyCases")
            }
        }
        // Scalar products around a cross-currency sum stay legal.
        guard let ok = currencyMoney("2 × (100 usd - 10 eur)") else {
            throw CaseFailure(message: "scalar × cross-currency sum", location: "CurrencyCases")
        }
        try expectClose(ok.value, 2 * (100 - 10 / 1.1), 1e-9, "legal shape")
        // The structural helper is the same rule.
        try expect(CurrencyArithmetic.hasCurrencyProductOrQuotient("(2 * __fx0) × (3 * __fx1)"),
                   "currency × currency detected")
        try expect(!CurrencyArithmetic.hasCurrencyProductOrQuotient("(2 * __fx0) × 3"),
                   "currency × scalar allowed")
        try expect(!CurrencyArithmetic.hasCurrencyProductOrQuotient("(2 * __fx0) + (3 * __fx1)"),
                   "currency + currency allowed")
    },

    EngineCase("currency-prose-and-malformed-shapes-stay-rejected") {
        // Unknown words still fail the money grammar.
        for line in ["500 usd xyz", "500 usd + unknownword"] {
            let r = currencyResults(line)[0]
            guard case .error = r else {
                throw CaseFailure(message: "\(line) must fail, got \(r)", location: "CurrencyCases")
            }
        }
        // A function call never carries a currency.
        guard case .error = currencyResults("sqrt(500 usd)")[0] else {
            throw CaseFailure(message: "function call must fail", location: "CurrencyCases")
        }
        // Physical units stay strict: no automatic unit conversion.
        guard case .error = currencyResults("500 usd + 3 km")[0] else {
            throw CaseFailure(message: "currency + physical unit must fail",
                              location: "CurrencyCases")
        }
    },

    EngineCase("currency-assignment-and-named-anchor") {
        // `balance = 500 usd - 300 eur` stores money in the anchor code.
        let lines = currencyResults("balance = 500 usd - 300 eur\nbalance + 100 usd")
        guard case .money(let stored, let code) = lines[0] else {
            throw CaseFailure(message: "assignment must be money, got \(lines[0])",
                              location: "CurrencyCases")
        }
        try expectClose(stored, 500 - 300 / 1.1, 1e-9, "stored value")
        try expectEqual(code, "USD", "stored in USD")
        guard case .money(let reused, let code2) = lines[1] else {
            throw CaseFailure(message: "named reuse must be money, got \(lines[1])",
                              location: "CurrencyCases")
        }
        try expectClose(reused, 500 - 300 / 1.1 + 100, 1e-9, "named reuse")
        try expectEqual(code2, "USD", "reuse keeps USD")
    },

    EngineCase("currency-named-first-operand-anchors") {
        let content = """
        usd wallet = 500 usd
        eur bill = 300 eur
        usd wallet - eur bill
        eur bill - usd wallet
        """
        let lines = currencyResults(content)
        guard case .money(let a, let ca) = lines[2] else {
            throw CaseFailure(message: "named mix must evaluate, got \(lines[2])",
                              location: "CurrencyCases")
        }
        try expectClose(a, 500 - 300 / 1.1, 1e-9, "wallet - bill")
        try expectEqual(ca, "USD", "first NAMED operand anchors USD")
        guard case .money(let b, let cb) = lines[3] else {
            throw CaseFailure(message: "reversed named mix must evaluate, got \(lines[3])",
                              location: "CurrencyCases")
        }
        try expectClose(b, 300 - 500 * 1.1, 1e-9, "bill - wallet")
        try expectEqual(cb, "EUR", "first named operand anchors EUR")
    },

    EngineCase("currency-constant-lowercase-and-mixed-caveat") {
        // A single-currency constant resolves like its uppercase
        // spelling, from any casing (constants are offline: no rates).
        let constants = [UserConstant(name: "Rent", expression: "500 usd")]
        var v: [String: Double] = [:]
        let resolved = evaluateSheet("Rent", variables: &v, rates: currencyRates(),
                                     decimalPlaces: 10, constants: constants)
        guard case .money(let rv, let rc) = resolved[0].result else {
            throw CaseFailure(message: "lowercase constant must resolve, got \(resolved[0].result)",
                              location: "CurrencyCases")
        }
        try expectClose(rv, 500, 1e-9, "constant value")
        try expectEqual(rc, "USD", "constant canonicalized to USD")
        // A mixed-currency constant needs a live table the offline
        // constant resolver does not have: it stays inactive (the name
        // is not a value, so the line is ordinary prose/skip — never a
        // silently converted money).
        let mixed = [UserConstant(name: "Net", expression: "500 usd - 300 eur")]
        var v2: [String: Double] = [:]
        let mixedResolved = evaluateSheet("Net", variables: &v2, rates: currencyRates(),
                                          decimalPlaces: 10, constants: mixed)
        switch mixedResolved[0].result {
        case .money:
            throw CaseFailure(message: "mixed constant must not resolve to money",
                              location: "CurrencyCases")
        case .error, .skip, .blank:
            break
        default:
            throw CaseFailure(message: "mixed constant must stay inactive, got \(mixedResolved[0].result)",
                              location: "CurrencyCases")
        }
    },

    EngineCase("currency-document-bytes-and-eval-parity") {
        // Evaluation never rewrites the source: the caret/document
        // bytes are the caller's.
        let source = "500 usd - 300 eur"
        let before = Array(source.utf8)
        _ = currencyResults(source)
        try expectEqual(Array(source.utf8), before, "source untouched")
        // evalLine / evaluateSheet / resolveSheet agree.
        var v: [String: Double] = [:]
        let line = evalLine("500 usd - 300 eur", variables: &v, rates: currencyRates(),
                            decimalPlaces: 10)
        try expectEqual(line, currencyResults("500 usd - 300 eur")[0], "evalLine parity")
        let ids = [UUID(), UUID()]
        let resolved = resolveSheet(content: "500 usd - 300 eur\n",
                                    lineIDs: ids, references: [], rates: currencyRates(),
                                    decimalPlaces: 10)
        try expectEqual(resolved.lines[0].result, currencyResults("500 usd - 300 eur")[0],
                        "resolveSheet parity")
    },

    // MARK: - Answer tokens

    EngineCase("currency-token-plus-literal") {
        // `TOKEN` = 500 usd; `TOKEN - 300 eur` must convert through the
        // same anchor + rates policy (U+FFFC offsets preserved).
        let u0 = UUID(), u1 = UUID()
        let content = "500 usd\n" + WM + " - 300 eur"
        let (lines, tokens) = resolveSheet(
            content: content, lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 8)],
            rates: currencyRates(), decimalPlaces: 10)
        try expectEqual(tokens.count, 1, "one token")
        // Token results carry the currency as their unit label (the
        // shared formatter renders it as money).
        guard case .number(let v, let u, _, _) = lines[1].result else {
            throw CaseFailure(message: "token - literal must be currency, got \(lines[1].result)",
                              location: "CurrencyCases")
        }
        try expectClose(v, 500 - 300 / 1.1, 1e-6, "token anchored USD")
        try expectEqual(u ?? "", "USD", "USD anchor from the token")
        // Missing rates: the explicit state.
        let (missing, _) = resolveSheet(
            content: content, lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 8)],
            rates: Rates(), decimalPlaces: 10)
        try expectEqual(missing[1].result, .error(message: "Rates unavailable"),
                        "token cross-currency needs rates")
    },

    EngineCase("currency-token-minus-token") {
        let u0 = UUID(), u1 = UUID(), u2 = UUID()
        let content = "500 usd\n300 eur\n" + WM + " - " + WM
        let (lines, _) = resolveSheet(
            content: content, lineIDs: [u0, u1, u2],
            references: [
                AnswerReference(sourceLineID: u0, labelLine: 1, location: 16),
                AnswerReference(sourceLineID: u1, labelLine: 2, location: 20)
            ],
            rates: currencyRates(), decimalPlaces: 10)
        guard case .number(let v, let u, _, _) = lines[2].result else {
            throw CaseFailure(message: "token - token must be currency, got \(lines[2].result)",
                              location: "CurrencyCases")
        }
        try expectClose(v, 500 - 300 / 1.1, 1e-6, "first token anchors")
        try expectEqual(u ?? "", "USD", "USD")
        // Live rate change re-evaluates through the new snapshot.
        let other = Rates(base: "USD", rates: ["USD": 1, "EUR": 0.8])
        let (changed, _) = resolveSheet(
            content: content, lineIDs: [u0, u1, u2],
            references: [
                AnswerReference(sourceLineID: u0, labelLine: 1, location: 16),
                AnswerReference(sourceLineID: u1, labelLine: 2, location: 20)
            ],
            rates: other, decimalPlaces: 10)
        if case .number(let v2, _, _, _) = changed[2].result {
            try expectClose(v2, 500 - 300 / 0.8, 1e-6, "re-evaluated with the new table")
        } else {
            throw CaseFailure(message: "live rate change must re-evaluate",
                              location: "CurrencyCases")
        }
    },

    EngineCase("currency-token-scalar-and-physical-non-regression") {
        // Physical tokens keep normal same-measurement behavior
        // (token-to-token: the token algebra has no unit literals).
        let u0 = UUID(), u1 = UUID(), u2 = UUID()
        let (keep, _) = resolveSheet(
            content: "2 kg\n3 kg\n" + WM + " + " + WM, lineIDs: [u0, u1, u2],
            references: [
                AnswerReference(sourceLineID: u0, labelLine: 1, location: 10),
                AnswerReference(sourceLineID: u1, labelLine: 2, location: 14)
            ],
            rates: currencyRates(), decimalPlaces: 10)
        try expectEqual(keep[2].result, .number(value: 5, unit: "kg"), "kg + kg unchanged")
        // Incompatible physical dimensions stay rejected.
        let (bad, _) = resolveSheet(
            content: "2 kg\n3 s\n" + WM + " + " + WM, lineIDs: [u0, u1, u2],
            references: [
                AnswerReference(sourceLineID: u0, labelLine: 1, location: 10),
                AnswerReference(sourceLineID: u1, labelLine: 2, location: 14)
            ],
            rates: currencyRates(), decimalPlaces: 10)
        guard case .error = bad[2].result else {
            throw CaseFailure(message: "kg + s must stay rejected, got \(bad[2].result)",
                              location: "CurrencyCases")
        }
        // A currency token combined with a physical-unit token is
        // rejected (no cross-dimension conversion).
        let (cross, _) = resolveSheet(
            content: "500 usd\n3 km\n" + WM + " + " + WM, lineIDs: [u0, u1, u2],
            references: [
                AnswerReference(sourceLineID: u0, labelLine: 1, location: 10),
                AnswerReference(sourceLineID: u1, labelLine: 2, location: 14)
            ],
            rates: currencyRates(), decimalPlaces: 10)
        guard case .error = cross[2].result else {
            throw CaseFailure(message: "money + physical must stay rejected",
                              location: "CurrencyCases")
        }
    },

    EngineCase("currency-token-assignment-and-missing-rates") {
        let u0 = UUID(), u1 = UUID()
        let content = "500 usd\n" + WM + " - 300 eur\ntotal = 1"
        let (lines, _) = resolveSheet(
            content: "500 usd\n" + WM + " - 300 eur", lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 8)],
            rates: currencyRates(), decimalPlaces: 10)
        guard case .number(let v, let u, _, _) = lines[1].result else {
            throw CaseFailure(message: "token line must be currency, got \(lines[1].result)",
                              location: "CurrencyCases")
        }
        try expectClose(v, 500 - 300 / 1.1, 1e-6, "token cross-currency value")
        try expectEqual(u ?? "", "USD", "USD")
        // The assignment form of a cross-currency right-hand side with
        // a token: `wallet = TOKEN + 100 eur` stores the anchor.
        let (assigned, _) = resolveSheet(
            content: "500 usd\nwallet = " + WM + " + 100 eur", lineIDs: [u0, u1],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 17)],
            rates: currencyRates(), decimalPlaces: 10)
        guard case .money(let av, let au) = assigned[1].result else {
            throw CaseFailure(message: "token assignment must be money, got \(assigned[1].result)",
                              location: "CurrencyCases")
        }
        try expectClose(av, 500 + 100 / 1.1, 1e-6, "token assignment value")
        try expectEqual(au, "USD", "token assignment anchor")
        // The recorded name is reusable as money.
        let (reuse, _) = resolveSheet(
            content: "500 usd\nwallet = " + WM + " + 100 eur\nwallet + 10 usd",
            lineIDs: [u0, u1, UUID()],
            references: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 17)],
            rates: currencyRates(), decimalPlaces: 10)
        if case .money(let rv, let rc) = reuse[2].result {
            try expectClose(rv, 500 + 100 / 1.1 + 10, 1e-6, "named money reuse")
            try expectEqual(rc, "USD", "reuse anchor")
        } else {
            throw CaseFailure(message: "named money reuse must be money, got \(reuse[2].result)",
                              location: "CurrencyCases")
        }
        _ = content
    },

    // MARK: - Highlighting and source guards

    EngineCase("currency-highlighting-case-insensitive-ranges") {
        var env = TypedEnv()
        let spans = SyntaxClassifier.spans(for: "500 usd - 300 eur", rates: currencyRates(),
                                           decimalPlaces: 10)
        let money = spans[0].filter { $0.role == .moneyMarker }
        try expectEqual(money.count, 2, "both ISO codes tint")
        try expectEqual(money[0].range, NSRange(location: 4, length: 3), "usd range")
        try expectEqual(money[1].range, NSRange(location: 14, length: 3), "eur range")
        // Prose and invalid codes never tint as money.
        let prose = SyntaxClassifier.spans(for: "the usd wallet", rates: currencyRates(),
                                           decimalPlaces: 10)
        try expect(prose[0].allSatisfy { $0.role != .moneyMarker },
                   "prose never tints as money")
        _ = env
    },

    EngineCase("currency-source-guards-shared-scanner") {
        guard let natural = currencySource("Sources/NumlexCore/Engine/NaturalCalculation.swift")
        else { throw CaseFailure(message: "missing NaturalCalculation", location: "CurrencyCases") }
        try expect(natural.contains("CurrencyAnnotations.occurrences(in: line)"),
                   "money core uses the shared scanner")
        try expect(!natural.contains("isoAnnotationRe"),
                   "the uppercase-only ISO regex is gone")
        try expect(natural.contains("case ratesUnavailable"), "explicit rates state exists")
        guard let scanner = currencySource("Sources/NumlexCore/Engine/CurrencyAnnotations.swift")
        else { throw CaseFailure(message: "missing scanner", location: "CurrencyCases") }
        try expect(scanner.contains("public static func canonicalCode"),
                   "canonical code API exists")
        try expect(scanner.contains("[A-Za-z]{3}"), "case-insensitive ISO pattern")
        guard let hl = currencySource("Sources/NumlexCore/Engine/SyntaxHighlighting.swift")
        else { throw CaseFailure(message: "missing highlighter", location: "CurrencyCases") }
        try expect(hl.contains("CurrencyAnnotations.isoOccurrences"),
                   "highlighter uses the shared ISO scanner")
        try expect(!hl.contains(#"\b[A-Z]{3}\b"#),
                   "the uppercase-only highlight pattern is gone")
        guard let resolver = currencySource("Sources/NumlexCore/Engine/ConstantResolver.swift")
        else { throw CaseFailure(message: "missing ConstantResolver", location: "CurrencyCases") }
        try expect(resolver.contains("CurrencyAnnotations"),
                   "constant resolver uses the shared scanner")
    }
]
