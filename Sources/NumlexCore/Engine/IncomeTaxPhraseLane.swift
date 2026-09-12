import Foundation

// MARK: - Estimated income-tax phrases (Package 2, Task 4)
//
// Strict sub-lane of the financial phrase architecture:
//
//   income tax on <money> in <country>       -> money (the estimated tax)
//   income after tax on <money> in <country> -> money (net income)
//   tax rate on <money> in <country>         -> percent (effective rate)
//
// `<country>` resolves through the bundled catalog's country/alias list
// (case-insensitive). The table declares its LOCAL currency: a different
// input currency is converted through the existing Rates table, the tax
// is computed in the local currency and the result is converted back to
// the input code. A missing pair is `Rates unavailable`; an unknown
// country is `no tax table for <country>`. Negative or non-finite income
// is a strict error; zero is deterministic.
enum IncomeTaxPhraseLane {

    enum Form { case incomeTax, incomeAfterTax, taxRate }

    static func tryLine(_ line: String, env: TypedEnv, rates: Rates,
                        context: NumberFormatContext,
                        financial: FinancialContext,
                        resolver: FinancialPhraseLane.MoneyResolver?)
        -> FinancialPhraseLane.Outcome? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return nil }
        let lower = trimmed.lowercased()
        for (head, form) in [("income after tax on ", Form.incomeAfterTax),
                             ("income tax on ", Form.incomeTax),
                             ("tax rate on ", Form.taxRate)] {
            guard lower.hasPrefix(head) else { continue }
            return evaluate(trimmed, body: String(trimmed.dropFirst(head.count)),
                            form: form, env: env, rates: rates, context: context,
                            financial: financial, resolver: resolver)
        }
        return nil
    }

    private static func evaluate(_ line: String, body: String, form: Form,
                                 env: TypedEnv, rates: Rates,
                                 context: NumberFormatContext,
                                 financial: FinancialContext,
                                 resolver: FinancialPhraseLane.MoneyResolver?)
        -> FinancialPhraseLane.Outcome? {
        guard let catalog = financial.incomeTaxTables else {
            return .error("no tax table for the configured region")
        }
        // `<money> in <country>`: the LAST ` in ` separates them (a
        // country name never contains ` in `).
        let trimmedBody = body.trimmingCharacters(in: .whitespaces)
        guard let range = trimmedBody.range(of: " in ", options: [.backwards, .caseInsensitive]) else {
            return .error("Invalid financial expression")
        }
        let moneyText = String(trimmedBody[trimmedBody.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let country = String(trimmedBody[range.upperBound...])
            .trimmingCharacters(in: .whitespaces)
        guard !moneyText.isEmpty, !country.isEmpty else {
            return .error("Invalid financial expression")
        }
        guard let table = catalog.table(for: country) else {
            return .error("no tax table for \(country)")
        }
        let resolve = resolver ?? FinancialPhraseLane.environmentResolver(
            env: env, context: context, rates: rates)
        let resolution = resolve(moneyText, 0)
        guard case .money(let value, let code) = resolution else {
            if resolution == .ratesUnavailable { return .error("Rates unavailable") }
            return .error("Invalid financial expression")
        }
        guard value.isFinite, value >= 0 else {
            return .error("Invalid financial expression")
        }
        // Convert the input to the table's local currency when needed.
        let factor: Double
        if code.uppercased() == table.currency {
            factor = 1
        } else {
            guard let f = rates.rate(from: code.uppercased(), to: table.currency),
                  f.isFinite, f > 0 else {
                return .error("Rates unavailable")
            }
            factor = f
        }
        let localIncome = value * factor
        guard localIncome.isFinite, localIncome >= 0 else {
            return .error("Invalid financial expression")
        }
        let localTax = table.tax(on: localIncome)
        guard localTax.isFinite else { return .error("Invalid financial expression") }
        switch form {
        case .taxRate:
            let rate = localIncome > 0 ? localTax / localIncome : 0
            guard rate.isFinite else { return .error("Invalid financial expression") }
            return .result(.number(value: rate, unit: nil, kind: .percent,
                                   fraction: nil))
        case .incomeTax, .incomeAfterTax:
            let localResult = form == .incomeTax ? localTax : localIncome - localTax
            let result = factor == 1 ? localResult : localResult / factor
            guard result.isFinite else { return .error("Invalid financial expression") }
            return .result(.money(value: result, code: code.uppercased()))
        }
    }
}
