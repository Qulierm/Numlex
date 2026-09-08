import Foundation

public enum ParseError: Error, LocalizedError {
    case emptyExpression
    case unknownVariable(String)
    case invalidVariable(String)
    case divisionByZero
    case nonFiniteResult
    case missingClosingParen
    case unexpectedEnd
    case unexpectedToken(String)
    case unexpectedCharacter(String)
    case invalidNumber(String)
    // r47: function-call syntax failures (deterministic, strict — a
    // function-shaped input never falls back to a parenthesized operand).
    case unknownFunction(String)
    case functionArity(name: String, got: Int, min: Int, max: Int)
    case functionEmptyArgs(String)
    case functionTrailingComma
    case functionDoubleComma
    case functionMissingComma
    /// A deterministic function DOMAIN/non-finite failure carried with
    /// its stable message (the registry's `MathFunctionError`).
    case functionError(String)
    // r82: strict typed-boolean failures. Every message is stable so
    // tests and the UI can rely on exact text.
    /// A boolean-shaped node reached the NUMERIC entry point: the
    /// numeric API never coerces booleans, it fails deterministically.
    case booleanExpression
    /// A logical/conditional position received a non-boolean operand.
    case booleanExpected(op: String)
    /// An arithmetic, relational-ordering or function position received
    /// a non-scalar operand (a boolean, or a chained comparison).
    case scalarExpected(op: String)
    /// `==` / `!=` with one scalar and one boolean operand.
    case mixedTypes(op: String)
    /// `if … then …` without an `else` branch.
    case missingElse
    public var errorDescription: String? {
        switch self {
        case .emptyExpression: return "Empty expression"
        case .unknownVariable(let n): return "Unknown variable '\(n)'"
        case .invalidVariable(let n): return "Invalid variable '\(n)'"
        case .divisionByZero: return "Division by zero"
        case .nonFiniteResult: return "Result is not finite"
        case .missingClosingParen: return "Missing closing parenthesis"
        case .unexpectedEnd: return "Unexpected end"
        case .unexpectedToken(let s): return "Unexpected token '\(s)'"
        case .unexpectedCharacter(let s): return "Unexpected character '\(s)'"
        case .invalidNumber(let s): return "Invalid number '\(s)'"
        case .unknownFunction(let n): return "Unknown function '\(n)'"
        case .functionArity(let n, let got, let min, let max):
            if min == max { return "\(n) expects exactly \(min) \(min == 1 ? "argument" : "arguments") (got \(got))" }
            if max == .max { return "\(n) expects at least \(min) arguments (got \(got))" }
            return "\(n) expects \(min) ... \(max) arguments (got \(got))"
        case .functionEmptyArgs(let n): return "\(n)() takes at least 1 argument"
        case .functionTrailingComma: return "Trailing comma in function arguments"
        case .functionDoubleComma: return "Unexpected comma in function arguments"
        case .functionMissingComma: return "Missing comma between function arguments"
        case .functionError(let s): return s
        case .booleanExpression: return "Boolean expression"
        case .booleanExpected(let op): return "Boolean expected in '\(op)'"
        case .scalarExpected(let op): return "Scalar expected in '\(op)'"
        case .mixedTypes(let op): return "Mixed types in '\(op)'"
        case .missingElse: return "Missing 'else' branch"
        }
    }
}

// MARK: - Expression AST

/// One parsed expression node. The parse phase is pure syntax (no
/// evaluation), which is what lets the evaluator apply CONTEXTUAL
/// percentage semantics: in an additive/subtractive context the RIGHT
/// operand being a pure percentage means a fraction of the accumulated
/// left side (`100 + 10%` = 110, `110 - 5%` = 104.5), while in every
/// other context a percentage is the ordinary scalar `p/100`
/// (`200 × 10%` = 20, `200 / 10%` = 2000, `50%` = 0.5).
///
/// r82: the boolean productions extend the same AST. The NUMERIC
/// entry point parses down to the additive level and rejects boolean
/// nodes; the TYPED entry point parses the full precedence chain
/// (or < and < not < equality < relational < additive < term <
/// factor < unary < primary, with the conditional lowest and
/// right-associative).
indirect enum Expr: Sendable {
    case num(Double)
    case variable(String)
    case add(Expr, Expr)
    case sub(Expr, Expr)
    case mul(Expr, Expr)
    case div(Expr, Expr)
    case pow(Expr, Expr)
    case neg(Expr)
    case percent(Expr)
    /// r83: the postfix multiplier suffix: `1.5x` is the FACTOR 1.5
    /// (rendered/copied as `1.5x`). The suffix binds to the preceding
    /// primary exactly like `%`, is recognized only when no active
    /// variable/constant is named `x` (keyword compatibility), and a
    /// multiplier joins `of`/`on`/`off` percentage slots (`1.5x of
    /// 20` = 30).
    case mult(Expr)
    /// The bounded percent infix: `15% of 490` = 0.15 × 490. r83:
    /// the left-hand side may also be a multiplier or a simple
    /// rational (`2/3 of 600` = 400).
    case of(Expr, Expr)
    /// r47: a builtin math function call. `name` is the LOWER-CASED
    /// registry name; arguments are full expressions (comma-separated,
    /// parsed with the shared precedence rules).
    case funcall(String, [Expr])
    // r82: boolean productions.
    /// `true` / `false` literal.
    case boolLit(Bool)
    /// `not x` / `!x` (binds tighter than `and`).
    case not(Expr)
    /// `x and y` / `x && y` (binds tighter than `or`, lazier).
    case and(Expr, Expr)
    /// `x or y` / `x || y`.
    case or(Expr, Expr)
    /// Strict relational ordering: scalar-scalar only.
    case lt(Expr, Expr)
    case le(Expr, Expr)
    case gt(Expr, Expr)
    case ge(Expr, Expr)
    /// Equality: scalar-scalar or bool-bool; mixed operands error.
    case eq(Expr, Expr)
    case ne(Expr, Expr)
    /// `if <cond> then <a> else <b>` — the conditional, lowest and
    /// right-associative. Branches are full (conditional) expressions.
    case ifThenElse(Expr, Expr, Expr)
}

/// A parsed value plus its SEMANTIC kind (r83): only a postfix `p%`
/// (including parenthesized `(p%)`) or a percent-typed named value is
/// a "pure percentage" (kind `.percent` — a fraction of the accumulated
/// base in additive/subtractive context); a postfix `x` is a
/// `.multiplier`; anything that has already combined with another
/// operand in a non-additive step is `.plain` again.
struct EvalValue: Sendable {
    var value: Double
    var kind: NumericKind
}

/// r82: the typed scalar a boolean-aware expression can produce. A
/// boolean is NEVER a numeric 1/0: the typed evaluator carries the two
/// kinds distinctly and strict typing keeps them from mixing.
/// r83: a typed NUMBER carries its semantic kind (percent/multiplier
/// propagate through variables, conditionals and tokens); fractions
/// are produced by the conversion grammar, never by an expression.
public enum TypedScalar: Equatable, Sendable {
    case number(value: Double, kind: NumericKind)
    case bool(Bool)
}

extension TypedScalar {
    /// The plain-number factory (pre-r83 call-site compatibility).
    public static func number(_ value: Double) -> TypedScalar {
        .number(value: value, kind: .plain)
    }
    public var numericValue: Double? {
        if case .number(let v, _) = self { return v } else { return nil }
    }
    /// The semantic kind (plain for booleans).
    public var kind: NumericKind {
        if case .number(_, let k) = self { return k } else { return .plain }
    }
}

// MARK: - Shared recursive-descent core

/// The ONE shared parser: tokenizer output plus a typed variable table.
/// Both the legacy numeric entry (parses down to the additive level and
/// evaluates with numeric semantics) and the typed entry (parses the
/// full conditional chain and evaluates with strict typed semantics)
/// run over this core, so precedence, function-call discipline and
/// keyword/variable resolution can never diverge between the two.
struct ExprParser {
    let tokens: [Token]
    /// The typed variable table: every entry is either a finite scalar
    /// or a boolean. The numeric entry maps its `[String: Double]`
    /// caller table onto `.number` values; the typed entry maps
    /// scalars and booleans and (by construction of the caller) never
    /// money — a money name in a boolean context must fail safely.
    let vars: [String: TypedScalar]
    var pos = 0

    init(tokens: [Token], vars: [String: TypedScalar]) {
        self.tokens = tokens
        self.vars = vars
    }

    func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }
    @discardableResult
    mutating func consume() -> Token { let t = tokens[pos]; pos += 1; return t }

    /// Whether an identifier is a LIVE boolean keyword: grammar wins
    /// only when no active variable/constant carries the same name
    /// (keyword compatibility — persisted sheets that historically used
    /// keyword-like identifiers keep working).
    func isKeyword(_ name: String, _ kw: String) -> Bool {
        guard name.lowercased() == kw else { return false }
        return vars[name] == nil
    }

    // MARK: - Productions (shared by both entries)

    /// r82: `if <cond> then <expr> else <expr>` — the LOWEST
    /// production, right-associative (the branches are themselves
    /// conditionals). When the line does not start with the `if`
    /// keyword the production falls through to the or-chain.
    mutating func parseConditional() throws -> Expr {
        if let t = peek(), case .identifier(let name) = t,
           isKeyword(name, "if") {
            _ = consume()
            let cond = try parseOr()
            guard let t2 = peek(), case .identifier(let w) = t2,
                  isKeyword(w, "then") else {
                throw ParseError.unexpectedToken("then")
            }
            _ = consume()
            let thenE = try parseConditional()
            guard let t3 = peek(), case .identifier(let w3) = t3,
                  isKeyword(w3, "else") else {
                throw ParseError.missingElse
            }
            _ = consume()
            let elseE = try parseConditional()
            return .ifThenElse(cond, thenE, elseE)
        }
        return try parseOr()
    }

    mutating func parseOr() throws -> Expr {
        var left = try parseAnd()
        while true {
            if let t = peek(), case .op(let op) = t, op == "||" {
                _ = consume()
                let right = try parseAnd()
                left = .or(left, right)
            } else if let t = peek(), case .identifier(let name) = t,
                      isKeyword(name, "or") {
                _ = consume()
                let right = try parseAnd()
                left = .or(left, right)
            } else {
                break
            }
        }
        return left
    }

    mutating func parseAnd() throws -> Expr {
        var left = try parseNot()
        while true {
            if let t = peek(), case .op(let op) = t, op == "&&" {
                _ = consume()
                let right = try parseNot()
                left = .and(left, right)
            } else if let t = peek(), case .identifier(let name) = t,
                      isKeyword(name, "and") {
                _ = consume()
                let right = try parseNot()
                left = .and(left, right)
            } else {
                break
            }
        }
        return left
    }

    /// `not` / `!` prefix. The tokenizer emits `!=` as its own op
    /// token, so the `!` pattern below can never consume the equality
    /// operator.
    mutating func parseNot() throws -> Expr {
        if let t = peek(), case .op("!") = t {
            _ = consume()
            return .not(try parseNot())
        }
        if let t = peek(), case .identifier(let name) = t,
           isKeyword(name, "not") {
            _ = consume()
            return .not(try parseNot())
        }
        return try parseEquality()
    }

    mutating func parseEquality() throws -> Expr {
        var left = try parseRelational()
        while let t = peek(), case .op(let op) = t,
              (op == "==" || op == "!=") {
            _ = consume()
            let right = try parseRelational()
            left = (op == "==") ? .eq(left, right) : .ne(left, right)
        }
        return left
    }

    mutating func parseRelational() throws -> Expr {
        var left = try parseExpression()
        while let t = peek(), case .op(let op) = t,
              (op == "<" || op == "<=" || op == ">" || op == ">=") {
            _ = consume()
            let right = try parseExpression()
            switch op {
            case "<": left = .lt(left, right)
            case "<=": left = .le(left, right)
            case ">": left = .gt(left, right)
            default: left = .ge(left, right)
            }
        }
        return left
    }

    mutating func parseExpression() throws -> Expr {
        var left = try parseTerm()
        while let t = peek(), case .op(let op) = t, (op == "+" || op == "-") {
            _ = consume()
            let right = try parseTerm()
            left = (op == "+") ? .add(left, right) : .sub(left, right)
        }
        return left
    }

    mutating func parseTerm() throws -> Expr {
        var left = try parseFactor()
        while true {
            if let t = peek(), case .op(let op) = t, (op == "*" || op == "/") {
                _ = consume()
                let right = try parseFactor()
                left = (op == "*") ? .mul(left, right) : .div(left, right)
            } else if let t = peek(), case .identifier(let name) = t,
                      name == "of", isOfEligible(left) {
                // Bounded: `of` is multiplication ONLY for a percent
                // left-hand side (including `of` chains) — never a
                // global word replacement.
                _ = consume()
                let right = try parseFactor()
                left = .of(left, right)
            } else {
                break
            }
        }
        return left
    }

    mutating func parseFactor() throws -> Expr {
        let left = try parseUnary()
        if let t = peek(), case .op("^") = t {
            _ = consume()
            let right = try parseFactor() // right associative
            return .pow(left, right)
        }
        return left
    }

    mutating func parseUnary() throws -> Expr {
        if let t = peek(), case .op(let op) = t, (op == "+" || op == "-") {
            _ = consume()
            let v = try parseUnary()
            return op == "-" ? .neg(v) : v
        }
        return try parsePrimary()
    }

    /// Whether the `x` keyword is LIVE as the postfix multiplier
    /// suffix: no active variable/constant is named `x` (keyword
    /// compatibility — a declared `x` keeps the identifier reading).
    func isMultiSuffix(_ name: String) -> Bool {
        name.lowercased() == "x" && vars[name] == nil
    }

    mutating func parsePrimary() throws -> Expr {
        guard let tok = peek() else { throw ParseError.unexpectedEnd }
        var node: Expr
        switch tok {
        case .number(let v):
            _ = consume()
            node = .num(v)
        case .identifier(let name):
            _ = consume()
            // r82: boolean literals — only when no active variable/
            // constant carries the same name (keyword compatibility).
            if isKeyword(name, "true") {
                node = .boolLit(true)
            } else if isKeyword(name, "false") {
                node = .boolLit(false)
            } else {
                // r47: call position. The tokenizer already skips
                // whitespace, so an identifier token directly followed
                // by a `(` token is `name(` or `name (` — a call head.
                // A KNOWN builtin takes precedence over any same-named
                // variable or constant ONLY here; in every non-call
                // position the identifier stays an ordinary variable
                // lookup. An UNKNOWN name in call position is strict —
                // a deterministic "unknown function" error, never a
                // parenthesized operand.
                if let next = peek(), case .paren("(") = next {
                    if MathFunctions.isKnown(name) {
                        node = try parseFunctionCall(name)
                    } else {
                        _ = consume()
                        throw ParseError.unknownFunction(name)
                    }
                } else {
                    node = .variable(name)
                }
            }
        case .paren("("):
            _ = consume()
            // r82: a parenthesized group is a FULL expression — it may
            // contain comparisons, logical operators and conditionals
            // (`false && (1/0 > 0)`, `not (true and false)`). The
            // numeric entry still rejects any boolean production inside
            // (evalNumeric throws `booleanExpression`).
            node = try parseConditional()
            guard let closing = peek(), case .paren(")") = closing else {
                throw ParseError.missingClosingParen
            }
            _ = consume()
        default:
            throw ParseError.unexpectedToken("\(tok)")
        }
        // Postfix percent: `50%`, `10%%` (legacy double-percent),
        // `(10 + 5)%`, ...
        while let t = peek(), case .op("%") = t {
            _ = consume()
            node = .percent(node)
        }
        // r83: postfix multiplier suffix `1.5x` — recognized only when
        // the `x` keyword is live (a variable named `x` keeps the
        // identifier reading, exactly like every other keyword).
        if let t = peek(), case .identifier(let name) = t, isMultiSuffix(name) {
            _ = consume()
            node = .mult(node)
        }
        return node
    }

    /// r47: parses the argument list of a known builtin opened at the
    /// current position (the `(` is consumed here). Comma discipline is
    /// strict and deterministic: empty args, trailing commas, doubled
    /// commas and missing separators are distinct syntax failures; a
    /// missing close reuses `missingClosingParen`.
    mutating func parseFunctionCall(_ name: String) throws -> Expr {
        let key = name.lowercased()
        let (minArgs, maxArgs) = MathFunctions.arity(key)!
        _ = consume() // "("
        var args: [Expr] = []
        while true {
            guard let t = peek() else { throw ParseError.missingClosingParen }
            if case .paren(")") = t {
                if args.isEmpty {
                    _ = consume()
                    throw ParseError.functionEmptyArgs(key)
                }
                _ = consume()
                break
            }
            if case .comma = t, args.isEmpty {
                // Leading comma: `sum(, 1)`.
                throw ParseError.functionDoubleComma
            }
            let arg = try parseExpression()
            args.append(arg)
            if maxArgs < .max, args.count > maxArgs {
                throw ParseError.functionArity(name: key, got: args.count, min: minArgs, max: maxArgs)
            }
            guard let t2 = peek() else { throw ParseError.missingClosingParen }
            if case .comma = t2 {
                _ = consume()
                guard let t3 = peek() else { throw ParseError.missingClosingParen }
                if case .comma = t3 { throw ParseError.functionDoubleComma }
                if case .paren(")") = t3 { throw ParseError.functionTrailingComma }
                continue
            }
            if case .paren(")") = t2 {
                _ = consume()
                break
            }
            throw ParseError.functionMissingComma
        }
        if args.count < minArgs {
            throw ParseError.functionArity(name: key, got: args.count, min: minArgs, max: maxArgs)
        }
        return .funcall(key, args)
    }

    func isOfEligible(_ node: Expr) -> Bool {
        if case .percent = node { return true }
        if case .mult = node { return true }
        if case .of = node { return true }
        // r83: a SIMPLE rational — a division tree of plain number
        // literals (`2/3`, `2/3/4`) — is a fraction operand for `of`
        // (`2/3 of 600` = 400). Anything compound (variables,
        // parentheses, other operators) stays ineligible exactly like
        // pre-r83, so prose and legacy lines are untouched.
        return Self.isSimpleRational(node)
    }

    /// A division tree whose leaves are all number literals AND which
    /// contains at least one division: `2/3`, `2/3/4` are fractions;
    /// a bare literal (`2`) is not (so `2 of 3` stays the legacy
    /// bounded-infix error, exactly like pre-r83).
    static func isSimpleRational(_ node: Expr) -> Bool {
        var sawDiv = false
        func go(_ n: Expr) -> Bool {
            switch n {
            case .num:
                return true
            case .div(let l, let r):
                sawDiv = true
                return go(l) && go(r)
            default:
                return false
            }
        }
        guard go(node) else { return false }
        return sawDiv
    }

    // MARK: - Numeric evaluation (legacy semantics)

    /// The legacy value evaluator: contextual percentages and pure
    /// scalar arithmetic. r83: the result carries its SEMANTIC kind —
    /// a percent mode (`10% + 20%` = 30%, `30% + 0.4` = 70%:
    /// percent + scalar adds RAW ratios) vs the contextual legacy
    /// (`200 + 10%` = 220: the percent is a fraction of the
    /// accumulated plain base) vs plain. r82: any boolean production
    /// reached here fails DETERMINISTICALLY — the numeric API never
    /// coerces a boolean to 0/1.
    func evalNumeric(_ node: Expr) throws -> EvalValue {
        switch node {
        case .num(let v):
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, kind: .plain)
        case .variable(let name):
            guard let v = vars[name] else { throw ParseError.unknownVariable(name) }
            if case .number(let n, let k) = v, n.isFinite {
                return EvalValue(value: n, kind: k)
            }
            throw ParseError.booleanExpression
        case .add(let l, let r):
            return try additive(l, r, plus: true)
        case .sub(let l, let r):
            return try additive(l, r, plus: false)
        case .mul(let l, let r):
            let a = try evalNumeric(l)
            let b = try evalNumeric(r)
            let v = a.value * b.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, kind: .plain)
        case .div(let l, let r):
            let a = try evalNumeric(l)
            let b = try evalNumeric(r)
            if b.value == 0 { throw ParseError.divisionByZero }
            let v = a.value / b.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, kind: .plain)
        case .pow(let l, let r):
            let a = try evalNumeric(l)
            let b = try evalNumeric(r)
            let v = pow(a.value, b.value)
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, kind: .plain)
        case .neg(let l):
            let a = try evalNumeric(l)
            let v = -a.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            // A unary minus yields an ordinary scalar: `-10%` = -0.1.
            return EvalValue(value: v, kind: .plain)
        case .percent(let l):
            let a = try evalNumeric(l)
            let v = a.value / 100
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, kind: .percent)
        case .mult(let l):
            // r83: the multiplier suffix is the FACTOR — `1.5x`
            // evaluates to the raw 1.5 with the multiplier kind.
            let a = try evalNumeric(l)
            guard a.value.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: a.value, kind: .multiplier)
        case .of(let l, let r):
            let a = try evalNumeric(l)
            let eligible: Bool
            if case .of = l {
                eligible = true
            } else {
                eligible = isOfEligible(l)
            }
            guard eligible else { throw ParseError.unexpectedToken("of") }
            let b = try evalNumeric(r)
            let v = a.value * b.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            // `of` always yields an ordinary number (`10% of 200` = 20,
            // `2/3 of 600` = 400, `1.5x of 20` = 30).
            return EvalValue(value: v, kind: .plain)
        case .funcall(let key, let args):
            // r47: arguments are plain scalars — a percent argument is
            // its non-additive value (`10%` = 0.1). Domain and
            // non-finite failures carry the registry's stable message.
            let values = try args.map { try evalNumeric($0).value }
            let v: Double
            do {
                v = try MathFunctions.evaluate(key, args: values)
            } catch let e as MathFunctions.MathFunctionError {
                throw ParseError.functionError(e.errorDescription ?? "Invalid function")
            }
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, kind: .plain)
        // r82: boolean productions are unreachable on a healthy numeric
        // line; when one reaches here (a boolean variable on a numeric
        // route) the deterministic failure is the boolean sentinel —
        // never a coercion.
        case .boolLit, .not, .and, .or, .lt, .le, .gt, .ge, .eq, .ne, .ifThenElse:
            throw ParseError.booleanExpression
        }
    }

    /// r83: the shared additive/subtractive step with semantic kinds.
    /// - PERCENT MODE: the accumulated left side is a percent — every
    ///   operand adds its RAW ratio (`10% + 20%` = 30%,
    ///   `30% + 0.4` = 70%, `100% + 2 + 30%` = 330%); the result stays
    ///   a percent.
    /// - CONTEXTUAL legacy: the accumulated side is plain (or a
    ///   multiplier acting as a scalar) and the RIGHT operand is a
    ///   percent — a fraction of the accumulated base (`200 + 10%`
    ///   = 220, `200 - 10%` = 180; sequential percents compound
    ///   because the base keeps growing).
    /// - otherwise: plain value arithmetic; the result is plain.
    private func additive(_ l: Expr, _ r: Expr, plus: Bool) throws -> EvalValue {
        let a = try evalNumeric(l)
        let b = try evalNumeric(r)
        let v: Double
        let kind: NumericKind
        if a.kind == .percent {
            v = plus ? a.value + b.value : a.value - b.value
            kind = .percent
        } else if b.kind == .percent {
            v = plus ? a.value + a.value * b.value
                     : a.value - a.value * b.value
            kind = a.kind
        } else {
            v = plus ? a.value + b.value : a.value - b.value
            kind = .plain
        }
        guard v.isFinite else { throw ParseError.nonFiniteResult }
        return EvalValue(value: v, kind: kind)
    }

    // MARK: - r82: typed evaluation (strict typing, lazy branches)

    /// Strict typed evaluation: scalars and booleans never mix.
    /// - arithmetic / `of` / functions: scalar operands only;
    /// - relational ordering (`< <= > >=`): scalar operands only (a
    ///   boolean here is a chained comparison — `1 < 2 < 3`);
    /// - equality / inequality: scalar-scalar or bool-bool;
    /// - `and` / `or` / `not` / the conditional: boolean operands,
    ///   and `and` / `or` / the conditional evaluate ONLY what is
    ///   required (the unselected branch never runs, so it cannot
    ///   divide by zero or mutate anything).
    func evalTyped(_ node: Expr) throws -> TypedScalar {
        switch node {
        case .num(let v):
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(value: v, kind: .plain)
        case .variable(let name):
            guard let v = vars[name] else { throw ParseError.unknownVariable(name) }
            if case .number(let n, _) = v, !n.isFinite { throw ParseError.invalidVariable(name) }
            return v
        case .add(let l, let r):
            return try typedAdditive(l, r, plus: true)
        case .sub(let l, let r):
            return try typedAdditive(l, r, plus: false)
        case .mul(let l, let r):
            return .number(value: try arithmetic(l, r) { a, b in a * b }, kind: .plain)
        case .div(let l, let r):
            let a = try scalar(l, op: "/")
            let b = try scalar(r, op: "/")
            if b == 0 { throw ParseError.divisionByZero }
            let v = a / b
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(value: v, kind: .plain)
        case .pow(let l, let r):
            let a = try scalar(l, op: "^")
            let b = try scalar(r, op: "^")
            let v = pow(a, b)
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(value: v, kind: .plain)
        case .neg(let l):
            let a = try scalar(l, op: "-")
            let v = -a
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(value: v, kind: .plain)
        case .percent(let l):
            let a = try scalar(l, op: "%")
            let v = a / 100
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(value: v, kind: .percent)
        case .mult(let l):
            // r83: the factor of the preceding primary, kind kept.
            let a = try scalar(l, op: "x")
            return .number(value: a, kind: .multiplier)
        case .of(let l, let r):
            let a = try scalar(l, op: "of")
            let b = try scalar(r, op: "of")
            let v = a * b
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(value: v, kind: .plain)
        case .funcall(let key, let args):
            let values = try args.map { try scalar($0, op: key) }
            let v: Double
            do {
                v = try MathFunctions.evaluate(key, args: values)
            } catch let e as MathFunctions.MathFunctionError {
                throw ParseError.functionError(e.errorDescription ?? "Invalid function")
            }
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(value: v, kind: .plain)
        case .boolLit(let b):
            return .bool(b)
        case .not(let l):
            let a = try boolean(l, op: "not")
            return .bool(!a)
        case .and(let l, let r):
            let a = try boolean(l, op: "and")
            if !a { return .bool(false) } // short-circuit: r never runs
            let b = try boolean(r, op: "and")
            return .bool(a && b)
        case .or(let l, let r):
            let a = try boolean(l, op: "or")
            if a { return .bool(true) } // short-circuit: r never runs
            let b = try boolean(r, op: "or")
            return .bool(a || b)
        case .lt(let l, let r):
            return .bool(try relational(l, r, op: "<") { $0 < $1 })
        case .le(let l, let r):
            return .bool(try relational(l, r, op: "<=") { $0 <= $1 })
        case .gt(let l, let r):
            return .bool(try relational(l, r, op: ">") { $0 > $1 })
        case .ge(let l, let r):
            return .bool(try relational(l, r, op: ">=") { $0 >= $1 })
        case .eq(let l, let r):
            return .bool(try equality(l, r, op: "==", negate: false))
        case .ne(let l, let r):
            return .bool(try equality(l, r, op: "!=", negate: true))
        case .ifThenElse(let cond, let t, let e):
            let c = try boolean(cond, op: "if")
            // Lazy: exactly one branch evaluates — the other cannot
            // divide by zero or mutate the environment.
            return c ? try evalTyped(t) : try evalTyped(e)
        }
    }

    /// r83: the typed additive step — the SAME kind rules as the
    /// numeric evaluator (percent mode vs contextual legacy vs plain),
    /// with percent/multiplier kinds carried on typed variables.
    private func typedAdditive(_ l: Expr, _ r: Expr, plus: Bool) throws -> TypedScalar {
        let a = try evalTyped(l)
        let b = try evalTyped(r)
        guard let av = a.numericValue, let bv = b.numericValue else {
            throw ParseError.scalarExpected(op: plus ? "+" : "-")
        }
        let (v, kind): (Double, NumericKind)
        if a.kind == .percent {
            v = plus ? av + bv : av - bv
            kind = .percent
        } else if b.kind == .percent {
            v = plus ? av + av * bv : av - av * bv
            kind = a.kind
        } else {
            v = plus ? av + bv : av - bv
            kind = .plain
        }
        guard v.isFinite else { throw ParseError.nonFiniteResult }
        return .number(value: v, kind: kind)
    }

    /// Both operands must be finite scalars (a boolean here — including
    /// a chained comparison like `1 < 2 < 3` — is a type error).
    private func arithmetic(_ l: Expr, _ r: Expr,
                            _ f: (Double, Double) -> Double) throws -> Double {
        let a = try scalar(l, op: "arithmetic")
        let b = try scalar(r, op: "arithmetic")
        let v = f(a, b)
        guard v.isFinite else { throw ParseError.nonFiniteResult }
        return v
    }

    private func scalar(_ node: Expr, op: String) throws -> Double {
        let v = try evalTyped(node)
        if case .number(let n, _) = v { return n }
        throw ParseError.scalarExpected(op: op)
    }

    private func boolean(_ node: Expr, op: String) throws -> Bool {
        let v = try evalTyped(node)
        if case .bool(let b) = v { return b }
        throw ParseError.booleanExpected(op: op)
    }

    private func relational(_ l: Expr, _ r: Expr, op: String,
                            _ f: (Double, Double) -> Bool) throws -> Bool {
        let a = try scalar(l, op: op)
        let b = try scalar(r, op: op)
        return f(a, b)
    }

    private func equality(_ l: Expr, _ r: Expr, op: String,
                          negate: Bool) throws -> Bool {
        let a = try evalTyped(l)
        let b = try evalTyped(r)
        let same: Bool
        switch (a, b) {
        case (.number(let x), .number(let y)):
            same = (x == y)
        case (.bool(let x), .bool(let y)):
            same = (x == y)
        case (.number, .bool), (.bool, .number):
            throw ParseError.mixedTypes(op: op)
        }
        return negate ? !same : same
    }
}

// MARK: - Entry points

/// The LEGACY numeric entry point: normalization, tokenization and the
/// recursive-descent parse all run under `context` (decimal
/// separators, grouping strips, the `;`/`,` argument convention). The
/// value grammar below is mode-independent: the normalized, tokenized
/// form is identical in shape to the legacy one.
public func evaluateExpression(_ expr: String, variables: [String: Double]) throws -> Double {
    try evaluateExpression(expr, variables: variables, context: .legacy)
}

/// The numeric entry: parses down to the ADDITIVE level (boolean
/// operators at the top level stay an unexpected-token failure,
/// exactly like the pre-r82 behavior for unknown characters) and
/// evaluates with the legacy contextual-percentage semantics. Any
/// boolean-shaped line fails deterministically (`booleanExpression` or
/// `unexpectedToken`) — never a coercion to 0/1.
public func evaluateExpression(_ expr: String, variables: [String: Double],
                               context: NumberFormatContext) throws -> Double {
    let trimmed = expr.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { throw ParseError.emptyExpression }
    // r47: normalize FIRST (idempotent — the line routes normalize
    // before calling, and re-normalizing a normalized string is a
    // no-op): commas outside calls are grouping artifacts and are
    // stripped, commas inside calls keep the shared separator rule.
    // The direct API and the line routes therefore always agree.
    let tokens = try tokenize(normalizeExprCorrect(trimmed, context: context), context: context)
    let vars = variables.mapValues { TypedScalar.number($0) }
    var parser = ExprParser(tokens: tokens, vars: vars)
    let parsed = try parser.parseExpression()
    if parser.pos < parser.tokens.count {
        throw ParseError.unexpectedToken("\(parser.tokens[parser.pos])")
    }
    let result = try parser.evalNumeric(parsed)
    guard result.value.isFinite else { throw ParseError.nonFiniteResult }
    return result.value
}

/// r83: the KIND-AWARE numeric entry — the same normalization,
/// tokenization and parse as `evaluateExpression`, but the result
/// carries its semantic kind (a percent mode like `10% + 20%` yields
/// `.percent`; the `x` suffix yields `.multiplier`; everything else
/// stays `.plain`). `variables` maps display names to their typed
/// values so a percent/multiplier-typed variable propagates its kind
/// (contextual `200 + x` after `x = 10%`).
public func evaluateExpressionKinded(
    _ expr: String,
    variables: [String: TypedScalar],
    context: NumberFormatContext
) throws -> (value: Double, kind: NumericKind) {
    let trimmed = expr.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { throw ParseError.emptyExpression }
    let tokens = try tokenize(normalizeExprCorrect(trimmed, context: context), context: context)
    var parser = ExprParser(tokens: tokens, vars: variables)
    let parsed = try parser.parseExpression()
    if parser.pos < parser.tokens.count {
        throw ParseError.unexpectedToken("\(parser.tokens[parser.pos])")
    }
    let result = try parser.evalNumeric(parsed)
    guard result.value.isFinite else { throw ParseError.nonFiniteResult }
    return (result.value, result.kind)
}

/// r83: the kind-aware entry over the legacy `[String: Double]`
/// projection (every value is plain — the convenience callers use).
public func evaluateExpressionKinded(
    _ expr: String,
    variables: [String: Double],
    context: NumberFormatContext
) throws -> (value: Double, kind: NumericKind) {
    try evaluateExpressionKinded(expr,
                                 variables: variables.mapValues { TypedScalar.number($0) },
                                 context: context)
}

/// r83: the structural shape of an operand in the percentage phrase
/// grammar: a percent literal (or percent-kind named value), a `x`
/// multiplier literal, a fraction (a simple division tree or a
/// fraction-kind value), or plain.
public enum OperandShape: Equatable {
    case plain, percent, multiplier, fraction
}

/// r83: the kind- and shape-aware operand evaluator used by the
/// percentage phrase grammar. Returns the value, the semantic kind
/// (percent/multiplier literals and named values keep their kinds) and
/// the structural shape the grammar gates on (`2/3 of 600` works
/// because the left operand's shape is .fraction; `5 of 600` stays
/// dead because a plain number is not a percent-ish magnitude).
public func evaluateOperand(_ expr: String,
                            variables: [String: TypedScalar],
                            context: NumberFormatContext) throws
    -> (value: Double, kind: NumericKind, shape: OperandShape) {
    let trimmed = expr.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { throw ParseError.emptyExpression }
    let tokens = try tokenize(normalizeExprCorrect(trimmed, context: context), context: context)
    var parser = ExprParser(tokens: tokens, vars: variables)
    let parsed = try parser.parseExpression()
    if parser.pos < parser.tokens.count {
        throw ParseError.unexpectedToken("\(parser.tokens[parser.pos])")
    }
    let result = try parser.evalNumeric(parsed)
    guard result.value.isFinite else { throw ParseError.nonFiniteResult }
    return (result.value, result.kind, operandShape(of: parsed, vars: variables))
}

/// The structural shape of a parsed operand tree: the top node
/// decides, with named values contributing their recorded kinds and
/// a simple division tree a .fraction.
func operandShape(of e: Expr, vars: [String: TypedScalar]) -> OperandShape {
    func varShape(_ name: String) -> OperandShape {
        switch vars[name] {
        case .number(_, .percent): return .percent
        case .number(_, .multiplier): return .multiplier
        case .number(_, .fraction): return .fraction
        default: return .plain
        }
    }
    func go(_ n: Expr) -> OperandShape {
        switch n {
        case .percent:
            return .percent
        case .mult:
            return .multiplier
        case .of(let a, _):
            return go(a) // the left operand is the magnitude
        case .variable(let name):
            return varShape(name)
        case .div:
            if ExprParser.isSimpleRational(n) { return .fraction }
            return .plain
        default:
            return .plain
        }
    }
    return go(e)
}

/// r82: the TYPED entry point: the same normalization/tokenization,
/// the full boolean precedence chain, and strict typed evaluation.
/// `variables` carries both finite scalars and booleans; a boolean
/// result is returned as `TypedScalar.bool` — never a numeric 1/0.
public func evaluateTypedExpression(_ expr: String,
                                    variables: [String: TypedScalar],
                                    context: NumberFormatContext = .legacy) throws -> TypedScalar {
    let trimmed = expr.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { throw ParseError.emptyExpression }
    let tokens = try tokenize(normalizeExprCorrect(trimmed, context: context), context: context)
    var parser = ExprParser(tokens: tokens, vars: variables)
    let parsed = try parser.parseConditional()
    if parser.pos < parser.tokens.count {
        throw ParseError.unexpectedToken("\(parser.tokens[parser.pos])")
    }
    return try parser.evalTyped(parsed)
}
