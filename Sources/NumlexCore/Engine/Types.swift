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

/// r83: the semantic KIND of a numeric quantity. The raw value is
/// ALWAYS the canonical one: a percent stores its RATIO (`40%` stores
/// 0.4 and renders/copies as `40%`), a multiplier stores its FACTOR
/// (`1.5x` stores 1.5), a fraction stores its reduced rational plus
/// the numeric value. Kinds are presentation + propagation metadata:
/// they never change the arithmetic value, they travel through
/// assignments, conditionals, tokens and totals (raw value), and they
/// drive display/copy and the contextual-percentage rules.
public enum NumericKind: Equatable, Sendable {
    /// An ordinary number (`123`, `200 × 10%` = 20, `2/3 of 600` = 400).
    case plain
    /// A percentage ratio: raw 0.4 renders and copies as `40%`.
    case percent
    /// A fraction: renders/copies as the reduced `numerator/denominator`.
    case fraction
    /// A multiplier factor: raw 1.5 renders and copies as `1.5x`.
    case multiplier
    /// A natural compound duration (`1 h 30 min`). The value and the
    /// unit stay ordinary quantity data — this kind only selects the
    /// natural decomposition for the visible answer and its copy.
    case duration
    /// temporal Task 3: an EXPLICIT `as timespan` duration. Like
    /// `.duration`, the value and unit stay ordinary quantity data, but
    /// the presentation is the timespan formatter (average yr/mo,
    /// pluralized full words for hour-or-larger roots) independent of
    /// the global notation. Selecting the global/per-line Timespan
    /// NOTATION on a time quantity produces the same text without
    /// changing the kind.
    case timespan
    /// temporal Task 4: seconds produced by the video-timecode lane
    /// (`15.6k frames / 24 fps` -> `650 s`). Renders as an ordinary
    /// single-unit quantity, but — like every timecode result — it is
    /// EXCLUDED from both totals and the numeric previous-answer chain.
    case timecodeSeconds
}

/// r83: one reduced rational. The reduction is DETERMINISTIC: the
/// denominator is always positive, the sign rides on the numerator,
/// and both parts share no common factor (GCD). `0` is the canonical
/// `0/1`. Simple integer values keep their exact form (`4` = 4/1);
/// decimal approximations are bounded by `fromDouble` (denominator
/// <= 1,000,000 with an explicit tolerance) so overflow never traps.
public struct Rational: Equatable, Sendable {
    public var numerator: Int64
    /// Always positive (1 for zero and integers).
    public var denominator: Int64

    public init(numerator: Int64, denominator: Int64) {
        self.numerator = numerator
        self.denominator = denominator
    }

    /// The canonical zero.
    public static let zero = Rational(numerator: 0, denominator: 1)

    /// The exact numeric value (never NaN/inf: denominators are
    /// positive and bounded, numerators are finite Int64).
    public var value: Double {
        Double(numerator) / Double(denominator)
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var x = a < 0 ? -a : a
        var y = b < 0 ? -b : b
        while y != 0 {
            let t = x % y
            x = y
            y = t
        }
        return x
    }

    /// Reduces `num/den` to canonical form (denominator > 0, sign on
    /// the numerator, GCD-reduced). Nil for a zero denominator or a
    /// non-representable extreme (overflow during sign flip/GCD).
    public static func reduce(numerator: Int64, denominator: Int64) -> Rational? {
        guard denominator != 0 else { return nil }
        var num = numerator
        var den = denominator
        if den < 0 {
            // Flipping both signs: `-Int64.min` overflows.
            if num == Int64.min { return nil }
            num = -num
            den = -den
        }
        let absNum: Int64
        if num == Int64.min { return nil }  // |Int64.min| overflows
        else { absNum = num < 0 ? -num : num }
        let g = absNum == 0 ? den : Self.gcd(absNum, den)
        guard g > 0 else { return nil }
        return Rational(numerator: num / g, denominator: den / g)
    }

    /// The bounded rational approximation of a finite `value`: the
    /// best `p/q` with `q <= maxDenominator` within the explicit
    /// relative tolerance. Exact integers stay exact; zero is the
    /// canonical `0/1`; non-finite input and out-of-bounds values are
    /// nil (the caller keeps the plain presentation).
    public static func fromDouble(
        _ value: Double,
        maxDenominator: Int64 = 1_000_000,
        tolerance: Double = 1e-9
    ) -> Rational? {
        guard value.isFinite else { return nil }
        if value == 0 { return .zero }
        let sign: Int64 = value < 0 ? -1 : 1
        let v = abs(value)
        // Exact integers are always representable.
        if v.rounded() == v, v < 9.223372036854775807e18 {
            return Rational(numerator: sign * Int64(v), denominator: 1)
        }
        // Simple continued fraction: convergents p/q with q ascending;
        // stop at the first convergent inside tolerance or at the
        // denominator bound. Bounded iterations — no trap on extreme
        // values, the bound simply yields nil.
        var a0 = v
        var p0 = Int64(0), q0 = Int64(1)
        var p1 = Int64(1), q1 = Int64(0)
        var guard_ = 0
        while q1 <= maxDenominator, guard_ < 200 {
            guard_ += 1
            let a = Int64(a0)
            guard a >= 0, a < 1 << 62 else { break }
            let p2 = a &* p1 + p0
            let q2 = a &* q1 + q0
            guard p2 >= 0, q2 >= 0, p2 < 1 << 62, q2 <= maxDenominator else { break }
            if q2 == 0 { break }
            p0 = p1; q0 = q1
            p1 = p2; q1 = q2
            let frac = a0 - Double(a)
            if abs(Double(p1) / Double(q1) - v) <= tolerance * max(1.0, v) {
                return Rational(numerator: sign * p1, denominator: q1)
            }
            if frac < 1e-15 { break }
            a0 = 1.0 / frac
        }
        // The last convergent met the denominator bound: accept it when
        // it is inside tolerance, otherwise no bounded rational fits.
        if q1 > 0, q1 <= maxDenominator,
           abs(Double(p1) / Double(q1) - v) <= tolerance * max(1.0, v) {
            return Rational(numerator: sign * p1, denominator: q1)
        }
        return nil
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
    /// r83: `kind` carries the semantic numeric kind (plain/percent/
    /// fraction/multiplier) and `fraction` the reduced rational for
    /// fraction results; both are presentation + propagation metadata
    /// — the persisted schemas (`.nlx`/store) are untouched, they are
    /// re-derived from the sheet text on every pass.
    case number(value: Double, unit: String?, kind: NumericKind, fraction: Rational?)
    /// r83: assignments carry the result's semantic kind top-down (`x
    /// = 10% + 20%` records a percent-typed value in the environment
    /// and displays `30%`).
    case variable(name: String, value: Double, kind: NumericKind, fraction: Rational?)
    /// r85: an assignment whose value is an EXACT Int64 (a base
    /// literal or an integer expression): the environment records the
    /// exact integer (with its presentation radix) and later lines
    /// use it in the exact lane; display is the canonical radix text.
    case variableInt(name: String, value: Int64, radix: Int)
    /// A natural money line (`$3k earnings ÷ 5 people`, `lunch was $55
    /// + 25% tip`): the value carries full engine precision and an ISO
    /// currency code; the display is the shared money presentation
    /// (`$600.00`), never `600 USD`. Money results never enter the
    /// INLINE `total` section sum and never mix across currencies;
    /// they DO contribute their evaluated output magnitude to the
    /// persistent bottom Total panel (`SheetFooterTotal`, which is
    /// deliberately dimension-agnostic).
    case money(value: Double, code: String)
    /// A date answer (`May 5 + 43 days`): component form, never a
    /// Double and never tokenized as a number. Display is compact
    /// English (`Jun 17`, year added when explicit or crossed).
    case date(year: Int, month: Int, day: Int, showYear: Bool)
    /// r82: a boolean answer (`2 < 3`, `true and not false`, a boolean
    /// variable or token). A real Bool — never numeric 1/0: it renders
    /// and copies as lowercase `true`/`false`, never enters the totals
    /// or the rounding slider, and is excluded from previous-answer
    /// (numeric) planning.
    case boolean(value: Bool)
    /// r85: an EXACT integer answer (base/binary/hex expressions,
    /// bitwise operations and base conversions). `value` is the full
    /// Int64 — never a Double as truth — and `radix` (2/8/10/16) the
    /// presentation radix: the explicit converter's radix, else the
    /// first non-decimal radix of the line, else decimal. Renders and
    /// copies as the canonical radix text (no decimal rounding menu);
    /// contributes its exact value to BOTH totals (deterministic:
    /// the inline section sum and the bottom footer, whose Double
    /// projection is exact while |v| <= 2^53) and is
    /// tokenizable. Never persisted as a schema: re-derived per pass.
    case integer(value: Int64, radix: Int)
    /// r85: a `location of <place>` answer: the resolved place's
    /// coordinate plus its resolved name. Renders and copies the
    /// retypeable `lat° N, lon° E` pair (decimal-comma modes use `;`
    /// as the pair separator so Copy stays retypeable). Copy/Delete
    /// only, never in totals or the previous-answer chain, tokenizable
    /// as a coordinate (a distance-query operand).
    case location(name: String, country: String?, coordinate: GeoCoordinate)
    /// r85: a `… as DMS` answer: the decimal degree split into
    /// degrees/minutes/seconds. Renders/copies `156° 44′ 31.2″`
    /// (locale-aware seconds decimal). Copy/Delete only.
    case dms(DMSParts)
    /// A line that is ONLY an inactive reference token (its source line
    /// was deleted or stopped evaluating to a number/variable). The token
    /// stays in place in the editor; the line displays the remembered
    /// `Line <line>` label. Dependent expressions instead yield a generic
    /// hidden error — never a stale snapshot.
    case brokenToken(line: Int)
    /// A wall-clock value (an instant of day). `dayOffset` counts whole
    /// calendar days relative to the captured `now` (0 = today) for the
    /// Yesterday/Today/Tomorrow qualification. Never numeric, never in a
    /// total, never tokenizable as a number.
    case clock(hour: Int, minute: Int, second: Int, hasSeconds: Bool, dayOffset: Int)
    /// An elapsed/laptime value in seconds, presented as `HH:MM:SS` (with
    /// fractional seconds when present). Non-numeric, excluded from totals.
    case laptime(seconds: Double)
    /// temporal Task 2: a calendar date-time — typed wall components plus
    /// the UTC offset that produced them. `iso` selects the canonical
    /// `yyyy-MM-dd'T'HH:mm:ssXXX` rendering; otherwise the row renders in
    /// Numlex's regional date-time presentation (regional 12/24 h clock
    /// style, English month-day ordering). Never numeric: excluded from
    /// InlineTotal/FooterTotal and from the numeric previous-answer chain.
    case dateTime(year: Int, month: Int, day: Int, hour: Int, minute: Int,
                  second: Int, hasSeconds: Bool, utcOffsetSeconds: Int, iso: Bool)
    /// temporal Task 2: an epoch-seconds value (Unix seconds since
    /// 1970-01-01T00:00:00Z; finite fractional values allowed). Renders
    /// and copies as a locale-formatted number; like every temporal
    /// shape it is excluded from both totals and the previous-answer
    /// chain.
    case timestamp(seconds: Double)
    /// temporal Task 4: a video timecode — a checked non-negative Int64
    /// total-frame count plus the positive frame rate (1...1000) it is
    /// measured at. Renders/copies `HH:MM:SS:FF` with zero-padded fields
    /// (the frame field is at least two digits); never numeric, never in
    /// a total, never an answer-token operand.
    case timecode(frames: Int64, fps: Int)
    /// temporal Task 4: a whole frame count (`43,440 frames`). Renders
    /// and copies with the regional grouping and the canonical `frames`
    /// label; never numeric, never in a total, never a token operand.
    case frameCount(frames: Int64)
    case error(message: String)
}

extension LineResult {
    /// r83: the ordinary-number factory — every pre-r83 construction
    /// site keeps its exact semantics through this shape.
    public static func number(value: Double, unit: String? = nil) -> LineResult {
        .number(value: value, unit: unit, kind: .plain, fraction: nil)
    }
    /// A percentage ratio result (`40%` stores 0.4).
    public static func percent(value: Double, unit: String? = nil) -> LineResult {
        .number(value: value, unit: unit, kind: .percent, fraction: nil)
    }
    /// A fraction result: the reduced rational plus its numeric value.
    public static func fraction(_ r: Rational, unit: String? = nil) -> LineResult {
        .number(value: r.value, unit: unit, kind: .fraction, fraction: r)
    }
    /// A multiplier factor result (`1.5x` stores 1.5).
    public static func multiplier(value: Double, unit: String? = nil) -> LineResult {
        .number(value: value, unit: unit, kind: .multiplier, fraction: nil)
    }
    /// The ordinary-variable factory (pre-r83 call-site compatibility).
    public static func variable(name: String, value: Double) -> LineResult {
        .variable(name: name, value: value, kind: .plain, fraction: nil)
    }

    /// r83: the semantic kind of a numeric result (plain for money —
    /// money is never a percent/fraction/multiplier quantity).
    public var numericKind: NumericKind {
        switch self {
        case .number(_, _, let kind, _): return kind
        case .variable(_, _, let kind, _): return kind
        default: return .plain
        }
    }

    /// r83: the reduced rational of a fraction result (nil otherwise).
    public var fractionValue: Rational? {
        switch self {
        case .number(_, _, .fraction, let r): return r
        case .variable(_, _, .fraction, let r): return r
        default: return nil
        }
    }

    /// r83: the canonical RAW value a numeric result contributes to
    /// totals, the previous-answer chain and token algebra (a percent
    /// contributes its ratio, a multiplier its factor, a fraction its
    /// numeric value — exactly where the prior plain `.number` would).
    public var rawNumericValue: Double? {
        switch self {
        case .number(let v, let u, _, _):
            return (u == nil || isCurrencyCode(u)) && v.isFinite ? v : nil
        case .integer(let v, _):
            // Deterministic: the nearest Double of the exact value
            // (exact while |v| <= 2^53; beyond that the DOUBLE is the
            // documented total contribution — never a second exact
            // total exists, so nothing is silently corrupted).
            return Double(v)
        case .variableInt(_, let v, _):
            return Double(v)
        case .variable(_, let v, _, _):
            return v.isFinite ? v : nil
        case .money(let v, _):
            return v.isFinite ? v : nil
        default:
            return nil
        }
    }
}

public struct SheetLine: Equatable, Sendable {
    public var sourceLineIndex: Int
    public var result: LineResult
    /// r57: derived presentation flag for an evaluated inline `total`
    /// command row (successful `.number` only). The answer renders
    /// semibold with a gray rule above it and is excluded from the
    /// bottom footer total (`SheetFooterTotal`) so the section subtotal
    /// is never double-counted. Defaulted so every existing constructor
    /// call stays source-compatible; never persisted to the store or
    /// to `.nlx` — each pass re-derives it from the sheet text.
    public var isTotal: Bool = false
    public init(sourceLineIndex: Int, result: LineResult, isTotal: Bool = false) {
        self.sourceLineIndex = sourceLineIndex
        self.result = result
        self.isTotal = isTotal
    }
}
