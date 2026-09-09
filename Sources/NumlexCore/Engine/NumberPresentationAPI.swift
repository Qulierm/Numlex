import Foundation

// MARK: - r87: the ONE presentation API for numeric answers
//
// Centralizes every numeric rendering into one pure function. The
// view, Copy Answer, token capsules, the constant preview and the
// settings previews all route through here — rendering is never
// forked per surface. Presentation-only: values, variables, totals
// and token payloads are never rounded or scaled by display.
//
// - `.automatic` reproduces the pre-r87 formatters byte-for-byte
//   (the shared `formatDisplayValue` incl. compact and >=1e16
//   scientific fallback; money keeps `formatMoney`'s shared shape);
// - `.decimal` / `.scientific` / `.engineering` / `.fraction` /
//   `.custom` apply the configured precision, the global negative
//   style and the pattern preferences;
// - custom falls back to `.automatic` on an invalid pattern (never
//   blank, never a crash);
// - money keeps its ISO minor digits and is never fractionized;
// - exact Int64 rows use exact digit paths (no Double change for
//   |v| > 2^53);
// - nonfinite inputs keep the shared fixed fallback strings (the
//   engine rejects nonfinite before display; the API stays total).

public enum NumberPresentation {
    /// The semantic result category. Explicit kinds (percent /
    /// fraction / multiplier) and the money route keep their
    /// specialized shapes; only the numeric component is
    /// notation-formatted.
    public enum Category: Equatable, Sendable {
        case plain
        case percent
        case multiplier
        case money
        case int64
    }

    /// THE rendered numeric string for one result component.
    /// - `value`: the engine's Double result (nil-only consumers pass 0)
    /// - `int64`: the exact Int64 path (decimal-radix integer rows and
    ///   values the caller knows exactly)
    /// - `notation`: the EFFECTIVE notation (per-line override ??
    ///   global) — nil = the global notation (passed by the caller)
    /// - `precision`: the effective decimals (0...10)
    /// - `context`: the app's one NumberFormatContext (callers that
    ///   copy pass the non-compact variant, reproducing the R73
    ///   display-vs-copy exception for `.automatic`)
    /// - `currencyCode`: the ISO code for money rows
    public static func format(_ value: Double,
                              int64: Int64? = nil,
                              category: Category,
                              notation: NumberNotation,
                              precision: Int,
                              prefs: NumberPresentationPreferences,
                              context: NumberFormatContext,
                              currencyCode: String? = nil) -> String {
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value > 0 ? "+∞" : "-∞" }
        switch category {
        case .money:
            return formatMoney(value, code: currencyCode ?? "USD",
                                notation: notation, prefs: prefs, context: context)
        case .int64:
            guard let exact = int64 else {
                return formatNumberComponent(value, notation: notation,
                                              precision: precision, prefs: prefs,
                                              context: context)
            }
            return formatInt64(exact, notation: notation, precision: precision,
                               prefs: prefs, context: context)
        case .plain, .percent, .multiplier:
            return formatNumberComponent(value, notation: notation,
                                         precision: precision, prefs: prefs,
                                         context: context)
        }
    }

    // MARK: numeric component (notation dispatch)

    static func formatNumberComponent(_ value: Double,
                                      notation: NumberNotation,
                                      precision: Int,
                                      prefs: NumberPresentationPreferences,
                                      context: NumberFormatContext) -> String {
        switch notation {
        case .automatic:
            // Byte-for-byte the pre-r87 shared formatter (compact
            // toggle, >=1e16 scientific, grouping, trimming).
            return formatDisplayValue(value, decimalPlaces: precision,
                                      context: context)
        case .decimal:
            return applyNegative(style: prefs.negativeStyle,
                                  to: fixedDecimal(value, precision: precision,
                                                   context: context))
        case .scientific:
            return applyNegative(style: prefs.negativeStyle,
                                  to: exponential(value, precision: precision,
                                                  engineering: false, context: context))
        case .engineering:
            return applyNegative(style: prefs.negativeStyle,
                                  to: exponential(value, precision: precision,
                                                  engineering: true, context: context))
        case .fraction:
            if let f = bestFraction(value, maxDenominator: prefs.fractionPreset.rawValue) {
                return applyNegative(style: prefs.negativeStyle, to: fractionText(f))
            }
            return applyNegative(style: prefs.negativeStyle,
                                  to: fixedDecimal(value, precision: precision,
                                                   context: context))
        case .custom:
            if let pattern = NumberPattern.tryValidated(prefs.customPattern) {
                return renderPattern(pattern, value: value,
                                      negativeStyle: prefs.negativeStyle,
                                      context: context)
            }
            // Invalid/overlong pattern: safe fallback, never blank.
            return formatDisplayValue(value, decimalPlaces: precision,
                                      context: context)
        }
    }

    // MARK: exact Int64 dispatch

    public static func formatInt64(_ v: Int64, notation: NumberNotation, precision: Int,
                            prefs: NumberPresentationPreferences,
                            context: NumberFormatContext) -> String {
        switch notation {
        case .automatic:
            return IntLiteral.formatDecimal(v, context: context)
        case .decimal:
            // Exact digits, localized grouping, no fractional part
            // (an integer value has no decimals to show at any
            // precision — documented).
            let digits = String(abs(v))
            let useGrouping = (context.displayGrouping || context.legacy)
                && !context.groupingSeparator.isEmpty
            let sep = context.groupingSeparator.isEmpty ? "," : context.groupingSeparator
            let grouped = useGrouping ? groupDigitsString(digits, separator: sep) : digits
            let body = v < 0 && v != Int64.min ? "-" + grouped : grouped
            return applyNegative(style: prefs.negativeStyle, to: body)
        case .scientific:
            return applyNegative(style: prefs.negativeStyle,
                                  to: exactScientific(v, precision: precision,
                                                      engineering: false, context: context))
        case .engineering:
            return applyNegative(style: prefs.negativeStyle,
                                  to: exactScientific(v, precision: precision,
                                                      engineering: true, context: context))
        case .fraction:
            // An integer fraction is itself.
            return applyNegative(style: prefs.negativeStyle,
                                  to: v < 0 && prefs.negativeStyle == .minus ? "-" + String(abs(v)) : String(v))
        case .custom:
            if let pattern = NumberPattern.tryValidated(prefs.customPattern) {
                return renderPattern(pattern, value: Double(v), int64: v,
                                      negativeStyle: prefs.negativeStyle,
                                      context: context)
            }
            return IntLiteral.formatDecimal(v, context: context)
        }
    }

    /// Exact scientific/engineering text straight from the digit
    /// string (no Double change for |v| > 2^53). `dp` is the digit
    /// count; the mantissa takes `precision` fraction digits from the
    /// exact digits.
    static func exactScientific(_ v: Int64, precision: Int,
                                engineering: Bool, context: NumberFormatContext) -> String {
        let digits = String(abs(v))
        guard digits != "0" else { return "0" }
        let dec = context.legacy || context.decimalSeparator == "." ? "." : context.decimalSeparator
        let dp = digits.count
        let m: Int
        let e: Int
        if engineering {
            let t = dp - 1
            m = 1 + ((t % 3) + 3) % 3
            e = dp - m
        } else {
            m = 1
            e = dp - 1
        }
        var mant = Array(digits.prefix(m))
        let needFrac = precision
        var frac = Array(digits.dropFirst(m).prefix(needFrac))
        if frac.count < needFrac { frac += Array(repeating: Character("0"), count: needFrac - frac.count) }
        while frac.count > 0, frac.last == "0", needFrac > 0 {
            // trim optional trailing zeros (precision slots are
            // optional on the exact path)
            if mant.count + frac.count - 1 >= m { frac.removeLast() } else { break }
        }
        var text = String(mant)
        if !frac.isEmpty { text += dec + String(frac) }
        let sign = e < 0 ? "-" : "+"
        text += "e\(sign)\(abs(e))"
        return v < 0 ? "-" + text : text
    }

    // MARK: decimal / scientific / fraction helpers

    /// Fixed precision with trailing-zero trimming and context
    /// separators — the `.decimal` shape. Huge magnitudes (>= 1e16)
    /// take the shared scientific safety fallback so the column never
    /// emits hundreds of glyphs.
    static func fixedDecimal(_ value: Double, precision: Int,
                             context: NumberFormatContext) -> String {
        if abs(value) >= 1e16 {
            return localizedScientificNotation(value, context: context)
        }
        let p = min(max(precision, 0), 10)
        var s = String(format: "%.\(p)f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        if !context.legacy, context.decimalSeparator != "." {
            s = s.replacingOccurrences(of: ".", with: context.decimalSeparator)
        }
        if !context.legacy, context.displayGrouping,
           !context.groupingSeparator.isEmpty,
           let sepChar = context.decimalSeparator.first,
           let dot = s.firstIndex(of: sepChar) {
            let minDot = s.index(after: s.startIndex)
            if dot > minDot {
                let intPart = String(s[s.startIndex..<dot])
                let sign = intPart.hasPrefix("-") ? "-" : ""
                let d = sign.isEmpty ? intPart : String(intPart.dropFirst())
                let grouped = groupDigitsString(d, separator: context.groupingSeparator)
                return "\(sign)\(grouped)\(s[dot...])"
            }
        } else if value.truncatingRemainder(dividingBy: 1) == 0,
                  (context.legacy || context.displayGrouping),
                  !context.groupingSeparator.isEmpty {
            // Integer values keep their grouping (legacy: unconditional;
            // regional: per the display toggle) — the trimmed decimal
            // shape never gains a point for whole values.
            let sign = s.hasPrefix("-") ? "-" : ""
            let d = sign.isEmpty ? s : String(s.dropFirst())
            if d.allSatisfy({ $0.isNumber }) {
                let grouped = groupDigitsString(d, separator: context.groupingSeparator)
                return "\(sign)\(grouped)"
            }
        }
        return s
    }

    /// Scientific (mantissa [1, 10)) or engineering (exponent a
    /// multiple of 3, mantissa [1, 1000)) with a localized mantissa
    /// and a deterministic ALWAYS-signed exponent. Zero renders as the
    /// plain trimmed decimal `0`.
    static func exponential(_ value: Double, precision: Int,
                            engineering: Bool, context: NumberFormatContext) -> String {
        if value == 0 { return "0" }
        let p = min(max(precision, 0), 10)
        var a = abs(value)
        var e = Int(floor(log10(a)))
        var mantissa = a / pow(10.0, Double(e))
        if mantissa >= 10 { e += 1; mantissa /= 10 }
        if mantissa < 1 { e -= 1; mantissa *= 10 }
        if engineering {
            // Bring the exponent down to a multiple of 3 (toward zero:
            // 12345 -> 12.345e+3, 0.012 -> 12e-3).
            let rem = ((e % 3) + 3) % 3
            if rem != 0 {
                e -= rem
                mantissa *= pow(10.0, Double(rem))
                if mantissa >= 1000 {
                    mantissa /= 10
                    e += 1
                }
            }
        }
        var text = String(format: "%.\(p)f", mantissa)
        // A rounding carry into 10 / 100 / 1000 re-normalizes.
        let intLen = engineering ? 3 : 1
        if let firstDot = text.firstIndex(of: ".") {
            // A rounding carry (9.999 -> 10.000) re-normalizes onto
            // the next exponent step.
            let intp = Array(text[text.startIndex..<firstDot])
            if intp.count > intLen {
                e += intp.count - intLen
                let moved = Array(intp.suffix(intLen))
                let fracPart = Array(text[firstDot...])
                text = String(moved + fracPart)
            }
        }
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        if !context.legacy, context.decimalSeparator != "." {
            text = text.replacingOccurrences(of: ".", with: context.decimalSeparator)
        }
        let eText = "e\(e < 0 ? "-" : "+")\(abs(e))"
        let mant = value < 0 ? "-" + text : text
        return mant + eText
    }

    // MARK: fractions

    /// The best rational approximation with denominator <=
    /// `maxDenominator` (continued-fraction convergents). Accepted
    /// when the relative error is within the documented deterministic
    /// tolerance `1e-4 * max(1, |v|)`; otherwise nil (the caller falls
    /// back to the decimal shape). Integral values are exact.
    static func bestFraction(_ value: Double, maxDenominator: Int)
        -> (n: Int64, d: Int64)? {
        guard value.isFinite else { return nil }
        let sign: Int64 = value < 0 ? -1 : 1
        let v = abs(value)
        if v == 0 { return (0, 1) }
        // Continued-fraction convergents, stopping at the bound.
        var x = v
        var h0: Double = 0, k0: Double = 1
        var h1: Double = 1, k1: Double = 0
        var best: (n: Double, d: Double)? = (h1, k1)
        for _ in 0..<48 {
            let a = floor(x)
            let h2 = a * h1 + h0
            let k2 = a * k1 + k0
            if k2 > Double(maxDenominator) { break }
            (h0, k0) = (h1, k1)
            (h1, k1) = (h2, k2)
            best = (h1, k1)
            let frac = x - a
            if frac < 1e-12 { break }
            x = 1 / frac
        }
        guard let b = best, b.d > 0,
              Int64(bitPattern: UInt64(b.d)) <= Int64(max(maxDenominator, 1)),
              Int64(bitPattern: UInt64(b.n)) <= Int64.max else { return nil }
        let n = Int64(b.n), d = Int64(b.d)
        let approx = Double(n) / Double(d)
        let tol = 1e-4 * max(1.0, v)
        guard abs(v - approx) <= tol else { return nil }
        return (sign * n, d)
    }

    /// The re-typeable ASCII fraction: mixed `1 3/4` (a space
    /// separates the whole part), proper `1/3`, whole `2`.
    public static func fractionText(_ f: (n: Int64, d: Int64)) -> String {
        let sign = f.n < 0 ? "-" : ""
        let n = abs(f.n)
        guard f.d != 0 else { return sign + String(n) }
        let whole = n / f.d
        let rem = n % f.d
        if rem == 0 { return sign + String(whole) }
        if whole == 0 { return sign + "\(n)/\(f.d)" }
        return sign + "\(whole) \(rem)/\(f.d)"
    }

    // MARK: negative style

    /// Wraps a formatted string in the configured negative shape.
    /// `magnitude: false` (the default): the string is the FULLY
    /// formatted value and may carry its own `-` prefix — `.minus` is
    /// the identity and the other shapes re-wrap signed strings only
    /// (positive strings are never touched). `magnitude: true`: the
    /// string is a prefix-free magnitude of a NEGATIVE value (the
    /// section-render pattern path) and always gains the shape.
    static func applyNegative(style: NegativeStyle, to s: String,
                              magnitude: Bool = false) -> String {
        let mag = s.hasPrefix("-") ? String(s.dropFirst()) : s
        if mag == "0" { return "0" }  // never `-0` / `(0)` / `0-`
        if !magnitude {
            guard s.hasPrefix("-") else { return s }
        }
        switch style {
        case .minus: return "-" + mag
        case .parentheses: return "(\(mag))"
        case .trailingMinus: return mag + "-"
        }
    }

    // MARK: custom pattern

    /// Renders through a validated pattern: explicit zero section at
    /// numeric zero, explicit negative section for negatives, the
    /// global negative style after magnitude formatting with a single
    /// section, and the positive section otherwise.
    public static func renderPattern(_ pattern: NumberPattern, value: Double,
                              int64: Int64? = nil,
                              negativeStyle: NegativeStyle,
                              context: NumberFormatContext,
                              currencySymbol: String? = nil) -> String {
        if value == 0, let zero = pattern.zero {
            return pattern.renderValue(0, section: zero, context: context,
                                       currencySymbol: currencySymbol)
        }
        if value < 0, let negative = pattern.negative {
            return pattern.renderValue(value, int64Value: int64, section: negative,
                                       context: context, currencySymbol: currencySymbol)
        }
        if value < 0, pattern.negative == nil {
            let mag = pattern.renderValue(value, int64Value: int64,
                                          section: pattern.positive,
                                          context: context,
                                          currencySymbol: currencySymbol)
            return applyNegative(style: negativeStyle, to: mag, magnitude: true)
        }
        return pattern.renderValue(value, int64Value: int64, section: pattern.positive,
                                   context: context, currencySymbol: currencySymbol)
    }

    // MARK: money

    /// The money route: ISO minor digits (0 for zero-decimal
    /// currencies), known symbols placed per the global placement
    /// setting (the pattern `¤` overrides placement when present),
    /// unknown codes keep the documented `<value> <CODE>` fallback.
    /// Money never fractionizes and never compacts.
    public static func formatMoney(_ value: Double, code: String,
                            notation: NumberNotation,
                            prefs: NumberPresentationPreferences,
                            context: NumberFormatContext) -> String {
        let upper = code.uppercased()
        let symbol = CurrencyPresentation.symbols[upper]
        if notation == .custom,
           let pattern = NumberPattern.tryValidated(prefs.customPattern),
           pattern.positive.hasCurrency || pattern.negative?.hasCurrency == true
           || pattern.zero?.hasCurrency == true {
            // The pattern places the currency explicitly.
            return renderPattern(pattern, value: value,
                                 negativeStyle: prefs.negativeStyle,
                                 context: context, currencySymbol: symbol)
        }
        switch notation {
        case .automatic, .decimal:
            let body = moneyBody(value, digits: CurrencyPresentation.minorDigits(for: upper),
                                  context: context)
            return moneyPlacement(value, code: upper, symbol: symbol,
                                   prefs: prefs, context: context)
        case .scientific, .engineering:
            let body = exponential(value, precision: 2,
                                   engineering: notation == .engineering,
                                   context: context)
            return moneyPlacement(value, code: upper, symbol: symbol,
                                   prefs: prefs, context: context)
        case .fraction:
            // Money never fractionizes: the decimal shape stands in.
            return moneyPlacement(value, code: upper, symbol: symbol,
                                   prefs: prefs, context: context)
        case .custom:
            if let pattern = NumberPattern.tryValidated(prefs.customPattern) {
                return renderPattern(pattern, value: value,
                                     negativeStyle: prefs.negativeStyle,
                                     context: context, currencySymbol: symbol)
            }
            // Invalid pattern: the automatic money shape, never blank.
            return moneyPlacement(value, code: upper, symbol: symbol,
                                   prefs: prefs, context: context)
        }
    }

    public static func moneyPlacement(_ value: Double, code: String, symbol: String?,
                               prefs: NumberPresentationPreferences,
                               context: NumberFormatContext) -> String {
        let body = moneyBody(value, digits: CurrencyPresentation.minorDigits(for: code),
                              context: context)
        if let s = symbol {
            return placeCurrency(symbol: s, body: body, placement: prefs.currencyPlacement)
        }
        return symbolFallback(body, code: code)
    }

    /// The numeric body of a money value at its fixed ISO minor
    /// digits — context-localized separators, no symbol.
    static func moneyBody(_ value: Double, digits: Int,
                          context: NumberFormatContext) -> String {
        guard value.isFinite else { return formatDisplayValue(value) }
        if abs(value) >= 1e16 {
            let body = localizedScientificNotation(abs(value), context: context)
            return value < 0 ? "-" + body : body
        }
        let sign = value < 0 ? "-" : ""
        let mag = abs(value)
        let f = NumberFormatter()
        f.locale = context.locale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = context.displayGrouping
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        if !context.legacy, context.decimalSeparator != "." {
            f.decimalSeparator = context.decimalSeparator
        }
        if !context.legacy, !context.groupingSeparator.isEmpty, context.displayGrouping {
            f.groupingSeparator = context.groupingSeparator
        }
        let body = f.string(from: NSNumber(value: mag)) ?? "\(mag)"
        return sign + body
    }

    static func placeCurrency(symbol: String, body: String,
                              placement: CurrencyPlacement) -> String {
        switch placement {
        case .before: return symbol + body
        case .beforeSpaced: return symbol + " " + body
        case .after: return body + symbol
        case .afterSpaced: return body + " " + symbol
        }
    }

    /// Unknown ISO codes keep the pre-r87 documented shape: the value,
    /// a space, the code once (the sign rides the value).
    static func symbolFallback(_ body: String, code: String) -> String {
        return body + " " + code
    }

}
