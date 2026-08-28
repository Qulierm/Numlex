import Foundation

func normalizeExprCorrect(_ expr: String) -> String {
    var s = expr.replacingOccurrences(of: ",", with: "")
    func expand(_ input: String, suffix: String, mult: String) -> String {
        let pattern = "(\\d+(?:\\.\\d+)?)\\s*\(suffix)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return input }
        let ns = input as NSString
        var result = input
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let num = ns.substring(with: m.range(at: 1))
            let repl = "(\(num)*\(mult))"
            if let r = Range(m.range, in: result) { result.replaceSubrange(r, with: repl) }
        }
        return result
    }
    s = expand(s, suffix: "k", mult: "1000")
    s = expand(s, suffix: "m", mult: "1000000")
    return s
}

private func isValidIdentifier(_ name: String) -> Bool {
    guard let regex = try? NSRegularExpression(pattern: #"^[A-Za-z_]\w*$"#) else { return false }
    return regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
}

private func tryEvaluateCleaned(_ line: String, variables: [String: Double]) -> Double? {
    // Replace unknown words with empty
    var cleaned = line
    if let regex = try? NSRegularExpression(pattern: #"[A-Za-z_]\w*"#) {
        let ns = line as NSString
        let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let w = ns.substring(with: m.range)
            if variables[w] == nil {
                if let r = Range(m.range, in: cleaned) { cleaned.replaceSubrange(r, with: "") }
            }
        }
    }
    let trimmed = cleaned.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return nil }
    // if only operators/parens/space and no digit -> skip
    if trimmed.range(of: #"\d"#, options: .regularExpression) == nil {
        // check if it contains only allowed chars without digit
        if trimmed.range(of: #"^[\s+\-*/^%().×]*$"#, options: .regularExpression) != nil { return nil }
    }
    do {
        return try evaluateExpression(trimmed, variables: variables)
    } catch { return nil }
}

/// The assignment LHS name of a line: a natural multiword LHS when
/// that grammar accepts it, otherwise the legacy single identifier.
func assignmentLHSName(_ line: String) -> String? {
    guard let eq = line.firstIndex(of: "=") else { return nil }
    let lhs = String(line[..<eq])
    if let natural = NaturalCalculation.naturalLHS(lhs) {
        return natural
    }
    let trimmed = lhs.trimmingCharacters(in: .whitespaces)
    return isValidIdentifier(trimmed) ? trimmed : nil
}

private func evalAssignment(line: String, env: inout TypedEnv, decimalPlaces: Int) -> LineResult? {
    guard let idx = line.firstIndex(of: "=") else { return nil }
    let left = String(line[..<idx]).trimmingCharacters(in: .whitespaces)
    let rightRaw = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
    let right = normalizeExprCorrect(rightRaw)
    if !isValidIdentifier(left) { return .error(message: "Invalid assignment") }
    // r33: global constants are IMMUTABLE in a sheet.
    if env.isConstant(display: left) {
        return .error(message: "Cannot assign to constant")
    }
    if right.isEmpty { return .error(message: "Missing expression") }
    do {
        let raw = try evaluateExpression(right, variables: env.scalarDict())
        let v = roundResult(raw, decimalPlaces: decimalPlaces)
        env.set(display: left, qty: .scalar(v))
        return .variable(name: left, value: v)
    } catch {
        if let cleaned = tryEvaluateCleaned(right, variables: env.scalarDict()) {
            let v = roundResult(cleaned, decimalPlaces: decimalPlaces)
            env.set(display: left, qty: .scalar(v))
            return .variable(name: left, value: v)
        }
        return .error(message: (error as? LocalizedError)?.errorDescription ?? "\(error)")
    }
}

private func evalFreeExpression(line: String, variables: [String: Double], decimalPlaces: Int) -> LineResult? {
    let trimmed = normalizeExprCorrect(line.trimmingCharacters(in: .whitespaces))
    if trimmed.isEmpty { return nil }
    if trimmed.range(of: #"\d"#, options: .regularExpression) == nil {
        if trimmed.range(of: #"[а-яА-ЯёЁ]"#, options: .regularExpression) != nil { return nil }
        let single = trimmed.trimmingCharacters(in: .whitespaces)
        if single.range(of: #"^[A-Za-z_]\w*$"#, options: .regularExpression) != nil, variables[single] != nil {
            // allow single known variable
        } else {
            return nil
        }
    }
    do {
        let raw = try evaluateExpression(trimmed, variables: variables)
        return .number(value: roundResult(raw, decimalPlaces: decimalPlaces), unit: nil)
    } catch {
        if let cleaned = tryEvaluateCleaned(trimmed, variables: variables) {
            return .number(value: roundResult(cleaned, decimalPlaces: decimalPlaces), unit: nil)
        }
        return .error(message: "Invalid expression")
    }
}

// MARK: - Typed named-value expressions

/// The SHARED strict core for named expressions (r33): every compound
/// (multiword) name occurrence is substituted with a tokenizer
/// placeholder, the residual text must contain nothing but numbers,
/// operators, parentheses, `of` and placeholders (NO word stripping, NO
/// fallback), and the shared expression engine evaluates the result.
/// Returns the FULL-precision value plus the set of money codes the
/// referenced names carry (more than one ⇒ hidden error upstream).
/// No rounding happens here — display rounding is the caller's choice.
func namedExprCore(_ line: String, env: TypedEnv) -> (value: Double, codes: Set<String>)? {
    let matches = NamedValues.matches(in: line, env: env)
    var expr = line
    var vars: [String: Double] = [:]
    var codes: Set<String> = []
    for e in env.entries {
        switch e.qty {
        case .scalar(let v) where v.isFinite:
            vars[e.display] = v
        case .money(let v, _) where v.isFinite:
            vars[e.display] = v
        default:
            break
        }
    }
    for (idx, m) in matches.enumerated() {
        switch m.entry.qty {
        case .scalar(let v) where v.isFinite:
            vars[namePlaceholder(idx)] = v
        case .money(let v, let c) where v.isFinite:
            vars[namePlaceholder(idx)] = v
            codes.insert(c.uppercased())
        default:
            break
        }
    }
    guard codes.count <= 1 else { return nil }
    for (idx, m) in matches.enumerated().reversed() {
        expr = (expr as NSString).replacingCharacters(in: m.range,
                                                      with: namePlaceholder(idx))
    }
    let trimmed = expr.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    do {
        let normalized = normalizeExprCorrect(trimmed)
        // Residual guard: every identifier must be a placeholder (or a
        // value the environment knows) or the `of` infix.
        for t in try tokenize(normalized) {
            if case .identifier(let n) = t, n != "of", vars[n] == nil {
                return nil
            }
        }
        let raw = try evaluateExpression(normalized, variables: vars)
        guard raw.isFinite else { return nil }
        return (raw, codes)
    } catch {
        return nil
    }
}

/// Evaluates an expression that may reference DECLARED named values,
/// with the line-pipeline's display rounding (10 decimals) applied.
func evaluateNamedExpr(_ line: String, env: TypedEnv) -> (value: Double, codes: Set<String>)? {
    guard let r = namedExprCore(line, env: env) else { return nil }
    return (roundResult(r.value, decimalPlaces: 10), r.codes)
}

/// `<name> to|in <unit>` conversion shape: the line starts with ONE
/// declared name, then exactly one `to`/`in` keyword and a non-empty
/// unit expression. Returns the unit text, or nil.
private func namedConversionShape(line: String, env: TypedEnv) -> String? {
    let ns = line as NSString
    let matches = NamedValues.matches(in: line, env: env)
    guard matches.count == 1 else { return nil }
    var offset = 0
    while offset < ns.length, ns.character(at: offset) == 0x20 { offset += 1 }
    guard matches[0].range.location == offset else { return nil }
    let after = ns.substring(from: NSMaxRange(matches[0].range))
    let t = after.trimmingCharacters(in: .whitespaces)
    let lower = t.lowercased()
    guard lower.hasPrefix("to") || lower.hasPrefix("in") else { return nil }
    guard t.count > 2, t.dropFirst(2).first!.isWhitespace else { return nil }
    let unitText = t.dropFirst(2).trimmingCharacters(in: .whitespaces)
    guard !unitText.isEmpty, unitText.contains(where: { $0.isLetter }) else { return nil }
    return unitText
}

/// The typed named-value pipeline stage: runs ONLY for lines that
/// reference a declared compound name (single-identifier lines keep the
/// legacy paths byte-for-byte). A line referencing a declared compound
/// name NEVER falls through to the word-stripping fallback — anything
/// it cannot evaluate is a hidden generic error.
private func evalNamedLine(_ line: String,
                           env: inout TypedEnv,
                           rates: Rates,
                           decimalPlaces: Int) -> LineResult? {
    // 1. Explicit conversion of a named quantity: `monthly rent in EUR`.
    if let unit = namedConversionShape(line: line, env: env) {
        let matches = NamedValues.matches(in: line, env: env)
        switch matches[0].entry.qty {
        case .money(let v, let code):
            guard let from = UnitCatalog.resolveExpression(code) else {
                return .error(message: "Invalid conversion")
            }
            guard let to = UnitCatalog.resolveExpression(unit) else {
                return .error(message: "Unknown units")
            }
            if case .currency = to.unit.kind {
                guard let r = rates.rate(from: code, to: to.unit.label) else {
                    return .error(message: "Rates unavailable")
                }
                let value = v * r
                guard value.isFinite else { return .error(message: "Invalid conversion") }
                return .number(value: roundResult(value, decimalPlaces: max(decimalPlaces, 10)),
                               unit: to.unit.label)
            }
            return .error(message: "Invalid conversion")
        case .scalar:
            break  // unitless name: not convertible, fall to reference
        }
    }
    // 2. Named reference expression: `monthly rent × 12`,
    //    `monthly rent + phone bill`, `monthly rent + 5%`.
    if let (v, codes) = evaluateNamedExpr(line, env: env) {
        if let c = codes.first {
            return .money(value: v, code: c)
        }
        return .number(value: v, unit: nil)
    }
    return .error(message: "Invalid expression")
}

// MARK: - The shared line pipeline

/// The full line pipeline in strict order, over the SHARED typed
/// environment (named unitless values AND money):
/// 1. conversion shape (`<number> <unit> to|in <unit>`, symbol sources);
/// 2. named-value stage (compound-name references, named money
///    assignments, `<name> in <unit>` conversions);
/// 3. natural money lines (currency marker or ISO annotation);
/// 4. date arithmetic lines (month/today ± duration);
/// 5. assignment; 6. free expression.
/// Money and date detection run BEFORE the blind word-stripping
/// fallback so currency- or date-looking input can never degenerate
/// into a leading number.
func evalLineTyped(_ line: String,
                   env: inout TypedEnv,
                   rates: Rates,
                   decimalPlaces: Int,
                   now: Date,
                   calendar: Calendar) -> LineResult? {
    // r33: assignment to an ACTIVE global constant is a visible error on
    // EVERY route (single identifier, multiword natural, money RHS) —
    // no fallback, no partial mutation. Constants never shadow or get
    // shadowed: an invalid/inactive constant row reserves no name.
    if line.contains("="), let lhs = assignmentLHSName(line),
       env.isConstant(display: lhs) {
        return .error(message: "Cannot assign to constant")
    }
    if let conv = tryConversion(line, rates: rates, decimalPlaces: decimalPlaces) {
        return conv
    }
    // Named assignment (any valid LHS, money right-hand side, or a
    // multiword name with a scalar right-hand side): the answer is the
    // assigned quantity and the name is recorded typed.
    if line.contains("="), let a = NaturalCalculation.tryAssignment(line: line, env: env) {
        switch a.value {
        case .money(let v, let c):
            env.set(display: a.name, qty: .money(v, code: c))
            return .money(value: v, code: c)
        case .scalar(let v) where a.name.contains(" "):
            env.set(display: a.name, qty: .scalar(v))
            return .variable(name: a.name, value: v)
        case .scalar:
            break  // single identifier: the legacy assignment path
        }
    }
    if NamedValues.referencesTypedName(line, env: env) {
        return evalNamedLine(line, env: &env, rates: rates, decimalPlaces: decimalPlaces)
    }
    switch NaturalCalculation.tryMoney(line: line, env: env) {
    case .money(let value, let code):
        return .money(value: value, code: code)
    case .malformed:
        return .error(message: "Invalid expression")
    case .none:
        break
    }
    switch DateArithmetic.detect(line: line, now: now, calendar: calendar) {
    case .value(let v):
        return .date(year: v.year, month: v.month, day: v.day, showYear: v.showYear)
    case .malformed:
        return .error(message: "Invalid expression")
    case .none:
        break
    }
    if line.contains("=") {
        return evalAssignment(line: line, env: &env, decimalPlaces: decimalPlaces)
    }
    return evalFreeExpression(line: line, variables: env.scalarDict(), decimalPlaces: decimalPlaces)
}

// MARK: - Backward-compatible public wrappers

public func evalLine(_ line: String, variables: inout [String: Double], rates: Rates, decimalPlaces: Int, constants: [UserConstant] = []) -> LineResult? {
    // Fresh reference clock/calendar per single-line call; sheet
    // evaluation captures ONE context for the whole sheet.
    evalLine(line, variables: &variables, rates: rates, decimalPlaces: decimalPlaces,
             now: Date(), calendar: Calendar.current, constants: constants)
}

/// The legacy `[String: Double]` entry point: seeds a typed environment
/// from the caller's variables, runs the shared typed pipeline, and
/// writes back the scalar entries (money names never leak into the
/// untyped dictionary).
/// Legacy single-line evaluation with GLOBAL constants (r33): the
/// constants are seeded AFTER the caller's variables so an immutable
/// constant always wins over a stale seed entry.
public func evalLine(_ line: String, variables: inout [String: Double], rates: Rates,
                     decimalPlaces: Int, now: Date, calendar: Calendar,
                     constants: [UserConstant] = []) -> LineResult? {
    var env = TypedEnv(seed: variables)
    env.seedConstants(constants)
    let result = evalLineTyped(line, env: &env, rates: rates,
                               decimalPlaces: decimalPlaces,
                               now: now, calendar: calendar)
    if result != nil {
        for (k, v) in env.scalarDict() { variables[k] = v }
    }
    return result
}

/// Evaluates a whole sheet with the STRICT ONE-RESULT-PER-LOGICAL-LINE
/// contract: the returned array has exactly one indexed `SheetLine` for
/// every element of `source.components(separatedBy: "\n")`, including
/// leading, consecutive and trailing blanks and `#` comments (each
/// `.blank`), `// ` lines (`.title`) and prose (`.skip`). Named values
/// (unitless AND money) accumulate strictly top-down in ONE shared
/// typed environment — only actual `evalLine` calls touch it, so
/// non-evaluable lines never affect it, and the result of every
/// evaluable line is exactly what the per-line evaluator produced.
/// Consumers must bind output by `sourceLineIndex`, never by position
/// after any filtering.
public func evaluateSheet(_ source: String, variables: inout [String: Double], rates: Rates, decimalPlaces: Int, constants: [UserConstant] = []) -> [SheetLine] {
    evaluateSheet(source, variables: &variables, rates: rates, decimalPlaces: decimalPlaces,
                  now: Date(), calendar: Calendar.current, constants: constants)
}

/// Sheet evaluation with ONE captured date context and ONE shared typed
/// environment per sheet: `today`/`tomorrow`/`yesterday`, implicit
/// years and named values (unitless and money) are consistent across
/// the whole sheet.
public func evaluateSheet(_ source: String, variables: inout [String: Double], rates: Rates,
                          decimalPlaces: Int, now: Date, calendar: Calendar,
                          constants: [UserConstant] = []) -> [SheetLine] {
    var env = TypedEnv(seed: variables)
    // r33: global constants are available BEFORE logical line 1; local
    // values still accumulate strictly top-down.
    env.seedConstants(constants)
    var rows: [SheetLine] = []
    let lines = source.components(separatedBy: "\n")
    for (index, line) in lines.enumerated() {
        let result: LineResult
        if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") {
            result = .blank
        } else if line.hasPrefix("// ") {
            result = .title(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        } else if line.hasPrefix("//") {
            result = .blank
        } else if let eval = evalLineTyped(line, env: &env, rates: rates,
                                           decimalPlaces: decimalPlaces,
                                           now: now, calendar: calendar) {
            result = eval
        } else {
            result = .skip
        }
        rows.append(SheetLine(sourceLineIndex: index, result: result))
    }
    for (k, v) in env.scalarDict() { variables[k] = v }
    return rows
}

/// Declared names, legacy and natural: single ASCII identifiers
/// (`x = 1`) AND bounded multiword natural names (`monthly rent = $5`)
/// — the same LHS grammar the evaluator accepts.
public func declaredVariables(_ source: String) -> [String: Bool] {
    var dict: [String: Bool] = [:]
    for line in source.components(separatedBy: "\n") {
        if let eq = line.firstIndex(of: "=") {
            let lhs = String(line[..<eq])
            if let natural = NaturalCalculation.naturalLHS(lhs) {
                dict[natural] = true
                continue
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"^\s*([A-Za-z_]\w*)\s*="#) {
            let ns = line as NSString
            if let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges >= 2 {
                let name = ns.substring(with: m.range(at: 1))
                dict[name] = true
            }
        }
    }
    return dict
}

/// Overflow-safe display formatting — a thin alias for the single shared
/// formatter (`formatDisplayValue`). The previous implementation trapped
/// on values above Int64.max via a direct `Int64(value)` cast.
public func formatNumberForDisplay(_ value: Double) -> String {
    formatDisplayValue(value)
}
