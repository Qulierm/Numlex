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

public func evaluateExpression(_ expr: String, variables: [String: Double]) throws -> Double {
    let trimmed = expr.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { throw ParseError.emptyExpression }
    let tokens = try tokenize(trimmed)
    var pos = 0
    func peek() -> Token? { pos < tokens.count ? tokens[pos] : nil }
    func consume() -> Token { let t = tokens[pos]; pos += 1; return t }

    func parseExpression() throws -> Double {
        var left = try parseTerm()
        while let t = peek(), case .op(let op) = t, (op == "+" || op == "-") {
            _ = consume()
            let right = try parseTerm()
            if op == "+" { left += right } else { left -= right }
        }
        return left
    }
    func parseTerm() throws -> Double {
        var left = try parseFactor()
        while let t = peek(), case .op(let op) = t, (op == "*" || op == "/") {
            _ = consume()
            let right = try parseFactor()
            if op == "*" { left *= right }
            else {
                if right == 0 { throw ParseError.divisionByZero }
                left /= right
            }
        }
        return left
    }
    func parseFactor() throws -> Double {
        var left = try parseUnary()
        if let t = peek(), case .op("^") = t {
            _ = consume()
            let right = try parseFactor() // right associative
            left = pow(left, right)
        }
        return left
    }
    func parseUnary() throws -> Double {
        if let t = peek(), case .op(let op) = t, (op == "+" || op == "-") {
            _ = consume()
            let v = try parseUnary()
            return op == "-" ? -v : v
        }
        return try parsePrimary()
    }
    func parsePrimary() throws -> Double {
        guard let tok = peek() else { throw ParseError.unexpectedEnd }
        var value: Double
        switch tok {
        case .number(let v):
            _ = consume()
            value = v
        case .identifier(let name):
            _ = consume()
            guard let v = variables[name] else { throw ParseError.unknownVariable(name) }
            if !v.isFinite { throw ParseError.invalidVariable(name) }
            value = v
        case .paren("("):
            _ = consume()
            value = try parseExpression()
            guard let closing = peek(), case .paren(")") = closing else { throw ParseError.missingClosingParen }
            _ = consume()
        default:
            throw ParseError.unexpectedToken("\(tok)")
        }
        // postfix percent
        while let t = peek(), case .op("%") = t {
            _ = consume()
            value /= 100
        }
        return value
    }

    let result = try parseExpression()
    if pos < tokens.count {
        throw ParseError.unexpectedToken("\(tokens[pos])")
    }
    // Overflow defense: pow/multiplication/addition can produce ±∞ or
    // NaN (e.g. `10 ^ 400`). The invariant is that evaluateExpression
    // only ever returns finite numbers, so every call site (expressions,
    // assignments, cleaned fallbacks) rejects non-finite results here.
    guard result.isFinite else { throw ParseError.nonFiniteResult }
    return result
}
