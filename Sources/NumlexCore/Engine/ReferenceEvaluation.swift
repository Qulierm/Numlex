import Foundation

/// The per-marker evaluation state reported for editor rendering and
/// clipboard text. The display is ALWAYS derived from the current source
/// line result — no snapshot is ever stored.
public struct TokenResolution: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// The source line currently evaluates to a finite number or a
        /// variable: the token is active and shows the full quantity.
        case active(value: Double, unit: String?, display: String)
        /// The source line is missing or invalid: the token stays in
        /// place, inactive, displaying its remembered label.
        case broken(line: Int)
    }
    /// UTF-16 offset of the marker in the sheet content.
    public let location: Int
    public let state: State
    public init(location: Int, state: State) {
        self.location = location
        self.state = state
    }
}

/// Reference-aware evaluation. The STRICT ONE-RESULT-PER-LOGICAL-LINE
/// contract of `evaluateSheet` is preserved (one indexed `SheetLine` per
/// element of `content.components(separatedBy: "\n")`) plus one
/// `TokenResolution` per U+FFFC marker found in the content.
///
/// Rules:
/// - A token resolves to the CURRENT result of its source line (by
///   stable line ID, never index): `.number(v, unit)` stays
///   (v, unit), `.variable(_, v)` becomes the unitless (v, nil).
/// - Only sources STRICTLY ABOVE the token line resolve: a forward or
///   circular reference cannot hang the top-down pass — it is simply
///   broken. A source that evaluates to anything else (error, blank,
///   conversion-prose, non-finite) breaks the token too.
/// - A bare token line (the marker plus whitespace only) shows the
///   full referenced quantity; when broken it is `.brokenToken` and
///   displays the remembered `Line N` label.
/// - In a larger expression a unitless token is a numeric operand; a
///   unit-bearing token takes part with strict quantity rules (scalar
///   × / ÷, same-unit + / −, same-unit ÷ ratio, `token to <unit>`
///   conversion). Incompatible algebra is a generic hidden error —
///   never a stale value.
public func resolveSheet(
    content: String,
    lineIDs: [UUID],
    references: [AnswerReference],
    rates: Rates,
    decimalPlaces: Int
) -> (lines: [SheetLine], tokens: [TokenResolution]) {
    let lines = content.components(separatedBy: "\n")
    var idToIndex: [UUID: Int] = [:]
    for (i, id) in lineIDs.enumerated() where idToIndex[id] == nil { idToIndex[id] = i }
    var refAt: [Int: AnswerReference] = [:]
    for r in references { refAt[r.location] = r }

    // UTF-16 document offset of every logical line's start.
    var docOffsets: [Int] = []
    var acc = 0
    for line in lines {
        docOffsets.append(acc)
        acc += (line as NSString).length + 1
    }

    var vars: [String: Double] = [:]
    var memo: [Int: LineResult] = [:]
    var tokenStates: [Int: TokenResolution.State] = [:]

    func plainLine(_ line: String) -> LineResult {
        // Exactly the line-kind handling `evaluateSheet` uses.
        if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") {
            return .blank
        }
        if line.hasPrefix("// ") {
            return .title(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("//") { return .blank }
        if let eval = evalLine(line, variables: &vars, rates: rates, decimalPlaces: decimalPlaces) {
            return eval
        }
        return .skip
    }

    func evalTokenLine(_ line: String, _ index: Int, _ docStart: Int) -> LineResult {
        let ns = line as NSString
        // Collect marker positions (UTF-16 within the line).
        var markerPos: [Int] = []
        var refsHere: [AnswerReference?] = []
        var p = 0
        while p < ns.length {
            if ns.character(at: p) == answerTokenMarkerUTF16 {
                markerPos.append(p)
                refsHere.append(refAt[docStart + p])
            }
            p += 1
        }
        // Resolve every marker to a quantity or mark it broken.
        var quantities: [Qty?] = []
        var anyBroken = false
        for (k, pos) in markerPos.enumerated() {
            let docPos = docStart + pos
            guard let ref = refsHere[k] else {
                // Orphan marker (no sidecar): treated as broken.
                tokenStates[docPos] = .broken(line: 1)
                quantities.append(nil)
                anyBroken = true
                continue
            }
            guard let srcIdx = idToIndex[ref.sourceLineID], srcIdx < index else {
                // Missing source or forward reference: broken, no hang.
                tokenStates[docPos] = .broken(line: ref.labelLine)
                quantities.append(nil)
                anyBroken = true
                continue
            }
            guard let src = memo[srcIdx] else {
                tokenStates[docPos] = .broken(line: ref.labelLine)
                quantities.append(nil)
                anyBroken = true
                continue
            }
            switch src {
            case .number(let v, let u) where v.isFinite:
                let display = formatDisplayValue(v, decimalPlaces: decimalPlaces)
                    + (u.map { " \($0)" } ?? "")
                tokenStates[docPos] = .active(value: v, unit: u, display: display)
                quantities.append(Qty(v: v, unit: u))
            case .variable(_, let v) where v.isFinite:
                // A variable source is a unitless quantity.
                let display = formatDisplayValue(v, decimalPlaces: decimalPlaces)
                tokenStates[docPos] = .active(value: v, unit: nil, display: display)
                quantities.append(Qty(v: v, unit: nil))
            default:
                // Error, blank, prose, non-finite: the token is inactive.
                tokenStates[docPos] = .broken(line: ref.labelLine)
                quantities.append(nil)
                anyBroken = true
            }
        }

        let isBare = {
            markerPos.count == 1
                && (line as NSString)
                    .replacingCharacters(in: NSRange(location: markerPos[0], length: 1), with: "")
                    .trimmingCharacters(in: .whitespaces).isEmpty
        }()
        if isBare {
            if anyBroken {
                return .brokenToken(line: refsHere[0]?.labelLine ?? 1)
            }
            if let q = quantities[0] {
                return .number(value: roundResult(q.v, decimalPlaces: decimalPlaces), unit: q.unit)
            }
        }
        if anyBroken {
            // A broken token inside a larger expression hides a generic
            // error — the line never shows a stale snapshot.
            return .error(message: "Invalid reference")
        }

        let qtyByPos: [Int: Qty] = Dictionary(
            uniqueKeysWithValues: markerPos.enumerated().compactMap { k, pos in
                quantities[k].map { (pos, $0) }
            }
        )

        // Conversion shape: exactly one marker, then `to <unit>`.
        if markerPos.count == 1,
           let toWord = tokenConversionShape(line: line, markerAt: markerPos[0]),
           let q = quantities[0] {
            if let (v, unit) = convertTokenQuantity(value: q.v, fromLabel: q.unit, to: toWord, rates: rates) {
                return .number(value: roundResult(v, decimalPlaces: decimalPlaces), unit: unit)
            }
            return .error(message: "Invalid conversion")
        }

        // Assignment: `name = <token expression>`.
        if let eq = line.firstIndex(of: "="),
           line[..<eq].rangeOfCharacter(from: CharacterSet(charactersIn: String(answerTokenMarker))) == nil {
            let lhs = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let rhs = String(line[line.index(after: eq)...])
            if isValidReferenceIdentifier(lhs) {
                let eqUTF16 = (line as NSString).range(of: "=").location
                var rhsMap: [Int: Qty] = [:]
                for (pos, q) in qtyByPos where pos > eqUTF16 {
                    // Re-key markers relative to the right-hand side.
                    rhsMap[pos - eqUTF16 - 1] = q
                }
                do {
                    let q = try TokenExpr.evaluate(rhs, markerQuantities: rhsMap, vars: vars)
                    guard q.unit == nil else { return .error(message: "Units cannot be assigned") }
                    vars[lhs] = q.v
                    return .variable(name: lhs, value: roundResult(q.v, decimalPlaces: decimalPlaces))
                } catch {
                    return .error(message: "Invalid expression")
                }
            }
            return .error(message: "Invalid assignment")
        }

        // General quantity expression.
        do {
            let q = try TokenExpr.evaluate(line, markerQuantities: qtyByPos, vars: vars)
            return .number(value: roundResult(q.v, decimalPlaces: decimalPlaces), unit: q.unit)
        } catch {
            return .error(message: "Invalid expression")
        }
    }

    var out: [SheetLine] = []
    for i in 0..<lines.count {
        let result: LineResult
        if lines[i].contains(String(answerTokenMarker)) {
            result = evalTokenLine(lines[i], i, docOffsets[i])
        } else {
            result = plainLine(lines[i])
        }
        memo[i] = result
        out.append(SheetLine(sourceLineIndex: i, result: result))
    }
    let tokens = tokenStates.keys.sorted().map { TokenResolution(location: $0, state: tokenStates[$0]!) }
    return (out, tokens)
}

/// The target unit text of a `<marker> to <unit>` conversion line, or
/// nil when the line does not have exactly that shape (the marker must
/// stand at the start, followed by the `to` keyword and a non-empty
/// unit expression — the unit may be multi-word, slashed or carry
/// `·`/`²` characters; the unit catalog decides legality).
private func tokenConversionShape(line: String, markerAt: Int) -> String? {
    let ns = line as NSString
    let before = ns.substring(to: markerAt).trimmingCharacters(in: .whitespaces)
    guard before.isEmpty else { return nil }
    let after = ns.substring(from: markerAt + 1)
    let t = after.trimmingCharacters(in: .whitespaces)
    guard t.lowercased().hasPrefix("to") else { return nil }
    let rest = String(t.dropFirst(2))
    guard !rest.isEmpty, rest.first!.isWhitespace else { return nil }
    let unitText = rest.trimmingCharacters(in: .whitespaces)
    guard !unitText.isEmpty, unitText.contains(where: { $0.isLetter }) else { return nil }
    return unitText
}

private func isValidReferenceIdentifier(_ name: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: #"^[A-Za-z_]\w*$"#) else { return false }
    return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
}

// MARK: - Quantity expression parser

/// One evaluated operand of a token expression.
struct Qty: Equatable {
    var v: Double
    var unit: String?
}

/// Recursive-descent evaluator for a line containing one or more
/// reference tokens. Plain runs (numbers, variables, parentheses) are
/// evaluated with the SHARED expression parser — tokenizer, precedence
/// and variable semantics are never duplicated. Tokens participate as
/// quantities with strict unit rules:
/// - `×` / `÷`: at most one side may carry a unit (a same-unit ÷ yields
///   a unitless ratio);
/// - `+` / `−`: both sides unitless or the SAME quantity unit
///   (case-insensitive label or same measurement dimension);
/// - every other combination is a hidden generic error.
/// Non-finite intermediates are rejected like everywhere else.
enum TokenExpr {
    enum ExprError: Error {
        case invalid
        case incompatibleUnits
        case divisionByZero
    }

    static func evaluate(_ line: String,
                         markerQuantities: [Int: Qty],
                         vars: [String: Double]) throws -> Qty {
        let ns = line as NSString
        var i = 0

        func skipWS() {
            while i < ns.length {
                let c = ns.character(at: i)
                if c == 0x20 || c == 0x09 { i += 1 } else { break }
            }
        }
        func nextChar() -> UInt16? {
            skipWS()
            return i < ns.length ? ns.character(at: i) : nil
        }

        func parseAdditive() throws -> Qty {
            var left = try parseMultiplicative()
            while let c = nextChar() {
                if c == 0x2B {
                    i += 1
                    let r = try parseMultiplicative()
                    left = try combine(left, r, "+")
                } else if c == 0x2D {
                    i += 1
                    let r = try parseMultiplicative()
                    left = try combine(left, r, "-")
                } else {
                    break
                }
            }
            return left
        }

        func parseMultiplicative() throws -> Qty {
            var left = try parsePrimary()
            while let c = nextChar() {
                if c == 0x00D7 || c == 0x2A { // × and *
                    i += 1
                    let r = try parsePrimary()
                    left = try combine(left, r, "*")
                } else if c == 0x2F || c == 0x00F7 { // / and ÷
                    i += 1
                    let r = try parsePrimary()
                    left = try combine(left, r, "/")
                } else {
                    break
                }
            }
            return left
        }

        func parsePrimary() throws -> Qty {
            // Unary sign applies to a token or a plain operand alike.
            if let c = nextChar(), c == 0x2B || c == 0x2D {
                let sign: Double = (c == 0x2B) ? 1 : -1
                i += 1
                let v = try parsePrimary()
                let r = v.v * sign
                guard r.isFinite else { throw ExprError.incompatibleUnits }
                return Qty(v: r, unit: v.unit)
            }
            // A reference token.
            skipWS()
            if i < ns.length, ns.character(at: i) == answerTokenMarkerUTF16 {
                let pos = i
                i += 1
                guard let q = markerQuantities[pos] else { throw ExprError.invalid }
                return q
            }
            guard let c = nextChar() else { throw ExprError.invalid }
            if c == 0x28 { // '('
                i += 1
                let v = try parseAdditive()
                guard let closing = nextChar(), closing == 0x29 else { throw ExprError.invalid }
                i += 1
                return v
            }
            if isDigit16(c) || c == 0x2E {
                var j = i
                while j < ns.length,
                      isDigit16(ns.character(at: j)) || ns.character(at: j) == 0x2E {
                    j += 1
                }
                let numStr = ns.substring(with: NSRange(location: i, length: j - i))
                i = j
                guard let n = Double(numStr), n.isFinite else { throw ExprError.invalid }
                var v = n
                while let pct = nextChar(), pct == 0x25 {
                    i += 1
                    v /= 100
                }
                guard v.isFinite else { throw ExprError.incompatibleUnits }
                return Qty(v: v, unit: nil)
            }
            if isLetter16(c) || c == 0x5F {
                var j = i
                while j < ns.length,
                      isLetter16(ns.character(at: j)) || isDigit16(ns.character(at: j))
                      || ns.character(at: j) == 0x5F {
                    j += 1
                }
                let word = ns.substring(with: NSRange(location: i, length: j - i))
                i = j
                guard let val = vars[word], val.isFinite else { throw ExprError.invalid }
                var v = val
                while let pct = nextChar(), pct == 0x25 {
                    i += 1
                    v /= 100
                }
                return Qty(v: v, unit: nil)
            }
            throw ExprError.invalid
        }

        func combine(_ a: Qty, _ b: Qty, _ op: String) throws -> Qty {
            switch op {
            case "+", "-":
                if a.unit == nil && b.unit == nil {
                    let v = (op == "+") ? a.v + b.v : a.v - b.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return Qty(v: v, unit: nil)
                }
                guard let ua = a.unit, let ub = b.unit, sameQuantityUnit(ua, ub) else {
                    throw ExprError.incompatibleUnits
                }
                guard let vb = convertQuantityUnit(b.v, fromLabel: ub, toLabel: ua) else {
                    throw ExprError.incompatibleUnits
                }
                let v = (op == "+") ? a.v + vb : a.v - vb
                guard v.isFinite else { throw ExprError.incompatibleUnits }
                return Qty(v: v, unit: ua)
            case "*":
                if a.unit == nil && b.unit == nil {
                    let v = a.v * b.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return Qty(v: v, unit: nil)
                }
                if let ua = a.unit, b.unit == nil {
                    let v = a.v * b.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return Qty(v: v, unit: ua)
                }
                if a.unit == nil, let ub = b.unit {
                    let v = a.v * b.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return Qty(v: v, unit: ub)
                }
                throw ExprError.incompatibleUnits
            case "/":
                if a.unit == nil && b.unit == nil {
                    guard b.v != 0 else { throw ExprError.divisionByZero }
                    let v = a.v / b.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return Qty(v: v, unit: nil)
                }
                if let ua = a.unit, b.unit == nil {
                    guard b.v != 0 else { throw ExprError.divisionByZero }
                    let v = a.v / b.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return Qty(v: v, unit: ua)
                }
                if a.unit == nil, b.unit != nil {
                    // A unitless scalar over a quantity is not a safe
                    // inverse here: hidden generic error.
                    throw ExprError.incompatibleUnits
                }
                if let ua = a.unit, let ub = b.unit, sameQuantityUnit(ua, ub) {
                    // Same-unit ratio: unitless.
                    guard let bb = convertQuantityUnit(b.v, fromLabel: ub, toLabel: ua), bb != 0 else {
                        throw ExprError.divisionByZero
                    }
                    let v = a.v / bb
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return Qty(v: v, unit: nil)
                }
                throw ExprError.incompatibleUnits
            default:
                throw ExprError.invalid
            }
        }

        let result = try parseAdditive()
        skipWS()
        guard i == ns.length else { throw ExprError.invalid }
        return result
    }

    private static func isDigit16(_ c: UInt16) -> Bool {
        (0x30...0x39).contains(c)
    }
    private static func isLetter16(_ c: UInt16) -> Bool {
        (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
    }
}
