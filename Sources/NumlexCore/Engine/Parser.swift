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
}

/// A parsed value plus its contextual-percentage flag. Only a postfix
/// `p%` (including parenthesized `(p%)`) is a "pure percentage";
/// anything that has already combined with another operand is not.
struct EvalValue: Sendable {
    var value: Double
    var purePercent: Bool
}

public func evaluateExpression(_ expr: String, variables: [String: Double]) throws -> Double {
    let trimmed = expr.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { throw ParseError.emptyExpression }
    // r47: normalize FIRST (idempotent — the line routes normalize
    // before calling, and re-normalizing a normalized string is a
    // no-op): commas outside calls are grouping artifacts and are
    // stripped, commas inside calls keep the shared separator rule.
    // The direct API and the line routes therefore always agree.
    let tokens = try tokenize(normalizeExprCorrect(trimmed))
    var pos = 0
    func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }
    func consume() -> Token { let t = tokens[pos]; pos += 1; return t }

    func parseExpression() throws -> Expr {
        var left = try parseTerm()
        while let t = peek(), case .op(let op) = t, (op == "+" || op == "-") {
            _ = consume()
            let right = try parseTerm()
            left = (op == "+") ? .add(left, right) : .sub(left, right)
        }
        return left
    }

    func parseTerm() throws -> Expr {
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

    func parseFactor() throws -> Expr {
        let left = try parseUnary()
        if let t = peek(), case .op("^") = t {
            _ = consume()
            let right = try parseFactor() // right associative
            return .pow(left, right)
        }
        return left
    }

    func parseUnary() throws -> Expr {
        if let t = peek(), case .op(let op) = t, (op == "+" || op == "-") {
            _ = consume()
            let v = try parseUnary()
            return op == "-" ? .neg(v) : v
        }
        return try parsePrimary()
    }

    func parsePrimary() throws -> Expr {
        guard let tok = peek() else { throw ParseError.unexpectedEnd }
        var node: Expr
        switch tok {
        case .number(let v):
            _ = consume()
            node = .num(v)
        case .identifier(let name):
            _ = consume()
            // r47: call position. The tokenizer already skips
            // whitespace, so an identifier token directly followed by a
            // `(` token is `name(` or `name (` — a call head. A KNOWN
            // builtin takes precedence over any same-named variable or
            // constant ONLY here; in every non-call position the
            // identifier stays an ordinary variable lookup. An UNKNOWN
            // name in call position is strict — a deterministic
            // "unknown function" error, never a parenthesized operand.
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
        case .paren("("):
            _ = consume()
            node = try parseExpression()
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
    func parseFunctionCall(_ name: String) throws -> Expr {
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

    func isPurePercent(_ node: Expr) -> Bool {
        if case .percent = node { return true }
        return false
    }

    func isOfEligible(_ node: Expr) -> Bool {
        if case .percent = node { return true }
        if case .of = node { return true }
        return false
    }

    // MARK: - Evaluation (contextual percentages live here)

    func eval(_ node: Expr) throws -> EvalValue {
        switch node {
        case .num(let v):
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .variable(let name):
            guard let v = variables[name] else { throw ParseError.unknownVariable(name) }
            guard v.isFinite else { throw ParseError.invalidVariable(name) }
            return EvalValue(value: v, purePercent: false)
        case .add(let l, let r):
            let a = try eval(l)
            let b = try eval(r)
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
            let a = try eval(l)
            let b = try eval(r)
            let v: Double
            if b.purePercent {
                v = a.value - a.value * b.value
            } else {
                v = a.value - b.value
            }
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .mul(let l, let r):
            let a = try eval(l)
            let b = try eval(r)
            let v = a.value * b.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .div(let l, let r):
            let a = try eval(l)
            let b = try eval(r)
            if b.value == 0 { throw ParseError.divisionByZero }
            let v = a.value / b.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .pow(let l, let r):
            let a = try eval(l)
            let b = try eval(r)
            let v = pow(a.value, b.value)
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .neg(let l):
            let a = try eval(l)
            let v = -a.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            // A unary minus yields an ordinary scalar: `-10%` = -0.1.
            return EvalValue(value: v, purePercent: false)
        case .percent(let l):
            let a = try eval(l)
            let v = a.value / 100
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: true)
        case .of(let l, let r):
            let a = try eval(l)
            let eligible: Bool
            if case .of = l {
                eligible = true
            } else {
                eligible = a.purePercent
            }
            guard eligible else { throw ParseError.unexpectedToken("of") }
            let b = try eval(r)
            let v = a.value * b.value
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        case .funcall(let key, let args):
            // r47: arguments are plain scalars — a percent argument is
            // its non-additive value (`10%` = 0.1). Domain and
            // non-finite failures carry the registry's stable message.
            let values = try args.map { try eval($0).value }
            let v: Double
            do {
                v = try MathFunctions.evaluate(key, args: values)
            } catch let e as MathFunctions.MathFunctionError {
                throw ParseError.functionError(e.errorDescription ?? "Invalid function")
            }
            guard v.isFinite else { throw ParseError.nonFiniteResult }
            return EvalValue(value: v, purePercent: false)
        }
    }

    let parsed = try parseExpression()
    if pos < tokens.count {
        throw ParseError.unexpectedToken("\(tokens[pos])")
    }
    // Overflow defense: every intermediate was checked above; the final
    // value is finite by construction (kept as a last-line invariant).
    let result = try eval(parsed)
    guard result.value.isFinite else { throw ParseError.nonFiniteResult }
    return result.value
}
