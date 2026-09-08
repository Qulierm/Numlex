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
    /// The bounded percent infix: `15% of 490` = 0.15 × 490.
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

/// A parsed value plus its contextual-percentage flag. Only a postfix
/// `p%` (including parenthesized `(p%)`) is a "pure percentage";
/// anything that has already combined with another operand is not.
struct EvalValue: Sendable {
    var value: Double
    var purePercent: Bool
}

/// r82: the typed scalar a boolean-aware expression can produce. A
/// boolean is NEVER a numeric 1/0: the typed evaluator carries the two
/// kinds distinctly and strict typing keeps them from mixing.
public enum TypedScalar: Equatable, Sendable {
    case number(Double)
    case bool(Bool)
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
        if case .of = node { return true }
        return false
    }

    // MARK: - Numeric evaluation (legacy semantics)

    /// The legacy value evaluator: contextual percentages and pure
    /// scalar arithmetic. r82: any boolean production reached here
    /// fails DETERMINISTICALLY — the numeric API never coerces a
    /// boolean to 0/1.
    func evalNumeric(_ node: Expr) throws -> EvalValue {
        switch node {
        case .num(let v):
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .variable(let name):
            guard let v = vars[name], case .number(let n) = v, n.isFinite else {
                if vars[name] == nil { throw ParseError.unknownVariable(name) }
                throw ParseError.booleanExpression
            }
            return EvalValue(value: n, purePercent: false)
        case .add(let l, let r):
            let a = try evalNumeric(l)
            let b = try evalNumeric(r)
            let v: Double
            if b.purePercent {
                // `base + base×p/100` — the base is the accumulated
                // left value, so sequential percents compound.
                v = a.value + a.value * b.value
            } else {
                v = a.value + b.value
            }
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .sub(let l, let r):
            let a = try evalNumeric(l)
            let b = try evalNumeric(r)
            let v: Double
            if b.purePercent {
                v = a.value - a.value * b.value
            } else {
                v = a.value - b.value
            }
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .mul(let l, let r):
            let a = try evalNumeric(l)
            let b = try evalNumeric(r)
            let v = a.value * b.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .div(let l, let r):
            let a = try evalNumeric(l)
            let b = try evalNumeric(r)
            if b.value == 0 { throw ParseError.divisionByZero }
            let v = a.value / b.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .pow(let l, let r):
            let a = try evalNumeric(l)
            let b = try evalNumeric(r)
            let v = pow(a.value, b.value)
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .neg(let l):
            let a = try evalNumeric(l)
            let v = -a.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            // A unary minus yields an ordinary scalar: `-10%` = -0.1.
            return EvalValue(value: v, purePercent: false)
        case .percent(let l):
            let a = try evalNumeric(l)
            let v = a.value / 100
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: true)
        case .of(let l, let r):
            let a = try evalNumeric(l)
            let eligible: Bool
            if case .of = l {
                eligible = true
            } else {
                eligible = a.purePercent
            }
            guard eligible else { throw ParseError.unexpectedToken("of") }
            let b = try evalNumeric(r)
            let v = a.value * b.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
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
            return EvalValue(value: v, purePercent: false)
        // r82: boolean productions are unreachable on a healthy numeric
        // line; when one reaches here (a boolean variable on a numeric
        // route) the deterministic failure is the boolean sentinel —
        // never a coercion.
        case .boolLit, .not, .and, .or, .lt, .le, .gt, .ge, .eq, .ne, .ifThenElse:
            throw ParseError.booleanExpression
        }
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
            return .number(v)
        case .variable(let name):
            guard let v = vars[name] else { throw ParseError.unknownVariable(name) }
            if case .number(let n) = v, !n.isFinite { throw ParseError.invalidVariable(name) }
            return v
        case .add(let l, let r):
            return .number(try arithmetic(l, r) { a, b in a + b })
        case .sub(let l, let r):
            return .number(try arithmetic(l, r) { a, b in a - b })
        case .mul(let l, let r):
            return .number(try arithmetic(l, r) { a, b in a * b })
        case .div(let l, let r):
            let a = try scalar(l, op: "/")
            let b = try scalar(r, op: "/")
            if b == 0 { throw ParseError.divisionByZero }
            let v = a / b
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(v)
        case .pow(let l, let r):
            let a = try scalar(l, op: "^")
            let b = try scalar(r, op: "^")
            let v = pow(a, b)
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(v)
        case .neg(let l):
            let a = try scalar(l, op: "-")
            let v = -a
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(v)
        case .percent(let l):
            let a = try scalar(l, op: "%")
            let v = a / 100
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(v)
        case .of(let l, let r):
            let a = try scalar(l, op: "of")
            let b = try scalar(r, op: "of")
            let v = a * b
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(v)
        case .funcall(let key, let args):
            let values = try args.map { try scalar($0, op: key) }
            let v: Double
            do {
                v = try MathFunctions.evaluate(key, args: values)
            } catch let e as MathFunctions.MathFunctionError {
                throw ParseError.functionError(e.errorDescription ?? "Invalid function")
            }
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return .number(v)
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
        if case .number(let n) = v { return n }
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
