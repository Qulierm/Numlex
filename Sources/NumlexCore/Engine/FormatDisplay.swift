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
    if value.isNaN { return "NaN" }
    if value.isInfinite { return value > 0 ? "+∞" : "-∞" }
    if abs(value) >= 1e16 { return scientificNotation(value) }
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        // |value| < 1e16: inside Int64 range with room to spare.
        let intVal = Int64(value)
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.groupingSeparator = ","
        fmt.locale = Locale(identifier: "en_US")
        return fmt.string(from: NSNumber(value: intVal)) ?? "\(intVal)"
    }
    var s = String(format: "%.\(decimalPlaces)f", value)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

/// Deterministic compact scientific notation: mantissa in [1, 10) with
/// trailing zeros trimmed, signed base-10 exponent.
/// `5e+22`, `1.5e+21`, `-2.5e-200`.
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
