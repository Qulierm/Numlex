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
    resolveSheet(content: content, lineIDs: lineIDs, references: references,
                 rates: rates, decimalPlaces: decimalPlaces,
                 now: Date(), calendar: Calendar.current)
}

/// Reference-aware sheet evaluation with ONE captured date context per
/// sheet (`today`/implicit years stay consistent across the sheet).
public func resolveSheet(
    content: String,
    lineIDs: [UUID],
    references: [AnswerReference],
    rates: Rates,
    decimalPlaces: Int,
    now: Date,
    calendar: Calendar
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

    // ONE shared typed environment for the whole sheet: named values
    // (unitless AND money) declared above a token line are visible to
    // it, exactly like in `evaluateSheet`.
    var env = TypedEnv()
    var memo: [Int: LineResult] = [:]
    var tokenStates: [Int: TokenResolution.State] = [:]

    /// Scalar view of the environment for the legacy `[String: Double]`
    /// expression plumbing: unitless names under their display name,
    /// money names by their raw value (a money name used as a plain
    /// operand keeps the surrounding quantity's unit).
    func varsAll() -> [String: Double] {
        var d: [String: Double] = [:]
        for e in env.entries {
            switch e.qty {
            case .scalar(let v) where v.isFinite: d[e.display] = v
            case .money(let v, _) where v.isFinite: d[e.display] = v
            default: break
            }
        }
        return d
    }

    func plainLine(_ line: String) -> LineResult {
        // Exactly the line-kind handling `evaluateSheet` uses.
        if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") {
            return .blank
        }
        if line.hasPrefix("// ") {
            return .title(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        }
        if line.hasPrefix("//") { return .blank }
        if let eval = evalLineTyped(line, env: &env, rates: rates, decimalPlaces: decimalPlaces,
                                    now: now, calendar: calendar) {
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
                // The shared quantity display: currency units render
                // through the money presentation (`$600.00`), every
                // other unit keeps `<value> <unit>`.
                let display = formatQuantity(v, unit: u, decimalPlaces: decimalPlaces)
                tokenStates[docPos] = .active(value: v, unit: u, display: display)
                quantities.append(Qty(v: v, unit: u))
            case .money(let v, let code) where v.isFinite:
                // A money source is a live quantity carrying the ISO
                // code — tokenizable and convertible (`<token> in EUR`).
                let display = formatMoney(v, code: code)
                tokenStates[docPos] = .active(value: v, unit: code, display: display)
                quantities.append(Qty(v: v, unit: code))
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

        // Conversion shape: exactly one marker, then `to <unit>` or
        // `in <unit>` (identical semantics).
        if markerPos.count == 1,
           let toWord = tokenConversionShape(line: line, markerAt: markerPos[0]),
           let q = quantities[0] {
            if let (v, unit) = convertTokenQuantity(value: q.v, fromLabel: q.unit, to: toWord, rates: rates) {
                return .number(value: roundResult(v, decimalPlaces: decimalPlaces), unit: unit)
            }
            // A currency pair the rate table cannot answer keeps the
            // explicit white `Rates unavailable` state.
            let targetIsCurrency = UnitCatalog.resolveExpression(toWord).map { p in
                if case .currency = p.unit.kind { return true } else { return false }
            } ?? false
            let fromIsCurrency = q.unit.flatMap { unitExpr(byLabel: $0).map { p in
                if case .currency = p.kind { return true } else { return false }
            } } ?? false
            if fromIsCurrency, targetIsCurrency {
                return .error(message: "Rates unavailable")
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
                    let q = try TokenExpr.evaluate(rhs, markerQuantities: rhsMap, vars: varsAll())
                    guard q.unit == nil else { return .error(message: "Units cannot be assigned") }
                    env.set(display: lhs, qty: .scalar(q.v))
                    return .variable(name: lhs, value: roundResult(q.v, decimalPlaces: decimalPlaces))
                } catch {
                    return .error(message: "Invalid expression")
                }
            }
            return .error(message: "Invalid assignment")
        }

        // General quantity expression. Money-context lines (a currency
        // marker, or token quantities carrying currency units) mask the
        // bounded neutral prose FIRST — range-preserving, so every
        // U+FFFC marker stays at its original offset; any other
        // surviving word is a hidden generic error, never a numeric
        // fallback.
        let tokenUnits = quantities.compactMap { $0?.unit }
        let moneyCtx = NaturalCalculation.isMoneyContext(line: line, tokenUnits: tokenUnits)
        let exprLine: String
        if moneyCtx, let stripped = NaturalCalculation.stripTokenProse(
            line: line, variables: varsAll(), moneyContext: true) {
            exprLine = stripped
        } else if moneyCtx {
            return .error(message: "Invalid expression")
        } else {
            exprLine = line
        }
        do {
            let q = try TokenExpr.evaluate(exprLine, markerQuantities: qtyByPos, vars: varsAll())
            // Currency units are carried as the quantity's unit label:
            // the shared `formatQuantity` renders them through
            // `formatMoney` (`$920.00`), exactly like a bare money
            // token — one result shape for every token quantity.
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

/// The target unit text of a `<marker> to|in <unit>` conversion line,
/// or nil when the line does not have exactly that shape (the marker
/// must stand at the start, followed by the `to` or `in` keyword and a
/// non-empty unit expression — the unit may be multi-word, slashed or
/// carry `·`/`²` characters; the unit catalog decides legality).
private func tokenConversionShape(line: String, markerAt: Int) -> String? {
    let ns = line as NSString
    let before = ns.substring(to: markerAt).trimmingCharacters(in: .whitespaces)
    guard before.isEmpty else { return nil }
    let after = ns.substring(from: markerAt + 1)
    let t = after.trimmingCharacters(in: .whitespaces)
    let lower = t.lowercased()
    guard lower.hasPrefix("to") || lower.hasPrefix("in") else { return nil }
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

        // A quantity plus its contextual-percentage flag: only a
        // postfix `p%` is a pure percentage (a fraction of the base in
        // additive/subtractive context); anything combined is scalar.
        struct PE: Equatable {
            var q: Qty
            var purePercent: Bool
        }

        func parseAdditive() throws -> PE {
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

        func parseMultiplicative() throws -> PE {
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

        func parsePrimary() throws -> PE {
            // Unary sign applies to a token or a plain operand alike.
            if let c = nextChar(), c == 0x2B || c == 0x2D {
                let sign: Double = (c == 0x2B) ? 1 : -1
                i += 1
                let v = try parsePrimary()
                let r = v.q.v * sign
                guard r.isFinite else { throw ExprError.incompatibleUnits }
                return PE(q: Qty(v: r, unit: v.q.unit), purePercent: false)
            }
            // A reference token.
            skipWS()
            if i < ns.length, ns.character(at: i) == answerTokenMarkerUTF16 {
                let pos = i
                i += 1
                guard let q = markerQuantities[pos] else { throw ExprError.invalid }
                return PE(q: q, purePercent: false)
            }
            guard let c = nextChar() else { throw ExprError.invalid }
            if c == 0x28 { // '('
                i += 1
                let v = try parseAdditive()
                guard let closing = nextChar(), closing == 0x29 else { throw ExprError.invalid }
                i += 1
                return v
            }
            // A currency literal: a marker (bare `$`/`€`/`£`/`¥`/`₽` or
            // letter-prefixed `CA$`/`NZ$`/`HK$`/`A$`/`S$`) glued in FRONT
            // of the amount — the same shared marker/amount grammar the
            // money pipeline uses.
            if prefixMarkerStarts(at: i) {
                let code = try parsePrefixMarker()
                let value = try parseAmount()
                return PE(q: Qty(v: value, unit: code), purePercent: false)
            }
            if isDigit16(c) || c == 0x2E {
                let n = try parseAmount()
                var v = n
                var pct = 0
                while let p = nextChar(), p == 0x25 {
                    i += 1
                    v /= 100
                    pct += 1
                }
                guard v.isFinite else { throw ExprError.incompatibleUnits }
                // Postfix marker: `240$`, `2.5k$` — a symbol glued right
                // after the amount (no digit after it, `45$5` is not a
                // marker) carries the currency unit.
                if pct == 0, let code = parsePostfixMarker() {
                    return PE(q: Qty(v: v, unit: code), purePercent: false)
                }
                return PE(q: Qty(v: v, unit: nil), purePercent: pct > 0)
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
                var pct = 0
                while let p = nextChar(), p == 0x25 {
                    i += 1
                    v /= 100
                    pct += 1
                }
                return PE(q: Qty(v: v, unit: nil), purePercent: pct > 0)
            }
            throw ExprError.invalid
        }

        /// Whether `i` starts a PREFIX currency marker: a bare symbol
        /// (`$` `€` `£` `¥` `₽`) followed by a number/decimal point, or a
        /// letter-prefixed dollar (`CA$`, `NZ$`, `HK$`, `A$`, `S$`) with
        /// the symbol followed by a number/decimal point.
        func prefixMarkerStarts(at idx: Int) -> Bool {
            let c = ns.character(at: idx)
            func numAfter(_ p: Int) -> Bool {
                guard p < ns.length else { return false }
                let d = ns.character(at: p)
                return (0x30...0x39).contains(d) || d == 0x2E
            }
            if c == 0x24 || c == 0x20AC || c == 0x00A3 || c == 0x00A5 || c == 0x20BD {
                return numAfter(idx + 1)
            }
            if isLetter16(c) {
                var j = idx
                while j < ns.length, isLetter16(ns.character(at: j)) { j += 1 }
                return j > idx && j < ns.length
                    && ns.character(at: j) == 0x24 && numAfter(j + 1)
            }
            return false
        }

        /// Consumes a prefix marker at `i` and returns its ISO code.
        /// Throws when the shape is not a real marker.
        func parsePrefixMarker() throws -> String {
            let c = ns.character(at: i)
            let marker: String
            if isLetter16(c) {
                var j = i
                while j < ns.length, isLetter16(ns.character(at: j)) { j += 1 }
                guard j < ns.length, j > i, ns.character(at: j) == 0x24 else {
                    throw ExprError.invalid
                }
                marker = ns.substring(with: NSRange(location: i, length: j - i + 1))
                i = j + 1
            } else {
                marker = String(utf16CodeUnits: [c], count: 1)
                i += 1
            }
            guard let code = CurrencyPresentation.code(forMarker: marker) else {
                throw ExprError.invalid
            }
            return code
        }

        /// Postfix marker at `i`: a bare symbol glued right after an
        /// amount (a digit after the symbol is NOT a marker).
        func parsePostfixMarker() -> String? {
            guard i < ns.length else { return nil }
            let c = ns.character(at: i)
            guard c == 0x24 || c == 0x20AC || c == 0x00A3 || c == 0x00A5 || c == 0x20BD
            else { return nil }
            let after = i + 1 < ns.length ? ns.character(at: i + 1) : 0
            guard !(0x30...0x39).contains(after) else { return nil }
            let code = CurrencyPresentation.code(forMarker: String(utf16CodeUnits: [c], count: 1))
            i += 1
            return code
        }

        /// One amount literal: digits with optional GROUPING commas and
        /// at most one decimal point, plus the shared compact suffixes
        /// (`k`/`K` ×1000, `m`/`M` ×1,000,000). Advances `i`.
        func parseAmount() throws -> Double {
            let start = i
            var j = i
            var hasDot = false
            while j < ns.length {
                let c = ns.character(at: j)
                if isDigit16(c) {
                    j += 1
                } else if c == 0x2E {
                    if hasDot { break }
                    hasDot = true
                    j += 1
                } else if c == 0x2C, j + 1 < ns.length, isDigit16(ns.character(at: j + 1)) {
                    j += 1
                } else {
                    break
                }
            }
            guard j > start else { throw ExprError.invalid }
            var text = ns.substring(with: NSRange(location: start, length: j - start))
            text = text.replacingOccurrences(of: ",", with: "")
            guard let n = Double(text), n.isFinite else { throw ExprError.invalid }
            i = j
            // Compact magnitude suffix (k/m/M), standalone word only.
            if j < ns.length {
                let sfx = ns.character(at: j)
                let mult: Double?
                if sfx == 0x6B || sfx == 0x4B { mult = 1_000 }
                else if sfx == 0x6D || sfx == 0x4D { mult = 1_000_000 }
                else { mult = nil }
                if let mult,
                   j + 1 >= ns.length
                       || !(isLetter16(ns.character(at: j + 1)) || isDigit16(ns.character(at: j + 1))) {
                    i = j + 1
                    let v = n * mult
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return v
                }
            }
            return n
        }

        func combine(_ a: PE, _ b: PE, _ op: String) throws -> PE {
            let aq = a.q
            let bq = b.q
            switch op {
            case "+", "-":
                if b.purePercent {
                    // Contextual percent: `base ± base×p/100` — the
                    // base is the accumulated left quantity (unit kept,
                    // so a money token plus `10% tip` stays money).
                    let v = (op == "+")
                        ? aq.v + aq.v * bq.v
                        : aq.v - aq.v * bq.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return PE(q: Qty(v: v, unit: aq.unit), purePercent: false)
                }
                if aq.unit == nil && bq.unit == nil {
                    let v = (op == "+") ? aq.v + bq.v : aq.v - bq.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return PE(q: Qty(v: v, unit: nil), purePercent: false)
                }
                guard let ua = aq.unit, let ub = bq.unit, sameQuantityUnit(ua, ub) else {
                    throw ExprError.incompatibleUnits
                }
                guard let vb = convertQuantityUnit(bq.v, fromLabel: ub, toLabel: ua) else {
                    throw ExprError.incompatibleUnits
                }
                let v = (op == "+") ? aq.v + vb : aq.v - vb
                guard v.isFinite else { throw ExprError.incompatibleUnits }
                return PE(q: Qty(v: v, unit: ua), purePercent: false)
            case "*":
                if aq.unit == nil && bq.unit == nil {
                    let v = aq.v * bq.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return PE(q: Qty(v: v, unit: nil), purePercent: false)
                }
                if let ua = aq.unit, bq.unit == nil {
                    let v = aq.v * bq.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return PE(q: Qty(v: v, unit: ua), purePercent: false)
                }
                if aq.unit == nil, let ub = bq.unit {
                    let v = aq.v * bq.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return PE(q: Qty(v: v, unit: ub), purePercent: false)
                }
                throw ExprError.incompatibleUnits
            case "/":
                if aq.unit == nil && bq.unit == nil {
                    guard bq.v != 0 else { throw ExprError.divisionByZero }
                    let v = aq.v / bq.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return PE(q: Qty(v: v, unit: nil), purePercent: false)
                }
                if let ua = aq.unit, bq.unit == nil {
                    guard bq.v != 0 else { throw ExprError.divisionByZero }
                    let v = aq.v / bq.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return PE(q: Qty(v: v, unit: ua), purePercent: false)
                }
                if aq.unit == nil, bq.unit != nil {
                    // A unitless scalar over a quantity is not a safe
                    // inverse here: hidden generic error.
                    throw ExprError.incompatibleUnits
                }
                if let ua = aq.unit, let ub = bq.unit, sameQuantityUnit(ua, ub) {
                    // Same-unit ratio: unitless.
                    guard let bb = convertQuantityUnit(bq.v, fromLabel: ub, toLabel: ua), bb != 0 else {
                        throw ExprError.divisionByZero
                    }
                    let v = aq.v / bb
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return PE(q: Qty(v: v, unit: nil), purePercent: false)
                }
                throw ExprError.incompatibleUnits
            default:
                throw ExprError.invalid
            }
        }

        let result = try parseAdditive()
        skipWS()
        guard i == ns.length else { throw ExprError.invalid }
        return result.q
    }

    private static func isDigit16(_ c: UInt16) -> Bool {
        (0x30...0x39).contains(c)
    }
    private static func isLetter16(_ c: UInt16) -> Bool {
        (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
    }
}
