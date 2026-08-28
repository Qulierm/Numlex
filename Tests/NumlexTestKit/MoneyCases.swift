import Foundation
import NumlexCore

/// Natural money arithmetic: typed detection (no blind word-stripping),
/// bounded prose, one currency per line, the shared money presentation,
/// symbol/ISO source conversions with `to` AND `in`, and money answer
/// tokens (live conversion, `+ %`, broken/clipboard display).

private let M = "\u{FFFC}"

private func mLine(_ line: String,
                   rates: Rates = Rates(),
                   vars: [String: Double] = [:]) -> LineResult? {
    var v = vars
    return evalLine(line, variables: &v, rates: rates, decimalPlaces: 7)
}

private func ratesUSD() -> Rates {
    Rates(base: "USD", rates: ["USD": 1, "EUR": 1.1, "RUB": 90, "JPY": 150])
}

public let moneyCases: [EngineCase] = [
    // MARK: Reference lines

    EngineCase("money-ref-earnings-division") {
        if case .money(let v, let code)? = mLine("$3k earnings ÷ 5 people") {
            try expectClose(v, 600, 1e-9, "$3k ÷ 5 = 600")
            try expectEqual(code, "USD", "dollar default")
        } else {
            try expect(false, "$3k earnings ÷ 5 people must be money")
        }
        try expectEqual(formatMoney(600, code: "USD"), "$600.00", "display $600.00")
    },

    EngineCase("money-ref-tip") {
        if case .money(let v, let code)? = mLine("lunch was $55 + 25% tip") {
            try expectClose(v, 68.75, 1e-9, "$55 + 25% = 68.75")
            try expectEqual(code, "USD", "dollar default")
        } else {
            try expect(false, "lunch was $55 + 25% tip must be money")
        }
        try expectEqual(formatMoney(68.75, code: "USD"), "$68.75", "display $68.75")
    },

    EngineCase("money-ref-sales-tax") {
        if case .money(let v, let code)? = mLine("$3,400 + 10% sales tax") {
            try expectClose(v, 3740, 1e-9, "$3,400 + 10% = 3,740")
            try expectEqual(code, "USD", "dollar default")
        } else {
            try expect(false, "$3,400 + 10% sales tax must be money")
        }
        try expectEqual(formatMoney(3740, code: "USD"), "$3,740.00", "display $3,740.00")
    },

    // MARK: Symbols, markers, ISO annotations

    EngineCase("money-bare-amounts") {
        if case .money(let v, let c)? = mLine("$100") {
            try expectClose(v, 100, 0); try expectEqual(c, "USD")
        } else { try expect(false, "$100 is money") }
        if case .money(let v, let c)? = mLine("€100") {
            try expectClose(v, 100, 0); try expectEqual(c, "EUR")
        } else { try expect(false, "€100 is money") }
        if case .money(let v, let c)? = mLine("£50") {
            try expectClose(v, 50, 0); try expectEqual(c, "GBP")
        } else { try expect(false, "£50 is money") }
        if case .money(let v, let c)? = mLine("¥1000") {
            try expectClose(v, 1000, 0); try expectEqual(c, "JPY")
        } else { try expect(false, "¥1000 is money") }
        if case .money(let v, let c)? = mLine("₽90") {
            try expectClose(v, 90, 0); try expectEqual(c, "RUB")
        } else { try expect(false, "₽90 is money") }
    },

    EngineCase("money-disambiguated-dollars") {
        if case .money(let v, let c)? = mLine("CA$50 + CA$10") {
            try expectClose(v, 60, 0); try expectEqual(c, "CAD")
        } else { try expect(false, "CA$ is CAD") }
        if case .money(let v, let c)? = mLine("A$100 - 10%") {
            try expectClose(v, 90, 1e-9); try expectEqual(c, "AUD")
        } else { try expect(false, "A$ is AUD with contextual %") }
        if case .money(let v, let c)? = mLine("NZ$5 × 2") {
            try expectClose(v, 10, 0); try expectEqual(c, "NZD")
        } else { try expect(false, "NZ$ is NZD") }
        if case .money(let v, let c)? = mLine("HK$200 + 50") {
            try expectClose(v, 250, 0); try expectEqual(c, "HKD")
        } else { try expect(false, "HK$ second amount inherits") }
        if case .money(let v, let c)? = mLine("S$10 + 20%") {
            try expectClose(v, 12, 1e-9); try expectEqual(c, "SGD")
        } else { try expect(false, "S$ is SGD") }
    },

    EngineCase("money-iso-annotation") {
        if case .money(let v, let c)? = mLine("100 USD + 50") {
            try expectClose(v, 150, 0); try expectEqual(c, "USD")
        } else { try expect(false, "100 USD + 50 is money") }
        if case .money(let v, let c)? = mLine("100 EUR × 2") {
            try expectClose(v, 200, 0); try expectEqual(c, "EUR")
        } else { try expect(false, "100 EUR × 2 is money") }
    },

    EngineCase("money-mixed-currencies-are-errors") {
        if case .error? = mLine("$10 + €5") {
            try expect(true, "mixed currencies hidden error")
        } else { try expect(false, "$10 + €5 must be an error") }
        if case .error? = mLine("CA$10 + NZ$5") {
            try expect(true, "mixed $-variants hidden error")
        } else { try expect(false, "CA$ + NZ$ must be an error") }
    },

    EngineCase("money-scalar-arithmetic") {
        if case .money(let v, _)? = mLine("$200 × 0.1") {
            try expectClose(v, 20, 1e-9, "$200 × 0.1")
        } else { try expect(false, "scalar ×") }
        if case .money(let v, _)? = mLine("$100 ÷ 4") {
            try expectClose(v, 25, 1e-9, "$100 ÷ 4")
        } else { try expect(false, "scalar ÷") }
        if case .money(let v, _)? = mLine("$100 + 10%") {
            try expectClose(v, 110, 1e-9, "$100 + 10% = 110")
        } else { try expect(false, "money + contextual %") }
        if case .money(let v, _)? = mLine("$100 - 10% - 5%") {
            try expectClose(v, 85.5, 1e-9, "$100 - 10% - 5% = 85.5")
        } else { try expect(false, "sequential money %") }
    },

    EngineCase("money-malformed-never-falls-through") {
        // Unknown words, trailing `to`, digit-less markers: hidden
        // errors, never a leading-number fallback.
        for bad in ["$5 + xyz", "$5 + 3 x", "$5 to", "$", "$$5"] {
            var r = mLine(bad)
            if case .money? = r {
                try expect(false, "malformed money returned money: \(bad)")
            }
            if case .number(let v, nil)? = r {
                try expect(false, "malformed money fell to a number: \(bad) → \(v)")
            }
        }
        // Prose with a $ NOT glued to a number is untouched prose
        // (evalLine returns nil; the sheet layer maps that to .skip).
        if case .skip? = (mLine("the $ sign") ?? .skip) {
            try expect(true, "$ prose stays prose")
        } else { try expect(false, "the $ sign must be prose") }
    },

    EngineCase("money-grouping-decimals-scientific") {
        if case .money(let v, _)? = mLine("$1,234.50 + 0.5") {
            try expectClose(v, 1235, 1e-9, "grouping + decimals")
        } else { try expect(false, "$1,234.50 + 0.5") }
        if case .money(let v, _)? = mLine("$1500 × 2") {
            try expectClose(v, 3000, 1e-9, "money × 2")
        } else { try expect(false, "$1500 × 2") }
        if case .money(let v, _)? = mLine("$2.5k + 100") {
            try expectClose(v, 2600, 1e-9, "compact k")
        } else { try expect(false, "$2.5k + 100") }
    },

    // MARK: Presentation metadata

    EngineCase("money-presentation-minor-digits") {
        try expectEqual(formatMoney(500, code: "JPY"), "¥500", "JPY 0 digits")
        try expectEqual(formatMoney(500, code: "KRW"), "₩500", "KRW 0 digits + safe symbol")
        try expectEqual(formatMoney(10, code: "BHD"), "10.000 BHD", "BHD 3 digits")
        try expectEqual(formatMoney(1234.5, code: "USD"), "$1,234.50", "default 2 + grouping")
        try expectEqual(formatMoney(600, code: "CHF"), "600.00 CHF", "ISO suffix fallback")
        try expectEqual(formatMoney(-5.5, code: "EUR"), "-€5.50", "negative keeps symbol")
        try expectEqual(formatMoney(107.6391, code: "EUR"), "€107.64", "display-only rounding")
    },

    EngineCase("money-presentation-huge-scientific") {
        try expectEqual(formatMoney(2e20, code: "USD"), "$2e+20", "huge stays scientific")
        try expectEqual(formatMoney(-1.5e19, code: "CAD"), "-CA$1.5e+19", "negative huge")
        try expectEqual(formatMoney(2e20, code: "CHF"), "2e+20 CHF", "huge fallback form")
        // Engine value untouched: no rounding of the stored amount.
        if case .money(let v, _)? = mLine("$99999999999999.99") {
            try expectClose(v, 99999999999999.99, 0.02, "full precision kept")
        } else { try expect(false, "huge money line") }
    },

    // MARK: Symbol-source conversions (`to` and `in`)

    EngineCase("money-symbol-conversions") {
        let r = ratesUSD()
        if case .number(let v, let u)? = mLine("$100 to EUR", rates: r) {
            try expectClose(v, 110, 1e-9, "$100 to EUR")
            try expectEqual(u ?? "", "EUR")
            try expectEqual(formatQuantity(v, unit: u, decimalPlaces: 7), "€110.00", "money display")
        } else { try expect(false, "$100 to EUR") }
        if case .number(let v, let u)? = mLine("€100 in USD", rates: r) {
            try expectClose(v, 100 / 1.1, 1e-9, "€100 in USD")
            try expectEqual(u ?? "", "USD")
        } else { try expect(false, "€100 in USD") }
        if case .number(let v, _)? = mLine("$3,740.00 in EUR", rates: r) {
            try expectClose(v, 4114, 1e-9, "$3,740.00 in EUR")
        } else { try expect(false, "$3,740.00 in EUR") }
        if case .number(let v, let u)? = mLine("100 USD in JPY", rates: r) {
            try expectClose(v, 15000, 1e-9, "100 USD in JPY")
            try expectEqual(u ?? "", "JPY")
        } else { try expect(false, "100 USD in JPY") }
        if case .number(let v, let u)? = mLine("100 JPY to USD", rates: r) {
            try expectClose(v, 100 / 150, 1e-9, "100 JPY to USD")
            try expectEqual(u ?? "", "USD")
        } else { try expect(false, "100 JPY to USD") }
    },

    EngineCase("money-in-works-for-measurements-too") {
        if case .number(let v, let u)? = mLine("5 m in cm") {
            try expectClose(v, 500, 1e-9, "5 m in cm")
            try expectEqual(u ?? "", "cm")
        } else { try expect(false, "5 m in cm") }
    },

    EngineCase("money-inch-unit-survives-in-keyword") {
        if case .number(let v, _)? = mLine("3 in to cm") {
            try expectClose(v, 7.62, 1e-9, "3 inches to cm")
        } else { try expect(false, "3 in to cm") }
    },

    EngineCase("money-missing-rate-explicit") {
        if case .error(let msg)? = mLine("10 USD to RUB", rates: Rates()) {
            try expectEqual(msg, "Rates unavailable", "explicit white state")
        } else { try expect(false, "missing rate must error") }
    },

    EngineCase("money-conversion-regression-huge-mass") {
        if case .number(let v, let u)? = mLine("50000000000000 kg to mg") {
            try expectClose(v, 5e19, 1.0, "5e13 kg → mg")
            try expectEqual(u ?? "", "mg")
        } else { try expect(false, "huge mass conversion") }
    },

    // MARK: Money answer tokens

    EngineCase("money-token-bare-display") {
        let src = "$3,400 + 10% sales tax"
        let content = src + "\n" + M
        let ids = [UUID(), UUID()]
        let refs = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                    location: (src as NSString).length + 1)]
        let (lines, tokens) = resolveSheet(content: content, lineIDs: ids, references: refs,
                                           rates: ratesUSD(), decimalPlaces: 7)
        if case .number(let v, let u) = lines[1].result {
            try expectClose(v, 3740, 1e-9, "bare money token")
            try expectEqual(u ?? "", "USD")
        } else { try expect(false, "bare money token line") }
        try expectEqual(tokens[0].state,
                        .active(value: 3740, unit: "USD", display: "$3,740.00"),
                        "token display is the money string")
    },

    EngineCase("money-token-in-eur-live") {
        let src = "$3,400 + 10% sales tax"
        let content = src + "\n" + M + " in EUR"
        let ids = [UUID(), UUID()]
        let refs = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                    location: (src as NSString).length + 1)]
        let (lines, _) = resolveSheet(content: content, lineIDs: ids, references: refs,
                                      rates: ratesUSD(), decimalPlaces: 7)
        if case .number(let v, let u) = lines[1].result {
            try expectClose(v, 4114, 1e-9, "token in EUR at live rate")
            try expectEqual(u ?? "", "EUR")
            try expectEqual(formatQuantity(v, unit: u, decimalPlaces: 7),
                            "€4,114.00", "money display")
        } else { try expect(false, "token in EUR line") }
        // The legacy keyword keeps working identically.
        let content2 = src + "\n" + M + " to EUR"
        let refs2 = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                     location: (src as NSString).length + 1)]
        let (lines2, _) = resolveSheet(content: content2, lineIDs: ids, references: refs2,
                                       rates: ratesUSD(), decimalPlaces: 7)
        if case .number(let v, _) = lines2[1].result {
            try expectClose(v, 4114, 1e-9, "token to EUR")
        } else { try expect(false, "token to EUR line") }
    },

    EngineCase("money-token-percent-tip") {
        let src = "$3,400 + 10% sales tax"
        let content = src + "\n" + M + " + 10% tip"
        let ids = [UUID(), UUID()]
        let refs = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                    location: (src as NSString).length + 1)]
        let (lines, _) = resolveSheet(content: content, lineIDs: ids, references: refs,
                                      rates: ratesUSD(), decimalPlaces: 7)
        if case .number(let v, let u) = lines[1].result {
            try expectClose(v, 3740 * 1.1, 1e-6, "moneyToken + 10% tip")
            try expectEqual(u ?? "", "USD", "unit carried")
        } else { try expect(false, "moneyToken + 10% tip line") }
    },

    EngineCase("money-token-missing-rate-explicit") {
        let src = "$100"
        let content = src + "\n" + M + " in RUB"
        let ids = [UUID(), UUID()]
        let refs = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                    location: (src as NSString).length + 1)]
        let (lines, _) = resolveSheet(content: content, lineIDs: ids, references: refs,
                                      rates: Rates(), decimalPlaces: 7)
        if case .error(let msg) = lines[1].result {
            try expectEqual(msg, "Rates unavailable", "explicit white state")
        } else { try expect(false, "token in RUB without rates") }
    },
]
