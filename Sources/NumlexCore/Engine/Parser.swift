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
    let tokens = try tokenize(trimmed)
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
            node = .variable(name)
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
