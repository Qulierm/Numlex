import Foundation

/// ONE overflow-safe, deterministic display formatter for numeric
/// results — the single shared source used by the answer column
/// (numbers, variables, Total) and by `formatNumberForDisplay`. It
/// NEVER performs a trapping Float→Int conversion:
///
/// - ordinary finite integral values (|v| < 1e16): en_US comma grouping
///   ("1,663"). The 1e16 threshold sits far below Int64.max (≈9.22e18),
///   so the `Int64` cast below can neither trap nor alter the value;
/// - other ordinary finite values: configured decimalPlaces with
///   trailing-zero trimming ("16.0934", "0.00001");
/// - very large finite magnitudes (|v| ≥ 1e16): compact deterministic
///   scientific notation with a signed exponent ("5e+22", "-2.5e-200")
///   so the 200pt answer column never generates hundreds of glyphs;
/// - direct NaN / +∞ / −∞ inputs: fixed fallback strings. The engine
///   must reject non-finite results before they are displayed; this
///   keeps the formatter total so even that invariant cannot crash.
public func formatDisplayValue(_ value: Double, decimalPlaces: Int = 7) -> String {
    formatDisplayValue(value, decimalPlaces: decimalPlaces, context: .legacy)
}

/// r73: the context-aware variant of the shared display formatter.
/// `context == .legacy` reproduces the exact pre-r73 behavior (en_US
/// comma grouping, dot decimals, no compact). A non-legacy context
/// swaps in its separators: integer parts group with the context's
/// grouping separator when its grouping display is on (legacy groups
/// unconditionally), decimals use the context's decimal separator, and
/// `|v| >= 1000 < 1e16` scalars compact to k/M/B/T (100000 → 100k)
/// when the context's compact notation is on — mantissa formatted at
/// `decimalPlaces` with trailing zeros trimmed (999999 → 999.999k;
/// a mantissa that rounds to 1000 keeps the lower suffix, e.g.
/// 1000T at the 1e15 boundary — documented carry behavior). The
/// stored value is NEVER mutated or rounded; compactness is purely
/// presentational. Money and unit results never compact (they route
/// through `formatMoney` / the `<value> <unit>` form). Scientific
/// notation for |v| >= 1e16 keeps the shared deterministic mantissa
/// and only localizes the mantissa's decimal separator.
public func formatDisplayValue(_ value: Double, decimalPlaces: Int,
                               context: NumberFormatContext) -> String {
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value > 0 ? "+∞" : "-∞" }
    if abs(value) >= 1e16 { return localizedScientificNotation(value, context: context) }
    if context.compactNotation && abs(value) >= 1000 {
        return compactNotation(value, decimalPlaces: decimalPlaces, context: context)
    }
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        // |value| < 1e16: inside Int64 range with room to spare. The
        // separator may be a full STRING (system NNBSP / multi-unit
        // separators), so this path — unlike the legacy-era
        // `groupedInteger` — takes the String form directly.
        let group = context.displayGrouping || context.legacy
        if group, !context.groupingSeparator.isEmpty {
            let intVal = Int64(value)
            let grouped = groupDigitsString(
                String(abs(intVal)), separator: context.groupingSeparator)
            return intVal < 0 ? "-\(grouped)" : grouped
        }
        return "\(Int64(value))"
    }
    // r51: trim ONLY fractional trailing zeros — a whole value like
    // "0" (%.0f of 0.33) or "-0" has no decimal point and must be
    // kept verbatim (the old unconditional trim ate them to ""/"-").
    var s = String(format: "%.\(decimalPlaces)f", value)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    if !context.legacy, context.decimalSeparator != "." {
        s = s.replacingOccurrences(of: ".", with: context.decimalSeparator)
    }
    // Grouping on the integer part of FRACTIONAL numbers too
    // (1234.5 -> "1,234.5" / "1234,5") in regional contexts with the
    // display toggle on. Legacy keeps the pre-r73 ungrouped fixed-
    // point shape for fractions byte-for-byte. The trimmed fractional
    // tail is never grouped.
    if !context.legacy, context.displayGrouping,
       !context.groupingSeparator.isEmpty,
       let sepChar = context.decimalSeparator.first,
       let dot = s.firstIndex(of: sepChar) {
        let minDot = s.index(after: s.startIndex)
        if dot > minDot {
            let intPart = String(s[s.startIndex..<dot])
            let sign = intPart.hasPrefix("-") ? "-" : ""
            let digits = sign.isEmpty ? intPart : String(intPart.dropFirst())
            let grouped = groupDigitsString(digits, separator: context.groupingSeparator)
            return "\(sign)\(grouped)\(s[dot...])"
        }
    }
    return s
}

/// Groups the digit string `digits` with `separator` every three digits
/// from the right (pure string math — no Int64 bounds to worry about).
func groupDigitsString(_ digits: String, separator: String) -> String {
    let chars = Array(digits)
    var grouped = ""
    for (i, ch) in chars.reversed().enumerated() {
        if i > 0 && i % 3 == 0 { grouped.append(separator) }
        grouped.append(ch)
    }
    return String(grouped.reversed())
}

/// r73: k/M/B/T compact mantissa for `|value| >= 1000` (callers bound
/// the upper side to < 1e16; larger values stay scientific). The
/// suffix is the LARGEST of k/M/B/T whose quotient is >= 1, so the
/// mantissa spans [1, 1000): 100000 → 100k, 999999 → 999.999k,
/// 1e6 → 1M, 2.5e9 → 2.5B, 1.5e15 → 1500T (no petabyte suffix).
/// Trailing zeros of the mantissa are trimmed; the sign rides in front.
func compactNotation(_ value: Double,
                     decimalPlaces: Int,
                     context: NumberFormatContext) -> String {
    let sign = value < 0 ? "-" : ""
    let mag = abs(value)
    let tiers: [(suffix: String, factor: Double)] = [
        ("T", 1e12), ("B", 1e9), ("M", 1e6), ("k", 1e3)
    ]
    let tier = tiers.first { mag / $0.factor >= 1 }!
    let mantissa = mag / tier.factor
    var s = String(format: "%.\(decimalPlaces)f", mantissa)
    if s.contains(".") {
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
    }
    if context.decimalSeparator != "." {
        s = s.replacingOccurrences(of: ".", with: context.decimalSeparator)
    }
    return "\(sign)\(s)\(tier.suffix)"
}

/// Groups an integer (|v| < 1e16, Int64-safe) with `separator` every
/// three digits from the right. Pure string math — no formatter.
func groupedInteger(_ value: Int64, separator: String) -> String {
    let s = "\(abs(value))"
    var grouped = ""
    for (i, ch) in s.reversed().enumerated() {
        if i > 0 && i % 3 == 0 { grouped.append(separator) }
        grouped.append(ch)
    }
    let out = String(grouped.reversed())
    return value < 0 ? "-\(out)" : out
}

/// r73: context-localized scientific notation — the shared deterministic
/// mantissa/exponent shape with the mantissa's decimal dot swapped for
/// the context's decimal separator (`5,5e+21` in decimal-comma modes).
func localizedScientificNotation(_ value: Double,
                                 context: NumberFormatContext) -> String {
    let base = scientificNotation(value)
    guard !context.legacy, context.decimalSeparator != "." else { return base }
    // The mantissa precedes the `e`; the exponent is integers only.
    guard let e = base.firstIndex(of: "e") else { return base }
    let mantissa = base[..<e].replacingOccurrences(of: ".", with: context.decimalSeparator)
    return "\(mantissa)\(base[e...])"
}

/// Deterministic compact scientific notation: mantissa in [1, 10) with
/// trailing zeros trimmed, signed base-10 exponent.
/// `5e+22`, `1.5e+21`, `-2.5e-200`.
/// r73: the context-aware currency presentation: the SAME symbol-prefix
/// shape (`$600.00`) rendered with the context's locale separators —
/// `€1.234,56` in decimal-comma modes. `context == .legacy` keeps the
/// fixed en_US_POSIX table byte-for-byte. Money never compacts: the
/// compact toggle is presentation-only for plain scalars, and compact
/// suffixes are ambiguous on currency (k/M collide with unit words and
/// currency magnitudes). Minor digits follow the ISO 4217 table.
public func formatMoney(_ value: Double, code: String,
                        context: NumberFormatContext) -> String {
    guard !context.legacy else {
        return CurrencyPresentation.formatMoney(value, code: code)
    }
    guard value.isFinite else { return formatDisplayValue(value) }
    let upper = code.uppercased()
    let sign = value < 0 ? "-" : ""
    let magnitude = abs(value)
    if magnitude >= 1e16 {
        let body = localizedScientificNotation(magnitude, context: context)
        return CurrencyPresentation.symbols[upper].map { "\(sign)\($0)\(body)" }
            ?? "\(sign)\(body) \(upper)"
    }
    // Fixed minor digits for money: 0 for the ISO zero-decimal
    // currencies, otherwise TWO — matching the legacy en_US_POSIX
    // presentation (the locale's own 3-digit tables must NOT leak in:
    // €1.234,56 keeps its exact cents).
    let digits = CurrencyPresentation.minorDigits(for: upper) == 0 ? 0 : 2
    let f = NumberFormatter()
    f.locale = context.locale
    f.numberStyle = .decimal
    f.usesGroupingSeparator = context.displayGrouping
    f.minimumFractionDigits = digits
    f.maximumFractionDigits = digits
    let body = f.string(from: NSNumber(value: magnitude)) ?? "\(magnitude)"
    return CurrencyPresentation.symbols[upper].map { "\(sign)\($0)\(body)" }
        ?? "\(sign)\(body) \(upper)"
}

/// r73: context-aware quantity display — currency codes render through
/// the context money presentation, everything else through the
/// context scalar formatter.
public func formatQuantity(_ value: Double, unit: String?, decimalPlaces: Int,
                           context: NumberFormatContext) -> String {
    if let unit, isCurrencyCode(unit) {
        return formatMoney(value, code: unit, context: context)
    }
    let v = formatDisplayValue(value, decimalPlaces: decimalPlaces, context: context)
    return unit.map { "\(v) \($0)" } ?? v
}

public func scientificNotation(_ value: Double) -> String {
    let sign = value < 0 ? "-" : ""
    let a = abs(value)
    var exponent = Int(floor(log10(a)))
    var mantissa = a / pow(10.0, Double(exponent))
    // log10 is not exact at powers of ten; keep the mantissa in [1, 10).
    if mantissa >= 10 { exponent += 1; mantissa /= 10 }
    if mantissa < 1 { exponent -= 1; mantissa *= 10 }
    var mantissaText = String(format: "%.6f", mantissa)
    while mantissaText.hasSuffix("0") { mantissaText.removeLast() }
    if mantissaText.hasSuffix(".") { mantissaText.removeLast() }
    return "\(sign)\(mantissaText)e\(exponent >= 0 ? "+" : "-")\(abs(exponent))"
}
