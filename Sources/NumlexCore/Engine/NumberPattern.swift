import Foundation

// MARK: - r87: validated custom number pattern (the `#,##0.00` grammar)
//
// ONE immutable, pure parser/renderer. Patterns are canonical ASCII
// skeletons (locale-neutral): the raw string never reaches Foundation
// formatters; output is localized through the caller's
// `NumberFormatContext` (decimal separator, grouping separator).
//
// Grammar (per section; up to three `;`-separated sections —
// positive;negative;zero):
// - quoted literals: `'...'` with `''` as the apostrophe escape
// - one numeric skeleton: required digits `0`, optional digits `#`,
//   one `.` (int `0`s may follow `#`s; fraction `0`s precede `#`s)
// - grouping `,` in the int part only: the rightmost comma segment
//   sizes the PRIMARY group; one repeated size to its left is the
//   SECONDARY group (Indian style `#,##,##0`); anything else is
//   rejected
// - one scaler: `%` (×100) or `‰` (×1000)
// - one currency placeholder `¤` (its position places the symbol)
// - optional exponent: `E0`, `E+0`, `E00`, `E+00`, `E-00` (1-2
//   exponent placeholders)
//
// Bounds: 96 Unicode scalars per pattern, 12 fractional placeholders,
// output capped at 256 characters. The renderer is total: NaN/±inf
// and ±0 are guarded by the caller; huge/subnormal magnitudes render
// through decimal digit strings and can never trap or hang.

public enum NumberPatternError: Error, Equatable, Sendable {
    case tooLong
    case tooManySections
    case unterminatedQuote
    case noSkeleton
    case multipleDecimals
    case multipleExponents
    case multipleScalers
    case multipleCurrencies
    case badDigitOrder
    case badGrouping
    case tooManyFractionDigits
    case tooManyExponentDigits
}

public struct NumberPatternSection: Equatable, Sendable {
    public var literalPrefix: String
    public var literalSuffix: String
    public var intRequired: Int
    public var intOptional: Int
    public var hasDecimal: Bool
    public var fracRequired: Int
    public var fracOptional: Int
    public var primaryGrouping: Int    // 0 = no grouping
    public var secondaryGrouping: Int  // 0 = none
    public var currencyPrefix: Bool
    public var currencySuffix: Bool
    public var percent: Bool
    public var perMille: Bool
    public var exponentDigits: Int     // 0 = no exponent part
    public var exponentSign: Character?

    public var hasCurrency: Bool { currencyPrefix || currencySuffix }
}

/// r87: the validated pattern. `raw` is the verbatim source (invalid
/// patterns stay persisted/editable; `validate` is the only gate to
/// rendering, so an invalid pattern can never reach the renderer).
public struct NumberPattern: Equatable, Sendable {
    public let raw: String
    public let positive: NumberPatternSection
    public let negative: NumberPatternSection?
    public let zero: NumberPatternSection?

    public init(raw: String, positive: NumberPatternSection,
                negative: NumberPatternSection?, zero: NumberPatternSection?) {
        self.raw = raw
        self.positive = positive
        self.negative = negative
        self.zero = zero
    }

    /// Convenience: the validated pattern, or nil when invalid.
    public static func tryValidated(_ raw: String) -> NumberPattern? {
        switch validate(raw) {
        case .success(let p): return p
        case .failure: return nil
        }
    }

    public static func validate(_ raw: String) -> Result<NumberPattern, NumberPatternError> {
        guard !raw.isEmpty, raw.unicodeScalars.count <= 96 else {
            return .failure(raw.isEmpty ? .noSkeleton : .tooLong)
        }
        let sections: [String]
        switch Self.splitSections(raw) {
        case .failure(let e): return .failure(e)
        case .success(let parts): sections = parts
        }
        guard sections.count <= 3 else { return .failure(.tooManySections) }
        let parsed: [NumberPatternSection?]
        do { parsed = try sections.map { s in
            // An EMPTY section means "absent" (e.g. `pos;;zero` has
            // no explicit negative section — the renderer falls back
            // to the global negative style for those values).
            s.isEmpty ? nil : try Self.parseSection(s)
        } }
        catch let e as NumberPatternError { return .failure(e) }
        catch { return .failure(.noSkeleton) }
        guard let positive = parsed[0] else { return .failure(.noSkeleton) }
        return .success(NumberPattern(
            raw: raw,
            positive: positive,
            negative: parsed.count > 1 ? parsed[1] : nil,
            zero: parsed.count > 2 ? parsed[2] : nil))
    }

    /// Splits on top-level `;` only (`;` inside `'...'` literals is
    /// data). Fails on unterminated quoting.
    static func splitSections(_ raw: String) -> Result<[String], NumberPatternError> {
        var parts: [String] = []
        var current = ""
        var inQuote = false
        var i = raw.startIndex
        while i < raw.endIndex {
            let ch = raw[i]
            if ch == "'" {
                let next = raw.index(after: i)
                let ahead = next < raw.endIndex ? raw[next] : Character(" ")
                if inQuote, ahead == "'" {
                    current.append("'")
                    i = raw.index(i, offsetBy: 2)
                    continue
                }
                inQuote.toggle()
                current.append(ch)
            } else if ch == ";", !inQuote {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
            i = raw.index(after: i)
        }
        guard !inQuote else { return .failure(.unterminatedQuote) }
        parts.append(current)
        return .success(parts)
    }

    // MARK: Parsing

    private static func parseSection(_ s: String) throws -> NumberPatternSection {
        var sec = NumberPatternSection(
            literalPrefix: "", literalSuffix: "",
            intRequired: 0, intOptional: 0, hasDecimal: false,
            fracRequired: 0, fracOptional: 0,
            primaryGrouping: 0, secondaryGrouping: 0,
            currencyPrefix: false, currencySuffix: false,
            percent: false, perMille: false,
            exponentDigits: 0, exponentSign: nil)

        // Single walk: quoted literals become the prefix or the suffix
        // depending on whether the skeleton had begun; everything else
        // is skeleton. Quoted regions are contiguous, so a run can
        // never straddle the skeleton boundary in valid grammar.
        var skeleton: [Character] = []
        var prefix = ""
        var suffix = ""
        var sawSkeleton = false
        var inQuote = false
        var buf = ""
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "'" {
                let next = s.index(after: i)
                let ahead = next < s.endIndex ? s[next] : Character(" ")
                if inQuote, ahead == "'" {
                    buf.append("'")  // escaped apostrophe (data)
                    i = s.index(i, offsetBy: 2)
                    continue
                }
                inQuote.toggle()
                if inQuote {
                    buf = ""
                } else {
                    if sawSkeleton { suffix.append(buf) } else { prefix.append(buf) }
                    buf = ""
                }
            } else if inQuote {
                buf.append(ch)
            } else {
                sawSkeleton = true
                skeleton.append(ch)
            }
            i = s.index(after: i)
        }
        guard !inQuote else { throw NumberPatternError.unterminatedQuote }
        sec.literalPrefix = prefix
        sec.literalSuffix = suffix

        let chars = Array(skeleton)
        guard !chars.isEmpty else { throw NumberPatternError.noSkeleton }

        // Exponent tail (at most one E marker).
        let eCount = chars.filter { $0 == "E" || $0 == "e" }.count
        guard eCount <= 1 else { throw NumberPatternError.multipleExponents }
        var exp: [Character] = []
        var body = chars
        if let eIdx = chars.firstIndex(where: { $0 == "E" || $0 == "e" }) {
            exp = Array(chars[chars.index(after: eIdx)...])
            body = Array(chars[..<eIdx])
        }
        if !exp.isEmpty {
            let digits = exp.filter { $0.isNumber }
            let signs = exp.filter { $0 == "+" || $0 == "-" }
            guard digits.count == exp.count - signs.count,
                  (1...2).contains(digits.count),
                  signs.count <= 1 else {
                throw NumberPatternError.tooManyExponentDigits
            }
            sec.exponentDigits = digits.count
            sec.exponentSign = signs.first
        }

        // Scalers / currency on the whole skeleton.
        let scalers = chars.filter { $0 == "%" || $0 == "‰" }
        guard scalers.count <= 1 else { throw NumberPatternError.multipleScalers }
        if chars.contains("%") { sec.percent = true }
        if chars.contains("‰") { sec.perMille = true }
        let curCount = chars.filter { $0 == "¤" }.count
        guard curCount <= 1 else { throw NumberPatternError.multipleCurrencies }
        if let cIdx = chars.firstIndex(of: "¤") {
            if let fd = chars.firstIndex(where: { $0 == "0" || $0 == "#" }) {
                if cIdx < fd { sec.currencyPrefix = true } else { sec.currencySuffix = true }
            } else {
                sec.currencySuffix = true
            }
        }
        if sec.exponentDigits > 0 && (sec.percent || sec.perMille || sec.hasCurrency) {
            throw NumberPatternError.multipleScalers
        }

        // Scalers are tail symbols in the OUTPUT: the skeleton
        // analysis ignores them (the renderer re-attaches the symbol
        // itself from the section flags), so `0%` and `#,##0.00‰`
        // both validate.
        body = body.filter { $0 != "%" && $0 != "\u{2030}" && $0 != "¤" }

        // Body: at most one decimal point.
        let dots = body.filter { $0 == "." }
        guard dots.count <= 1 else { throw NumberPatternError.multipleDecimals }
        var intChars: [Character] = []
        var fracChars: [Character] = []
        if let dIdx = body.firstIndex(of: ".") {
            intChars = Array(body[body.startIndex..<dIdx])
            fracChars = Array(body[body.index(after: dIdx)...])
            sec.hasDecimal = true
        } else {
            intChars = body
        }

        let (intZeros, intHashes, intCommas) = try Self.classifyDigits(intChars, isInt: true)
        sec.intRequired = intZeros
        sec.intOptional = intHashes
        if intCommas > 0 {
            let (primary, secondary) = try Self.groupingSizes(intChars)
            sec.primaryGrouping = primary
            sec.secondaryGrouping = secondary
        }

        let (fracZeros, fracHashes, _) = try Self.classifyDigits(fracChars, isInt: false)
        sec.fracRequired = fracZeros
        sec.fracOptional = fracHashes
        guard fracZeros + fracHashes <= 12 else { throw NumberPatternError.tooManyFractionDigits }

        guard intZeros + intHashes + fracZeros + fracHashes > 0
        else { throw NumberPatternError.noSkeleton }
        if sec.exponentDigits > 0 {
            guard intZeros + intHashes + fracZeros > 0
            else { throw NumberPatternError.noSkeleton }
        }
        return sec
    }

    /// Order-validated digit counts: int — `#`s then `0`s (a `0` never
    /// precedes a `#`); fraction — `0`s then `#`s. Commas only in the
    /// int part (grouping, not digits).
    private static func classifyDigits(_ chars: [Character],
                                       isInt: Bool) throws
        -> (zeros: Int, hashes: Int, commas: Int) {
        var zeros = 0, hashes = 0, commas = 0
        var sawZero = false
        for ch in chars {
            switch ch {
            case "0":
                zeros += 1
                sawZero = true
            case "#":
                if isInt, sawZero { throw NumberPatternError.badDigitOrder }
                hashes += 1
            case ",":
                guard isInt else { throw NumberPatternError.badGrouping }
                commas += 1
            default:
                throw NumberPatternError.badDigitOrder
            }
        }
        if !isInt {
            var seenHash = false
            for ch in chars {
                if ch == "#" { seenHash = true }
                if ch == "0", seenHash { throw NumberPatternError.badDigitOrder }
            }
        }
        return (zeros, hashes, commas)
    }

    /// The comma-implied group sizes, right to left. The rightmost
    /// segment (after the last comma) defines the PRIMARY group size;
    /// every full segment to its left must be one repeated SECONDARY
    /// size; the leftmost may be a partial remainder (<= secondary).
    private static func groupingSizes(_ intChars: [Character]) throws
        -> (primary: Int, secondary: Int) {
        var segments: [Int] = []
        var size = 0
        for ch in intChars.reversed() {
            switch ch {
            case "0", "#": size += 1
            case ",":
                segments.append(size)
                size = 0
            default: break
            }
        }
        segments.append(size)
        guard !segments.isEmpty else { throw NumberPatternError.badGrouping }
        let primary = segments[0]
        guard (1...3).contains(primary) else { throw NumberPatternError.badGrouping }
        var secondary = 0
        if segments.count >= 3 {
            // Two or more grouped blocks: every block except the
            // leftmost remainder is the fixed secondary size
            // (`#,##,##0` = Indian-style 3/3).
            secondary = segments[1]
            guard (1...3).contains(secondary) else { throw NumberPatternError.badGrouping }
            for (idx, seg) in segments.enumerated() where idx >= 2 {
                let isLeftmost = idx == segments.count - 1
                guard seg == secondary || (isLeftmost && seg <= secondary) else {
                    throw NumberPatternError.badGrouping
                }
            }
        } else if segments.count == 2 {
            // ONE comma: the block left of it is the leftmost
            // remainder (no secondary size at all — `#,##0` groups
            // every 3 digits: 1,234,567).
            guard (1...primary).contains(segments[1]) else {
                throw NumberPatternError.badGrouping
            }
        }
        return (primary, secondary)
    }

    // MARK: Rendering

    /// Renders `value` through `section` (the caller picks
    /// positive/negative/zero) — pure string math on the value's
    /// decimal digits: total for every finite input, never blank
    /// (at least one digit is always emitted), output capped at 256
    /// characters. `int64Value` gives the EXACT Int64 digit path
    /// (no Double precision change for |v| > 2^53). `currencySymbol`
    /// replaces the pattern's `¤` placeholder; without it the token
    /// renders as `¤` (unknown-currency shape is the API layer's job).
    public func renderValue(_ value: Double,
                            int64Value: Int64? = nil,
                            section: NumberPatternSection,
                            context: NumberFormatContext,
                            currencySymbol: String? = nil) -> String {
        let digits = Self.magnitudeDigits(value: value, int64: int64Value, section: section)
        return renderDigits(digits, section: section, context: context,
                            currencySymbol: currencySymbol)
    }

    /// The signed magnitude as (sign, intDigits, fracDigits): the
    /// scaled (percent/per-mille shifted) decimal digits rounded at
    /// the pattern's fraction boundary (away from zero — deterministic
    /// display rounding). Zero and -0 normalize to unsigned "0".
    static func magnitudeDigits(value: Double,
                                int64: Int64?,
                                section: NumberPatternSection)
        -> (sign: Bool, intDigits: [Character], fracDigits: [Character]) {
        if let exact = int64 {
            var d = exact
            if section.percent { d = d * 100 }
            if section.perMille { d = d * 1000 }
            let neg = d < 0
            let mag = neg ? -d : d
            return (neg, Array(String(mag)), [])
        }
        guard value.isFinite else {
            // Guarded by the caller; the fallback renders as zero.
            return (false, ["0"], [])
        }
        let neg = value < 0
        let mag = value == 0 ? 0 : abs(value)
        let needFrac = section.fracRequired + section.fracOptional
        let shift = section.percent ? 2 : (section.perMille ? 3 : 0)
        let factor = shift == 2 ? 100.0 : (shift == 3 ? 1000.0 : 1.0)
        let scaled = mag * factor
        // Guard digits beyond the pattern's need keep the rounding at
        // the boundary stable for display.
        let precision = needFrac + 2
        let text = String(format: "%.\(precision)f", scaled)
        let chars = Array(text)
        // The point sits after the int digits: prefix EXCLUDING it.
        let point = chars.count - precision - 1
        var intPart = Array(chars.prefix(point))
        var fracPart = Array(chars.suffix(precision))
        let keep = needFrac
        if fracPart.count > keep {
            // Round at the boundary: a next digit >= 5 bumps the last
            // kept digit (propagating through 9s and the int part).
            if fracPart[keep] >= "5" {
                Self.roundUp(&intPart, &fracPart, keep: keep)
            }
            fracPart = Array(fracPart.prefix(keep))
        }
        while intPart.count > 1, intPart.first == "0" { intPart.removeFirst() }
        return (neg, intPart, fracPart)
    }

    /// Adds 1 to the last kept fraction digit, carrying through 9s
    /// into the int part (returns the new int part length).
    private static func roundUp(_ intPart: inout [Character],
                                _ fracPart: inout [Character],
                                keep: Int) {
        func bump(_ arr: inout [Character], _ i: Int) -> Bool {
            let v = arr[i].asciiValue!
            if v < 57 { arr[i] = Character(UnicodeScalar(v + 1)); return true }
            arr[i] = "0"
            return false
        }
        var i = keep - 1
        while i >= 0 {
            if bump(&fracPart, i) { return }
            i -= 1
        }
        var j = intPart.count - 1
        while j >= 0 {
            if bump(&intPart, j) { return }
            j -= 1
        }
        intPart.insert("1", at: 0)
    }

    /// The digit layout through the section's skeleton: int padding
    /// and grouping, required/optional fraction digits, literal
    /// prefix/suffix, the currency placeholder, percent/per-mille
    /// markers and the exponent part. Localized through `context`.
    private func renderDigits(_ digits: (sign: Bool, intDigits: [Character], fracDigits: [Character]),
                              section: NumberPatternSection,
                              context: NumberFormatContext,
                              currencySymbol: String?) -> String {
        var intD = digits.intDigits
        var fracD = digits.fracDigits
        let dec = context.legacy || context.decimalSeparator == "." ? "." : context.decimalSeparator
        let grp = context.groupingSeparator.isEmpty ? "," : context.groupingSeparator
        let curSymbol = section.hasCurrency
            ? (currencySymbol?.isEmpty == false ? currencySymbol! : "¤")
            : ""

        if section.exponentDigits > 0 {
            return renderExponent(digits: digits, section: section, dec: dec,
                                  currencySymbol: curSymbol)
        }

        var out = section.literalPrefix
        if section.currencyPrefix { out += curSymbol }
        // Int part: pad up to the pattern's required digit count
        // (`00.##` shows leading zeros); overflow digits extend left.
        if intD.count < section.intRequired {
            intD = Array(repeating: Character("0"),
                         count: section.intRequired - intD.count) + intD
        }
        let intText = groupDigits(intD, section: section, separator: grp)
        out += intText
        if section.hasDecimal || section.fracRequired > 0 || section.fracOptional > 0 {
            let neededFrac = section.fracRequired + section.fracOptional
            if fracD.count < neededFrac {
                fracD = fracD + Array(repeating: Character("0"),
                                      count: neededFrac - fracD.count)
            }
            // Required digits always show; optional trailing zeros
            // trim away. An all-zero optional fraction with NO
            // required digits suppresses the decimal point entirely
            // (`1.00` -> `1`; `0.00` keeps the pattern's zeros).
            var shown = fracD
            while shown.count > section.fracRequired,
                  let last = shown.last, last == "0" {
                shown.removeLast()
            }
            if section.hasDecimal || section.fracRequired > 0 || !shown.isEmpty {
                out += dec
                out += String(shown)
            }
        }
        if section.percent { out += "%" }
        if section.perMille { out += "‰" }
        if section.currencySuffix { out += curSymbol }
        out += section.literalSuffix
        if out.unicodeScalars.count > 256 { out = String(out.prefix(256)) }
        return out
    }

    /// Groups `d` from the right: the trailing `primary` digits stay
    /// together; the digits to their left group in `secondary` runs
    /// (the leftmost run may be a partial remainder). No separators
    /// while the int part is not longer than the primary group.
    private func groupDigits(_ d: [Character],
                             section: NumberPatternSection,
                             separator: String) -> String {
        let p = section.primaryGrouping
        guard p > 0 else { return String(d) }
        let n = d.count
        guard n > p else { return String(d) }
        let s = section.secondaryGrouping > 0 ? section.secondaryGrouping : p
        // Block sizes, left to right: [remainder?, s, s, …, p]
        var sizes: [Int] = []
        let rest = n - p
        if rest > 0 {
            var lead = rest % s
            if lead == 0 { lead = s }
            sizes.append(lead)
            let fullBlocks = (rest - lead) / s
            for _ in 0..<fullBlocks { sizes.append(s) }
        }
        sizes.append(p)
        var out = ""
        var idx = 0
        for (bi, size) in sizes.enumerated() {
            if bi > 0 { out += separator }
            out += String(d[idx..<idx + size])
            idx += size
        }
        return out
    }

    /// Exponent section: the mantissa fills the pattern's digit slots
    /// from the first significant digit; the exponent is `dp -
    /// mantissaInt` with the pattern's minimum digits and optional
    /// fixed sign, where `dp` is the decimal position of the first
    /// significant digit (123.45 → 3, 0.0045 → -2). An int part
    /// written with required `0`s anchors the mantissa on those
    /// (scientific shape); an all-`#` int part anchors the exponent
    /// on a multiple of 3 (engineering shape).
    private func renderExponent(digits: (sign: Bool, intDigits: [Character], fracDigits: [Character]),
                                section: NumberPatternSection,
                                dec: String,
                                currencySymbol: String) -> String {
        let signChar: String = digits.sign ? "-" : ""
        let intD = digits.intDigits
        let fracD = digits.fracDigits
        let isZero = intD.count == 1 && intD[0] == "0" && fracD.allSatisfy { $0 == "0" }

        let dp: Int
        if isZero {
            dp = 1
        } else {
            let leadingZeroInt = intD.count - intD.drop(while: { $0 == "0" }).count
            if leadingZeroInt < intD.count {
                dp = intD.count - leadingZeroInt
            } else {
                let fracLeading = fracD.prefix(while: { $0 == "0" }).count
                dp = 1 - (fracLeading + 1)
            }
        }

        let mantissaInt: Int
        let exp: Int
        if section.intRequired >= 1 {
            // Scientific anchor: the required int digits pin `dp - m`.
            mantissaInt = max(section.intRequired, 1)
            exp = dp - mantissaInt
        } else {
            // Engineering anchor: exponent a multiple of 3, mantissa
            // in [1, 1000).
            let t = dp - 1
            let m = 1 + ((t % 3) + 3) % 3
            mantissaInt = m
            exp = dp - m
        }

        var mantissa: [Character]
        if isZero {
            mantissa = Array(repeating: Character("0"), count: mantissaInt)
        } else {
            let stream = intD + fracD
            let firstSig = stream.firstIndex { $0 != "0" }!
            var idx = firstSig
            var count = 0
            mantissa = []
            while count < mantissaInt + section.fracRequired,
                  idx < stream.endIndex {
                mantissa.append(stream[idx])
                count += 1
                idx = stream.index(after: idx)
            }
            while mantissa.count < mantissaInt + section.fracRequired {
                mantissa.append("0")
            }
            while mantissa.count > mantissaInt + section.fracRequired,
                  mantissa.last == "0" {
                mantissa.removeLast()
            }
        }
        var mantissaText = String(mantissa.prefix(mantissaInt))
        if section.hasDecimal, mantissa.count > mantissaInt {
            mantissaText += dec + String(mantissa[mantissaInt...])
        }
        var expText = String(abs(exp))
        if section.exponentDigits > expText.count {
            expText = String(repeating: "0", count: section.exponentDigits - expText.count) + expText
        }
        let signMark: String
        if exp < 0 { signMark = "-" }
        else if section.exponentSign == "-" { signMark = "-" }
        else { signMark = section.exponentSign == "+" ? "+" : "" }

        var out = section.literalPrefix
        if section.currencyPrefix { out += currencySymbol }
        out += signChar
        out += mantissaText
        out += "e\(signMark)\(expText)"
        if section.currencySuffix { out += currencySymbol }
        out += section.literalSuffix
        if out.unicodeScalars.count > 256 { out = String(out.prefix(256)) }
        return out
    }
}
