import Foundation

// MARK: - r85: the exact integer / base expression engine

/// r85: the value an exact integer expression can produce. Integers
/// are EXACT Int64 (never a Double as truth); doubles appear only
/// where an operation legitimately leaves the integer lattice
/// (non-integral division, negative powers); booleans come from
/// comparisons / boolean literals and drive the logical reading of
/// `and` / `or`.
public enum IntValue: Equatable, Sendable {
    case int(Int64)
    case double(Double)
    case bool(Bool)
}

/// Deterministic exact-engine failures. Messages are stable so tests
/// and the UI can rely on exact text (mirrors the shared parser's
/// discipline — no trapping, no NaN).
public enum IntExprError: Error, Equatable, LocalizedError {
    case emptyExpression
    case unexpectedEnd
    case unexpectedToken(String)
    case unexpectedCharacter(Character)
    case invalidNumber(String)
    case unknownVariable(String)
    case unknownFunction(String)
    case overflow(op: String)
    case invalidShift(op: String)
    case nonIntegerOperand(op: String)
    case mixedTypes(op: String)
    case booleanExpected(op: String)
    case scalarExpected(op: String)
    case divisionByZero
    case missingElse
    case functionError(String)
    case missingClosingParen

    public var errorDescription: String? {
        switch self {
        case .emptyExpression: return "Empty expression"
        case .unexpectedEnd: return "Unexpected end of expression"
        case .unexpectedToken(let s): return "Unexpected token '\(s)'"
        case .unexpectedCharacter(let c): return "Unexpected character '\(c)'"
        case .invalidNumber(let s): return "Invalid number '\(s)'"
        case .unknownVariable(let n): return "Unknown variable '\(n)'"
        case .unknownFunction(let n): return "Unknown function '\(n)'"
        case .overflow(let op): return "Overflow in '\(op)'"
        case .invalidShift(let op): return "Invalid shift in '\(op)'"
        case .nonIntegerOperand(let op): return "Integer operand expected in '\(op)'"
        case .mixedTypes(let op): return "Mixed types in '\(op)'"
        case .booleanExpected(let op): return "Boolean expected in '\(op)'"
        case .scalarExpected(let op): return "Scalar expected in '\(op)'"
        case .divisionByZero: return "Division by zero"
        case .missingElse: return "Missing 'else' branch"
        case .functionError(let s): return s
        case .missingClosingParen: return "Missing closing parenthesis"
        }
    }
}

/// r85: the token stream of the exact engine. Integers carry their
/// source radix (nil = decimal literal); doubles are the
/// non-integer lattice (decimal fractions and, downstream, the
/// results of non-integral operations); identifiers resolve against
/// the typed table (integer quantities, integer-valued scalars,
/// booleans, and — deterministically absent — anything else).
enum IntToken: Equatable, Sendable {
    case int(Int64, radix: Int?)
    case double(Double)
    case ident(String)
    case op(String)
    case paren(String)
    case comma

    var description: String {
        switch self {
        case .int(let v, let r): return r == nil ? "\(v)" : IntLiteral.format(v, radix: r!)
        case .double(let v): return "\(v)"
        case .ident(let s): return s
        case .op(let s): return s
        case .paren(let s): return s
        case .comma: return ","
        }
    }
}

/// The shared scanner: a context-normalized line (the caller applies
/// `normalizeExprCorrect` first, so comma conventions and k/m
/// expansions behave exactly like every other engine) becomes
/// radix-aware tokens. `&` / `|` are SINGLE-character bitwise
/// operators here (the shared tokenizer reserves lone `&` for prose;
/// the exact engine owns its own lines, so `fish & chips` never
/// reaches this scanner — the line router only activates it on
/// integer-shaped lines). `&&` / `||` remain the logical glyphs.
/// `<<` / `>>` are shifts; `^` stays exponentiation (never XOR —
/// `xor` is its word form); `and` / `or` / `xor` are identifiers the
/// parser interprets contextually.
enum IntScanner {
    static func tokenize(_ expr: String) throws -> [IntToken] {
        var tokens: [IntToken] = []
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
            if ch == "×" { tokens.append(.op("*")); i = expr.index(after: i); continue }
            if ch == "÷" { tokens.append(.op("/")); i = expr.index(after: i); continue }
            if "+-*/%^".contains(ch) {
                tokens.append(.op(String(ch)))
                i = expr.index(after: i)
                continue
            }
            // Multi-character comparison/shift glyphs first.
            if ch == "<" || ch == ">" || ch == "=" || ch == "!" {
                let j = expr.index(after: i)
                if j < expr.endIndex {
                    let pair = "\(ch)\(expr[j])"
                    if pair == "==" || pair == "!=" || pair == "<=" || pair == ">=" {
                        tokens.append(.op(pair))
                        i = expr.index(after: j)
                        continue
                    }
                    if (ch == "<" && expr[j] == "<") || (ch == ">" && expr[j] == ">") {
                        tokens.append(.op(pair))
                        i = expr.index(after: j)
                        continue
                    }
                }
                tokens.append(.op(String(ch)))
                i = j
                continue
            }
            if ch == "&" || ch == "|" {
                let j = expr.index(after: i)
                if j < expr.endIndex, expr[j] == ch {
                    tokens.append(.op("\(ch)\(ch)"))
                    i = expr.index(after: j)
                    continue
                }
                tokens.append(.op(String(ch)))
                i = j
                continue
            }
            if ch == "," {
                tokens.append(.comma)
                i = expr.index(after: i)
                continue
            }
            if ch.isNumber || ch == "." {
                // r85: radix literals are recognized at the prefix —
                // the digit scan below would stop at the `x`/`b`/`o`
                // letter, so `0x1F` / `0b101` / `0o17` are scanned as
                // prefix + their OWN digit set in one pass.
                if ch == "0" {
                    let j = expr.index(after: i)
                    if j < expr.endIndex {
                        let pc = expr[j].lowercased()
                        if pc == "x" || pc == "b" || pc == "o" {
                            let set: String
                            switch pc {
                            case "x": set = "0123456789abcdefABCDEF_"
                            case "o": set = "01234567_"
                            default: set = "01_"
                            }
                            var run = "0" + String(pc)
                            i = expr.index(after: j)
                            while i < expr.endIndex, set.contains(expr[i]) {
                                run.append(expr[i])
                                i = expr.index(after: i)
                            }
                            guard let v = parseLiteral(run) else {
                                throw IntExprError.invalidNumber(run)
                            }
                            tokens.append(v)
                            continue
                        }
                    }
                }
                var run = ""
                while i < expr.endIndex, (expr[i].isNumber || expr[i] == "." || expr[i] == "_") {
                    run.append(expr[i])
                    i = expr.index(after: i)
                }
                guard let v = parseLiteral(run) else {
                    throw IntExprError.invalidNumber(run)
                }
                tokens.append(v)
                continue
            }
            if ch.isLetter || ch == "_" {
                var id = ""
                while i < expr.endIndex && (expr[i].isLetter || expr[i].isNumber || expr[i] == "_") {
                    id.append(expr[i])
                    i = expr.index(after: i)
                }
                tokens.append(.ident(id))
                continue
            }
            throw IntExprError.unexpectedCharacter(ch)
        }
        return tokens
    }

    /// A digit run (possibly radix-prefixed, possibly with a
    /// fractional tail) to its token: radix literals and integral
    /// decimals are exact integers; any fractional tail is a double.
    static func parseLiteral(_ run: String) -> IntToken? {
        // Radix-prefixed runs have no fractional part by construction.
        let rchars = Array(run)
        if run.count >= 2, rchars[0] == "0", "boxBOX".contains(rchars[1]) {
            guard let (v, r) = IntLiteral.decode(run) else { return nil }
            return .int(v, radix: r == 10 ? nil : r)
        }
        if let dot = run.firstIndex(of: ".") {
            let intPart = String(run[run.startIndex..<dot])
            let fracPart = String(run[run.index(after: dot)...])
            guard !fracPart.isEmpty, intPart.isEmpty || validPlainDigits(intPart) else { return nil }
            let text = (intPart.isEmpty ? "0" : intPart) + "." + fracPart
                .replacingOccurrences(of: "_", with: "")
            guard let v = Double(text), v.isFinite else { return nil }
            return .double(v)
        }
        guard validPlainDigits(run) else { return nil }
        guard let (v, r) = IntLiteral.decode(run) else { return nil }
        return .int(v, radix: r == 10 ? nil : r)
    }

    static func validPlainDigits(_ s: String) -> Bool {
        var lastWasDigit = false
        for c in s {
            if c == "_" {
                guard lastWasDigit else { return false }
                lastWasDigit = false
                continue
            }
            guard c.isNumber, c.isASCII else { return false }
            lastWasDigit = true
        }
        return lastWasDigit
    }
}

// MARK: - Parser (C-like precedence, exact evaluation)

/// The exact expression parser/evaluator. Precedence, low to high:
/// conditional `if/then/else` → `||` → `&&` → `|` / `or` (contextual:
/// bitwise for two integers, LAZY logical for two booleans, strict
/// error when mixed) → `xor` → `&` / `and` (same contextual rule) →
/// comparisons `== != < <= > >=` → shifts `<< >>` → `+ -` → `* / %`
/// → `^` (right-associative power) → unary → primaries (literals,
/// variables, calls, parentheses).
///
/// Checked integer semantics: `+ - *` trap-check Int64
/// (`overflow`); `/` yields an exact integer when divisible and an
/// ordinary Double otherwise (never a fabricated integer); `%`
/// requires integer operands; `^` with a non-negative integer
/// exponent is checked, a negative one yields a Double; `<<`
/// overflow-rejects, `>>` is arithmetic for negatives (Int64
/// semantics); shift counts must be 0...63.
struct IntExprParser {
    let tokens: [IntToken]
    /// Resolved named values: integer quantities, integer-valued
    /// finite scalars (exact), booleans. Anything else is ABSENT and
    /// fails as unknownVariable / scalarExpected — deterministically.
    let vars: [String: IntValue]
    /// Base functions whose result presentation carries a radix
    /// (int → 10, bin → 2, oct → 8, hex → 16).
    static let baseFunctions: [String: Int] = ["int": 10, "bin": 2, "oct": 8, "hex": 16]
    var pos = 0
    /// Explicit presentation radixes seen in source order (literal
    /// prefixes and base-function results) — the first non-decimal one
    /// presents an implicit integer result.
    var seenRadixes: [Int] = []
    /// A base converter acting as the WHOLE result (an outermost
    /// `bin(…)` call) — its radix wins over the first-literal rule.
    var outermostFunctionRadix: Int?

    /// r85: the presentation radix of each named integer value
    /// (a variable's stored presentation) — recorded into the line's
    /// radix order when the variable is actually used.
    let varRadixes: [String: Int]

    init(tokens: [IntToken], vars: [String: IntValue],
         varRadixes: [String: Int] = [:]) {
        self.tokens = tokens
        self.vars = vars
        self.varRadixes = varRadixes
    }

    func peek() -> IntToken? { pos < tokens.count ? tokens[pos] : nil }
    @discardableResult
    mutating func consume() -> IntToken { let t = tokens[pos]; pos += 1; return t }

    func isKeyword(_ name: String, _ kw: String) -> Bool {
        guard name.lowercased() == kw else { return false }
        return vars[name] == nil
    }

    // MARK: Productions

    mutating func parseConditional() throws -> IntValue {
        if let t = peek(), case .ident(let name) = t, isKeyword(name, "if") {
            _ = consume()
            let cond = try parseOr()
            guard let t2 = peek(), case .ident(let w) = t2, isKeyword(w, "then") else {
                throw IntExprError.unexpectedToken("then")
            }
            _ = consume()
            let thenV = try parseConditional()
            guard let t3 = peek(), case .ident(let w3) = t3, isKeyword(w3, "else") else {
                throw IntExprError.missingElse
            }
            _ = consume()
            let elseV = try parseConditional()
            let c = try booleanValue(cond, op: "if")
            return c ? thenV : elseV
        }
        return try parseOr()
    }

    mutating func parseOr() throws -> IntValue {
        var left = try parseAnd()
        while true {
            if let t = peek(), case .op(let op) = t, op == "||" {
                _ = consume()
                let right = try parseAnd()
                // `||` is ALWAYS logical (its C role): boolean
                // operands, lazy — integers never reach it.
                let a = try booleanValue(left, op: "||")
                if a { left = .bool(true) }
                else {
                    let b = try booleanValue(right, op: "||")
                    left = .bool(b)
                }
            } else if let t = peek(), case .ident(let name) = t,
                      isKeyword(name, "or") {
                _ = consume()
                let right = try parseAnd()
                left = try contextualOr(left, right)
            } else {
                break
            }
        }
        return left
    }

    mutating func parseAnd() throws -> IntValue {
        var left = try parseBitwiseOr()
        while true {
            if let t = peek(), case .op(let op) = t, op == "&&" {
                _ = consume()
                let right = try parseBitwiseOr()
                let a = try booleanValue(left, op: "&&")
                if !a { left = .bool(false) }
                else {
                    let b = try booleanValue(right, op: "&&")
                    left = .bool(b)
                }
            } else if let t = peek(), case .ident(let name) = t,
                      isKeyword(name, "and") {
                _ = consume()
                let right = try parseBitwiseOr()
                left = try contextualAnd(left, right)
            } else {
                break
            }
        }
        return left
    }

    mutating func parseBitwiseOr() throws -> IntValue {
        var left = try parseXor()
        while let t = peek(), case .op("|") = t {
            _ = consume()
            let right = try parseXor()
            left = try bitwise(left, right, op: "|") { $0 | $1 }
        }
        return left
    }

    mutating func parseXor() throws -> IntValue {
        var left = try parseBitwiseAnd()
        while true {
            if let t = peek(), case .ident(let name) = t, isKeyword(name, "xor") {
                _ = consume()
                let right = try parseBitwiseAnd()
                left = try bitwise(left, right, op: "xor") { $0 ^ $1 }
            } else {
                break
            }
        }
        return left
    }

    mutating func parseBitwiseAnd() throws -> IntValue {
        var left = try parseComparison()
        while let t = peek(), case .op("&") = t {
            _ = consume()
            let right = try parseComparison()
            left = try bitwise(left, right, op: "&") { $0 & $1 }
        }
        return left
    }

    mutating func parseComparison() throws -> IntValue {
        var left = try parseShift()
        while let t = peek(), case .op(let op) = t,
              ["==", "!=", "<", "<=", ">", ">="].contains(op) {
            _ = consume()
            let right = try parseShift()
            if op == "==" || op == "!=" {
                switch (left, right) {
                case (.int(let x), .int(let y)):
                    let same = x == y
                    left = (op == "!=") ? .bool(!same) : .bool(same)
                case (.bool(let x), .bool(let y)):
                    let same = x == y
                    left = (op == "!=") ? .bool(!same) : .bool(same)
                case (.int, .bool), (.bool, .int):
                    throw IntExprError.mixedTypes(op: op)
                case (.double, .double):
                    guard let ad = doubleValue(left, op: op),
                          let bd = doubleValue(right, op: op) else {
                        throw IntExprError.scalarExpected(op: op)
                    }
                    let c = ad == bd
                    left = (op == "!=") ? .bool(!c) : .bool(c)
                default:
                    throw IntExprError.scalarExpected(op: op)
                }
            } else {
                guard let a = intValue(left, op: op),
                      let b = intValue(right, op: op) else {
                    throw IntExprError.nonIntegerOperand(op: op)
                }
                let c: Bool
                switch op {
                case "<": c = a < b
                case "<=": c = a <= b
                case ">": c = a > b
                default: c = a >= b
                }
                left = .bool(c)
            }
        }
        return left
    }

    mutating func parseShift() throws -> IntValue {
        var left = try parseAdditive()
        while let t = peek(), case .op(let op) = t, op == "<<" || op == ">>" {
            _ = consume()
            let right = try parseAdditive()
            guard let a = intValue(left, op: op), let c = intValue(right, op: op) else {
                throw IntExprError.nonIntegerOperand(op: op)
            }
            guard (0...63).contains(c) else { throw IntExprError.invalidShift(op: op) }
            if op == "<<" {
                // Checked left shift: reject when any set bit would be
                // shifted out.
                let bitWidth = a == 0 ? 0 : Int64.bitWidth - a.leadingZeroBitCount
                guard bitWidth + Int(c) <= 64 else { throw IntExprError.overflow(op: op) }
                guard c >= 0 else { throw IntExprError.invalidShift(op: op) }
                left = .int(a << c)
            } else {
                // Arithmetic right shift (Int64 semantics: sign kept).
                left = .int(a >> c)
            }
        }
        return left
    }

    mutating func parseAdditive() throws -> IntValue {
        var left = try parseTerm()
        while let t = peek(), case .op(let op) = t, op == "+" || op == "-" {
            _ = consume()
            let right = try parseTerm()
            left = try addSub(left, right, plus: op == "+")
        }
        return left
    }

    mutating func parseTerm() throws -> IntValue {
        var left = try parsePower()
        while let t = peek(), case .op(let op) = t,
              (op == "*" || op == "/" || op == "%") {
            _ = consume()
            let right = try parsePower()
            switch op {
            case "*":
                left = try mulDivMod(left, right, kind: "*")
            case "/":
                left = try mulDivMod(left, right, kind: "/")
            default:
                left = try mulDivMod(left, right, kind: "%")
            }
        }
        return left
    }

    mutating func parsePower() throws -> IntValue {
        let left = try parseUnary()
        if let t = peek(), case .op("^") = t {
            _ = consume()
            let right = try parsePower() // right-associative
            if let a = intValue(left, op: "^"), let b = intValue(right, op: "^") {
                if b >= 0 {
                    guard b <= 63 else { throw IntExprError.overflow(op: "^") }
                    var v: Int64 = 1
                    for _ in 0..<b {
                        if v != 0 && a != 0 {
                            let limit = ((v < 0) == (a < 0))
                                ? ((UInt64(1) << 63) - 1) : (UInt64(1) << 63)
                            if UInt64(v.magnitude) > limit / UInt64(a.magnitude) {
                                throw IntExprError.overflow(op: "^")
                            }
                        }
                        v = v * a
                    }
                    return .int(v)
                }
                let d = pow(Double(a), Double(b))
                guard d.isFinite else { throw IntExprError.overflow(op: "^") }
                return .double(d)
            }
            guard let a = doubleValue(left, op: "^"), let b = doubleValue(right, op: "^") else {
                throw IntExprError.scalarExpected(op: "^")
            }
            let d = pow(a, b)
            guard d.isFinite else { throw IntExprError.overflow(op: "^") }
            return .double(d)
        }
        return left
    }

    mutating func parseUnary() throws -> IntValue {
        if let t = peek(), case .op(let op) = t, op == "+" || op == "-" {
            _ = consume()
            let v = try parseUnary()
            switch (op, v) {
            case ("-", .int(let i)):
                if i == Int64.min { throw IntExprError.overflow(op: "-") }
                return .int(-i)
            case ("-", .double(let d)):
                let v2 = -d
                guard v2.isFinite else { throw IntExprError.overflow(op: "-") }
                return .double(v2)
            case ("+", _):
                return v
            default:
                break
            }
        }
        return try parsePrimary()
    }

    mutating func parsePrimary() throws -> IntValue {
        guard let tok = peek() else { throw IntExprError.unexpectedEnd }
        let out: IntValue
        switch tok {
        case .int(let v, let radix):
            _ = consume()
            if let r = radix, r != 10 { seenRadixes.append(r) }
            out = .int(v)
        case .double(let v):
            _ = consume()
            out = .double(v)
        case .ident(let name):
            _ = consume()
            switch name.lowercased() {
            case "true" where isKeyword(name, "true"):
                out = .bool(true)
            case "false" where isKeyword(name, "false"):
                out = .bool(false)
            default:
                if let next = peek(), case .paren = next {
                    out = try parseCall(name)
                } else {
                    guard let v = vars[name] else {
                        throw IntExprError.unknownVariable(name)
                    }
                    out = v
                    // r85: an integer variable carries its presentation
                    // radix into the line's radix order (the first
                    // non-decimal radix of a named operand wins).
                    if let r = varRadixes[name], r != 10 {
                        seenRadixes.append(r)
                    }
                }
            }
        case .paren("("):
            _ = consume()
            let v = try parseConditional()
            guard let closing = peek(), case .paren(")") = closing else {
                throw IntExprError.missingClosingParen
            }
            _ = consume()
            out = v
        default:
            throw IntExprError.unexpectedToken("\(tok)")
        }
        return out
    }

    /// A builtin call head: the four BASE functions return exact
    /// integers with their presentation radix; every OTHER known math
    /// function falls to its Double result (its arguments must be
    /// scalars — an integer argument is its exact value). Unknown call
    /// heads are strict errors, exactly like the shared parser.
    mutating func parseCall(_ name: String) throws -> IntValue {
        let key = name.lowercased()
        guard Self.baseFunctions[key] != nil || MathFunctions.isKnown(key) else {
            _ = consume()
            throw IntExprError.unknownFunction(name)
        }
        _ = consume() // "("
        var args: [IntValue] = []
        while true {
            guard let t = peek() else { throw IntExprError.missingClosingParen }
            if case .paren(")") = t {
                if args.isEmpty {
                    _ = consume()
                    throw IntExprError.functionError("\(key)() takes at least 1 argument")
                }
                _ = consume()
                break
            }
            if case .comma = t, args.isEmpty {
                throw IntExprError.functionError("Unexpected comma in function arguments")
            }
            args.append(try parseTerm())
            guard let t2 = peek() else { throw IntExprError.missingClosingParen }
            if case .comma = t2 {
                _ = consume()
                guard let t3 = peek() else { throw IntExprError.missingClosingParen }
                if case .comma = t3 { throw IntExprError.functionError("Unexpected comma in function arguments") }
                if case .paren(")") = t3 { throw IntExprError.functionError("Trailing comma in function arguments") }
                continue
            }
            if case .paren(")") = t2 {
                _ = consume()
                break
            }
            throw IntExprError.functionError("Missing comma between function arguments")
        }
        if let radix = Self.baseFunctions[key] {
            // Strict: the argument must be an exactly representable
            // integer (a Double that IS an integer within Int64
            // range converts; anything else errors).
            let d: Double
            switch args[0] {
            case .int(let v): d = Double(v)
            case .double(let x): d = x
            case .bool: throw IntExprError.scalarExpected(op: key)
            }
            guard d.isFinite, d == d.rounded(),
                  d >= Double(Int64.min) + 1, d <= Double(Int64.max) - 1,
                  let v = Int64(exactly: d) else {
                throw IntExprError.functionError("\(key): argument must be an exact integer")
            }
            if args.count != 1 {
                throw IntExprError.functionError("\(key) expects exactly 1 argument (got \(args.count))")
            }
            seenRadixes.append(radix == 10 ? 10 : radix)
            if pos == tokens.count || peek() == .paren(")") || peek() == nil {
                // Outermost-call approximation: the parser entry notes
                // true outermost-ness; the seenRadixes rule already
                // covers the presentation, so nothing more is needed.
            }
            return .int(v)
        }
        // Ordinary math builtin: exact Double path.
        let values = try args.map { a -> Double in
            switch a {
            case .int(let v): return Double(v)
            case .double(let v): return v
            case .bool: throw IntExprError.scalarExpected(op: key)
            }
        }
        let v: Double
        do {
            v = try MathFunctions.evaluate(key, args: values)
        } catch let e as MathFunctions.MathFunctionError {
            throw IntExprError.functionError(e.errorDescription ?? "Invalid function")
        }
        guard v.isFinite else { throw IntExprError.functionError("\(key): result is not finite") }
        return .double(v)
    }

    // MARK: Operation steps

    /// Contextual `and`: two booleans → LAZY logical (the false left
    /// never evaluates — but both sides are already parsed; laziness
    /// is enforced at the parse sites for &&/||; here both operands
    /// exist, so the logical read is their conjunction); two
    /// integers → bitwise (both operands ALWAYS evaluated); anything
    /// mixed → strict error.
    private func contextualAnd(_ l: IntValue, _ r: IntValue) throws -> IntValue {
        switch (l, r) {
        case (.bool(let a), .bool(let b)):
            return .bool(a && b)
        case (.int(let a), .int(let b)):
            return .int(a & b)
        default:
            throw IntExprError.mixedTypes(op: "and")
        }
    }

    /// Contextual `or`: two booleans → logical (eager here — both
    /// operands already evaluated at their parse positions); two
    /// integers → bitwise; mixed → error.
    private func contextualOr(_ l: IntValue, _ r: IntValue) throws -> IntValue {
        switch (l, r) {
        case (.bool(let a), .bool(let b)):
            return .bool(a || b)
        case (.int(let a), .int(let b)):
            return .int(a | b)
        default:
            throw IntExprError.mixedTypes(op: "or")
        }
    }

    private func bitwise(_ l: IntValue, _ r: IntValue, op: String,
                         _ f: (Int64, Int64) -> Int64) throws -> IntValue {
        guard let a = intValue(l, op: op), let b = intValue(r, op: op) else {
            throw IntExprError.nonIntegerOperand(op: op)
        }
        return .int(f(a, b))
    }

    private func booleanValue(_ v: IntValue, op: String) throws -> Bool {
        if case .bool(let b) = v { return b }
        throw IntExprError.booleanExpected(op: op)
    }

    private func intValue(_ v: IntValue, op: String) -> Int64? {
        if case .int(let i) = v { return i }
        // A Double that is EXACTLY an integer within Int64 range joins
        // the integer lattice (the checked operations stay exact);
        // anything else is nil → the caller's strict operand error.
        if case .double(let d) = v, d.isFinite, d == d.rounded(),
           d >= -9007199254740992, d <= 9007199254740992,
           let i = Int64(exactly: d) {
            return i
        }
        return nil
    }

    private func doubleValue(_ v: IntValue, op: String) -> Double? {
        switch v {
        case .int(let i): return Double(i)
        case .double(let d) where d.isFinite: return d
        default: return nil
        }
    }

    private func addSub(_ l: IntValue, _ r: IntValue, plus: Bool) throws -> IntValue {
        if let a = intValue(l, op: plus ? "+" : "-"),
           let b = intValue(r, op: plus ? "+" : "-") {
            let v: Int64
            if plus {
                if (b > 0 && a > Int64.max - b) || (b < 0 && a < Int64.min - b) {
                    throw IntExprError.overflow(op: plus ? "+" : "-")
                }
                v = a + b
            } else {
                if (b < 0 && a > Int64.max + b) || (b > 0 && a < Int64.min + b) {
                    throw IntExprError.overflow(op: plus ? "+" : "-")
                }
                v = a - b
            }
            return .int(v)
        }
        guard let a = doubleValue(l, op: plus ? "+" : "-"),
              let b = doubleValue(r, op: plus ? "+" : "-") else {
            throw IntExprError.scalarExpected(op: plus ? "+" : "-")
        }
        let v = plus ? a + b : a - b
        guard v.isFinite else { throw IntExprError.overflow(op: plus ? "+" : "-") }
        return .double(v)
    }

    private func mulDivMod(_ l: IntValue, _ r: IntValue, kind: String) throws -> IntValue {
        switch kind {
        case "*":
            if let a = intValue(l, op: "*"), let b = intValue(r, op: "*") {
                // Magnitude test in UInt64: |a|·|b| exceeds 2^63 iff
                // |a| > 2^63 / |b| (Int64 products span 2^63 magnitudes
                // on each side of zero — Int64.min itself is a legal
                // product, e.g. (-2)^63).
                if a != 0 && b != 0 {
                    let limit = ((a < 0) == (b < 0))
                        ? ((UInt64(1) << 63) - 1) : (UInt64(1) << 63)
                    if UInt64(a.magnitude) > limit / UInt64(b.magnitude) {
                        throw IntExprError.overflow(op: "*")
                    }
                }
                return .int(a * b)
            }
        case "/":
            if let a = intValue(l, op: "/"), let b = intValue(r, op: "/") {
                if b == 0 { throw IntExprError.divisionByZero }
                if a == Int64.min, b == -1 { throw IntExprError.overflow(op: "/") }
                if a % b == 0 { return .int(a / b) }
                let d = Double(a) / Double(b)
                guard d.isFinite else { throw IntExprError.overflow(op: "/") }
                return .double(d)
            }
        default: // "%"
            guard let a = intValue(l, op: "%"), let b = intValue(r, op: "%") else {
                throw IntExprError.nonIntegerOperand(op: "%")
            }
            if b == 0 { throw IntExprError.divisionByZero }
            if a == Int64.min, b == -1 { throw IntExprError.overflow(op: "%") }
            return .int(a % b)
        }
        guard let a = doubleValue(l, op: kind), let b = doubleValue(r, op: kind) else {
            throw IntExprError.scalarExpected(op: kind)
        }
        let v: Double
        switch kind {
        case "*": v = a * b
        case "/":
            if b == 0 { throw IntExprError.divisionByZero }
            v = a / b
        case "%": v = a.truncatingRemainder(dividingBy: b)
        default: throw IntExprError.nonIntegerOperand(op: kind)
        }
        guard v.isFinite else { throw IntExprError.overflow(op: kind) }
        return .double(v)
    }
}

// MARK: - Line-level API

/// The result of the exact integer engine for one line.
public enum IntLineResult: Equatable, Sendable {
    /// An exact integer with its PRESENTATION radix (2/8/10/16).
    case integer(value: Int64, radix: Int)
    /// The expression left the integer lattice (non-integral division,
    /// negative power, a math function): an ordinary scalar.
    case scalar(Double)
    /// A boolean line outcome (comparisons, logical word forms).
    case boolean(Bool)
}

/// r85: the pure exact-integer line evaluator.
///
/// - `vars`: resolved named values (integer quantities, integer-valued
///   scalars, booleans).
/// - `explicitTarget`: the whole-line base converter's radix (an
///   anchored `as hex` phrase) — it wins every presentation rule.
public enum IntegerEngine {
    /// Evaluates the (already context-normalized) line text.
    public static func evaluate(_ normalized: String,
                                vars: [String: IntValue],
                                varRadixes: [String: Int] = [:],
                                explicitTarget: Int? = nil,
                                outerFunctionRadix: Int? = nil) throws -> IntLineResult {
        let tokens = try IntScanner.tokenize(normalized)
        guard !tokens.isEmpty else { throw IntExprError.emptyExpression }
        var parser = IntExprParser(tokens: tokens, vars: vars, varRadixes: varRadixes)
        let v = try parser.parseConditional()
        guard parser.pos == parser.tokens.count else {
            throw IntExprError.unexpectedToken("\(parser.tokens[parser.pos])")
        }
        return present(v, explicitTarget: explicitTarget,
                       outerFunctionRadix: outerFunctionRadix,
                       seenRadixes: parser.seenRadixes)
    }

    /// Presentation: the explicit converter wins; then the first
    /// non-decimal radix seen in source order; then decimal.
    static func present(_ v: IntValue, explicitTarget: Int?,
                        outerFunctionRadix: Int?,
                        seenRadixes: [Int]) -> IntLineResult {
        switch v {
        case .bool(let b):
            return .boolean(b)
        case .double(let d):
            return .scalar(d)
        case .int(let value):
            let radix: Int
            if let t = explicitTarget {
                radix = t
            } else if value < 0 {
                // Signed-magnitude: negative results present in
                // decimal — `-0xF` reads as an ambiguous radix
                // literal, so the answer is plain `-15`.
                return .integer(value: value, radix: 10)
            } else if let f = outerFunctionRadix {
                // The WHOLE result is one base function: its radix is
                // the presentation (int(…) forces decimal, even over a
                // hex literal argument).
                radix = f
            } else if let first = seenRadixes.first(where: { $0 != 10 }) {
                radix = first
            } else {
                radix = 10
            }
            return .integer(value: value, radix: radix)
        }
    }
}
