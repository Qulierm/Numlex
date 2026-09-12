import Foundation

// MARK: - CPI inflation phrases (Package 2, Task 5)
//
// Strict sub-lane of the financial phrase architecture. Every direction
// is the historical ratio amount * CPI(target) / CPI(source); the bare
// past-to-today target is the BUNDLE'S snapshot year/index (never the
// wall clock), so answers are deterministic per dataset release.
//
//   what is <money> from <year>              -> past to snapshot
//   value of <money> from <year>             -> past to snapshot
//   <money> from <year> worth [what today]   -> past to snapshot
//   what was <money> worth in <year>         -> snapshot to historical
//   value of <money> in <year>               -> snapshot to historical
//   <money> is worth what in <year>          -> snapshot to historical
//   what is <money> in <y1> worth in <y2>    -> explicit ratio
//   <money> from <y1> is worth what in <y2>  -> explicit ratio
//   <money> in <year> dollars                -> past to snapshot
//   what will <money> be worth in <future> at R% [inflation]
//                                            -> amount / (1+R)^years
//
// A year outside the table is `no CPI data for <year>`; a future target
// without an explicit rate is a strict error, and an explicit forecast
// requires target > the snapshot year with a finite domain (1+R > 0).
enum CPIPhraseLane {

    static func tryLine(_ line: String, env: TypedEnv, rates: Rates,
                        context: NumberFormatContext,
                        financial: FinancialContext,
                        decimalPlaces: Int,
                        resolver: FinancialPhraseLane.MoneyResolver?)
        -> FinancialPhraseLane.Outcome? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 160 else { return nil }
        guard let catalog = financial.cpi else { return nil }
        let resolve = resolver ?? FinancialPhraseLane.environmentResolver(
            env: env, context: context, rates: rates)
        let lower = trimmed.lowercased()
        let snapshotYear = catalog.latestSnapshotYear

        func money(_ text: String) -> FinancialPhraseLane.MoneyResolution {
            resolve(text.trimmingCharacters(in: .whitespaces), 0)
        }

        /// Resolves the money operand; nil = the operand is not money
        /// (the line is not ours), otherwise the typed outcome.
        func moneyOrOutcome(_ text: String, code: (Double, String) -> FinancialPhraseLane.Outcome)
            -> FinancialPhraseLane.Outcome? {
            switch money(text) {
            case .money(let value, let currency):
                return code(value, currency)
            case .none:
                return nil
            case .ratesUnavailable:
                return .error("Rates unavailable")
            case .malformed:
                return .error("Invalid financial expression")
            }
        }

        func yearError(_ year: Int) -> FinancialPhraseLane.Outcome {
            .error("no CPI data for \(year)")
        }

        func ratio(sourceYear: Int, targetYear: Int, amount: Double,
                   currency: String) -> FinancialPhraseLane.Outcome {
            guard let source = catalog.index(for: sourceYear) else {
                return yearError(sourceYear)
            }
            guard let target = catalog.index(for: targetYear) else {
                return yearError(targetYear)
            }
            guard source > 0 else { return .error("Invalid financial expression") }
            let value = amount * target / source
            guard value.isFinite else { return .error("Invalid financial expression") }
            return .result(.money(value: value, code: currency))
        }

        // 10. `what will <money> be worth in <futureYear> at|assuming R% [inflation]`.
        if lower.hasPrefix("what will "),
           let worthRange = trimmed.range(of: " be worth in ", options: .caseInsensitive) {
            let afterPrefix = trimmed.index(trimmed.startIndex,
                                            offsetBy: "what will ".count)
            let moneyText = String(trimmed[afterPrefix..<worthRange.lowerBound])
            let rest = String(trimmed[worthRange.upperBound...])
            guard let (year, rateText) = splitFutureYearAndRate(rest) else {
                return .error("Invalid financial expression")
            }
            return moneyOrOutcome(moneyText) { amount, currency in
                guard year > snapshotYear else {
                    return .error("Invalid financial expression")
                }
                guard let rateText else {
                    // A future target without an explicit rate is strict.
                    return .error("Invalid financial expression")
                }
                guard let rate = FinancialPhraseLane.parsePercent(rateText,
                                                                  context: context) else {
                    return .error("Invalid financial expression")
                }
                let base = 1 + rate
                let years = Double(year - snapshotYear)
                guard base > 0, base.isFinite, years > 0, years <= 1000 else {
                    return .error("Invalid financial expression")
                }
                let factor = pow(base, years)
                guard factor.isFinite, factor > 0 else {
                    return .error("Invalid financial expression")
                }
                let value = amount / factor
                guard value.isFinite else { return .error("Invalid financial expression") }
                return .result(.money(value: value, code: currency))
            }
        }

        // 8. `what is <money> in <y1> worth in <y2>`.
        if lower.hasPrefix("what is "),
           let worthRange = trimmed.range(of: " worth in ", options: .caseInsensitive) {
            let afterPrefix = trimmed.index(trimmed.startIndex, offsetBy: "what is ".count)
            let before = trimmed[afterPrefix..<worthRange.lowerBound]
            guard let inRange = before.range(of: " in ", options: [.backwards, .caseInsensitive]),
                  let y1 = parseYear(String(before[inRange.upperBound...])),
                  let y2 = parseYear(String(trimmed[worthRange.upperBound...])) else {
                return nil
            }
            let moneyText = String(before[before.startIndex..<inRange.lowerBound])
            return moneyOrOutcome(moneyText) { amount, currency in
                ratio(sourceYear: y1, targetYear: y2, amount: amount, currency: currency)
            }
        }

        // 9. `<money> from <y1> is worth what in <y2>`.
        if let fromRange = lower.range(of: " from "),
           let worthWhat = lower.range(of: " is worth what in ") {
            let moneyText = String(trimmed[trimmed.startIndex..<fromRange.lowerBound])
            let y1Text = String(trimmed[fromRange.upperBound..<worthWhat.lowerBound])
            let y2Text = String(trimmed[worthWhat.upperBound...])
            if let y1 = parseYear(y1Text), let y2 = parseYear(y2Text) {
                return moneyOrOutcome(moneyText) { amount, currency in
                    ratio(sourceYear: y1, targetYear: y2, amount: amount,
                          currency: currency)
                }
            }
        }

        // 3. `what was <money> worth in <year>`.
        if lower.hasPrefix("what was "),
           let worthIn = trimmed.range(of: " worth in ", options: .caseInsensitive) {
            let afterPrefix = trimmed.index(trimmed.startIndex, offsetBy: "what was ".count)
            let moneyText = String(trimmed[afterPrefix..<worthIn.lowerBound])
            guard let year = parseYear(String(trimmed[worthIn.upperBound...])) else {
                return nil
            }
            return moneyOrOutcome(moneyText) { amount, currency in
                ratio(sourceYear: snapshotYear, targetYear: year, amount: amount,
                      currency: currency)
            }
        }

        // 4. `value of <money> in <year>`.
        if lower.hasPrefix("value of "),
           let inRange = trimmed.range(of: " in ", options: [.backwards, .caseInsensitive]) {
            let afterPrefix = trimmed.index(trimmed.startIndex, offsetBy: "value of ".count)
            let moneyText = String(trimmed[afterPrefix..<inRange.lowerBound])
            guard let year = parseYear(String(trimmed[inRange.upperBound...])) else {
                return nil
            }
            return moneyOrOutcome(moneyText) { amount, currency in
                ratio(sourceYear: snapshotYear, targetYear: year, amount: amount,
                      currency: currency)
            }
        }

        // 5. `<money> is worth what in <year>`.
        if let worthWhat = trimmed.range(of: " is worth what in ", options: .caseInsensitive) {
            let moneyText = String(trimmed[trimmed.startIndex..<worthWhat.lowerBound])
            guard let year = parseYear(String(trimmed[worthWhat.upperBound...])) else {
                return nil
            }
            return moneyOrOutcome(moneyText) { amount, currency in
                ratio(sourceYear: snapshotYear, targetYear: year, amount: amount,
                      currency: currency)
            }
        }

        // 1/2. `what is <money> from <year>` / `value of <money> from <year>`.
        for prefix in ["what is ", "value of "] {
            guard lower.hasPrefix(prefix),
                  let fromRange = trimmed.range(of: " from ", options: [.backwards, .caseInsensitive]) else {
                continue
            }
            let afterPrefix = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let moneyText = String(trimmed[afterPrefix..<fromRange.lowerBound])
            guard let year = parseYear(String(trimmed[fromRange.upperBound...])) else {
                return nil
            }
            return moneyOrOutcome(moneyText) { amount, currency in
                ratio(sourceYear: year, targetYear: snapshotYear, amount: amount,
                      currency: currency)
            }
        }

        // 6. `<money> from <year> worth [what today]`.
        if let fromRange = trimmed.range(of: " from ", options: .caseInsensitive),
           let worthRange = trimmed.range(of: " worth", options: [.backwards, .caseInsensitive]) {
            let moneyText = String(trimmed[trimmed.startIndex..<fromRange.lowerBound])
            let yearText = String(trimmed[fromRange.upperBound..<worthRange.lowerBound])
            let tail = String(trimmed[worthRange.upperBound...])
                .trimmingCharacters(in: .whitespaces).lowercased()
            if tail.isEmpty || tail == "what today" || tail == "today" || tail == "what" {
                guard let year = parseYear(yearText) else { return nil }
                return moneyOrOutcome(moneyText) { amount, currency in
                    ratio(sourceYear: year, targetYear: snapshotYear, amount: amount,
                          currency: currency)
                }
            }
        }

        // 7. `<money> in <year> dollars`.
        if lower.hasSuffix(" dollars") {
            let before = trimmed.dropLast(" dollars".count)
            guard let inRange = before.range(of: " in ", options: [.backwards, .caseInsensitive]),
                  let year = parseYear(String(before[inRange.upperBound...])) else {
                return nil
            }
            let moneyText = String(before[before.startIndex..<inRange.lowerBound])
            return moneyOrOutcome(moneyText) { amount, currency in
                ratio(sourceYear: year, targetYear: snapshotYear, amount: amount,
                      currency: currency)
            }
        }

        _ = decimalPlaces
        return nil
    }

    // MARK: helpers

    /// `<year> at R% [inflation]` or `<year> assuming|with R% inflation`.
    private static func splitFutureYearAndRate(_ text: String)
        -> (year: Int, rate: String?)? {
        let tokens = text.split(whereSeparator: { $0 == " " }).map(String.init)
        guard let first = tokens.first, let year = parseYear(first) else { return nil }
        guard tokens.count > 1 else { return (year, nil) }
        let lowered = tokens.map { $0.lowercased() }
        if ["at", "assuming", "with"].contains(lowered[1]), tokens.count >= 3 {
            return (year, tokens[2])
        }
        return (year, nil)
    }

    /// A strict 4-digit year token.
    static func parseYear(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 4, trimmed.allSatisfy({ $0.isNumber }),
              let year = Int(trimmed) else { return nil }
        return year
    }
}
