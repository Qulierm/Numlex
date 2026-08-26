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
    /// plus one entries). Returns `nil` when the line must be left
    /// untouched (prose, comment, title, blank, conversion).
    public static func canonicalLine(_ line: String,
                                     rates: Rates = Rates(),
                                     decimalPlaces: Int = 7) -> (text: String, map: [Int])? {
        let env = TypedEnv()
        guard isMathematical(line, env: env, rates: rates, decimalPlaces: decimalPlaces) else {
            return nil
        }
        let text = canonicalMathText(line)
        return (text, insertionMap(from: line, to: text))
    }

    /// One canonical pass over a whole document, following the same
    /// top-down TYPED environment flow the evaluator and the answer
    /// column use. Untouched lines — and every natural line (money
    /// assignments, rate lines, named references, even incomplete
    /// prefixes typed mid-edit) — are preserved byte-for-byte.
    public static func canonicalDocument(_ content: String,
                                         rates: Rates = Rates(),
                                         decimalPlaces: Int = 7) -> String {
        var env = TypedEnv()
        let lines = content.components(separatedBy: "\n")
        var out: [String] = []
        for line in lines {
            // Natural lines are NEVER touched: their prose and glyph
            // placement (currency markers, `per`/time words, terminal
            // dots, multiword names) have no caret map, and rewriting
            // them mid-typing would move the caret or the U+FFFC
            // answer markers.
            if isNaturalShape(line, env: env) {
                out.append(line)
                continue
            }
            if let result = evalLineTyped(line, env: &env, rates: rates,
                                          decimalPlaces: decimalPlaces,
                                          now: Date(), calendar: Calendar.current) {
                switch result {
                case .number(_, .none), .variable, .error:
                    out.append(canonicalMathText(line))
                case .number(_, .some), .money, .date, .blank, .skip, .title, .brokenToken:
                    // Conversions, money and date lines are preserved
                    // byte-identical: their prose and glyph placement
                    // (currency markers, month names) have no caret map.
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

    /// The pure text transformation for a mathematical line (see the
    /// type-level rules). Idempotent: already-canonical input comes back
    /// unchanged.
    public static func canonicalMathText(_ input: String) -> String {
        // Preserve leading indentation verbatim.
        var prefix = ""
        var i = input.startIndex
        while i < input.endIndex, input[i] == " " || input[i] == "\t" {
            prefix.append(input[i])
            i = input.index(after: i)
        }
        var s = String(input[i...]).replacingOccurrences(of: "*", with: "×")
        s = s.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\t", with: " ")
        return prefix + reemit(scan(s))
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

    private static func scan(_ s: String) -> [Tok] {
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
            if opChars.contains(c) {
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

    private static func reemit(_ toks: [Tok]) -> String {
        var out = ""
        var lastWasOp = false
        var justUnary = false
        for t in toks {
            switch t.kind {
            case .op:
                if !out.isEmpty && !out.hasSuffix(" ") { out.append(" ") }
                out.append(t.text)
                out.append(" ")
                lastWasOp = true
                justUnary = false
            case .unary:
                // Attached to the operand; a pending space stays only
                // when it belongs to the previous operator (`x × -2`).
                out.append(t.text)
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
