import Foundation

public enum Token: Equatable, Sendable {
    case number(Double)
    case identifier(String)
    case op(String)       // + - * / ^ % (× canonicalizes to *, ÷ to /)
    case paren(String)    // ( )
    case comma            // r47: argument separator (grouping commas are
                          // stripped by the function-aware normalization)
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

/// r73: the exact pre-r73 tokenizer (decimal `.`, argument `,`;
/// `;` stays an unexpected character) — every existing call site and
/// store keeps byte-identical behavior.
public func tokenize(_ expr: String) throws -> [Token] {
    try tokenize(expr, context: .legacy)
}

/// r73: the context-aware tokenizer. The only differences from the
/// legacy scanner are decimal-comma mode (the context's decimal
/// separator — `,` — is a digit-run decimal point, and `;` is the
/// function argument separator) and decimal-point mode where `;`
/// remains an unexpected character, exactly as before. NBSP group
/// separators never reach the tokenizer: they are already stripped by
/// the context normalizer, and a stray NBSP is whitespace (the
/// documented no-op input rule).
public func tokenize(_ expr: String, context: NumberFormatContext) throws -> [Token] {
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
        if ch == "×" {
            // The display multiplication sign: identical semantics to `*`
            // (precedence included); the token stays canonical `*`.
            tokens.append(.op("*"))
            i = expr.index(after: i)
            continue
        }
        if ch == "÷" {
            // The division glyph: identical semantics to `/`;
            // the token stays canonical `/`.
            tokens.append(.op("/"))
            i = expr.index(after: i)
            continue
        }
        if "+-*/^%".contains(ch) {
            tokens.append(.op(String(ch)))
            i = expr.index(after: i)
            continue
        }
        if ch == "," {
            // The argument separator of decimal-point modes. In
            // decimal-comma modes a surviving comma is the SPACED
            // argument separator (the normalizer converted every
            // digit-adjacent comma to a decimal dot, and a digit-
            // leading decimal run is a number for the number branch
            // below) — a stray one degrades to a parser error, never
            // a tokenizer panic.
            tokens.append(.comma)
            i = expr.index(after: i)
            continue
        }
        if ch == ";" {
            // r73: the decimal-comma argument separator
            // (`max(1,5; 2,5)`). In decimal-point modes `;` is an
            // unexpected character, exactly like any other unknown
            // character.
            if context.decimalComma {
                tokens.append(.comma)
            } else {
                throw TokenizeError.unexpectedCharacter(ch)
            }
            i = expr.index(after: i)
            continue
        }
        if ch.isNumber || ch == "." {
            var numStr = ""
            var dots = 0
            while i < expr.endIndex {
                let c = expr[i]
                if c.isNumber {
                    numStr.append(c)
                    i = expr.index(after: i)
                    continue
                }
                if c == "." {
                    dots += 1
                    numStr.append(".")
                    i = expr.index(after: i)
                    continue
                }
                break
            }
            if dots > 1 || numStr == "." || numStr.isEmpty {
                throw TokenizeError.invalidNumber(numStr)
            }
            // A literal with hundreds of digits can parse to +∞ (or −∞
            // via a later sign); non-finite literals are rejected at the
            // boundary instead of flowing through the evaluator.
            guard let v = Double(numStr), v.isFinite else { throw TokenizeError.invalidNumber(numStr) }
            tokens.append(.number(v))
            continue
        }
        if context.decimalComma, ch == "," {
            // r73: a decimal-comma run must START with a digit after
            // the comma (`,5` is the leading-dot edge of `0,5`);
            // anything else is a stray decimal comma -> unexpected.
            let next = expr.index(after: i)
            guard next < expr.endIndex, expr[next].isNumber else {
                throw TokenizeError.unexpectedCharacter(ch)
            }
            var numStr = "."
            i = next
            while i < expr.endIndex, expr[i].isNumber {
                numStr.append(expr[i])
                i = expr.index(after: i)
            }
            guard let v = Double(numStr), v.isFinite else {
                throw TokenizeError.invalidNumber(numStr)
            }
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
