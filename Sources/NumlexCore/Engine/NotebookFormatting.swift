import Foundation

/// Pure, testable canonical formatting for mathematical notebook lines.
///
/// The canonical form:
/// - writes the actual multiplication sign `×` instead of `*`;
/// - keeps exactly ONE space around binary `+`, `-`, `×`, `/`, `^` and
///   the assignment `=`;
/// - keeps unary `+`/`-` attached to their operand (`-5`, `x × -2`,
///   `-(2 + 3)`);
/// - keeps postfix `%` attached (`50%`);
/// - never puts a space just inside parentheses;
/// - collapses redundant whitespace but preserves leading indentation,
///   and preserves the original adjacency of tokens that carry no
///   spacing rule (e.g. `2(3)` stays tight, `2 (3)` keeps its space).
///
/// Only lines the evaluator treats as mathematical are ever touched:
/// plain numbers, variable assignments and evaluation errors (which
/// always contain a digit). Prose, `#` comments, `//` titles, blank
/// lines and conversion phrases (`10 cm to m`) come back byte-identical.
public enum NotebookFormatting {

    // MARK: - Public API

    /// Canonical form of one line plus a UTF-16 insertion-point map from
    /// the original line to the result (`map` has `line`'s UTF-16 length
    /// plus one entries). Natural lines get the bounded operator
    /// canonicalization (never nil); returns `nil` when the line must be
    /// left untouched (prose, comment, title, blank, conversion).
    public static func canonicalLine(_ line: String,
                                     rates: Rates = Rates(),
                                     decimalPlaces: Int = 7) -> (text: String, map: [Int])? {
        let env = TypedEnv()
        if isNaturalShape(line, env: env) {
            return naturalOperatorCanonical(line)
        }
        if isMathematical(line, env: env, rates: rates, decimalPlaces: decimalPlaces) {
            let text = canonicalMathText(line)
            return (text, insertionMap(from: line, to: text))
        }
        // A money result that is not in natural shape (a reference to a
        // single-identifier money name) gets the bounded natural pass.
        var env2 = env
        if case .money? = evalLineTyped(line, env: &env2, rates: rates,
                                        decimalPlaces: decimalPlaces,
                                        now: Date(), calendar: Calendar.current) {
            return naturalOperatorCanonical(line)
        }
        return nil
    }

    /// One canonical pass over a whole document, following the same
    /// top-down TYPED environment flow the evaluator and the answer
    /// column use. Untouched lines come back byte-identical; natural
    /// lines (money assignments, rate lines, named references, token
    /// expressions — even incomplete prefixes typed mid-edit) get the
    /// BOUNDED operator canonicalization only: `*` becomes `×`, binary
    /// operators get exactly one space on each side, everything else —
    /// prose, currency adjacency, compact suffixes, time words, terminal
    /// punctuation, U+FFFC markers, unrelated whitespace — is preserved
    /// byte-for-byte.
    public static func canonicalDocument(_ content: String,
                                         rates: Rates = Rates(),
                                         decimalPlaces: Int = 7) -> String {
        var env = TypedEnv()
        let lines = content.components(separatedBy: "\n")
        var out: [String] = []
        for line in lines {
            if isNaturalShape(line, env: env) {
                // Advance the shared top-down environment exactly like
                // the evaluator: a natural assignment records its name
                // for the LATER lines, so names format and evaluate
                // consistently in the same pass.
                var lineEnv = env
                _ = evalLineTyped(line, env: &lineEnv, rates: rates,
                                  decimalPlaces: decimalPlaces,
                                  now: Date(), calendar: Calendar.current)
                env = lineEnv
                out.append(naturalOperatorCanonical(line).text)
                continue
            }
            if let result = evalLineTyped(line, env: &env, rates: rates,
                                          decimalPlaces: decimalPlaces,
                                          now: Date(), calendar: Calendar.current) {
                switch result {
                case .number(_, .none), .variable, .error:
                    out.append(canonicalMathText(line))
                case .money:
                    // A money result that is NOT in natural shape (a
                    // reference to a single-identifier money name like
                    // `rent × 12`): the BOUNDED natural operator pass —
                    // operators canonicalized, every other glyph (names,
                    // markers, prose) byte-identical.
                    out.append(naturalOperatorCanonical(line).text)
                case .number(_, .some), .date, .blank, .skip, .title, .brokenToken:
                    // Conversions and date lines are preserved
                    // byte-identical: their prose and glyph placement
                    // (unit words, month names) have no caret map.
                    out.append(line)
                }
            } else {
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    /// True when the line evaluates to a plain number, a variable
    /// assignment, or an evaluation error. Error lines always contain a
    /// digit (the evaluator classifies digit-less lines as prose), so
    /// natural-language text is never classified as mathematical.
    public static func isMathematical(_ line: String,
                                      rates: Rates = Rates(),
                                      decimalPlaces: Int = 7) -> Bool {
        let env = TypedEnv()
        return isMathematical(line, env: env, rates: rates, decimalPlaces: decimalPlaces)
    }

    /// The typed variant: a line is mathematical only when it is NOT in
    /// natural shape (money assignment, rate line, named reference —
    /// preserved byte-identical on every tick) AND it evaluates to a
    /// plain number, a variable assignment, or an evaluation error.
    /// Error lines always contain a digit (the evaluator classifies
    /// digit-less lines as prose), so natural-language text is never
    /// classified as mathematical.
    static func isMathematical(_ line: String, env: TypedEnv,
                               rates: Rates, decimalPlaces: Int) -> Bool {
        if isNaturalShape(line, env: env) { return false }
        var env2 = env
        switch evalLineTyped(line, env: &env2, rates: rates,
                             decimalPlaces: decimalPlaces,
                             now: Date(), calendar: Calendar.current) {
        case .number(_, let unit):
            return unit == nil
        case .variable, .error:
            return true
        case .money, .date, .blank, .skip, .title, .brokenToken, .none:
            // Money/date lines keep their exact typed form.
            return false
        }
    }

    /// Pure shape probe for natural lines — no evaluation involved, so
    /// it answers correctly for INCOMPLETE prefixes while typing
    /// (`monthly rent = $`, `food = $50 per`, `contractor = $85 / hr`):
    /// - a currency marker adjacent to a digit anywhere (`$5`, `45$`,
    ///   `$2.5k`);
    /// - an ISO code annotating a number (`100 USD`);
    /// - a grammar-valid natural LHS before `=` — multiword names
    ///   always, single identifiers when the RHS carries a marker;
    /// - a rate or duration word shape (`per day`, `/ hr`, `30 days`);
    /// - a reference to a declared compound name in `env`.
    public static func isNaturalShape(_ line: String, env: TypedEnv) -> Bool {
        if !NaturalCalculation.markerOccurrences(in: line).isEmpty { return true }
        if let m = line.range(of: #"(\d)\s+([A-Z]{3})\b"#, options: .regularExpression) {
            let code = String(line[m].suffix(3))
            if isCurrencyCode(code) { return true }
        }
        if let eq = line.firstIndex(of: "=") {
            let lhs = String(line[..<eq])
            if let name = NaturalCalculation.naturalLHS(lhs) {
                if name.contains(" ") { return true }
                let rhs = String(line[line.index(after: eq)...])
                if !NaturalCalculation.markerOccurrences(in: rhs).isEmpty { return true }
            }
        }
        let timeWords = "(?:s|sec|secs|second|seconds|min|mins|minute|minutes|"
            + "h|hr|hrs|hour|hours|d|day|days|w|wk|wks|week|weeks)"
        if line.range(of: "(?<![A-Za-z0-9_])per\\s+" + timeWords + "(?![a-z0-9])",
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if line.range(of: "/\\s*" + timeWords + "(?![a-z0-9])",
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if line.range(of: "(?<![A-Za-z0-9_])\\d+(?:\\.\\d+)?\\s+" + timeWords + "(?![a-z0-9])",
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        if NamedValues.matches(in: line, env: env).contains(
            where: { !TypedEnv.isLegacyIdentifier($0.display) }) {
            return true
        }
        return false
    }

    /// The pure, BOUNDED operator canonicalizer for natural lines
    /// (money/rate/named/token expressions — see `isNaturalShape`):
    /// - ASCII `*` becomes the canonical `×`;
    /// - binary `+`, `-`, `×`, `÷`, `/`, `^` and `=` get EXACTLY one
    ///   space on each side (unary signs and postfix `%` stay attached);
    /// - every other glyph is preserved verbatim: prose words, currency
    ///   adjacency (`$50`, `45$`, `CA$`), compact suffixes (`2.5k`),
    ///   time/unit words, terminal punctuation, hyphenated words
    ///   (`state-of-the-art`), `and/or`-style prose slashes, leading
    ///   indentation, U+FFFC markers and unrelated explicitly-typed
    ///   whitespace.
    ///
    /// The output keeps every non-space character in order (only `*`
    /// becomes `×`), so the shared `insertionMap` contract applies:
    /// the returned map is monotone and exact for caret/selection and
    /// marker remapping.
    public static func naturalOperatorCanonical(_ line: String, replaceStar: Bool = true) -> (text: String, map: [Int]) {
        let ns = line as NSString
        let n = ns.length
        guard n > 0 else { return (line, [0]) }
        let c = (0..<n).map { ns.character(at: $0) }
        let opSet: Set<unichar> = [0x2B, 0x2D, 0x00D7, 0x00F7, 0x2F, 0x5E, 0x3D]
        func isDigit(_ u: unichar) -> Bool { (0x30...0x39).contains(u) }
        func isAlpha(_ u: unichar) -> Bool {
            (0x41...0x5A).contains(u) || (0x61...0x7A).contains(u)
        }
        func isMarker(_ u: unichar) -> Bool {
            u == 0x24 || u == 0x20AC || u == 0x00A3 || u == 0x00A5 || u == 0x20BD
        }
        func prevSig(_ i: Int) -> unichar? {
            var k = i - 1
            while k >= 0, c[k] == 0x20 { k -= 1 }
            return k >= 0 ? c[k] : nil
        }
        func nextSigIndex(_ i: Int) -> Int? {
            var k = i + 1
            while k < n, c[k] == 0x20 { k += 1 }
            return k < n ? k : nil
        }
        /// Whether the operator at `i` is binary (spaced) rather than
        /// unary/prose. Deliberately conservative: a `-` between two
        /// letters is a prose hyphen, a `/` between two letters is prose
        /// (`and/or`) — both pass through byte-identical.
        func binary(_ op: unichar, at i: Int) -> Bool {
            let p = prevSig(i)
            let nx = nextSigIndex(i).flatMap { c[$0] }
            switch op {
            case 0x3D:  // =
                return p != nil
            case 0x2B:  // +
                guard let p else { return false }
                return !opSet.contains(p) && p != 0x28
            case 0x00D7, 0x00F7, 0x5E:  // × ÷ ^
                return p != nil && nx != nil
            case 0x2F:  // /
                guard let p, let nx else { return false }
                // An arithmetic context on EITHER side: `$85 / hr`,
                // `240$ / 2`, `) / (`. Word/word (`and/or`) is prose
                // and passes through byte-identical.
                let pArith = isDigit(p) || p == 0x29 || p == 0x25
                    || p == 0xFFFC || isMarker(p)
                let nxArith = isDigit(nx) || nx == 0x28
                    || nx == 0xFFFC || isMarker(nx)
                return pArith || nxArith
            case 0x2D:  // -
                guard let p, let nx else { return false }
                // After an operator, `=`, `(` or a line start the sign
                // is UNARY: it stays attached to its operand.
                if opSet.contains(p) || p == 0x28 { return false }
                if isDigit(nx) || nx == 0x28 || nx == 0xFFFC || isMarker(nx) { return true }
                if isDigit(p) && isAlpha(nx) { return true }
                return false
            default:
                return false
            }
        }
        var out: [unichar] = []
        out.reserveCapacity(n)
        var i = 0
        while i < n {
            let ch = c[i]
            // `*` is the ASCII multiplication in natural lines: the same
            // binary rule as `×`, emitted as `×`.
            let op: unichar? = (ch == 0x2A) ? 0x00D7 : (opSet.contains(ch) ? ch : nil)
            if let op, binary(op, at: i) {
                // Left: exactly one space (drop any run, add one).
                while let last = out.last, last == 0x20 { out.removeLast() }
                if !out.isEmpty { out.append(0x20) }
                // `*` emits as `×` only when the replacement is on.
                out.append((ch == 0x2A && !replaceStar) ? 0x2A : op)
                // Right: exactly one space while a next significant
                // glyph exists — EXCEPT before `(`, where the ORIGINAL
                // adjacency is preserved (`× (2)` stays loose, `×(2)`
                // stays tight). Trailing spaces after an operator never
                // survive.
                if let j = nextSigIndex(i) {
                    if c[j] == 0x28 {
                        if i + 1 < n, c[i + 1] == 0x20 {
                            out.append(contentsOf: c[(i + 1)..<j])
                        }
                    } else {
                        out.append(0x20)
                    }
                    i = j
                    continue
                }
                i = n
                continue
            }
            out.append(ch == 0x2A && replaceStar ? 0x00D7 : ch)
            i += 1
        }
        let text = String(utf16CodeUnits: out, count: out.count)
        return (text, insertionMap(from: line, to: text))
    }

    /// The pure text transformation for a mathematical line (see the
    /// type-level rules). Idempotent: already-canonical input comes back
    /// unchanged.
    public static func canonicalMathText(_ input: String, replaceStar: Bool = true) -> String {
        // Preserve leading indentation verbatim.
        var prefix = ""
        var i = input.startIndex
        while i < input.endIndex, input[i] == " " || input[i] == "\t" {
            prefix.append(input[i])
            i = input.index(after: i)
        }
        var s = String(input[i...])
        // Legacy behavior always rewrites `*`; r19 keeps it when the
        // user disabled the replacement (it still gets padded below).
        if replaceStar { s = s.replacingOccurrences(of: "*", with: "×") }
        s = s.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\t", with: " ")
        return prefix + reemit(scan(s, replaceStar: replaceStar), replaceStar: replaceStar)
    }

    /// UTF-16 insertion-point map: `map[p]` is the position in `to` that
    /// corresponds to insertion point `p` (0...`from`'s UTF-16 length)
    /// in `from`. Valid for the formatter's transformations, which keep
    /// every non-space character in the same order (only `*` becomes
    /// `×` and spaces are inserted/removed).
    public static func insertionMap(from: String, to: String) -> [Int] {
        let f = from as NSString
        let t = to as NSString
        var corePosInTo: [Int] = []
        for u in 0..<t.length where !isSpace16(t.character(at: u)) {
            corePosInTo.append(u)
        }
        var prefix = [Int](repeating: 0, count: f.length + 1)
        for u in 0..<f.length {
            prefix[u + 1] = prefix[u] + (isSpace16(f.character(at: u)) ? 0 : 1)
        }
        var map = [Int](repeating: 0, count: f.length + 1)
        for p in 0...f.length {
            let coresBefore = prefix[p]
            map[p] = coresBefore == 0 ? 0 : corePosInTo[coresBefore - 1] + 1
        }
        return map
    }

    /// Whole-document UTF-16 insertion-point map from `from` to `to`
    /// (both must have the same line count, as produced by
    /// `canonicalDocument`). `map[p]` maps insertion point `p` of the
    /// original document to the canonical one.
    public static func mapDocument(from: String, to: String) -> [Int] {
        let fParts = from.components(separatedBy: "\n")
        let tParts = to.components(separatedBy: "\n")
        var map = [Int]()
        var tOffset = 0
        for (i, line) in fParts.enumerated() {
            let fLineLen = (line as NSString).length
            let tLine = i < tParts.count ? tParts[i] : line
            let lineMap = insertionMap(from: line, to: tLine)
            // The insertion point at the start of line i > 0 is the same
            // point as "just after the previous newline", which the loop
            // already appended — so later lines start at p = 1. Empty
            // later lines contribute no entry of their own.
            let startP = i == 0 ? 0 : 1
            if fLineLen >= startP {
                for p in startP...fLineLen {
                    map.append(tOffset + lineMap[p])
                }
            }
            if i < fParts.count - 1 {
                // The insertion point just after the newline.
                map.append(tOffset + lineMap[lineMap.count - 1] + 1)
            }
            tOffset += (tLine as NSString).length + (i < tParts.count - 1 ? 1 : 0)
        }
        return map
    }

    // MARK: - Scanner

    private struct Tok {
        enum Kind { case op, unary, parenOpen, parenClose, percent, text }
        let kind: Kind
        let text: String
        let wsBefore: Bool
    }

    private static let opChars: Set<Character> = ["+", "-", "×", "÷", "/", "^", "="]

    private static func scan(_ s: String, replaceStar: Bool) -> [Tok] {
        // With the star replacement OFF, `*` survives the input and must
        // still be treated as a binary operator for the padding rules.
        let ops = replaceStar ? opChars : opChars.union(["*"])
        var toks: [Tok] = []
        var i = s.startIndex
        var wsBefore = false
        while i < s.endIndex {
            let c = s[i]
            if c == " " {
                wsBefore = true
                i = s.index(after: i)
                continue
            }
            let kind: Tok.Kind
            if ops.contains(c) {
                // Unary when there is nothing before, or the previous
                // significant token is an operator/`(`/`=`.
                kind = (toks.isEmpty || lastSignificant(toks)) ? .unary : .op
            } else if c == "(" {
                kind = .parenOpen
            } else if c == ")" {
                kind = .parenClose
            } else if c == "%" {
                kind = .percent
            } else {
                kind = .text
            }
            var j = i
            if kind == .text {
                while j < s.endIndex,
                      s[j].isLetter || s[j].isNumber || s[j] == "."
                      || s[j] == "_" || s[j] == "," {
                    j = s.index(after: j)
                }
                if j == i { j = s.index(after: i) }
            } else {
                j = s.index(after: i)
            }
            toks.append(Tok(kind: kind, text: String(s[i..<j]), wsBefore: wsBefore))
            wsBefore = false
            i = j
        }
        return toks
    }

    /// Whether the last significant token makes a following sign unary:
    /// an operator, `=`, or `(`.
    private static func lastSignificant(_ toks: [Tok]) -> Bool {
        guard let t = toks.last else { return false }
        switch t.kind {
        case .op, .unary:
            return true
        case .parenOpen:
            return true
        case .parenClose, .percent, .text:
            return false
        }
    }

    // MARK: - Re-emitter

    private static func reemit(_ toks: [Tok], replaceStar: Bool) -> String {
        var out = ""
        var lastWasOp = false
        var justUnary = false
        for t in toks {
            switch t.kind {
            case .op:
                let glyph = (t.text == "*" && replaceStar) ? "×" : t.text
                if !out.isEmpty && !out.hasSuffix(" ") { out.append(" ") }
                out.append(glyph)
                out.append(" ")
                lastWasOp = true
                justUnary = false
            case .unary:
                // Attached to the operand; a pending space stays only
                // when it belongs to the previous operator (`x × -2`).
                out.append((t.text == "*" && replaceStar) ? "×" : t.text)
                lastWasOp = false
                justUnary = true
            case .parenOpen:
                if t.wsBefore && !out.hasSuffix(" ") { out.append(" ") }
                out.append("(")
                lastWasOp = false
                justUnary = false
            case .parenClose:
                out.append(")")
                lastWasOp = false
                justUnary = false
            case .percent:
                if !lastWasOp, out.hasSuffix(" ") { out.removeLast() }
                out.append("%")
                lastWasOp = false
                justUnary = false
            case .text:
                if justUnary {
                    out.append(t.text)
                } else if t.wsBefore && !lastWasOp && !out.hasSuffix("(") {
                    out.append(" ")
                    out.append(t.text)
                } else {
                    out.append(t.text)
                }
                lastWasOp = false
                justUnary = false
            }
        }
        // Trailing whitespace never survives canonicalization.
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }

    private static func isSpace16(_ u: unichar) -> Bool {
        u == 0x20 || u == 0x09
    }
}
