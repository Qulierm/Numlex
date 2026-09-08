import Foundation

/// r82: the shared typed-boolean line logic. This file owns the three
/// things every boolean-aware route must agree on, so they can never
/// diverge:
///
/// - `assignmentSplit`: the ONE recognizer of the single assignment
///   `=`. `==`, `!=`, `<=`, `>=` are comparison operators and NEVER
///   enter any assignment route; every legacy `line.contains("=")` /
///   `firstIndex(of: "=")` call site has moved to this helper.
///
/// - `booleanShape`: the activation probe. A line is boolean-looking
///   when it carries explicit boolean syntax (comparison/logical
///   glyphs, a standalone `true`/`false` word, or the `if`/`then`/
///   `else` word triple) or references a declared boolean name in an
///   expression-shaped line. Prose without any of these signals is
///   never routed to the boolean engine.
///
/// - `boolOutcome` / `conditionalLine`: the strict boolean cores.
///   Declared names are substituted with collision-proof placeholders
///   (the shared `NamedValues` matcher, so highlighting and
///   evaluation cannot drift); MONEY names are deliberately absent
///   from the typed table — a money quantity can never implicitly
///   become a scalar in a boolean context (it fails safely, exactly
///   like the numeric strict core). `and`/`or`/`if` are lazy: the
///   unselected branch never evaluates, so it cannot divide by zero
///   or mutate the environment.
public enum BooleanLogic {

    // MARK: - Assignment recognition (centralized)

    /// The line split at the FIRST single assignment `=` — nil when
    /// the line carries no assignment (`==`, `!=`, `<=`, `>=` are
    /// comparison operators, never assignment). This is the single
    /// source of truth every assignment route and classifier uses.
    public static func assignmentSplit(_ line: String) -> (lhs: String, rhs: String)? {
        let ns = line as NSString
        var i = 0
        while i < ns.length {
            if ns.character(at: i) == 0x3D { // '='
                let prev = i > 0 ? ns.character(at: i - 1) : 0
                let next = i + 1 < ns.length ? ns.character(at: i + 1) : 0
                // Part of a two-character comparison operator: skip it.
                // The scan must advance on EVERY path — a `==` run
                // contains two `=` characters and must not re-examine
                // the same index twice.
                if prev == 0x21 || prev == 0x3C || prev == 0x3E || prev == 0x3D {
                    i += 1
                    continue
                }
                if next == 0x3D { i += 1; continue } // ==
                let lhs = ns.substring(to: i)
                let rhs = ns.substring(from: i + 1)
                return (lhs, rhs)
            }
            i += 1
        }
        return nil
    }

    /// Whether the line carries a single assignment (see
    /// `assignmentSplit`).
    public static func hasAssignment(_ line: String) -> Bool {
        assignmentSplit(line) != nil
    }

    // MARK: - Activation probe

    /// Comparison/logical glyph runs: `<` `>` `<=` `>=` `==` `!=`
    /// `&&` `||` (and the single-character forms of the same ops).
    private static func hasComparisonGlyphs(_ line: String) -> Bool {
        line.contains("<") || line.contains(">")
            || line.contains("==") || line.contains("!=")
            || line.contains("&&") || line.contains("||")
    }

    /// A `!` that is NOT the line's final significant character (a
    /// trailing prose exclamation stays prose).
    private static func hasLogicalNegation(_ line: String) -> Bool {
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            if chars[i] == "!" {
                if i + 1 < chars.count, chars[i + 1] == "=" { i += 2; continue }
                var isLast = true
                for k in (i + 1)..<chars.count where !chars[k].isWhitespace {
                    isLast = false
                    break
                }
                if !isLast { return true }
            }
            i += 1
        }
        return false
    }

    private static func hasTrueFalseWord(_ line: String) -> Bool {
        boolWordPattern(#"(?<![A-Za-z0-9_])(true|false)(?![A-Za-z0-9_])"#, in: line) != nil
    }

    private static func hasIfThenElseTriple(_ line: String) -> Bool {
        boolWordPattern(#"(?<![A-Za-z0-9_])if(?![A-Za-z0-9_])"#, in: line) != nil
            && boolWordPattern(#"(?<![A-Za-z0-9_])then(?![A-Za-z0-9_])"#, in: line) != nil
            && boolWordPattern(#"(?<![A-Za-z0-9_])else(?![A-Za-z0-9_])"#, in: line) != nil
    }

    /// Explicit boolean syntax, environment-independent:
    /// - a comparison/logical glyph run;
    /// - a non-terminal `!`;
    /// - a standalone `true`/`false` word;
    /// - the `if` + `then` + `else` word triple.
    /// Used by callers with no environment (constant validation, the
    /// conditional shape probe); line ROUTES use `liveExplicitSyntax`
    /// so keyword shadowing can deactivate the word forms.
    public static func hasBooleanSyntax(_ line: String) -> Bool {
        hasComparisonGlyphs(line)
            || hasLogicalNegation(line)
            || hasTrueFalseWord(line)
            || hasIfThenElseTriple(line)
    }

    /// The explicit syntax that is LIVE in this environment: glyph and
    /// `!` forms are never shadowable; the `true`/`false` words and
    /// the `if`/`then`/`else` triple count only when no active
    /// variable or constant carries the keyword name (keyword
    /// compatibility — `true = 7` declares a variable named `true`,
    /// and a later standalone `true` line is a plain variable
    /// reference, not a boolean literal).
    static func liveExplicitSyntax(_ line: String, env: TypedEnv) -> Bool {
        if hasComparisonGlyphs(line) { return true }
        if hasLogicalNegation(line) { return true }
        if hasTrueFalseWord(line)
            && !env.shadowsKeyword("true") && !env.shadowsKeyword("false") {
            return true
        }
        if hasIfThenElseTriple(line)
            && !env.shadowsKeyword("if")
            && !env.shadowsKeyword("then")
            && !env.shadowsKeyword("else") {
            return true
        }
        return false
    }

/// A standalone logical word (`and`, `or`, `not`) — counted only
    /// in lines that ALSO reference a declared boolean name (the
    /// name-driven clause of `booleanShape`), so ordinary prose like
    /// `bread and butter` can never become math.
    private static func hasLogicalWord(_ line: String) -> Bool {
        boolWordPattern(#"(?<![A-Za-z0-9_])(and|or|not)(?![A-Za-z0-9_])"#, in: line) != nil
    }

    /// The full activation probe: explicit boolean syntax, or a
    /// declared boolean name in an expression-shaped line (a logical
    /// word counts as shape only WITH a boolean name), or a boolean
    /// name standing alone on the line.
    public static func booleanShape(_ line: String, env: TypedEnv) -> Bool {
        if liveExplicitSyntax(line, env: env) { return true }
        guard !env.entries.isEmpty else { return false }
        let boolMatches = NamedValues.matches(in: line, env: env).filter {
            if case .bool = $0.entry.qty { return true } else { return false }
        }
        guard !boolMatches.isEmpty else { return false }
        let exprLike = line.unicodeScalars.contains {
            "0123456789+-*/^(!<>=&|".unicodeScalars.contains($0)
                || $0 == "×" || $0 == "÷"
        } || hasLogicalWord(line)
        if exprLike { return true }
        let trimmedKey = canonicalNameKey(line)
        return boolMatches.contains { canonicalNameKey($0.display) == trimmedKey }
    }

    private static func boolWordPattern(_ pattern: String, in line: String) -> Range<String.Index>? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              m.range.location != NSNotFound else { return nil }
        return Range(m.range, in: line)
    }

    // MARK: - The strict boolean core

    /// The boolean right-hand side / free expression of a line.
    /// - `.notBool`: the line is not boolean — the caller falls
    ///   through to its other routes (or stays prose);
    /// - `.value`: the strict typed evaluation succeeded;
    /// - `.error`: the line IS boolean (explicit syntax or a logical
    ///   word with a boolean name) but failed strictly — the caller
    ///   surfaces the deterministic message, never a fallback.
    public enum BoolOutcome: Equatable {
        case notBool
        case value(Bool)
        case error(String)
    }

    /// Whether a right-hand side (or free expression) is worth trying
    /// as boolean: explicit syntax, a logical word, or a declared
    /// boolean name on the text.
    public static func isBoolLikely(_ line: String, env: TypedEnv) -> Bool {
        hasBooleanSyntax(line)
            || hasLogicalWord(line)
            || NamedValues.matches(in: line, env: env).contains {
                if case .bool = $0.entry.qty { return true } else { return false }
            }
    }

    /// Evaluates `line` as a boolean expression against the typed
    /// environment (see the type-level rules). The line text is
    /// never rewritten in place — only an evaluation copy is
    /// placeholder-substituted.
    public static func boolOutcome(_ line: String, env: TypedEnv,
                                   context: NumberFormatContext = .legacy) -> BoolOutcome {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .notBool }
        let explicit = liveExplicitSyntax(trimmed, env: env)
            || hasLogicalWord(trimmed)
        let boolNameHere = NamedValues.matches(in: trimmed, env: env).contains {
            if case .bool = $0.entry.qty { return true } else { return false }
        }
        guard explicit || boolNameHere else { return .notBool }

        // Named substitution: scalars and booleans join the typed
        // table; money is DELIBERATELY absent (a money quantity can
        // never silently become a scalar in boolean context — it
        // fails the residual guard below and errors safely).
        let matches = NamedValues.matches(in: trimmed, env: env)
        var vars: [String: TypedScalar] = [:]
        for e in env.entries {
            switch e.qty {
            case .scalar(let v) where v.isFinite: vars[e.display] = .number(v)
            case .bool(let b): vars[e.display] = .bool(b)
            default: break
            }
        }
        var expr = trimmed
        for (idx, m) in matches.enumerated() {
            switch m.entry.qty {
            case .scalar(let v) where v.isFinite: vars[namePlaceholder(idx)] = .number(v)
            case .bool(let b): vars[namePlaceholder(idx)] = .bool(b)
            default: break
            }
        }
        // Replace from the end so earlier ranges stay valid.
        for (idx, m) in matches.enumerated().reversed() {
            expr = (expr as NSString).replacingCharacters(in: m.range, with: namePlaceholder(idx))
        }
        let normalized = normalizeExprCorrect(expr, context: context)
        guard !normalized.isEmpty else { return explicit ? .error("Invalid expression") : .notBool }
        do {
            // Residual guard: every identifier must be a typed
            // variable/placeholder, a boolean keyword, or a known
            // builtin (call position) — unknown words keep the line
            // strict, exactly like the numeric core.
            for t in try tokenize(normalized, context: context) {
                if case .identifier(let n) = t, vars[n] == nil {
                    let kw = n.lowercased()
                    if !(kw == "true" || kw == "false" || kw == "not" || kw == "and"
                        || kw == "or" || kw == "if" || kw == "then" || kw == "else"),
                       !MathFunctions.isKnown(kw) {
                        return explicit ? .error("Invalid expression") : .notBool
                    }
                }
            }
            let v = try evaluateTypedExpression(normalized, variables: vars, context: context)
            if case .bool(let b) = v { return .value(b) }
            // Boolean-looking text that evaluates to a scalar
            // (`if`-free lines only): explicit syntax is a strict
            // failure, name-driven falls through quietly.
            return explicit ? .error("Invalid expression") : .notBool
        } catch {
            return explicit ? .error((error as? LocalizedError)?.errorDescription ?? "Invalid expression")
                             : .notBool
        }
    }

    // MARK: - Conditional lines (`if … then … else …`)

    /// Splits a trimmed line on the TOP-LEVEL (parenthesis-depth-0)
    /// `then` and `else` words after a leading `if` word. Nil when the
    /// line does not have the conditional shape.
    public static func splitConditional(_ line: String)
        -> (cond: String, thenBranch: String, elseBranch: String)? {
        let chars = Array(line)
        guard let first = chars.first, first.isLetter else { return nil }
        var i = 0
        // Leading `if` word (isWordAt advances `i` past the word); the
        // condition starts right after it.
        guard isWordAt(chars, "if", &i) else { return nil }
        let condStart = i
        var depth = 0
        var thenStart = -1
        while i < chars.count {
            let c = chars[i]
            if c == "(" {
                depth += 1
            } else if c == ")" {
                depth -= 1
            } else if depth == 0, c.isLetter {
                if thenStart == -1, isWordAt(chars, "then", &i) {
                    // `i` now sits just past `then`; remember where it
                    // started (the word is exactly four characters).
                    thenStart = i - 4
                    continue
                }
                let elseStart = i
                if isWordAt(chars, "else", &i) {
                    guard thenStart != -1 else { return nil }
                    let thenEnd = thenStart + 4
                    let cond = String(chars[condStart..<thenStart]).trimmingCharacters(in: .whitespaces)
                    let thenB = String(chars[thenEnd..<elseStart])
                    let elseB = String(chars[(elseStart + 4)...])
                    guard !cond.isEmpty else { return nil }
                    guard !thenB.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                    guard !elseB.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                    return (cond: cond, thenBranch: thenB, elseBranch: elseB)
                }
            }
            i += 1
        }
        return nil
    }

    private static func isWordAt(_ chars: Array<Character>, _ word: String,
                                 _ i: inout Int) -> Bool {
        let w = Array(word)
        let start = i
        guard i + w.count <= chars.count else { return false }
        for (k, c) in w.enumerated() where String(chars[i + k]).lowercased() != String(c) {
            return false
        }
        // Word boundaries: no identifier character before or after.
        func isIdentChar(_ c: Character) -> Bool {
            guard let u = c.unicodeScalars.first else { return false }
            let v = u.value
            return (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)
                || (v >= 0x30 && v <= 0x39) || v == 0x5F
        }
        if start > 0, isIdentChar(chars[start - 1]) { return false }
        let end = start + w.count
        if end < chars.count, isIdentChar(chars[end]) { return false }
        i = end
        return true
    }

    /// The complete conditional line: value form (`if c then a else b`
    /// — either branch may be scalar or boolean) or the conditional
    /// ASSIGNMENT form (`if c then x = a else x = b`, both branches
    /// must name the SAME target, and only the selected branch
    /// evaluates and mutates the environment). Returns nil when the
    /// line is not a conditional shape; deterministic results
    /// otherwise — a visible `LineResult` for every well-formed
    /// conditional.
    public static func conditionalLine(_ line: String, env: inout TypedEnv,
                                       context: NumberFormatContext = .legacy) -> LineResult? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("//"), !trimmed.hasPrefix("#") else { return nil }
        guard BooleanLogic.booleanShape(trimmed, env: env) else { return nil }
        guard let parts = splitConditional(trimmed) else { return nil }

        // The condition must evaluate to a boolean.
        switch boolOutcome(parts.cond, env: env, context: context) {
        case .notBool:
            return nil // not a conditional after all
        case .error(let m):
            return .error(message: m)
        case .value(let cond):
            // --- conditional ASSIGNMENT: both branches are
            // `<name> = <expr>` with the SAME canonical target.
            let thenA = assignmentSplit(parts.thenBranch)
            let elseA = assignmentSplit(parts.elseBranch)
            if let tA = thenA, let eA = elseA {
                guard let t = assignmentLHSOf(tA.lhs), let e = assignmentLHSOf(eA.lhs) else {
                    return .error(message: "Invalid assignment")
                }
                guard canonicalNameKey(t) == canonicalNameKey(e) else {
                    return .error(message: "Conditional branches must assign the same name")
                }
                if env.isConstant(display: t) {
                    return .error(message: "Cannot assign to constant")
                }
                let branch = cond ? tA : eA
                // The UNSELECTED branch is never evaluated.
                if let r = branchValue(branch.rhs, env: env, context: context) {
                    switch r {
                    case .boolean(let b):
                        env.set(display: t, qty: .bool(b))
                        return .boolean(value: b)
                    case .number(let v, nil):
                        env.set(display: t, qty: .scalar(v))
                        return .variable(name: t, value: v)
                    default:
                        break
                    }
                }
                return .error(message: "Invalid expression")
            }
            // --- value form: exactly one branch evaluates.
            let branchText = cond ? parts.thenBranch : parts.elseBranch
            if let r = branchValue(branchText, env: env, context: context) {
                return r
            }
            return .error(message: "Invalid expression")
        }
    }

    /// The value of one conditional branch (or a conditional-assignment
    /// right-hand side): the typed engine first — it understands
    /// nested conditionals, booleans and boolean/mixed names — then the
    /// shared named core for money references. Money quantities are
    /// never coerced (a money-only branch fails), and nil means the
    /// branch is unusable (the caller errors).
    public static func branchValue(_ text: String, env: TypedEnv,
                                   context: NumberFormatContext = .legacy) -> LineResult? {
        let matches = NamedValues.matches(in: text, env: env)
        var vars: [String: TypedScalar] = [:]
        for e in env.entries {
            switch e.qty {
            case .scalar(let v) where v.isFinite: vars[e.display] = .number(v)
            case .bool(let b): vars[e.display] = .bool(b)
            default: break
            }
        }
        var expr = text
        for (idx, m) in matches.enumerated() {
            switch m.entry.qty {
            case .scalar(let v) where v.isFinite: vars[namePlaceholder(idx)] = .number(v)
            case .bool(let b): vars[namePlaceholder(idx)] = .bool(b)
            default: break
            }
        }
        for (idx, m) in matches.enumerated().reversed() {
            expr = (expr as NSString).replacingCharacters(in: m.range, with: namePlaceholder(idx))
        }
        if let v = try? evaluateTypedExpression(expr, variables: vars, context: context) {
            switch v {
            case .number(let n) where n.isFinite:
                return .number(value: n, unit: nil)
            case .bool(let b):
                return .boolean(value: b)
            default:
                break
            }
        }
        if let (n, codes) = evaluateNamedExpr(text, env: env, context: context) {
            guard codes.isEmpty else { return nil }
            return .number(value: n, unit: nil)
        }
        return nil
    }

    /// The validated left-hand name of a conditional-assignment branch:
    /// a natural multiword name or a legacy single identifier.
    private static func assignmentLHSOf(_ lhs: String) -> String? {
        let trimmed = lhs.trimmingCharacters(in: .whitespaces)
        if let natural = NaturalCalculation.naturalLHS(lhs) { return natural }
        guard let re = try? NSRegularExpression(pattern: "^[A-Za-z_]\\w*$") else { return nil }
        return re.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil
            ? trimmed : nil
    }
}
