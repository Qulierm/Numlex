import Foundation

// MARK: - Financial phrase lane (Package 2)
//
// ONE strict typed phrase architecture for the financial forms. It
// dispatches BEFORE the generic money/word-stripping paths, owns only
// the exact shapes below, and never touches `neutralWords`:
//
//   Investments (Task 1)
//     <money> after N years at R% [compounding monthly|quarterly|daily|annually]
//     <money> for N years at R% ...
//     interest on <money> after|for N years at|@ R% [...]
//     <money> invested <money2> returned
//     annual return on <money> invested <money2> returned after N years
//     present value of <money> after|for N years at|@ R% [...]
//
//   Loans (Task 2)
//     daily|monthly|annual repayment on <money> over N years at R%
//     daily|monthly|annual interest on <money> over N years at R%
//     total repayment on <money> over N years at R%
//     total interest on <money> over N years at R%
//
// Money operands resolve through the SAME money core as ordinary lines
// (markers, ISO codes, named typed money); the token path passes a
// resolver that maps marker operands to their resolved quantities. All
// formulas are bounded, checked for finiteness and never round an
// intermediate (currency minor digits are display-only).

enum FinancialPhraseLane {

    enum Outcome {
        case result(LineResult)
        case error(String)
        case notMine
    }

    enum MoneyResolution: Equatable {
        case money(value: Double, code: String)
        case ratesUnavailable
        case malformed
        case none
    }

    /// The operand text plus its UTF-16 offset in the line (the token
    /// path maps markers by their exact position).
    typealias MoneyResolver = (String, Int) -> MoneyResolution

    // MARK: bounds

    static let maxLength = 160
    static let maxYears = 1000.0
    static let maxPeriods = 400_000.0
    static let maxRatePercent = 1000.0

    // MARK: entry

    static func tryLine(_ line: String,
                        env: TypedEnv,
                        rates: Rates,
                        context: NumberFormatContext,
                        unitContext: UnitContext,
                        financial: FinancialContext,
                        decimalPlaces: Int,
                        resolver: MoneyResolver? = nil) -> Outcome {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= maxLength else { return .notMine }
        let resolve = resolver ?? environmentResolver(env: env, context: context,
                                                      rates: rates)
        // Task 3 owns tax phrases and runs after the investment/loan
        // heads so `interest on` never collides with a tax name.
        if let loan = loanShape(trimmed, resolve: resolve, context: context) { return loan }
        if let investment = investmentShape(trimmed, resolve: resolve,
                                            context: context) { return investment }
        if let tax = TaxPhraseLane.tryLine(trimmed, env: env, rates: rates,
                                           context: context, financial: financial,
                                           decimalPlaces: decimalPlaces,
                                           resolver: resolver) { return tax }
        if let income = IncomeTaxPhraseLane.tryLine(trimmed, env: env, rates: rates,
                                                    context: context,
                                                    financial: financial,
                                                    resolver: resolver) { return income }
        if let cpi = CPIPhraseLane.tryLine(trimmed, env: env, rates: rates,
                                           context: context,
                                           financial: financial,
                                           decimalPlaces: decimalPlaces,
                                           resolver: resolver) { return cpi }
        return .notMine
    }

    /// The environment-backed money resolver: a WHOLE-operand named typed
    /// money value is valid by construction here (the phrase grammar
    /// proved it is an operand), even though a bare name line would not
    /// be expression-shaped on its own; everything else goes through the
    /// ONE shared money core.
    static func environmentResolver(env: TypedEnv, context: NumberFormatContext,
                                    rates: Rates) -> MoneyResolver {
        { text, _ in
            let nameMatches = NamedValues.matches(in: text, env: env)
            let nsLen = (text as NSString).length
            if nameMatches.count == 1,
               nameMatches[0].range == NSRange(location: 0, length: nsLen),
               case .money(let v, let c) = nameMatches[0].entry.qty, v.isFinite {
                return .money(value: v, code: c.uppercased())
            }
            switch NaturalCalculation.moneyOutcome(text, env: env, context: context,
                                                   rates: rates) {
            case .money(let v, let c): return .money(value: v, code: c)
            case .ratesUnavailable: return .ratesUnavailable
            case .malformed: return .malformed
            case .none: return .none
            }
        }
    }

    // MARK: investment shapes (Task 1)

    private static func investmentShape(_ line: String, resolve: MoneyResolver,
                                        context: NumberFormatContext) -> Outcome? {
        let lower = line.lowercased()

        // `interest on <money> <tail>` / `present value of <money> <tail>`.
        for (prefix, kind) in [("interest on ", InvestmentKind.interest),
                               ("present value of ", InvestmentKind.presentValue)] {
            guard lower.hasPrefix(prefix) else { continue }
            let body = String(line.dropFirst(prefix.count))
            guard let split = splitAtTail(body) else { return .error("Invalid financial expression") }
            let resolution = resolve(split.operand, prefix.count + split.offset)
            guard case .money(let value, let code) = resolution else {
                return resolutionOutcome(resolution, fallback: .notMine)
            }
            guard let tail = parseYearsTail(split.tail, context: context) else {
                return .error("Invalid financial expression")
            }
            switch kind {
            case .interest:
                guard let result = computeFutureValue(principal: value, tail: tail) else {
                    return .error("Invalid financial expression")
                }
                return .result(.money(value: result - value, code: code))
            case .presentValue:
                guard let present = computePresentValue(futureValue: value, tail: tail) else {
                    return .error("Invalid financial expression")
                }
                return .result(.money(value: present, code: code))
            }
        }

        // `annual return on <money> invested <money2> returned after N years`.
        if lower.hasPrefix("annual return on ") {
            let headLength = "annual return on ".count
            let body = String(line.dropFirst(headLength))
            return cagrShape(body, offsetBase: headLength, resolve: resolve,
                             context: context)
        }

        // `<money> invested <money2> returned` (ROI).
        if let roi = roiShape(line, resolve: resolve) { return roi }

        // `<money> after|for <tail>` (future value).
        if let split = splitAtTail(line) {
            switch resolve(split.operand, split.offset) {
            case .money(let value, let code):
                guard let tail = parseYearsTail(split.tail, context: context) else {
                    return .error("Invalid financial expression")
                }
                guard let result = computeFutureValue(principal: value, tail: tail) else {
                    return .error("Invalid financial expression")
                }
                return .result(.money(value: result, code: code))
            case .ratesUnavailable:
                return .error("Rates unavailable")
            case .malformed:
                return .error("Invalid financial expression")
            case .none:
                return nil
            }
        }
        return nil
    }

    private enum InvestmentKind { case interest, presentValue }

    /// `<money> invested <money2> returned` -> ROI multiplier.
    private static func roiShape(_ line: String, resolve: MoneyResolver) -> Outcome? {
        guard let investedRange = line.range(of: " invested ", options: .caseInsensitive),
              let returnedRange = line.range(of: " returned", options: .caseInsensitive),
              investedRange.upperBound <= returnedRange.lowerBound else { return nil }
        let rawLeft = String(line[line.startIndex..<investedRange.lowerBound])
        let rawRight = String(line[investedRange.upperBound..<returnedRange.lowerBound])
        let left = rawLeft.trimmingCharacters(in: .whitespaces)
        let right = rawRight.trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        let leftOffset = rawLeft.prefix { $0 == " " || $0 == "\t" }.count
        let rightOffset = (line.distance(from: line.startIndex,
                                         to: investedRange.upperBound)
                           + rawRight.prefix { $0 == " " || $0 == "\t" }.count)
        // The whole line must be exactly this shape (no tail after
        // `returned`); the annual-return form carries the tail and is
        // handled above.
        let tail = String(line[returnedRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard tail.isEmpty else { return nil }
        let invested = resolve(left, leftOffset)
        let returned = resolve(right, rightOffset)
        guard case .money(let p, let code) = invested,
              case .money(let f, let fCode) = returned else {
            for resolution in [invested, returned] {
                if case .ratesUnavailable = resolution { return .error("Rates unavailable") }
            }
            return nil
        }
        guard p > 0, code == fCode else {
            if code != fCode { return .error("Rates unavailable") }
            return .error("Invalid financial expression")
        }
        let roi = (f - p) / p
        guard roi.isFinite else { return .error("Invalid financial expression") }
        return .result(.number(value: roi, unit: nil, kind: .multiplier, fraction: nil))
    }

    /// `annual return on <money> invested <money2> returned after N years`.
    private static func cagrShape(_ body: String, offsetBase: Int,
                                  resolve: MoneyResolver,
                                  context: NumberFormatContext) -> Outcome {
        guard let investedRange = body.range(of: " invested ", options: .caseInsensitive),
              let returnedRange = body.range(of: " returned", options: .caseInsensitive),
              investedRange.upperBound <= returnedRange.lowerBound else {
            return .error("Invalid financial expression")
        }
        let rawLeft = String(body[body.startIndex..<investedRange.lowerBound])
        let rawRight = String(body[investedRange.upperBound..<returnedRange.lowerBound])
        let left = rawLeft.trimmingCharacters(in: .whitespaces)
        let right = rawRight.trimmingCharacters(in: .whitespaces)
        let tail = String(body[returnedRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let leftOffset = offsetBase + rawLeft.prefix { $0 == " " || $0 == "\t" }.count
        let rightOffset = offsetBase + body.distance(from: body.startIndex,
                                                     to: investedRange.upperBound)
            + rawRight.prefix { $0 == " " || $0 == "\t" }.count
        let leftResolution = resolve(left, leftOffset)
        let rightResolution = resolve(right, rightOffset)
        guard case .money(let p, let code) = leftResolution,
              case .money(let f, let fCode) = rightResolution else {
            if case .ratesUnavailable = leftResolution { return .error("Rates unavailable") }
            if case .ratesUnavailable = rightResolution { return .error("Rates unavailable") }
            return .error("Invalid financial expression")
        }
        guard p > 0, f > 0, code == fCode else {
            if code != fCode { return .error("Rates unavailable") }
            return .error("Invalid financial expression")
        }
        // `after N years` tail.
        let lowerTail = tail.lowercased()
        let prefix = "after "
        guard lowerTail.hasPrefix(prefix) else { return .error("Invalid financial expression") }
        let yearsText = String(tail.dropFirst(prefix.count))
        guard let years = parseYearCount(yearsText, context: context) else {
            return .error("Invalid financial expression")
        }
        let ratio = f / p
        let cagr = pow(ratio, 1.0 / years) - 1
        guard cagr.isFinite, ratio > 0 else { return .error("Invalid financial expression") }
        return .result(.number(value: cagr, unit: nil, kind: .percent, fraction: nil))
    }

    // MARK: loan shapes (Task 2)

    private enum LoanFrequency: String {
        case daily, monthly, annual
        var periodsPerYear: Double {
            switch self {
            case .daily: return 365
            case .monthly: return 12
            case .annual: return 1
            }
        }
        var displayName: String { rawValue }
    }

    private static func loanShape(_ line: String, resolve: MoneyResolver,
                                  context: NumberFormatContext) -> Outcome? {
        let lower = line.lowercased()
        let heads: [(String, LoanRequest)] = [
            ("daily repayment on ", .repayment(.daily)),
            ("monthly repayment on ", .repayment(.monthly)),
            ("annual repayment on ", .repayment(.annual)),
            ("daily interest on ", .interest(.daily)),
            ("monthly interest on ", .interest(.monthly)),
            ("annual interest on ", .interest(.annual)),
            ("total repayment on ", .totalRepayment),
            ("total interest on ", .totalInterest),
        ]
        for (head, request) in heads {
            guard lower.hasPrefix(head) else { continue }
            let body = String(line.dropFirst(head.count))
            guard let split = splitOverTail(body) else {
                return .error("Invalid financial expression")
            }
            let principalResolution = resolve(split.operand, head.count + split.offset)
            guard case .money(let principal, let code) = principalResolution else {
                if case .ratesUnavailable = principalResolution {
                    return .error("Rates unavailable")
                }
                return .error("Invalid financial expression")
            }
            guard let terms = parseLoanTerms(split.tail, context: context) else {
                return .error("Invalid financial expression")
            }
            guard let schedule = amortization(principal: principal, terms: terms) else {
                return .error("Invalid financial expression")
            }
            let value: Double
            switch request {
            case .repayment(let f):
                value = schedule.total / (f.periodsPerYear * terms.years)
            case .interest(let f):
                value = schedule.totalInterest / (f.periodsPerYear * terms.years)
            case .totalRepayment:
                value = schedule.total
            case .totalInterest:
                value = schedule.totalInterest
            }
            guard value.isFinite else { return .error("Invalid financial expression") }
            return .result(.money(value: value, code: code))
        }
        return nil
    }

    private enum LoanRequest {
        case repayment(LoanFrequency)
        case interest(LoanFrequency)
        case totalRepayment
        case totalInterest
    }

    struct LoanTerms {
        var years: Double
        /// The entered annual rate as a FRACTION (0.06 for 6%).
        var annualRate: Double
    }

    struct LoanSchedule {
        var monthlyPayment: Double
        var total: Double
        var totalInterest: Double
    }

    /// ONE monthly amortization schedule for every requested frequency:
    /// rm = annualRate/12, nm = 12*years, pmt = P*rm/(1-(1+rm)^-nm)
    /// (zero rate: P/nm), total = pmt*nm. A requested daily/annual
    /// repayment divides that total by the requested period count — it
    /// is NEVER an independent daily/annual amortization.
    static func amortization(principal: Double, terms: LoanTerms) -> LoanSchedule? {
        guard principal.isFinite, terms.years > 0, terms.years <= maxYears,
              terms.annualRate.isFinite, terms.annualRate < 1.0 else { return nil }
        let nm = 12.0 * terms.years
        guard nm.isFinite, nm > 0, nm <= maxPeriods * 12 else { return nil }
        let rm = terms.annualRate / 12.0
        let payment: Double
        if rm == 0 {
            payment = principal / nm
        } else {
            let base = pow(1 + rm, -nm)
            guard base.isFinite, 1 - base != 0 else { return nil }
            payment = principal * rm / (1 - base)
        }
        let total = payment * nm
        guard payment.isFinite, total.isFinite else { return nil }
        return LoanSchedule(monthlyPayment: payment, total: total,
                            totalInterest: total - principal)
    }

    private static func parseLoanTerms(_ tail: String, context: NumberFormatContext)
        -> LoanTerms? {
        // The `over` separator was already consumed: `N years at|@ R%`.
        let body = tail.trimmingCharacters(in: .whitespaces)
        var range = body.range(of: " years ", options: .caseInsensitive)
        if range == nil {
            range = body.range(of: " year ", options: .caseInsensitive)
        }
        guard let split = range else { return nil }
        let yearsText = String(body[body.startIndex..<split.lowerBound])
        let rest = String(body[split.upperBound...])
        guard let years = parseYearCount(yearsText + " years", context: context) else {
            return nil
        }
        guard let rate = parseRateTail(rest, context: context) else { return nil }
        return LoanTerms(years: years, annualRate: rate)
    }

    private static func splitOverTail(_ body: String)
        -> (operand: String, offset: Int, tail: String)? {
        guard let range = body.range(of: " over ", options: .caseInsensitive) else { return nil }
        let rawOperand = String(body[body.startIndex..<range.lowerBound])
        let operand = rawOperand.trimmingCharacters(in: .whitespaces)
        let tail = String(body[range.upperBound...])
        guard !operand.isEmpty else { return nil }
        let leading = rawOperand.prefix { $0 == " " || $0 == "\t" }.count
        return (operand, leading, tail)
    }

    // MARK: future value (Task 1)

    struct YearsTail {
        var years: Double
        /// The annual rate as a FRACTION.
        var annualRate: Double
        var periodsPerYear: Double
    }

    static func computeFutureValue(principal: Double, tail: YearsTail) -> Double? {
        guard let factor = compoundFactor(tail) else { return nil }
        let value = principal * factor
        guard value.isFinite else { return nil }
        return value
    }

    /// The compound factor `(1+R/m)^(m*y)` with the full domain/bound
    /// checks (a negative base with a fractional exponent is a strict
    /// domain rejection, never a fabricated NaN).
    static func compoundFactor(_ tail: YearsTail) -> Double? {
        guard tail.years > 0, tail.years <= maxYears,
              tail.annualRate.isFinite, abs(tail.annualRate) <= maxRatePercent / 100,
              tail.periodsPerYear > 0, tail.periodsPerYear <= 366 else { return nil }
        let m = tail.periodsPerYear
        guard tail.years * m <= maxPeriods else { return nil }
        let base = 1 + tail.annualRate / m
        let exponent = m * tail.years
        guard base.isFinite, exponent.isFinite else { return nil }
        if base == 0 {
            // 0^(positive) is 0; 0^0 is outside the useful domain.
            guard exponent > 0 else { return nil }
            return 0
        }
        if base < 0, exponent != exponent.rounded() { return nil }
        let factor = pow(base, exponent)
        guard factor.isFinite, factor >= 0 else { return nil }
        return factor
    }

    /// `PV = FV / (1+R/m)^(m*y)` (the exact inverse of the future-value
    /// factor; a zero factor is rejected).
    static func computePresentValue(futureValue: Double, tail: YearsTail) -> Double? {
        guard let factor = compoundFactor(tail), factor > 0 else { return nil }
        let value = futureValue / factor
        guard value.isFinite else { return nil }
        return value
    }

    /// `<N> years at|@ <R>% [compounding <freq>]`.
    static func parseYearsTail(_ text: String, context: NumberFormatContext) -> YearsTail? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let tokens = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard tokens.count >= 4 else { return nil }
        // `<N> years`
        guard tokens[1].lowercased() == "years" || tokens[1].lowercased() == "year" else {
            return nil
        }
        guard let years = parseYearCount(tokens[0], context: context) else { return nil }
        // `at|@ R%`
        var idx = 2
        let connector = tokens[idx].lowercased()
        guard connector == "at" || connector == "@" else { return nil }
        idx += 1
        guard idx < tokens.count, let rate = parsePercent(tokens[idx], context: context) else {
            return nil
        }
        idx += 1
        var periods = 1.0
        if idx < tokens.count {
            let word = tokens[idx].lowercased()
            guard word == "compounding" || word == "compounded" else { return nil }
            idx += 1
            guard idx < tokens.count else { return nil }
            switch tokens[idx].lowercased() {
            case "annually", "annual": periods = 1
            case "quarterly", "quarter": periods = 4
            case "monthly", "month": periods = 12
            case "daily", "day": periods = 365
            default: return nil
            }
            idx += 1
        }
        guard idx == tokens.count else { return nil }
        return YearsTail(years: years, annualRate: rate, periodsPerYear: periods)
    }

    /// `<N> years` (the loan/CAGR tail).
    static func parseYearCount(_ text: String, context: NumberFormatContext) -> Double? {
        var body = text.trimmingCharacters(in: .whitespaces).lowercased()
        for suffix in [" years", " year"] {
            if body.hasSuffix(suffix) {
                body = String(body.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        guard let years = parseNumber(body, context: context),
              years.isFinite, years > 0, years <= maxYears else { return nil }
        return years
    }

    /// `R%` -> the fraction (7 -> 0.07).
    static func parsePercent(_ text: String, context: NumberFormatContext) -> Double? {
        var body = text.trimmingCharacters(in: .whitespaces)
        guard body.hasSuffix("%") else { return nil }
        body = String(body.dropLast())
        guard let percent = parseNumber(body, context: context),
              percent.isFinite, abs(percent) <= maxRatePercent else { return nil }
        return percent / 100
    }

    /// `at|@ R%` (the rate tail after `years`).
    static func parseRateTail(_ text: String, context: NumberFormatContext) -> Double? {
        let tokens = text.trimmingCharacters(in: .whitespaces)
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .map(String.init)
        guard tokens.count == 2, ["at", "@"].contains(tokens[0].lowercased()) else {
            return nil
        }
        return parsePercent(tokens[1], context: context)
    }

    // MARK: shared helpers

    /// Split `<money> after|for <tail>` at the LAST tail keyword whose
    /// left side resolves to money; the FIRST keyword boundary is used
    /// for strictness (a money operand never contains these words).
    static func splitAtTail(_ body: String)
        -> (operand: String, offset: Int, tail: String)? {
        let lower = body.lowercased()
        for keyword in [" after ", " for "] {
            guard let range = lower.range(of: keyword) else { continue }
            let rawOperand = String(body[body.startIndex..<range.lowerBound])
            let operand = rawOperand.trimmingCharacters(in: .whitespaces)
            let leading = rawOperand.prefix { $0 == " " || $0 == "\t" }.count
            let tail = String(body[range.upperBound...])
            guard !operand.isEmpty, !tail.trimmingCharacters(in: .whitespaces).isEmpty else {
                continue
            }
            return (operand, leading, tail)
        }
        return nil
    }

    private static func resolutionOutcome(_ resolution: MoneyResolution,
                                          fallback: Outcome) -> Outcome {
        switch resolution {
        case .ratesUnavailable: return .error("Rates unavailable")
        case .malformed: return .error("Invalid financial expression")
        case .none: return fallback
        case .money: return fallback
        }
    }

    /// A strict decimal literal honoring the active regional separators
    /// (grouping stripped; a decimal comma is accepted in comma modes).
    static func parseNumber(_ raw: String, context: NumberFormatContext) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
        var text = trimmed
        if context.decimalComma {
            if !context.groupingSeparator.isEmpty {
                text = text.replacingOccurrences(of: context.groupingSeparator, with: "")
            }
            text = text.replacingOccurrences(of: ",", with: ".")
        } else {
            text = text.replacingOccurrences(of: ",", with: "")
        }
        guard text.range(of: #"^[+-]?(\d+(\.\d*)?|\.\d+)$"#,
                         options: .regularExpression) != nil else { return nil }
        return Double(text)
    }

    /// The public entry used by `evalLineTyped` (fixed parameter order).
    static func tryLine(_ line: String,
                        env: TypedEnv,
                        rates: Rates,
                        context: NumberFormatContext,
                        unitContext: UnitContext,
                        financial: FinancialContext) -> Outcome {
        tryLine(line, env: env, rates: rates, context: context,
                unitContext: unitContext, financial: financial,
                decimalPlaces: 10, resolver: nil)
    }
}
