import Foundation

/// The per-marker evaluation state reported for editor rendering and
/// clipboard text. The display is ALWAYS derived from the current source
/// line result — no snapshot is ever stored.
public struct TokenResolution: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// The source line currently evaluates to a finite number or a
        /// variable: the token is active and shows the full quantity.
        case active(value: Double, unit: String?, display: String)
        /// r83: an active token whose answer carries a SEMANTIC kind —
        /// a percent (`20%`), a fraction (`1/5`) or a multiplier
        /// (`1.5x`). The display is the kinded string and the kind
        /// rides along so expressions treat the token contextually
        /// (`200 + TOKEN` reads the percent like the `200 + 20%`
        /// literal) and copies stay kinded.
        case activeKinded(value: Double, unit: String?, kind: NumericKind,
                          fraction: Rational?, display: String)
        /// r82: the source line evaluates to a boolean — a DISTINCT
        /// resolution (never a 0/1 Double): the capsule shows the
        /// lowercase word and the token joins logical expressions.
        case activeBool(value: Bool, display: String)
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
    decimalPlaces: Int,
    constants: [UserConstant] = [],
    weather: WeatherContext = .empty,
    context: NumberFormatContext = .legacy,
    unitContext: UnitContext = .builtIns
) -> (lines: [SheetLine], tokens: [TokenResolution]) {
    resolveSheet(content: content, lineIDs: lineIDs, references: references,
                 rates: rates, decimalPlaces: decimalPlaces,
                 now: Date(), calendar: Calendar.current,
                 constants: constants, weather: weather, context: context,
                 unitContext: unitContext)
}

/// Reference-aware sheet evaluation with ONE captured date context per
/// sheet (`today`/implicit years stay consistent across the sheet) and,
/// when given, the GLOBAL user constants (r33) available before line 1
/// on every path — normal lines, reference-token lines and their
/// expression algebra alike.
public func resolveSheet(
    content: String,
    lineIDs: [UUID],
    references: [AnswerReference],
    rates: Rates,
    decimalPlaces: Int,
    now: Date,
    calendar: Calendar,
    constants: [UserConstant] = [],
    weather: WeatherContext = .empty,
    context: NumberFormatContext = .legacy,
    unitContext: UnitContext = .builtIns
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
    // it, exactly like in `evaluateSheet`. r33: global constants are
    // seeded first and are IMMUTABLE on every assignment route.
    var env = TypedEnv()
    env.seedConstants(constants)
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
            case .scalar(let v, _, _) where v.isFinite: d[e.display] = v
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
                                    now: now, calendar: calendar, weather: weather,
                                    context: context, unitContext: unitContext) {
            return eval
        }
        return .skip
    }

    func evalTokenLine(_ line: String, _ index: Int, _ docStart: Int) -> LineResult {
        // r33: constant-assignment guard on the token route too — the
        // token lines bypass `evalLineTyped` entirely.
        // r82: the shared `=` recognizer (comparison operators never
        // enter the assignment route).
        if let split = BooleanLogic.assignmentSplit(line) {
            let lhs = split.lhs.trimmingCharacters(in: .whitespaces)
            if env.isConstant(display: lhs) {
                return .error(message: "Cannot assign to constant")
            }
        }
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
            case .number(let v, let u, let kind, let fraction) where v.isFinite:
                // The shared quantity display: currency units render
                // through the money presentation (`$600.00`), every
                // other unit keeps `<value> <unit>`. r83: a SEMANTIC
                // kind rides along with its kinded display (`20%`,
                // `1/5`, `1.5x`).
                if kind != .plain {
                    let display = AnswerDisplay.formatKinded(v, unit: u,
                                                              kind: kind, fraction: fraction,
                                                              decimalPlaces: decimalPlaces,
                                                              context: context)
                    tokenStates[docPos] = .activeKinded(value: v, unit: u, kind: kind,
                                                        fraction: fraction, display: display)
                } else {
                    let display = formatQuantity(v, unit: u, decimalPlaces: decimalPlaces,
                                                          context: context)
                    tokenStates[docPos] = .active(value: v, unit: u, display: display)
                }
                quantities.append(Qty(v: v, unit: u, kind: kind, fraction: fraction))
            case .money(let v, let code) where v.isFinite:
                // A money source is a live quantity carrying the ISO
                // code — tokenizable and convertible (`<token> in EUR`).
                let display = formatMoney(v, code: code, context: context)
                tokenStates[docPos] = .active(value: v, unit: code, display: display)
                quantities.append(Qty(v: v, unit: code))
            case .variable(_, let v, _, _) where v.isFinite:
                // A variable source is a unitless quantity.
                let display = formatDisplayValue(v, decimalPlaces: decimalPlaces,
                                                  context: context)
                tokenStates[docPos] = .active(value: v, unit: nil, display: display)
                quantities.append(Qty(v: v, unit: nil))
            case .boolean(let b):
                // r82: a boolean source is a live BOOLEAN token — a
                // distinct resolution that shows the lowercase word
                // and feeds the typed boolean engine, never a 0/1.
                let display = b ? "true" : "false"
                tokenStates[docPos] = .activeBool(value: b, display: display)
                quantities.append(Qty(v: 0, unit: nil, boolValue: b))
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
                // r82: a bare boolean token shows its lowercase word
                // as a real boolean answer (copyable, tokenizable,
                // never numeric).
                if let b = q.boolValue {
                    return .boolean(value: b)
                }
                // r83: a percent/fraction/multiplier token answers
                // with its semantic kind (displayed `20%`, `1/5`,
                // `1.5x`), never as a plain 0.2/0.2/1.5.
                if q.kind != .plain || q.fraction != nil {
                    return .number(value: roundResult(q.v, decimalPlaces: decimalPlaces),
                                   unit: q.unit, kind: q.kind, fraction: q.fraction)
                }
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

        // r83: a percentage phrase with a marker standing in an
        // operand (`TOKEN is what % of 200`, `15% of TOKEN`,
        // `TOKEN as fraction`). Markers become word placeholders so
        // the grammar sees them as named operands; the token's OWN
        // kind (percent/multiplier/fraction) decides the percent-ish
        // gates, exactly like a named value. A gate failure (a plain
        // token in a percent slot) falls through to the routes below,
        // which read the line exactly as before.
        var subLine = line
        for (k, pos) in markerPos.enumerated().reversed() {
            subLine = (subLine as NSString)
                .replacingCharacters(in: NSRange(location: pos, length: 1),
                                     with: "r83tok\(k)")
        }
        if let m = PercentageGrammar.match(line: subLine, env: env) {
            var ops: [PercentageGrammar.OperandValue] = []
            var failed = false
            for p in m.operandPieces {
                if p.isWord, let w = p.word(), w.hasPrefix("r83tok"),
                   let k = Int(w.dropFirst("r83tok".count)) {
                    guard let q = quantities[k] else { failed = true; break }
                    let currency = q.unit.flatMap { isCurrencyCode($0) ? $0 : nil }
                    ops.append(PercentageGrammar.OperandValue(
                        value: q.v, kind: q.kind,
                        shape: shapeForTokenKind(q.kind),
                        currency: currency, fraction: q.fraction))
                } else {
                    let named: String? = p.isWord ? p.text : nil
                    guard let v = PercentageGrammar.operandValue(
                            p.text, named: named, env: env, context: context) else {
                        failed = true
                        break
                    }
                    ops.append(v)
                }
            }
            if failed {
                return .error(message: "Invalid reference")
            }
            if let r = m.form.eval(ops) {
                switch r {
                case .number(let v, let u, let k, let f):
                    guard v.isFinite else { return .error(message: "Invalid expression") }
                    return .number(value: roundResult(v, decimalPlaces: decimalPlaces),
                                   unit: u, kind: k, fraction: f)
                case .money(let v, let c):
                    return .money(value: roundResult(v, decimalPlaces: decimalPlaces), code: c)
                default:
                    break
                }
            }
            // A matched form whose gate failed: fall through — the
            // routes below read the line exactly as they always did.
        } else {
            // A DANGLING phrase (missing value operand) fails safely
            // instead of degrading to the token-expression routes.
            let pcs = PercentageGrammar.pieces(of: subLine) ?? []
            let dangling = PercentageGrammar.forms(env: env).contains {
                if case .dangling = PercentageGrammar.matchResult(form: $0, pcs: pcs, env: env) {
                    return true
                }
                return false
            }
            if dangling {
                return .error(message: "Invalid expression")
            }
        }

        // Conversion shape: exactly one marker, then `to <unit>` or
        // `in <unit>` (identical semantics).
        if markerPos.count == 1,
           let toWord = tokenConversionShape(line: line, markerAt: markerPos[0]),
           let q = quantities[0] {
            if let (v, unit) = convertTokenQuantity(value: q.v, fromLabel: q.unit, to: toWord, rates: rates, context: unitContext) {
                return .number(value: roundResult(v, decimalPlaces: decimalPlaces), unit: unit)
            }
            // A currency pair the rate table cannot answer keeps the
            // explicit white `Rates unavailable` state.
            let targetIsCurrency = unitContext.resolveExpression(toWord).map { p in
                if case .currency = p.unit.kind { return true } else { return false }
            } ?? false
            let fromIsCurrency = q.unit.flatMap { unitExpr(byLabel: $0, context: unitContext).map { p in
                if case .currency = p.kind { return true } else { return false }
            } } ?? false
            if fromIsCurrency, targetIsCurrency {
                return .error(message: "Rates unavailable")
            }
            return .error(message: "Invalid conversion")
        }

        // Assignment: `name = <token expression>`.
        if let split = BooleanLogic.assignmentSplit(line),
           split.lhs.rangeOfCharacter(from: CharacterSet(charactersIn: String(answerTokenMarker))) == nil {
            let lhs = split.lhs.trimmingCharacters(in: .whitespaces)
            let rhs = split.rhs
            if isValidReferenceIdentifier(lhs) {
                // r33: token-expression assignment to an active global
                // constant is blocked exactly like the other routes.
                if env.isConstant(display: lhs) {
                    return .error(message: "Cannot assign to constant")
                }
                // r82: the assignment `=` position is exactly the
                // (untrimmed) LHS length — never a comparison `==`.
                let eqUTF16 = (split.lhs as NSString).length
                let rhsQuantities: [Qty] = qtyByPos
                    .filter { $0.key > eqUTF16 }
                    .sorted(by: { $0.key < $1.key })
                    .map { $0.value }
                // r47: a UNITLESS function/power right-hand side goes
                // through the ONE shared strict engine (markers become
                // collision-proof placeholders) — `x = sqrt(<M>)`,
                // `x = sum(<M>, <M>, 2)`, `x = <M> ^ 2`. The env is
                // updated ONLY on success; unit-bearing or money
                // arguments fail safely (no implicit stripping).
                let rhsAllUnitless = !rhsQuantities.isEmpty
                    && rhsQuantities.allSatisfy { $0.unit == nil }
                // r82: a BOOLEAN right-hand side (explicit boolean
                // syntax, a logical word, or a boolean token) goes
                // through the ONE shared typed engine — placeholders
                // carry their real types, so arithmetic on a boolean
                // token fails strictly and a money token can never
                // coerce. The name is recorded as a real boolean.
                if BooleanLogic.isBoolLikely(rhs, env: env)
                        || rhsQuantities.contains(where: { $0.boolValue != nil }) {
                    var tvars: [String: TypedScalar] = [:]
                    for e in env.entries {
                        switch e.qty {
                        case .scalar(let v, _, _) where v.isFinite: tvars[e.display] = .number(v)
                        case .bool(let b): tvars[e.display] = .bool(b)
                        default: break
                        }
                    }
                    for (k, q) in rhsQuantities.enumerated() {
                        if let b = q.boolValue { tvars[namePlaceholder(k)] = .bool(b) }
                        else if q.unit == nil, q.v.isFinite { tvars[namePlaceholder(k)] = .number(q.v) }
                        // Unit/money tokens stay absent: they fail
                        // safely in a boolean context.
                    }
                    if let r = try? typedBoolResult(
                            text: rhs,
                            variables: tvars,
                            decimalPlaces: decimalPlaces,
                            context: context) {
                        switch r {
                        case .boolean(let b):
                            env.set(display: lhs, qty: .bool(b))
                            return .boolean(value: b)
                        case .number(let v, nil, let kind, let fraction):
                            // A conditional value branch may pick a
                            // scalar: record it like any assignment
                            // (r83: with its semantic kind).
                            env.set(display: lhs, qty: .scalar(v))
                            return .variable(name: lhs, value: v)
                        default:
                            break
                        }
                    }
                    return .error(message: "Invalid expression")
                }
                if rhsAllUnitless,
                   FunctionCalls.hasCallHead(rhs) || rhs.contains("^") {
                    let exprRhs = replacingTokenMarkers(rhs)
                    var extra: [String: Double] = [:]
                    for (k, q) in rhsQuantities.enumerated() where q.v.isFinite {
                        extra[namePlaceholder(k)] = q.v
                    }
                    if let (v, codes) = strictExprCore(exprRhs, env: env, extraVars: extra),
                       codes.isEmpty, v.isFinite {
                        env.set(display: lhs, qty: .scalar(v))
                        return .variable(name: lhs, value: roundResult(v, decimalPlaces: decimalPlaces))
                    }
                    return .error(message: "Invalid expression")
                }
                var rhsMap: [Int: Qty] = [:]
                for (pos, q) in qtyByPos where pos > eqUTF16 {
                    // Re-key markers relative to the right-hand side.
                    rhsMap[pos - eqUTF16 - 1] = q
                }
                do {
                    let q = try TokenExpr.evaluate(rhs, markerQuantities: rhsMap, vars: varsAll(),
                                             context: context, unitContext: unitContext)
                    guard q.unit == nil else { return .error(message: "Units cannot be assigned") }
                    env.set(display: lhs, qty: .scalar(q.v))
                    return .variable(name: lhs, value: roundResult(q.v, decimalPlaces: decimalPlaces))
                } catch {
                    return .error(message: "Invalid expression")
                }
            }
            return .error(message: "Invalid assignment")
        }

        // r47: UNITLESS function/power token lines route through the
        // ONE shared strict engine (markers become collision-proof
        // placeholders — parser semantics are never duplicated in
        // TokenExpr): `sqrt(<M>)`, `sum(<M>, <M>, 2)`, `round(<M>/3, 2)`,
        // `<M> ^ 2`, nested with numbers, variables and constants. Each
        // marker keeps its own identity/location/state (the states were
        // already resolved above). A unit-bearing or currency-token
        // argument to any function or power fails safely below in the
        // quantity parser; unitless lines WITHOUT a call shape or `^`
        // keep the legacy route byte-for-byte.
        let allUnitless = quantities.allSatisfy { q in
            q.map { $0.unit == nil } ?? false
        }
        // r82: a BOOLEAN-shaped token line — explicit comparison/logical
        // syntax, a logical word, or a boolean token anywhere — routes
        // through the ONE shared typed engine: placeholders carry their
        // real types, so `and`/`or`/`not`/comparisons/if-then-else
        // evaluate strictly, arithmetic on a boolean token fails
        // deterministically, and unit/money tokens can never coerce
        // into a boolean context. Non-boolean token lines keep the
        // legacy routes byte-for-byte.
        let hasBoolToken = quantities.contains { $0?.boolValue != nil }
        if BooleanLogic.isBoolLikely(line, env: env) || hasBoolToken {
            var tvars: [String: TypedScalar] = [:]
            for e in env.entries {
                switch e.qty {
                case .scalar(let v, _, _) where v.isFinite: tvars[e.display] = .number(v)
                case .bool(let b): tvars[e.display] = .bool(b)
                default: break
                }
            }
            for (k, q) in quantities.enumerated() {
                guard let q else { continue }
                if let b = q.boolValue { tvars[namePlaceholder(k)] = .bool(b) }
                else if q.unit == nil, q.v.isFinite { tvars[namePlaceholder(k)] = .number(q.v) }
            }
            if let r = try? typedBoolResult(
                    text: line,
                    variables: tvars,
                    decimalPlaces: decimalPlaces,
                    context: context) {
                return r
            }
            return .error(message: "Invalid expression")
        }
        if allUnitless,
           NaturalCalculation.markerOccurrences(in: line).isEmpty,
           FunctionCalls.hasCallHead(line) || line.contains("^") {
            let exprLine = replacingTokenMarkers(line)
            var extra: [String: Double] = [:]
            for (k, q) in quantities.enumerated() {
                if let q, q.v.isFinite { extra[namePlaceholder(k)] = q.v }
            }
            if let (v, codes) = strictExprCore(exprLine, env: env, extraVars: extra),
               codes.isEmpty, v.isFinite {
                return .number(value: roundResult(v, decimalPlaces: decimalPlaces), unit: nil)
            }
            return .error(message: "Invalid expression")
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
            let q = try TokenExpr.evaluate(exprLine, markerQuantities: qtyByPos, vars: varsAll(),
                                            context: context, unitContext: unitContext)
            // Currency units are carried as the quantity's unit label:
            // the shared `formatQuantity` renders them through
            // `formatMoney` (`$920.00`), exactly like a bare money
            // token — one result shape for every token quantity.
            // r83: semantic kinds ride the result (`TOKEN + TOKEN` =
            // 40% when both are 20% tokens; `200 + TOKEN` stays a
            // plain 220 contextual sum).
            if q.kind != .plain || q.fraction != nil {
                return .number(value: roundResult(q.v, decimalPlaces: decimalPlaces),
                               unit: q.unit, kind: q.kind, fraction: q.fraction)
            }
            return .number(value: roundResult(q.v, decimalPlaces: decimalPlaces), unit: q.unit)
        } catch {
            return .error(message: "Invalid expression")
        }
    }

    // r57/r58: the same shared inline-total SECTION accumulator
    // `evaluateSheet` uses — one O(n) top-down pass. Token lines
    // resolve normally first (a token-derived scalar contributes like
    // any row of its section); a total command resolves against its
    // section, resets it, and enters the memo BEFORE later references
    // resolve, so tokens on a total stay live and forward references
    // still break. The command never mutates the environment.
    var totals = TotalAccumulator()
    var out: [SheetLine] = []
    for i in 0..<lines.count {
        let result: LineResult
        var isTotalRow = false
        if lines[i].contains(String(answerTokenMarker)) {
            result = evalTokenLine(lines[i], i, docOffsets[i])
        } else if InlineTotal.isCommand(lines[i], env: env) {
            result = totals.total(decimalPlaces: decimalPlaces)
            if case .number = result { isTotalRow = true }
        } else {
            result = plainLine(lines[i])
        }
        totals.observe(result: result, isTotalRow: isTotalRow)
        memo[i] = result
        out.append(SheetLine(sourceLineIndex: i, result: result, isTotal: isTotalRow))
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

/// r47: replaces the k-th U+FFFC marker (line order) with the
/// collision-proof placeholder `namePlaceholder(k)` so a unitless
/// token line can route through the ONE shared strict engine. Markers
/// are never rewritten in place — the sheet content, lineIDs and
/// reference geometry stay untouched; this is an evaluation-copy only.
private func replacingTokenMarkers(_ line: String) -> String {
    var out = ""
    var k = 0
    for ch in line {
        if ch == answerTokenMarker {
            out += namePlaceholder(k)
            k += 1
        } else {
            out.append(ch)
        }
    }
    return out
}

/// r82: the typed boolean route for token lines. The evaluation copy
/// swaps every marker for its collision-proof placeholder (the sheet
/// content is never rewritten), then runs the ONE shared typed engine
/// over the caller's typed table (scalar tokens -> numbers, boolean
/// tokens -> booleans, unit/money tokens absent). The result is a
/// scalar or a REAL boolean — arithmetic on a boolean token, mixed
/// equality and money coercion all throw, and the caller maps that to
/// the deterministic hidden error.
private func typedBoolResult(text: String,
                             variables: [String: TypedScalar],
                             decimalPlaces: Int,
                             context: NumberFormatContext) throws -> LineResult {
    let expr = replacingTokenMarkers(text)
    let v = try evaluateTypedExpression(expr, variables: variables, context: context)
    switch v {
    case .number(let n, let kind):
        guard n.isFinite else { throw ParseError.nonFiniteResult }
        return LineResult.number(value: roundResult(n, decimalPlaces: decimalPlaces),
                                 unit: nil, kind: kind, fraction: nil)
    case .bool(let b):
        return .boolean(value: b)
    }
}

// MARK: - Quantity expression parser

/// One evaluated operand of a token expression.
struct Qty: Equatable {
    var v: Double
    var unit: String?
    /// r83: the semantic kind of the quantity. A percent-kind token
    /// is CONTEXTUAL in additive expressions (exactly like a `p%`
    /// literal: `200 + TOKEN` = 220 when TOKEN = 20%); multiplier and
    /// fraction kinds ride along for their kinded displays.
    var kind: NumericKind = .plain
    /// r83: the reduced rational of a fraction-kind quantity.
    var fraction: Rational? = nil
    /// r82: non-nil when the token is a BOOLEAN quantity — `v` is
    /// unused (0) and the token can never join unit algebra; it
    /// participates only in the typed boolean engine.
    var boolValue: Bool? = nil
}

/// r83: the grammar shape of a token quantity's kind — a percent-kind
/// token is a percent-ish magnitude in the phrase gates (`TOKEN of
/// 200` works for a 20% token), a fraction-kind token a fraction, a
/// multiplier-kind token a multiplier.
func shapeForTokenKind(_ kind: NumericKind) -> OperandShape {
    switch kind {
    case .percent: return .percent
    case .multiplier: return .multiplier
    case .fraction: return .fraction
    case .plain: return .plain
    }
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
                         vars: [String: Double],
                         context: NumberFormatContext = .legacy,
                         unitContext: UnitContext = .builtIns) throws -> Qty {
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
            // A reference token. r83: a percent-kind token is
            // CONTEXTUAL in additive expressions exactly like a `p%`
            // literal (`200 + TOKEN` = 220 when TOKEN = 20%).
            skipWS()
            if i < ns.length, ns.character(at: i) == answerTokenMarkerUTF16 {
                let pos = i
                i += 1
                guard let q = markerQuantities[pos] else { throw ExprError.invalid }
                return PE(q: q, purePercent: q.kind == .percent)
            }
            guard let c = nextChar() else { throw ExprError.invalid }
            if c == 0x28 { // '('
                i += 1
                let v = try parseAdditive()
                guard let closing = nextChar(), closing == 0x29 else { throw ExprError.invalid }
                i += 1
                return v
            }
            // A currency literal: ANY shared-table marker (bare symbols
            // `$`/`€`/`₹`/…, letter forms `CA$`/`R$`/`Rp`/`zł`/`Kč`)
            // glued in FRONT of the amount — the same shared
            // marker/amount grammar the money pipeline uses.
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
                // r83: the multiplier suffix `1.5x` (no letter/digit
                // after it — `1.5xy` is a variable, not a factor).
                if pct == 0, let p = nextChar(), (p == 0x78 || p == 0x58) {
                    let j = i + 1
                    if j >= ns.length
                        || !(isLetter16(ns.character(at: j)) || isDigit16(ns.character(at: j))) {
                        i = j
                        return PE(q: Qty(v: v, unit: nil, kind: .multiplier), purePercent: false)
                    }
                }
                // Postfix marker: `240$`, `2.5K$`, `100zł` — a
                // shared-table marker glued right after the amount (no
                // digit after it, `45$5` is not a marker) carries the
                // currency unit.
                if pct == 0, let code = parsePostfixMarker() {
                    return PE(q: Qty(v: v, unit: code), purePercent: false)
                }
                return PE(q: Qty(v: v, unit: nil,
                                 kind: pct > 0 ? .percent : .plain),
                          purePercent: pct > 0)
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

        /// The marker starting exactly at `idx` — a lookup against
        /// CurrencyPresentation's shared marker metadata at the current
        /// UTF-16 position (longest-first, so `CN¥` never degrades to
        /// `¥` and `Rp` never to a bare letter).
        func markerAt(_ idx: Int) -> String? {
            for m in tokenMarkerTable {
                let len = (m as NSString).length
                if idx + len <= ns.length,
                   ns.substring(with: NSRange(location: idx, length: len)) == m {
                    return m
                }
            }
            return nil
        }

        /// Whether `i` starts a PREFIX currency marker: a shared-table
        /// marker glued in front of a number/decimal point, preceded by
        /// a non-alphanumeric (a doubled `$$` is never a marker).
        func prefixMarkerStarts(at idx: Int) -> Bool {
            guard let marker = markerAt(idx) else { return false }
            let end = idx + (marker as NSString).length
            guard end < ns.length else { return false }
            let after = ns.character(at: end)
            guard (0x30...0x39).contains(after) || after == 0x2E else { return false }
            guard idx > 0 else { return true }
            let before = ns.character(at: idx - 1)
            guard !(0x30...0x39).contains(before), before != 0x24,
                  !(0x41...0x5A).contains(before), !(0x61...0x7A).contains(before)
            else { return false }
            return true
        }

        /// Consumes the prefix marker at `i` and returns its ISO code.
        /// Throws when the shape is not a real marker.
        func parsePrefixMarker() throws -> String {
            guard let marker = markerAt(i) else { throw ExprError.invalid }
            guard let code = CurrencyPresentation.code(forMarker: marker) else {
                throw ExprError.invalid
            }
            i += (marker as NSString).length
            return code
        }

        /// Postfix marker at `i`: a shared-table marker glued right
        /// after an amount — preceded by a digit or a compact
        /// `k`/`m`/`K`/`M` suffix (itself preceded by a digit/`.`), and
        /// NOT followed by a digit (`45$5` is not a marker); letter
        /// markers additionally never end an alphanumeric run
        /// (`100Rpm` is not a marker).
        func parsePostfixMarker() -> String? {
            guard let marker = markerAt(i), i > 0 else { return nil }
            let len = (marker as NSString).length
            let before = ns.character(at: i - 1)
            let beforeIsDigit = (0x30...0x39).contains(before)
            var beforeIsSuffix = false
            if before == 0x6B || before == 0x6D || before == 0x4B || before == 0x4D, i >= 2 {
                let b = ns.character(at: i - 2)
                beforeIsSuffix = (0x30...0x39).contains(b) || b == 0x2E
            }
            guard beforeIsDigit || beforeIsSuffix else { return nil }
            let after = i + len < ns.length ? ns.character(at: i + len) : 0
            guard !(0x30...0x39).contains(after) else { return nil }
            if marker.first!.isLetter,
               (0x41...0x5A).contains(after) || (0x61...0x7A).contains(after) {
                return nil
            }
            guard let code = CurrencyPresentation.code(forMarker: marker) else { return nil }
            i += len
            return code
        }

        /// One amount literal: digits with optional GROUPING commas and
        /// at most one decimal point, plus the shared compact suffixes
        /// (`k`/`K` ×1000, `m`/`M` ×1,000,000). Advances `i`.
        func parseAmount() throws -> Double {
            let start = i
            var j = i
            var hasDecimal = false
            func threeGroup(_ k: Int) -> Bool {
                guard j + 3 < ns.length || true else { return false }
                guard k + 3 <= ns.length else { return false }
                guard isDigit16(ns.character(at: k + 1)),
                      isDigit16(ns.character(at: k + 2)),
                      isDigit16(ns.character(at: k + 3)) else { return false }
                if k + 4 < ns.length, isDigit16(ns.character(at: k + 4)) { return false }
                return true
            }
            while j < ns.length {
                let c = ns.character(at: j)
                if isDigit16(c) {
                    j += 1
                } else if c == 0x2E {
                    if hasDecimal { break }
                    // r73: in decimal-comma modes a dot run of EXACTLY
                    // three digits is a group separator (dropped);
                    // otherwise the dot is the decimal point — the same
                    // documented rule as the line normalizer.
                    if context.decimalComma, threeGroup(j) {
                        j += 4
                    } else {
                        hasDecimal = true
                        j += 1
                    }
                } else if c == 0x2C, j + 1 < ns.length, isDigit16(ns.character(at: j + 1)) {
                    // Dot modes: grouping comma (dropped below). Decimal
                    // comma modes: the decimal point (canonicalized to
                    // a dot below); two decimals end the literal.
                    if hasDecimal { break }
                    if context.decimalComma { hasDecimal = true }
                    j += 1
                } else {
                    break
                }
            }
            guard j > start else { throw ExprError.invalid }
            var text = ns.substring(with: NSRange(location: start, length: j - start))
            // Canonicalize: grouping commas (dot modes) / dropped group
            // dots leave only digits and the single decimal point; any
            // remaining comma is the decimal comma -> dot.
            if context.decimalComma {
                text = text.replacingOccurrences(of: ",", with: ".")
            } else {
                text = text.replacingOccurrences(of: ",", with: "")
            }
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
                // r83: semantic percent rules — the SAME rules as the
                // line engine. PERCENT MODE: the accumulated side is a
                // percent (or the right side is not) — every operand
                // adds its RAW ratio (`T1 + T2` = 30%, `10% + 100` =
                // 100.1): the result stays a percent. CONTEXTUAL:
                // the accumulated side is plain/multiplier and the
                // RIGHT operand is a percent — a fraction of the
                // accumulated base (`200 + TOKEN` = 220), the result
                // keeps the accumulated kind.
                if aq.kind == .percent || bq.kind == .percent {
                    if aq.kind == .percent || bq.kind != .percent {
                        let v = (op == "+") ? aq.v + bq.v : aq.v - bq.v
                        guard v.isFinite else { throw ExprError.incompatibleUnits }
                        return PE(q: Qty(v: v, unit: aq.unit, kind: .percent),
                                  purePercent: true)
                    }
                    let v = (op == "+")
                        ? aq.v + aq.v * bq.v
                        : aq.v - aq.v * bq.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return PE(q: Qty(v: v, unit: aq.unit, kind: aq.kind),
                              purePercent: false)
                }
                if aq.unit == nil && bq.unit == nil {
                    let v = (op == "+") ? aq.v + bq.v : aq.v - bq.v
                    guard v.isFinite else { throw ExprError.incompatibleUnits }
                    return PE(q: Qty(v: v, unit: nil), purePercent: false)
                }
                guard let ua = aq.unit, let ub = bq.unit, sameQuantityUnit(ua, ub) else {
                    throw ExprError.incompatibleUnits
                }
                guard let vb = convertQuantityUnit(bq.v, fromLabel: ub, toLabel: ua,
                                                   context: unitContext) else {
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
                if let ua = aq.unit, let ub = bq.unit, sameQuantityUnit(ua, ub, context: unitContext) {
                    // Same-unit ratio: unitless.
                    guard let bb = convertQuantityUnit(bq.v, fromLabel: ub, toLabel: ua,
                                                       context: unitContext), bb != 0 else {
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

/// The shared currency marker table (one file-scope copy,
/// longest-first) used by the token expression parser.
private let tokenMarkerTable = CurrencyPresentation.orderedMarkers
