import Foundation

/// Shared currency presentation metadata and display helpers.
///
/// One deterministic symbol table drives BOTH the input markers
/// (`$`, `€`, `£`, `¥`, `₽`, disambiguated `CA$`/`A$`/`NZ$`/`HK$`/`S$`)
/// and the rendered output (`$600.00`, not `600 USD`). Currencies
/// without a safe unambiguous symbol fall back to the ISO code suffix
/// (`600.00 CHF`). Minor digits follow the ISO 4217 standard: 0 for
/// JPY/KRW/VND/CLP, 3 for BHD/KWD/JOD/OMR/TND, 2 everywhere else.
///
/// The stored engine/token value is NEVER rounded here — rounding is a
/// display-only concern. Huge finite values use the shared scientific
/// fallback and can never trap on an Int64 cast.
public enum CurrencyPresentation {

    /// Output symbol per ISO code (prefix forms). Anything missing from
    /// this table uses the ISO-code suffix fallback.
    public static let symbols: [String: String] = [
        "USD": "$",
        "EUR": "€",
        "GBP": "£",
        "JPY": "¥",
        "RUB": "₽",
        "CAD": "CA$",
        "AUD": "A$",
        "NZD": "NZ$",
        "HKD": "HK$",
        "SGD": "S$",
        "CNY": "CN¥",
    ]

    /// Standard minor digit counts (ISO 4217).
    public static func minorDigits(for code: String) -> Int {
        switch code.uppercased() {
        case "JPY", "KRW", "VND", "CLP":
            return 0
        case "BHD", "KWD", "JOD", "OMR", "TND":
            return 3
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

    /// The input marker grammar: disambiguated dollar forms first (longest
    /// prefix wins), then the bare symbols. `$` alone defaults to USD.
    public static let inputMarkerPattern =
        "CA\\$|NZ\\$|HK\\$|A\\$|S\\$|\\$|€|£|¥|₽"

    /// Maps one input marker string to its ISO code.
    public static func code(forMarker marker: String) -> String? {
        switch marker {
        case "CA$": return "CAD"
        case "NZ$": return "NZD"
        case "HK$": return "HKD"
        case "A$": return "AUD"
        case "S$": return "SGD"
        case "$": return "USD"
        case "€": return "EUR"
        case "£": return "GBP"
        case "¥": return "JPY"
        case "₽": return "RUB"
        default: return nil
        }
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

    // MARK: - Cached formatters (en_US_POSIX: deterministic separators)

    private static func moneyFormatter(digits: Int) -> NumberFormatter {
        switch digits {
        case 0: return formatter0
        case 3: return formatter3
        default: return formatter2
        }
    }
    private static let formatter0: NumberFormatter = makeMoneyFormatter(digits: 0)
    private static let formatter2: NumberFormatter = makeMoneyFormatter(digits: 2)
    private static let formatter3: NumberFormatter = makeMoneyFormatter(digits: 3)

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
