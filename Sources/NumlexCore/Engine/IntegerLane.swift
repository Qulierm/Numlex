import Foundation

// MARK: - r85: the exact-integer line lane

/// r85: decides WHICH lines the exact integer engine owns, and runs it.
///
/// Triggers (on the raw line, case-insensitive where noted):
/// - STRONG (shape-owned — an engine failure is a VISIBLE error, the
///   line never degrades to word stripping): a radix literal
///   (`0x…` / `0b…` / `0o…` with a valid leading digit), a base
///   function call head (`int(` / `bin(` / `oct(` / `hex(`), the
///   anchored base phrase (`… as hex`, `… in binary`, `… to base 8`)
///   or a bitwise glyph (`&`, `|`, `<<`, `>>`, the word `xor`).
/// - WEAK (attempted; an engine failure falls through to the next
///   lane so prose and boolean lines keep working): the word forms
///   `and` / `or` with BOTH neighbors (across whitespace) starting
///   with a digit, a radix literal, an operator/paren, a declared
///   name or a token marker — `fish and chips` (word neighbors) stays
///   prose; `1 and 2`, `x and y` (declared), `TOKEN & 0x0F` are math.
///
/// The engine's named-value table: integer quantities ride as exact
/// integers; finite integer-valued scalars (|v| ≤ 2^53) join the
/// integer lattice exactly; other scalars stay doubles; booleans
/// carry their real value; unit quantities and money names are ABSENT
/// (a reference to them is a strict unknown-variable / operand error
/// inside the exact lane — deterministic, never a coercion).
public enum IntegerLane {
    /// The four base-function call heads (lowercased, no paren).
    public static let baseFunctionNames: Set<String> = ["int", "bin", "oct", "hex"]

    /// Whether the line is integer-shaped (strong or weak).
    public static func isIntegerLine(_ line: String, env: TypedEnv) -> Bool {
        hasStrongTrigger(line, env: env) || hasWeakTrigger(line, env: env)
    }

    /// Whether the line carries math content beyond prose: a digit, a
    /// token marker or a declared name (the glyph triggers below
    /// require it, so `fish & chips` stays prose while `2 & 3` is
    /// bitwise — exactly the legacy strictness of `&` lines).
    static func hasMathContent(_ line: String, env: TypedEnv) -> Bool {
        if line.unicodeScalars.contains(where: { $0.value >= 0x30 && $0.value <= 0x39 }) {
            return true
        }
        if line.contains(answerTokenMarker) { return true }
        return NamedValues.matches(in: line, env: env).isEmpty == false
    }

    /// STRONG triggers: radix literal, base call head, base phrase —
    /// always; bitwise glyphs / the xor word only with math content
    /// (a lone `&` in pure prose stays prose).
    public static func hasStrongTrigger(_ line: String, env: TypedEnv) -> Bool {
        if line.range(of: #"0[xX][0-9a-fA-F_]"#, options: .regularExpression) != nil {
            return true
        }
        if line.range(of: #"(?i)0[bB][01_]"#, options: .regularExpression) != nil {
            return true
        }
        if line.range(of: #"(?i)0[oO][0-9_]"#, options: .regularExpression) != nil {
            return true
        }
        for f in baseFunctionNames {
            if line.range(of: f + #"\s*\("#, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }
        if BasePhrase.match(line) != nil { return true }
        // Bitwise glyphs: a lone & / | (the doubled &&/|| are logical
        // and stay with the boolean lane) or the shift pairs — each
        // requires math content so pure prose never becomes an error.
        if hasMathContent(line, env: env) {
            if line.range(of: #"(?<![&|])[&|](?![&|])"#, options: .regularExpression) != nil {
                return true
            }
            if line.contains("<<") || line.contains(">>") { return true }
            // The xor WORD (standalone, case-insensitive).
            if standaloneWord(line, "xor") { return true }
        }
        return false
    }

    /// WEAK trigger: a word `and` / `or` (the standalone word forms —
    /// `&&` / `||` are the symbolic logical operators and are NOT
    /// weak triggers) whose BOTH sides start with math content.
    public static func hasWeakTrigger(_ line: String, env: TypedEnv) -> Bool {
        for word in ["and", "or"] {
            guard let w = standaloneWordRange(line, word) else { continue }
            // Neighbors: skip whitespace on both sides.
            let before = line[line.startIndex..<w.lowerBound]
            var b = before
            while let last = b.last, last.isWhitespace { b = b.dropLast() }
            let after = line[w.upperBound...]
            var a = after
            while let first = a.first, first.isWhitespace { a = a.dropFirst() }
            guard startsMath(b, env: env) && startsMath(a, env: env) else { continue }
            return true
        }
        // A bare arithmetic line that references an INTEGER-valued
        // variable is exact integer math: `x = 0x1F` then `x + 1`
        // → `0x20` (variable radix preserved), not a Double detour.
        for e in env.entries {
            guard case .integer = e.qty else { continue }
            // No length guard: integer-valued variables are
            // user-named; the weak trigger falls through when the
            // engine cannot parse the line, so prose stays safe.
            if line.contains(e.display) { return true }
        }
        return false
    }

    /// When the WHOLE line is exactly one base-function call
    /// (`hex(10)`, `int(0o55)`, `bin(x)`), that function's radix wins
    /// the presentation — even over literal radixes inside the
    /// argument.
    static func singleCallRadix(_ line: String) -> Int? {
        let t = line
        guard let open = t.firstIndex(of: "(") else { return nil }
        let name = String(t[t.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0 == "_" }),
              let radix = IntExprParser.baseFunctions[name.lowercased()] else { return nil }
        guard t.hasSuffix(")"), t.count > 2 else { return nil }
        var depth = 1
        var closePos: String.Index? = nil
        var i = t.index(after: open)
        while i < t.endIndex {
            let ch = t[i]
            if ch == "(" { depth += 1 } else if ch == ")" {
                depth -= 1
                if depth == 0 { closePos = t.index(after: i); break }
            }
            i = t.index(after: i)
        }
        return closePos == t.endIndex ? radix : nil
    }

    /// Whether a (trimmed) side of a word-form logical operator starts
    /// with math content: a digit (or radix prefix), an operator, a
    /// paren, a declared name, a token marker or a base function.
    static func startsMath(_ s: Substring, env: TypedEnv) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let c = t.first else { return false }
        if c == answerTokenMarker { return true }
        if c.isNumber { return true }
        if "+-*/^%<>=!".contains(c) { return true }
        if c == "(" { return true }
        if c.isLetter || c == "_" {
            let word = t.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            if baseFunctionNames.contains(word.lowercased()) { return true }
            let firstWord = String(word).lowercased()
            if ["true", "false"].contains(firstWord) || firstWord == "if" { return true }
            // A declared name (the first word probes; longest-match
            // is the engine's job — a compound name whose first word
            // is declared still resolves downstream).
            if env.entry(display: String(word)) != nil { return true }
            return false
        }
        return false
    }

    /// Standalone word test: the word appears bounded by non-word
    /// characters (line edges, whitespace, operators).
    public static func standaloneWord(_ line: String, _ word: String) -> Bool {
        standaloneWordRange(line, word) != nil
    }

    public static func standaloneWordRange(_ line: String, _ word: String) -> Range<String.Index>? {
        let ns = line as NSString
        let w = word as NSString
        var from = 0
        while true {
            let r = ns.range(of: word, options: [.caseInsensitive],
                             range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { return nil }
            let okBefore = r.location == 0 || !isWord16(ns.character(at: r.location - 1))
            let okAfter = NSMaxRange(r) >= ns.length || !isWord16(ns.character(at: NSMaxRange(r)))
            if okBefore && okAfter {
                guard let lo = Range(NSRange(location: r.location, length: 0), in: line),
                      let hi = Range(NSRange(location: r.location + r.length, length: 0), in: line)
                else { return nil }
                return lo.lowerBound..<hi.lowerBound
            }
            from = r.location + 1
            if from >= ns.length { return nil }
        }
        _ = w
    }

    private static func isWord16(_ c: UInt16) -> Bool {
        (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
            || (0x30...0x39).contains(c) || c == 0x5F
    }

    // MARK: Execution

    /// Runs the exact lane for one non-assignment line. Returns the
    /// line's result, or nil to fall through to the next lane:
    /// - weak-trigger failures always fall through (prose safety);
    /// - strong-trigger failures are shape-owned: the caller surfaces
    ///   the returned error.
    /// `strong` is the lane's OWN trigger kind (weak lines that fail
    /// fall through even when the caller's trigger was ambiguous).
    public static func tryLine(_ line: String,
                               env: TypedEnv,
                               context: NumberFormatContext,
                               decimalPlaces: Int) -> LineResult? {
        // r85: degree/DMS lines are the geography lane's shapes — the
        // exact lane never owns a line carrying a degree, prime or
        // double-prime glyph (`156.742 as DMS` included: `as decimal`
        // is a base alias, but the degree glyphs decide first).
        guard !line.contains("\u{00B0}"), !line.contains("\u{2032}"),
              !line.contains("\u{2033}") else { return nil }
        // A BARE base-variable reference owns its line and renders the
        // variable's own stored presentation (`x` after `x = 0x1F`).
        let bare = line.trimmingCharacters(in: .whitespaces)
        if !bare.isEmpty,
           bare.range(of: #"^[A-Za-z_]\w*$"#, options: .regularExpression) != nil,
           let e = env.entry(display: bare),
           case .integer(let v, let r) = e.qty {
            return .integer(value: v, radix: r)
        }
        let strong = hasStrongTrigger(line, env: env)
        let weak = strong || hasWeakTrigger(line, env: env)
        guard weak else { return nil }

        // The anchored base phrase owns the whole line: the expression
        // side is evaluated with the phrase's EXPLICIT target radix.
        if let phrase = BasePhrase.match(line) {
            guard let r = run(phrase.expression, vars: varTable(env),
                              varRadixes: varRadixTable(env),
                              context: context,
                              explicitTarget: phrase.targetRadix) else {
                return strong ? .error(message: "Invalid expression") : nil
            }
            return r
        }

        let normalized = normalizeExprCorrect(line.trimmingCharacters(in: .whitespaces),
                                              context: context)
        // A line that is a BARE integer variable reference renders the
        // variable's own stored presentation (x after `x = 0x1F`).
        let trimmed = normalized.trimmingCharacters(in: .whitespaces)
        if trimmed.range(of: #"^[A-Za-z_]\w*$"#, options: .regularExpression) != nil,
           let e = env.entry(display: trimmed),
           case .integer(let v, let radix) = e.qty {
            return .integer(value: v, radix: radix)
        }
        guard let r = run(normalized, vars: varTable(env),
                          varRadixes: varRadixTable(env), context: context,
                          explicitTarget: nil) else {
            // Strong trigger: shape-owned, the failure is visible.
            // Weak trigger: fall through (the boolean/prose lanes
            // decide next) — never a false error on prose.
            return strong ? .error(message: "Invalid expression") : nil
        }
        return r
    }

    /// The exact engine over one normalized expression.
    private static func run(_ expr: String, vars: [String: IntValue],
                            varRadixes: [String: Int],
                            context: NumberFormatContext,
                            explicitTarget: Int?) -> LineResult? {
        guard !expr.isEmpty else { return nil }
        do {
            let r = try IntegerEngine.evaluate(expr, vars: vars,
                                               varRadixes: varRadixes,
                                               explicitTarget: explicitTarget,
                                               outerFunctionRadix: Self.singleCallRadix(expr))
            switch r {
            case .integer(let v, let radix):
                return .integer(value: v, radix: radix)
            case .scalar(let d):
                guard d.isFinite else { return nil }
                return .number(value: roundResult(d, decimalPlaces: 10), unit: nil)
            case .boolean(let b):
                return .boolean(value: b)
            }
        } catch {
            return nil
        }
    }

    /// r85: the presentation radix of each named integer value — the
    /// parallel table to `varTable` (only integer quantities carry one).
    static func varRadixTable(_ env: TypedEnv) -> [String: Int] {
        var t: [String: Int] = [:]
        for e in env.entries {
            if case .integer(_, let r) = e.qty, r != 10 { t[e.display] = r }
        }
        return t
    }

    /// Named values the exact lane can resolve (see the type doc).
    /// `vars` is also fed by the token route (marker placeholders).
    static func varTable(_ env: TypedEnv) -> [String: IntValue] {
        var t: [String: IntValue] = [:]
        for e in env.entries {
            switch e.qty {
            case .integer(let v, _):
                t[e.display] = .int(v)
            case .scalar(let v, _, _) where v.isFinite:
                if v == v.rounded(), abs(v) <= 9007199254740992,
                   let i = Int64(exactly: v) {
                    t[e.display] = .int(i)
                } else {
                    t[e.display] = .double(v)
                }
            case .bool(let b):
                t[e.display] = .bool(b)
            case .money(let v, _) where v.isFinite:
                t[e.display] = .double(v)
            case .quantity:
                break // strict: quantity names are absent from this lane
            default:
                break
            }
        }
        return t
    }
}
