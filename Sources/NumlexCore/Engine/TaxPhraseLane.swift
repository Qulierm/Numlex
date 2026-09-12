import Foundation

// MARK: - Configured sales-tax phrases (Package 2, Task 3)
//
// A strict sub-lane of the financial phrase architecture. The accepted
// tax names are one case-insensitive registry — `sales tax`, `VAT`,
// `GST`, plus the configured custom name — and all map to the configured
// rate. The configured rate is a PERCENT (15 means 15%).
//
//   $300 + VAT              -> $345.00   gross (net + tax)
//   $345 - VAT              -> $300.00   net (remove the included tax)
//   VAT on $300             -> $45.00    tax on the net amount
//   pre-tax price of $345   -> $300.00   net
//   gross price of $300     -> $345.00   gross
//   $300 including VAT      -> $345.00   gross (documented Soulver alias)
//
// A missing rate is the exact actionable error
// `set sales tax in Settings → Tax`. Owned heads that fail to carry a
// money operand are strict errors; unrelated prose, explicit
// percentage phrases (`sales tax 8% of $120`) and ordinary money never
// reach this lane's ownership.
enum TaxPhraseLane {

    static let missingRateMessage = "set sales tax in Settings → Tax"

    static func tryLine(_ line: String, env: TypedEnv, rates: Rates,
                        context: NumberFormatContext,
                        financial: FinancialContext,
                        decimalPlaces: Int,
                        resolver: FinancialPhraseLane.MoneyResolver?) -> FinancialPhraseLane.Outcome? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return nil }
        let tax = financial.tax
        let names = acceptedNames(configured: tax.name)
        let lower = trimmed.lowercased()

        let resolve = resolver ?? FinancialPhraseLane.environmentResolver(
            env: env, context: context, rates: rates)

        func rateFraction() -> Double? {
            guard let percent = tax.ratePercent, percent.isFinite else { return nil }
            return percent / 100
        }

        func missingRate() -> FinancialPhraseLane.Outcome? {
            guard rateFraction() == nil else { return nil }
            return .error(missingRateMessage)
        }

        func gross(_ resolution: FinancialPhraseLane.MoneyResolution) -> FinancialPhraseLane.Outcome {
            guard case .money(let value, let code) = resolution else {
                return resolution == .ratesUnavailable
                    ? .error("Rates unavailable")
                    : .error("Invalid financial expression")
            }
            guard let rate = rateFraction() else { return .error(missingRateMessage) }
            let result = value * (1 + rate)
            guard result.isFinite else { return .error("Invalid financial expression") }
            return .result(.money(value: result, code: code))
        }

        func net(_ resolution: FinancialPhraseLane.MoneyResolution) -> FinancialPhraseLane.Outcome {
            guard case .money(let value, let code) = resolution else {
                return resolution == .ratesUnavailable
                    ? .error("Rates unavailable")
                    : .error("Invalid financial expression")
            }
            guard let rate = rateFraction() else { return .error(missingRateMessage) }
            let divisor = 1 + rate
            guard divisor != 0 else { return .error("Invalid financial expression") }
            let result = value / divisor
            guard result.isFinite else { return .error("Invalid financial expression") }
            return .result(.money(value: result, code: code))
        }

        // A. `<name> on <money>` -> the tax amount on the net.
        for name in names where lower.hasPrefix(name + " on ") {
            let body = String(trimmed.dropFirst(name.count + " on ".count))
                .trimmingCharacters(in: .whitespaces)
            guard case .money(let value, let code) = resolve(body, 0) else {
                return resolve(body, 0) == .ratesUnavailable
                    ? .error("Rates unavailable") : .error("Invalid financial expression")
            }
            guard let rate = rateFraction() else { return .error(missingRateMessage) }
            let result = value * rate
            guard result.isFinite else { return .error("Invalid financial expression") }
            return .result(.money(value: result, code: code))
        }

        // D/E. `pre-tax price of <money>` / `gross price of <money>`.
        if lower.hasPrefix("pre-tax price of ") {
            let body = String(trimmed.dropFirst("pre-tax price of ".count))
            return net(resolve(body, 0))
        }
        if lower.hasPrefix("gross price of ") {
            let body = String(trimmed.dropFirst("gross price of ".count))
            return gross(resolve(body, 0))
        }

        // B/C/F. `<money> +|including <name>` / `<money> - <name>`.
        for name in names {
            for suffix in [" + " + name, " including " + name] {
                guard lower.hasSuffix(suffix) else { continue }
                let body = String(trimmed.dropLast(suffix.count))
                    .trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { return .error("Invalid financial expression") }
                let resolution = resolve(body, 0)
                guard case .money = resolution else {
                    // Not a money prefix: not our phrase.
                    return nil
                }
                return gross(resolution)
            }
            let minusSuffix = " - " + name
            if lower.hasSuffix(minusSuffix) {
                let body = String(trimmed.dropLast(minusSuffix.count))
                    .trimmingCharacters(in: .whitespaces)
                guard !body.isEmpty else { return .error("Invalid financial expression") }
                let resolution = resolve(body, 0)
                guard case .money = resolution else { return nil }
                return net(resolution)
            }
        }

        _ = decimalPlaces
        return nil
    }

    /// The ONE case-insensitive registry: the built-in aliases plus the
    /// configured custom name.
    static func acceptedNames(configured: String) -> [String] {
        var names = ["sales tax", "vat", "gst"]
        let custom = configured.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !custom.isEmpty, !names.contains(custom) {
            names.append(custom)
        }
        return names
    }
}
