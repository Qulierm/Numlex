import Foundation

/// One currency occurrence on one input line: a symbol marker (`$500`,
/// `240$`, `100zł`) or a case-insensitive ISO code annotation
/// (`500 usd`). The code is always the canonical UPPERCASE ISO code and
/// the ranges are exact UTF-16 spans of the ORIGINAL line — the source
/// text is never rewritten, so caret, selection and document bytes stay
/// untouched.
public struct CurrencyOccurrence: Equatable, Sendable {
    public enum Shape: Equatable, Sendable {
        /// A shared-table symbol/letter marker (`$`, `€`, `CA$`, `Rp`, `zł`).
        case symbolMarker
        /// A three-letter ISO code annotating an amount (`500 usd`).
        case isoCode
    }

    /// Canonical UPPERCASE ISO code (`usd`/`Usd`/`USD` all give `USD`).
    public let code: String
    /// UTF-16 range of the marker/code text itself.
    public let range: NSRange
    public let shape: Shape
    /// A marker glued BEFORE its amount (`$500`, `Rp25000`).
    public let isPrefix: Bool
    /// UTF-16 index right AFTER the amount this occurrence annotates —
    /// the insertion point for an internal conversion factor.
    public let amountEnd: Int

    public init(code: String, range: NSRange, shape: Shape,
                isPrefix: Bool, amountEnd: Int) {
        self.code = code
        self.range = range
        self.shape = shape
        self.isPrefix = isPrefix
        self.amountEnd = amountEnd
    }
}

/// THE shared currency-annotation scanner. One boundary-safe,
/// case-insensitive pass returns every symbol marker and every ISO code
/// annotation on a line, canonicalized and positioned. Used by money
/// detection, natural-shape probing and syntax highlighting, so the
/// three can never drift.
public enum CurrencyAnnotations {

    /// The canonical uppercase ISO code for a case-insensitive
    /// three-ASCII-letter token, or nil when it is not a supported
    /// fiat code. Never rewrites the caller's text.
    public static func canonicalCode(_ raw: String) -> String? {
        guard raw.count == 3 else { return nil }
        for scalar in raw.unicodeScalars {
            let v = scalar.value
            let isLetter = (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v)
            guard isLetter else { return nil }
        }
        let upper = raw.uppercased()
        return FiatCurrencies.codes.contains(upper) ? upper : nil
    }

    /// ISO code annotations: a three-letter code after an amount
    /// (digit or decimal point, then whitespace). Boundary-safe — the
    /// code must not be glued to a following/previous alphanumeric run,
    /// so identifiers, prose and `2 apples` are never money.
    private static let isoRe = try? NSRegularExpression(
        pattern: #"(?<=[0-9.])\s+([A-Za-z]{3})(?![A-Za-z0-9_])"#)

    /// Every ISO annotation on `line`, source order. A lowercase
    /// spelling that is already an existing NON-currency unit label
    /// (`250 cup` is a volume, not CUP) keeps its unit reading — the
    /// case-insensitive money grammar never captures a real unit.
    public static func isoOccurrences(in line: String) -> [CurrencyOccurrence] {
        guard let isoRe else { return [] }
        let ns = line as NSString
        var out: [CurrencyOccurrence] = []
        for m in isoRe.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            guard m.numberOfRanges >= 2 else { continue }
            let raw = ns.substring(with: m.range(at: 1))
            guard let code = canonicalCode(raw) else { continue }
            if raw != raw.uppercased(), isNonCurrencyUnitWord(raw) { continue }
            // The amount ends where the whitespace run before the code
            // begins (the regex guarantees a digit/`.` right before it).
            var end = m.range(at: 1).location
            while end > 0, ns.character(at: end - 1) == 0x20 || ns.character(at: end - 1) == 0x09 {
                end -= 1
            }
            out.append(CurrencyOccurrence(code: code, range: m.range(at: 1),
                                          shape: .isoCode, isPrefix: false,
                                          amountEnd: end))
        }
        return out
    }

    /// Every symbol-marker occurrence on `line` (the shared
    /// boundary grammar), source order.
    public static func symbolOccurrences(in line: String) -> [CurrencyOccurrence] {
        let ns = line as NSString
        var out: [CurrencyOccurrence] = []
        for r in CurrencyPresentation.markerOccurrences(in: line) {
            let marker = ns.substring(with: r)
            guard let code = CurrencyPresentation.code(forMarker: marker) else { continue }
            let end = r.location + r.length
            let next = end < ns.length ? ns.character(at: end) : 0
            let isPrefix = (0x30...0x39).contains(next) || next == 0x2E
            let amountEnd = isPrefix ? amountEndAfterPrefixMarker(ns, at: end) : r.location
            out.append(CurrencyOccurrence(code: code, range: r,
                                          shape: .symbolMarker, isPrefix: isPrefix,
                                          amountEnd: amountEnd))
        }
        return out
    }

    /// The UTF-16 start of the amount an occurrence annotates: the
    /// matching `(` of a parenthesized amount (`(500 + 100) usd`), else
    /// the start of the numeric run (regional separators and a compact
    /// `k`/`M` suffix included). Used to wrap an amount in an explicit
    /// conversion product without ever re-parsing its digits.
    public static func amountStart(in line: String, amountEnd: Int) -> Int {
        let ns = line as NSString
        guard amountEnd > 0, amountEnd <= ns.length else { return amountEnd }
        if ns.character(at: amountEnd - 1) == 0x29 { // ')'
            var depth = 0
            var i = amountEnd - 1
            while i >= 0 {
                let c = ns.character(at: i)
                if c == 0x29 { depth += 1 }
                else if c == 0x28 { depth -= 1; if depth == 0 { return i } }
                i -= 1
            }
            return amountEnd
        }
        var start = amountEnd
        while start > 0 {
            let c = ns.character(at: start - 1)
            let isDigit = (0x30...0x39).contains(c)
            let isSep = c == 0x2C || c == 0x2E || c == 0x27 || c == 0xA0 || c == 0x202F
            if isDigit || isSep { start -= 1; continue }
            if c == 0x6B || c == 0x4B || c == 0x6D || c == 0x4D, start >= 2 {
                // A compact suffix only counts glued to a digit/`.`.
                let b = ns.character(at: start - 2)
                if (0x30...0x39).contains(b) || b == 0x2E { start -= 1; continue }
            }
            break
        }
        return start
    }

    /// Every currency occurrence on `line` — symbol markers and ISO
    /// codes alike — sorted by source position.
    public static func occurrences(in line: String) -> [CurrencyOccurrence] {
        (symbolOccurrences(in: line) + isoOccurrences(in: line))
            .sorted { $0.range.location < $1.range.location }
    }

    /// Whether the line carries any currency annotation.
    public static func hasAnnotation(in line: String) -> Bool {
        !symbolOccurrences(in: line).isEmpty || !isoOccurrences(in: line).isEmpty
    }

    /// Whether a lowercase word is already an existing unit label of a
    /// NON-currency kind (`cup`, `gal`, ...). Currency labels are not
    /// units for this purpose: `250 usd` is money.
    private static func isNonCurrencyUnitWord(_ raw: String) -> Bool {
        let w = raw.lowercased()
        guard let p = UnitCatalog.resolveExpression(w) else { return false }
        if case .currency = p.unit.kind { return false }
        return true
    }

    /// The end of the amount glued to a prefix marker: digits with
    /// regional separators, an optional compact `k`/`K`/`m`/`M`
    /// suffix and an optional `%`.
    private static func amountEndAfterPrefixMarker(_ ns: NSString, at start: Int) -> Int {
        var i = start
        var sawDigit = false
        while i < ns.length {
            let c = ns.character(at: i)
            if (0x30...0x39).contains(c) { sawDigit = true; i += 1; continue }
            if !sawDigit { break }
            if c == 0x2C || c == 0x2E || c == 0x27 || c == 0x20 || c == 0xA0 || c == 0x202F {
                // A separator must be followed by another digit to stay
                // part of the amount (`$5 + 2` never swallows the `+`).
                guard i + 1 < ns.length, (0x30...0x39).contains(ns.character(at: i + 1)) else { break }
                i += 1
                continue
            }
            break
        }
        guard sawDigit else { return start }
        if i < ns.length {
            let c = ns.character(at: i)
            if c == 0x6B || c == 0x4B || c == 0x6D || c == 0x4D { i += 1 }
        }
        if i < ns.length, ns.character(at: i) == 0x25 { i += 1 }
        return i
    }
}

/// The pure cross-currency arithmetic policy shared by the money core
/// and the answer-token algebra: which currency anchors a result, the
/// per-operand factors into that anchor, and the structural rejection
/// of currency ×/÷ currency. No I/O, no display parsing, no evaluator
/// state.
public enum CurrencyArithmetic {

    /// The anchor code: the FIRST explicit/named money operand in
    /// source order (never a `Set.first` over unordered codes). Returns
    /// nil when there is no money operand at all.
    public static func anchor(
        occurrences: [CurrencyOccurrence],
        namedMoney: [(location: Int, code: String)]
    ) -> String? {
        var best: (location: Int, code: String)?
        for o in occurrences {
            let c = (location: o.range.location, code: o.code)
            if best == nil || c.location < best!.location { best = c }
        }
        for n in namedMoney {
            let c = (location: n.location, code: n.code.uppercased())
            if best == nil || c.location < best!.location { best = c }
        }
        return best?.code
    }

    /// The factor that converts a value in `code` into `anchor` (1 for
    /// the anchor itself and for a same-code operand, which never needs
    /// a rate table). Nil when the pair is unavailable — the caller
    /// surfaces `Rates unavailable`, never a fabricated rate.
    public static func factor(from code: String, to anchor: String,
                              rates: Rates) -> Double? {
        let from = code.uppercased(), to = anchor.uppercased()
        if from == to { return 1 }
        guard let r = rates.rate(from: from, to: to) else { return nil }
        return r.isFinite ? r : nil
    }

    /// The per-code factors into `anchor`, or nil when any pair is
    /// missing from the supplied table.
    public static func factors(codes: Set<String>, anchor: String,
                               rates: Rates) -> [String: Double]? {
        var out: [String: Double] = [:]
        for c in codes {
            guard let f = factor(from: c, to: anchor, rates: rates) else { return nil }
            out[c.uppercased()] = f
        }
        return out
    }

    /// Whether the rewritten expression multiplies or divides a
    /// currency operand by ANOTHER currency operand (never allowed —
    /// no `USD²`, no cross-currency ratio). Currency × scalar and
    /// currency ÷ scalar stay legal; physical units are untouched.
    /// `currencyFactor` marks the internal conversion-factor
    /// identifiers so an atom can be recognized as a money operand.
    public static func hasCurrencyProductOrQuotient(_ expression: String,
                                                    currencyFactor: String = "__fx") -> Bool {
        let ns = expression as NSString
        var i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c == 0x2A || c == 0x00D7 || c == 0x2F || c == 0x00F7 { // * × / ÷
                let left = atom(ns, endingAt: i, currencyFactor: currencyFactor)
                let right = atom(ns, startingAt: i + 1, currencyFactor: currencyFactor)
                if left, right { return true }
            } else if c == 0x5E { // ^ — a money base or exponent is invalid
                // A money operand on either side of `^` would silently
                // square a currency; reject like a product.
                let left = atom(ns, endingAt: i, currencyFactor: currencyFactor)
                let right = atom(ns, startingAt: i + 1, currencyFactor: currencyFactor)
                if left || right { return true }
            } else if c == 0x28 { // (
                // Walk into the group normally; each operator is visited.
            }
            i += 1
        }
        return false
    }

    /// Whether the atom immediately before `index` contains a currency
    /// conversion factor: a parenthesized group is inspected whole, an
    /// identifier/number only if it carries the factor marker.
    private static func atom(_ ns: NSString, endingAt index: Int,
                             currencyFactor: String) -> Bool {
        var i = index - 1
        while i >= 0, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i -= 1 }
        guard i >= 0 else { return false }
        if ns.character(at: i) == 0x29 { // ')'
            var depth = 0
            var start = i
            while start >= 0 {
                let c = ns.character(at: start)
                if c == 0x29 { depth += 1 }
                else if c == 0x28 { depth -= 1; if depth == 0 { break } }
                start -= 1
            }
            guard start >= 0 else { return false }
            let group = ns.substring(with: NSRange(location: start, length: i - start + 1))
            return group.contains(currencyFactor)
        }
        var start = i
        while start >= 0 {
            let c = ns.character(at: start)
            let isWord = (0x30...0x39).contains(c) || (0x41...0x5A).contains(c)
                || (0x61...0x7A).contains(c) || c == 0x5F || c == 0x2E
            if !isWord { break }
            start -= 1
        }
        let word = ns.substring(with: NSRange(location: start + 1, length: i - start))
        return word.contains(currencyFactor)
    }

    /// Whether the atom immediately after `index` contains a currency
    /// conversion factor.
    private static func atom(_ ns: NSString, startingAt index: Int,
                             currencyFactor: String) -> Bool {
        var i = index
        while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        guard i < ns.length else { return false }
        if ns.character(at: i) == 0x28 { // '('
            var depth = 0
            var end = i
            while end < ns.length {
                let c = ns.character(at: end)
                if c == 0x28 { depth += 1 }
                else if c == 0x29 { depth -= 1; if depth == 0 { break } }
                end += 1
            }
            guard end < ns.length else { return false }
            let group = ns.substring(with: NSRange(location: i, length: end - i + 1))
            return group.contains(currencyFactor)
        }
        var end = i
        while end < ns.length {
            let c = ns.character(at: end)
            let isWord = (0x30...0x39).contains(c) || (0x41...0x5A).contains(c)
                || (0x61...0x7A).contains(c) || c == 0x5F || c == 0x2E
            if !isWord { break }
            end += 1
        }
        let word = ns.substring(with: NSRange(location: i, length: end - i))
        return word.contains(currencyFactor)
    }
}
