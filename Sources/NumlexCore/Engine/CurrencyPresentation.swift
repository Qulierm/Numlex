import Foundation

/// Shared currency presentation metadata and display helpers.
///
/// ONE marker table drives everything: the input markers
/// (`$`, `€`, `£`, `¥`, `CN¥`, `Rp`, `zł`, `Kč`, …), the generated
/// input-marker regex, the positional prefix/postfix parsers, and the
/// rendered output (`$600.00`, not `600 USD`). Currencies without a
/// safe unambiguous symbol fall back to the ISO code suffix
/// (`600.00 CHF`). Minor digits follow the ISO 4217 minor-unit table
/// comprehensively (0/2/3/4 digits), never the value.
///
/// The stored engine/token value is NEVER rounded here — rounding is a
/// display-only concern. Huge finite values use the shared scientific
/// fallback and can never trap on an Int64 cast.
public enum CurrencyPresentation {

    /// THE ONE marker table: input marker → ISO code, listed
    /// longest-first. `inputMarkerPattern` and the positional lookup
    /// below are GENERATED from this table, so no second hard-coded
    /// list can drift. Bare `$` deliberately stays USD; bare
    /// `¥` stays JPY (CNY uses the unambiguous `CN¥`); no bare
    /// `pound`/`peso`/`franc`/`dinar`/`riyal`/`shilling`/`rupee`
    /// markers exist.
    public static let markers: [(marker: String, code: String)] = [
        ("NZ$", "NZD"), ("CA$", "CAD"), ("HK$", "HKD"), ("MX$", "MXN"), ("NT$", "TWD"),
        ("A$", "AUD"), ("S$", "SGD"), ("R$", "BRL"),
        ("CN¥", "CNY"),
        ("Rp", "IDR"), ("RM", "MYR"), ("zł", "PLN"), ("Kč", "CZK"),
        ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"), ("₽", "RUB"),
        ("₩", "KRW"), ("₹", "INR"), ("₺", "TRY"), ("₴", "UAH"), ("₫", "VND"),
        ("₱", "PHP"), ("฿", "THB"), ("₪", "ILS"), ("₦", "NGN"), ("₾", "GEL"),
        ("₸", "KZT"), ("₮", "MNT"), ("₯", "LAK"), ("៛", "KHR"), ("₡", "CRC"),
        ("₲", "PYG"), ("₵", "GHS"),
    ]

    /// Exact marker → ISO code lookup (prefix/postfix parsers).
    public static let markerCode: [String: String] =
        Dictionary(uniqueKeysWithValues: markers.map { ($0.marker, $0.code) })

    /// Output symbol per ISO code (prefix forms), inverted from the
    /// ONE marker table. Anything missing from this table uses the
    /// ISO-code suffix fallback.
    public static let symbols: [String: String] =
        Dictionary(uniqueKeysWithValues: markers.map { ($0.code, $0.marker) })

    /// The input markers ordered by DESCENDING UTF-16 length (ties
    /// alphabetical), so regex alternation and positional lookup are
    /// longest-first: `CN¥` can never be eaten by its own tail `¥`.
    public static let orderedMarkers: [String] =
        markers.map(\.marker).sorted { a, b in
            let la = a.utf16.count, lb = b.utf16.count
            return la == lb ? a < b : la > lb
        }

    /// The generated input-marker regex: a longest-first alternation of
    /// the regex-escaped markers. Multi-character markers (`CN¥`, `Rp`)
    /// therefore win over any shorter marker sharing a character.
    public static let inputMarkerPattern: String = orderedMarkers
        .map { NSRegularExpression.escapedPattern(for: $0) }
        .joined(separator: "|")

    /// Standard minor digit counts (ISO 4217, comprehensive):
    /// 0 digits: BIF CLP DJF GNF ISK JPY KMF KRW PYG RWF UGX VND VUV
    /// XAF XOF XPF; 3 digits: BHD IQD JOD KWD LYD OMR TND; 4 digits:
    /// CLF; 2 digits everywhere else. Display-only: stored values are
    /// never rounded to these.
    public static func minorDigits(for code: String) -> Int {
        switch code.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW",
             "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF":
            return 0
        case "BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND":
            return 3
        case "CLF":
            return 4
        default:
            return 2
        }
    }

    /// Whether a display unit label is a known ISO fiat currency code.
    public static func isCurrencyCode(_ label: String?) -> Bool {
        guard let label, label.count == 3 else { return false }
        return FiatCurrencies.codes.contains {
            $0.caseInsensitiveCompare(label) == .orderedSame
        }
    }

    /// Maps one input marker string to its ISO code (exact lookup in
    /// the ONE marker table).
    public static func code(forMarker marker: String) -> String? {
        markerCode[marker]
    }

    /// Renders a currency amount: `$600.00`, `CA$1,234.50`, `¥500`,
    /// `-$12.34`; currencies without a safe symbol render
    /// `600.00 CHF`. Display-only: the value is never mutated.
    public static func formatMoney(_ value: Double, code: String) -> String {
        guard value.isFinite else { return formatDisplayValue(value) }
        let upper = code.uppercased()
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        // Huge finite values: the shared scientific fallback — an
        // Int64 cast is only ever performed below 1e16.
        if magnitude >= 1e16 {
            let body = scientificNotation(magnitude)
            return symbols[upper].map { "\(sign)\($0)\(body)" } ?? "\(sign)\(body) \(upper)"
        }
        let digits = minorDigits(for: upper)
        let body = moneyFormatter(digits: digits).string(from: NSNumber(value: magnitude))
            ?? "\(magnitude)"
        return symbols[upper].map { "\(sign)\($0)\(body)" } ?? "\(sign)\(body) \(upper)"
    }

    /// One display string for a quantity: currency codes render through
    /// `formatMoney` (a single `$600.00` token, no unit suffix); every
    /// other unit keeps the existing `<value> <unit>` form unchanged.
    public static func formatQuantity(_ value: Double,
                                      unit: String?,
                                      decimalPlaces: Int) -> String {
        if let unit, isCurrencyCode(unit) {
            return formatMoney(value, code: unit)
        }
        let v = formatDisplayValue(value, decimalPlaces: decimalPlaces)
        return unit.map { "\(v) \($0)" } ?? v
    }

    // MARK: - Positional marker grammar (shared by ALL parser paths)

    /// The marker starting exactly at UTF-16 position `idx` in `ns`
    /// (longest-first over the ONE marker table), or nil.
    public static func marker(at idx: Int, in ns: NSString) -> String? {
        for m in orderedMarkers {
            let len = (m as NSString).length
            if idx + len <= ns.length,
               ns.substring(with: NSRange(location: idx, length: len)) == m {
                return m
            }
        }
        return nil
    }

    /// Whether the character before `pos` is a compact money suffix
    /// (`k`/`m`/`K`/`M`) that is itself preceded by a digit or `.`
    /// (`2.5K$` counts; `km$5` does not — that is a unit, not a
    /// suffix).
    private static func compactSuffixBefore(_ ns: NSString, at pos: Int) -> Bool {
        guard pos >= 2 else { return false }
        let sfx = ns.character(at: pos - 1)
        guard sfx == 0x6B || sfx == 0x6D || sfx == 0x4B || sfx == 0x4D else { return false }
        let b = ns.character(at: pos - 2)
        return (0x30...0x39).contains(b) || b == 0x2E
    }

    /// Every valid currency-marker occurrence in `line` (UTF-16
    /// ranges) — the single boundary grammar used by money-line
    /// detection, token parsing and syntax highlighting:
    /// - PREFIX: the marker is glued before a number or decimal point
    ///   (`$45`, `Rp25000`, `zł100`) and preceded by a non-alphanumeric
    ///   (a doubled `$$` is never a marker);
    /// - POSTFIX: the marker is glued after a number or a compact
    ///   `k`/`m`/`K`/`M` suffix (`240$`, `2.5K$`, `100zł`) and not
    ///   followed by a digit (letter markers additionally never end an
    ///   alphanumeric run, so `100Rpm` is not a marker).
    public static func markerOccurrences(in line: String) -> [NSRange] {
        let ns = line as NSString
        var out: [NSRange] = []
        for marker in orderedMarkers {
            let len = (marker as NSString).length
            let letterMarker = marker.first!.isLetter
            var start = 0
            while start + len <= ns.length {
                guard ns.substring(with: NSRange(location: start, length: len)) == marker else {
                    start += 1
                    continue
                }
                let before = start > 0 ? ns.character(at: start - 1) : 0
                let afterIdx = start + len
                let after = afterIdx < ns.length ? ns.character(at: afterIdx) : 0
                let beforeIsDigit = (0x30...0x39).contains(before)
                let beforeIsLetter = (0x41...0x5A).contains(before) || (0x61...0x7A).contains(before)
                let afterIsDigit = (0x30...0x39).contains(after)
                let afterIsLetter = (0x41...0x5A).contains(after) || (0x61...0x7A).contains(after)
                var hit = false
                if !afterIsDigit {
                    // POSTFIX: number (or compact suffix) right before.
                    if letterMarker, afterIsLetter { hit = false }
                    else if beforeIsDigit || compactSuffixBefore(ns, at: start) { hit = true }
                }
                if !hit && ((0x30...0x39).contains(after) || after == 0x2E)
                    && !beforeIsDigit && !beforeIsLetter && before != 0x24 {
                    // PREFIX: number (or decimal point) right after.
                    hit = true
                }
                if hit {
                    out.append(NSRange(location: start, length: len))
                    start = afterIdx  // no overlapping re-match of tails
                    continue
                }
                start += 1
            }
        }
        return out.sorted { $0.location < $1.location }
    }

    // MARK: - Cached formatters (en_US_POSIX: deterministic separators)

    private static func moneyFormatter(digits: Int) -> NumberFormatter {
        // The ISO 4217 minor-digit table spans 0–4; everything else
        // falls back to the standard 2.
        switch digits {
        case 0: return formatter0
        case 3: return formatter3
        case 4: return formatter4
        default: return formatter2
        }
    }
    private static let formatter0: NumberFormatter = makeMoneyFormatter(digits: 0)
    private static let formatter2: NumberFormatter = makeMoneyFormatter(digits: 2)
    private static let formatter3: NumberFormatter = makeMoneyFormatter(digits: 3)
    private static let formatter4: NumberFormatter = makeMoneyFormatter(digits: 4)

    private static func makeMoneyFormatter(digits: Int) -> NumberFormatter {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.decimalSeparator = "."
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f
    }
}

/// Convenience wrapper used by views, token resolution and the clipboard.
public func formatMoney(_ value: Double, code: String) -> String {
    CurrencyPresentation.formatMoney(value, code: code)
}

/// Convenience wrapper: one display string for value + unit.
public func formatQuantity(_ value: Double, unit: String?, decimalPlaces: Int) -> String {
    CurrencyPresentation.formatQuantity(value, unit: unit, decimalPlaces: decimalPlaces)
}

/// Convenience wrapper: is this display label a fiat currency code?
public func isCurrencyCode(_ label: String?) -> Bool {
    CurrencyPresentation.isCurrencyCode(label)
}
