import Foundation

public enum Token: Equatable, Sendable {
    case number(Double)
    case identifier(String)
    case op(String)       // + - * / ^ %
    case paren(String)    // ( )
}

public enum TokenizeError: Error, LocalizedError {
    case invalidNumber(String)
    case unexpectedCharacter(Character)
    public var errorDescription: String? {
        switch self {
        case .invalidNumber(let s): return "Invalid number '\(s)'"
        case .unexpectedCharacter(let c): return "Unexpected character '\(c)'"
        }
    }
}

public func tokenize(_ expr: String) throws -> [Token] {
    var tokens: [Token] = []
    var i = expr.startIndex
    while i < expr.endIndex {
        let ch = expr[i]
        if ch.isWhitespace {
            i = expr.index(after: i)
            continue
        }
        if ch == "(" || ch == ")" {
            tokens.append(.paren(String(ch)))
            i = expr.index(after: i)
            continue
        }
        if "+-*/^%".contains(ch) {
            tokens.append(.op(String(ch)))
            i = expr.index(after: i)
            continue
        }
        if ch.isNumber || ch == "." {
            var numStr = ""
            var dots = 0
            while i < expr.endIndex && (expr[i].isNumber || expr[i] == ".") {
                if expr[i] == "." { dots += 1 }
                numStr.append(expr[i])
                i = expr.index(after: i)
            }
            if dots > 1 || numStr == "." || numStr.isEmpty {
                throw TokenizeError.invalidNumber(numStr)
            }
            guard let v = Double(numStr) else { throw TokenizeError.invalidNumber(numStr) }
            tokens.append(.number(v))
            continue
        }
        if ch.isLetter || ch == "_" {
            var id = ""
            while i < expr.endIndex && (expr[i].isLetter || expr[i].isNumber || expr[i] == "_") {
                id.append(expr[i])
                i = expr.index(after: i)
            }
            tokens.append(.identifier(id))
            continue
        }
        throw TokenizeError.unexpectedCharacter(ch)
    }
    return tokens
}
