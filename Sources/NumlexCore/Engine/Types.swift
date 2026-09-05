import Foundation

/// A validated currency rate table: a base ISO code plus `rates` giving
/// UNITS of each code PER ONE UNIT of the base code.
///
/// `rate(from:to:)` is an O(1) division of two table entries
/// (`rates[to] / rates[from]`) and returns nil whenever either code is
/// missing or either entry is not a positive finite number — the
/// conversion layer turns that nil into the generic "Rates unavailable"
/// error, so a bad table can never leak a non-finite value.
///
/// The old per-pair format (`{"USD": 90, "EUR": 100, "EURUSD": 1.1}`)
/// is still decoded for stored files and migrated to a consistent
/// USD-based table.
public struct Rates: Codable, Equatable, Sendable {
    public var base: String
    public var rates: [String: Double]

    public init(base: String = FiatCurrencies.defaultBase,
                rates: [String: Double] = [:]) {
        self.base = base
        self.rates = rates
    }

    /// Units of `to` per one unit of `from`, or nil when the table
    /// cannot answer the pair (missing code or non-positive/non-finite
    /// entry).
    public func rate(from: String, to: String) -> Double? {
        guard from != to else { return 1 }
        guard let f = rates[from], let t = rates[to] else { return nil }
        guard f.isFinite, t.isFinite, f > 0, t > 0 else { return nil }
        return t / f
    }

    public var isEmpty: Bool { rates.isEmpty }

    // MARK: Decoding (new format + legacy migration)

    private enum Keys: String, CodingKey {
        case base, rates
        case USD, EUR, EURUSD
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if c.allKeys.contains(.base) || c.allKeys.contains(.rates) {
            self.base = try c.decodeIfPresent(String.self, forKey: .base)
                ?? FiatCurrencies.defaultBase
            self.rates = try c.decodeIfPresent([String: Double].self, forKey: .rates) ?? [:]
        } else {
            // Legacy per-pair table: `USD` = RUB per USD, `EURUSD` = EUR
            // per USD, `EUR` = RUB per EUR. The old triple was not
            // transitively consistent (90/1.1 != 100), so the migration
            // keeps the two USD legs and derives EUR<->RUB from them;
            // the direct `EUR` leg is dropped. Live tables are
            // consistent, and a refresh replaces the migrated table.
            let usd = try c.decodeIfPresent(Double.self, forKey: .USD)
            let eurUSD = try c.decodeIfPresent(Double.self, forKey: .EURUSD)
            var table: [String: Double] = [:]
            if let usd, usd.isFinite, usd > 0 { table["USD"] = 1; table["RUB"] = usd }
            if let eurUSD, eurUSD.isFinite, eurUSD > 0 { table["EUR"] = eurUSD }
            self.base = FiatCurrencies.defaultBase
            self.rates = table
        }
    }
}

/// One evaluated logical line: its explicit 0-based index into
/// `source.components(separatedBy: "\n")` plus its result. `evaluateSheet`
/// returns exactly one SheetLine per logical line — leading, consecutive
/// and trailing blanks and `#` comments are `.blank`, so consumers can
/// bind rendered output to the exact editor line instead of to a
/// position after filtering.
public enum LineResult: Equatable, Sendable {
    case blank
    case skip
    case title(String)
    case number(value: Double, unit: String?)
    case variable(name: String, value: Double)
    /// A natural money line (`$3k earnings ÷ 5 people`, `lunch was $55
    /// + 25% tip`): the value carries full engine precision and an ISO
    /// currency code; the display is the shared money presentation
    /// (`$600.00`), never `600 USD`. Money results never enter the
    /// numeric Total and never mix across currencies.
    case money(value: Double, code: String)
    /// A date answer (`May 5 + 43 days`): component form, never a
    /// Double and never tokenized as a number. Display is compact
    /// English (`Jun 17`, year added when explicit or crossed).
    case date(year: Int, month: Int, day: Int, showYear: Bool)
    /// A line that is ONLY an inactive reference token (its source line
    /// was deleted or stopped evaluating to a number/variable). The token
    /// stays in place in the editor; the line displays the remembered
    /// `Line <line>` label. Dependent expressions instead yield a generic
    /// hidden error — never a stale snapshot.
    case brokenToken(line: Int)
    case error(message: String)
}

public struct SheetLine: Equatable, Sendable {
    public var sourceLineIndex: Int
    public var result: LineResult
    /// r57: derived presentation flag for an evaluated inline `total`
    /// command row (successful `.number` only). The answer renders
    /// semibold with a gray rule above it and is excluded from the
    /// bottom summary sum. Defaulted so every existing constructor
    /// call stays source-compatible; never persisted to the store or
    /// to `.nlx` — each pass re-derives it from the sheet text.
    public var isTotal: Bool = false
    public init(sourceLineIndex: Int, result: LineResult, isTotal: Bool = false) {
        self.sourceLineIndex = sourceLineIndex
        self.result = result
        self.isTotal = isTotal
    }
}
