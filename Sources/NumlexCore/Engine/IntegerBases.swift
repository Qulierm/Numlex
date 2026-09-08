import Foundation

// MARK: - r85: exact integer bases

/// r85: the canonical base names and their aliases. `name(for:)` is the
/// canonical spelling (lowercase) used by phrase grammar; `radix(from:)`
/// is the case-insensitive alias resolver (decimal/base10, binary/base2,
/// octal/base8, hex/hexadecimal/base16). Radices are the only four the
/// language supports end-to-end.
public enum RadixNames {
    /// Canonical names per radix (10 maps to "decimal").
    public static func name(for radix: Int) -> String? {
        switch radix {
        case 2: return "binary"
        case 8: return "octal"
        case 10: return "decimal"
        case 16: return "hex"
        default: return nil
        }
    }

    /// Case-insensitive alias table: canonical names, `base N` spellings
    /// (resolved by the caller via `baseRadix(word:)`) and the
    /// hexadecimal alias.
    public static func radix(from word: String) -> Int? {
        switch word.lowercased() {
        case "decimal", "base10": return 10
        case "binary", "base2": return 2
        case "octal", "base8": return 8
        case "hex", "hexadecimal", "base16": return 16
        default: return nil
        }
    }

    /// The explicit `base N` spelling: `base 2` ... `base 16` (the
    /// grammar matches `base` followed by a single integer literal).
    public static func isBaseWord(_ word: String) -> Bool {
        word.lowercased() == "base"
    }

    /// The `0b` / `0o` / `0x` prefix of a non-decimal radix; decimal
    /// has none.
    public static func prefix(for radix: Int) -> String? {
        switch radix {
        case 2: return "0b"
        case 8: return "0o"
        case 16: return "0x"
        default: return nil
        }
    }
}

/// r85: strict integer literal decoding and canonical formatting.
///
/// Literal grammar: an OPTIONAL unary sign (handled by the caller's
/// parser; `decode` sees the digit run), an optional case-insensitive
/// `0b` / `0o` / `0x` prefix that fixes the radix, then the STRICT
/// digit set of that radix (binary `0-1`, octal `0-7`, hex `0-9 a-f
/// A-F`, decimal `0-9`). A single underscore may separate two digits
/// (`0x1_0`, `100_000`) — never doubled, never at an edge, never
/// adjacent to the prefix's last digit boundary in a way that breaks
/// the "between two digits" rule. Decimal runs may carry a single
/// fractional tail (the scanner hands those to the Double side).
///
/// Decoding is overflow-checked per digit: any run that cannot be an
/// Int64 is nil (bounded digit counts short-circuit first), and the
/// caller decides the visible error.
public enum IntLiteral {
    /// Hard cap on digit-run length before the per-digit fold: beyond
    /// this no Int64 can be produced (2^63 needs at most 64 binary
    /// digits and 20 decimal digits).
    static let maxDigits = 100

    /// Decodes a raw digit run (no sign) to (value, radix), or nil on
    /// an invalid digit, an illegal underscore position, an ambiguous
    /// prefix (`0b2`) or an Int64 overflow.
    public static func decode(_ raw: String) -> (value: Int64, radix: Int)? {
        let chars = Array(raw)
        var i = 0
        var radix = 10
        if chars.count >= 2, chars[0] == "0" {
            let p = chars[1].lowercased()
            if p == "b" { radix = 2 }
            else if p == "o" { radix = 8 }
            else if p == "x" { radix = 16 }
        }
        let isHex = radix == 16
        let isOct = radix == 8
        let isBin = radix == 2
        func allowed(_ c: Character) -> Bool {
            if c == "_" { return true } // position-checked below
            if isBin { return c == "0" || c == "1" }
            if isOct { return "01234567".contains(c) }
            if isHex { return "0123456789abcdefABCDEF".contains(c) }
            return c.isNumber && c.isASCII
        }
        // The digit run starts after the optional prefix.
        let start = (chars.count >= 2 && chars[0] == "0"
                     && (chars[1].lowercased() == "b" || chars[1].lowercased() == "o"
                         || chars[1].lowercased() == "x")) ? 2 : 0
        let digits = chars.dropFirst(start)
        guard !digits.isEmpty, digits.count <= maxDigits else { return nil }
        var value: Int64 = 0
        var lastWasDigit = false
        for c in digits {
            guard allowed(c) else { return nil }
            if c == "_" {
                // Between two digits only: no leading/trailing/doubled
                // underscores.
                guard lastWasDigit else { return nil }
                // The next character (checked next iteration) must be a
                // digit: a trailing underscore fails the final check.
                lastWasDigit = false
                continue
            }
            let d: Int
            if isHex {
                if let i = c.asciiValue, i >= 65, i <= 70 { d = Int(i - 55) }
                else if let i = c.asciiValue, i >= 97, i <= 102 { d = Int(i - 87) }
                else if let i = c.asciiValue, (48...57).contains(i) { d = Int(i - 48) }
                else { return nil }
            } else if let i = c.asciiValue, (48...57).contains(i) {
                d = Int(i - 48)
            } else {
                return nil
            }
            guard d < radix else { return nil }
            // Overflow-checked accumulation.
            guard value <= Int64.max / Int64(radix)
                    || (value == Int64.max / Int64(radix)
                        && Int64(d) <= Int64.max % Int64(radix)) else {
                return nil
            }
            value = value * Int64(radix) + Int64(d)
            lastWasDigit = true
        }
        guard lastWasDigit else { return nil } // trailing underscore
        return (value, radix)
    }

    /// Canonical display: lowercase prefix, uppercase A–F hex digits,
    /// signed-magnitude text for negatives (`-0xff`, `101101`, plain
    /// decimal for radix 10 without a prefix). Underscores are NOT
    /// added (the canonical form is compact).
    public static func format(_ v: Int64, radix: Int) -> String {
        let sign = v < 0 ? "-" : ""
        let mag: Int64
        if v == Int64.min {
            // |Int64.min| overflows: render the magnitude by folding.
            var digits: [Character] = []
            var x = UInt64(bitPattern: v)
            let r = UInt64(radix)
            repeat {
                let d = x / r
                let rem = x % r
                digits.append(char(rem))
                x = d
            } while x > 0
            return sign + digits.reversed().map(String.init).joined()
        } else {
            // Sign was extracted above; the magnitude must be
            // positive (Int64.min handled in the fold path).
            mag = v < 0 ? -v : v
        }
        let r = Int64(radix)
        guard r >= 2 else { return sign + "\(v)" }
        var digits: [Character] = []
        var x = mag
        repeat {
            let d = x % r
            digits.append(char(d))
            x = x / r
        } while x > 0
        if let prefix = RadixNames.prefix(for: radix) {
            return sign + prefix + digits.reversed().map(String.init).joined()
        }
        return sign + digits.reversed().map(String.init).joined()
    }

    /// The locale-aware DECIMAL presentation of an exact Int64:
    /// signed-magnitude digits with the context's integer grouping
    /// separator (comma in dot-decimal modes, the context separator in
    /// decimal-comma modes — including NBSP/space presets, which are
    /// documented no-ops on re-input). No compact notation, no
    /// decimals: base answers copy exactly what they show.
    public static func formatDecimal(_ v: Int64, context: NumberFormatContext) -> String {
        let sign = v == Int64.min ? "-" : (v < 0 ? "-" : "")
        let mag = v == Int64.min
            ? String(UInt64(bitPattern: v))
            : String(v.magnitude)
        let sep: Character
        if context.decimalComma {
            // The decimal-comma grouping glyph: NBSP or plain space
            // presets stay their documented no-op characters; a dot
            // grouping in comma mode is the Eastern preset's `.`.
            sep = Character(context.groupingSeparator.unicodeScalars.first!)
        } else {
            sep = ","
        }
        var grouped = ""
        let chars = Array(mag)
        for (i, c) in chars.enumerated() {
            if i > 0 && (chars.count - i) % 3 == 0 { grouped.append(sep) }
            grouped.append(c)
        }
        return sign + grouped
    }

    private static func char(_ d: Int64) -> Character {
        if d < 10 { return Character(UnicodeScalar(UInt8(d) + 48)) }
        // A–F uppercase per the canonical presentation contract.
        return Character(UnicodeScalar(UInt8(d - 10) + 65))
    }
    private static func char(_ d: UInt64) -> Character {
        if d < 10 { return Character(UnicodeScalar(UInt8(d) + 48)) }
        return Character(UnicodeScalar(UInt8(d - 10) + 65))
    }
}

/// r85: the anchored whole-line base-conversion phrase
/// `<expression> (as|in|to) <base name | base N>` — the EXPLICIT
/// converter whose target radix wins the result presentation. The
/// expression side is everything before the keyword and must be a
/// non-empty candidate expression (the integer scanner validates it
/// downstream); the target must be one of the four base names or
/// `base <2|8|10|16>`.
public enum BasePhrase {
    /// Matches the line shape and returns (expression, targetRadix).
    /// The LATEST keyword whose trailing tail is exactly a base name
    /// wins (earlier keywords belong to the expression). Returns nil
    /// when no such keyword exists or the expression side is empty.
    public static func match(_ line: String) -> (expression: String, targetRadix: Int)? {
        let ns = line as NSString
        var best: (utf16Start: Int, radix: Int)? = nil
        for k in ["as", "in", "to"] {
            var searchFrom = 0
            while true {
                let r = ns.range(of: k, options: .caseInsensitive,
                                 range: NSRange(location: searchFrom, length: ns.length - searchFrom))
                if r.location == NSNotFound { break }
                searchFrom = r.location + r.length
                // Standalone keyword: line start or whitespace before.
                if r.location > 0 {
                    let prev = ns.character(at: r.location - 1)
                    if !(prev == 0x20 || prev == 0x09) { continue }
                }
                let tail = ns.substring(from: NSMaxRange(r))
                    .trimmingCharacters(in: .whitespaces)
                    .lowercased()
                if let radix = RadixNames.radix(from: tail) {
                    // The tail must be EXACTLY an alias spelling.
                    guard ["decimal", "base10", "binary", "base2", "octal", "base8",
                           "hex", "hexadecimal", "base16"].contains(tail) else { continue }
                    best = (utf16Start: r.location, radix: radix)
                    continue
                }
                if tail.hasPrefix("base") {
                    let rest = tail.dropFirst(4)
                    guard rest.first == " " || rest.isEmpty else { continue }
                    let n = rest.trimmingCharacters(in: .whitespaces)
                    guard let v = Int(n), [2, 8, 10, 16].contains(v) else { continue }
                    best = (utf16Start: r.location, radix: v)
                }
            }
        }
        guard let hit = best else { return nil }
        let expression = ns.substring(to: hit.utf16Start)
            .trimmingCharacters(in: .whitespaces)
        guard !expression.isEmpty else { return nil }
        return (expression, hit.radix)
    }
}
