import Foundation

func normalizeExprCorrect(_ expr: String) -> String {
    normalizeExprCorrect(expr, context: .legacy)
}

/// r73: the context-aware normalization.
///
/// - decimal-point modes (legacy, North America, dot-decimal system
///   locales): the EXACT r47 function-aware comma rule, unchanged —
///   outside a call every comma is stripped (`1,234` -> `1234`);
///   inside a call a comma stays an argument separator unless it is a
///   grouping comma by the shared `FunctionCalls` rule.
/// - decimal-comma modes (Western/Eastern Europe, comma-decimal system
///   locales): a comma directly after a digit is the DECIMAL separator
///   and becomes `.` (`1,5` -> `1.5`; a stray comma stays and the
///   tokenizer reports it — deterministic, no silent rewrite); the
///   context's grouping separator (`.`, NBSP — plus the Eastern
///   preset's plain space) is stripped ONLY in well-formed groups:
///   a 1-3 digit run before and EXACTLY three digits after (the
///   following character must not be a digit, so `1.2345` keeps its
///   decimal meaning and `1.23` reads as the decimal 1.23);
/// - both: the k/m expansion below runs after all of the above.
public func normalizeExprCorrect(_ expr: String, context: NumberFormatContext) -> String {
    let chars = Array(expr)
    let n = chars.count
    // r47's function-aware depth map. Decimal-comma modes still need
    // it: a spaced comma decimal OUTSIDE a call (`1, 5 + 1` -> `1.5`)
    // converts, while the same shape INSIDE a call stays an argument
    // separator (`sum(1, 5)`).
    let fnCtx = FunctionCalls.context(expr)
    // The grouping separators this mode strips (dot modes group with
    // `,` which never reaches the stripping path — it IS the decimal
    // mode's stripped/kept character above).
    let groupChars: Set<Character> = {
        var set: Set<Character> = []
        func add(_ str: String) {
            str.unicodeScalars.forEach { set.insert(Character($0)) }
        }
        if !context.legacy {
            add(context.groupingSeparator)
            context.inputGroupingSeparators.forEach(add)
        }
        return set
    }()
    func isDig(_ i: Int) -> Bool { i >= 0 && i < n && chars[i].isNumber }
    func isWord(_ c: Character) -> Bool { c.isLetter || c == "_" }
    func isWellFormedGroup(_ i: Int) -> Bool {
        guard i > 0, isDig(i - 1) else { return false }
        var runStart = i - 1
        while runStart - 1 >= 0, isDig(runStart - 1) { runStart -= 1 }
        let runLen = i - runStart
        guard (1...3).contains(runLen) else { return false }
        // Identifier guard: `a 234` must not fuse into an identifier.
        if runStart - 1 >= 0, isWord(chars[runStart - 1]) { return false }
        for k in 1...3 {
            if i + k >= n || !isDig(i + k) { return false }
        }
        if i + 4 < n, isDig(i + 4) { return false } // >= 4 digits after: decimal-ish, keep
        return true
    }
    var out: [Character] = []
    out.reserveCapacity(chars.count)
    // r73: set when a spaced comma decimal just became `.` and the
    // space that separated comma and digit must be dropped for the
    // decimal to stay well-formed (`1, 5` -> `1.5`, never `1. 5`).
    var commaDecimalEatsSpace = false
    for (i, ch) in chars.enumerated() {
        if commaDecimalEatsSpace, ch == " " {
            commaDecimalEatsSpace = false
            continue
        }
        commaDecimalEatsSpace = false
        if ch == "," {
            if context.decimalComma {
                if i > 0, isDig(i - 1) {
                    // A digit-adjacent comma is the decimal separator
                    // at any depth (`sum(1,5)` keeps working). A
                    // SPACED comma decimal converts only OUTSIDE a
                    // call — `1, 5 + 1` -> `1.5 + 1` — while the same
                    // shape inside a call stays an argument separator
                    // (`sum(1, 5)`).
                    let nextDigit = i + 1 < n && isDig(i + 1)
                    if nextDigit {
                        out.append(".")
                    } else if fnCtx.depth[i] == 0 {
                        out.append(".")
                        commaDecimalEatsSpace = true
                    } else {
                        out.append(ch)
                    }
                } else {
                    out.append(ch) // stray: the tokenizer reports it
                }
                continue
            }
            if fnCtx.depth[i] > 0,
               !FunctionCalls.isGroupingComma(chars, at: i) {
                out.append(ch)
            }
            continue
        }
        if context.decimalComma, groupChars.contains(ch), isWellFormedGroup(i) {
            continue // strip the well-formed group separator
        }
        out.append(ch)
    }
    var s = String(out)
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

private func tryEvaluateCleaned(_ line: String, variables: [String: Double],
                             context: NumberFormatContext = .legacy) -> Double? {
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
        return try evaluateExpression(trimmed, variables: variables, context: context)
    } catch { return nil }
}

/// The assignment LHS name of a line: a natural multiword LHS when
/// that grammar accepts it, otherwise the legacy single identifier.
/// r82: the `=` is recognized through `BooleanLogic.assignmentSplit`
/// (the single shared recognizer — `==`, `!=`, `<=`, `>=` never enter
/// assignment routes).
func assignmentLHSName(_ line: String) -> String? {
    guard let split = BooleanLogic.assignmentSplit(line) else { return nil }
    let lhs = split.lhs
    if let natural = NaturalCalculation.naturalLHS(lhs) {
        return natural
    }
    let trimmed = lhs.trimmingCharacters(in: .whitespaces)
    return isValidIdentifier(trimmed) ? trimmed : nil
}

private func evalAssignment(line: String, env: inout TypedEnv, decimalPlaces: Int,
                                   context: NumberFormatContext = .legacy) -> LineResult? {
    guard let split = BooleanLogic.assignmentSplit(line) else { return nil }
    let left = split.lhs.trimmingCharacters(in: .whitespaces)
    let rightRaw = split.rhs.trimmingCharacters(in: .whitespaces)
    let right = normalizeExprCorrect(rightRaw, context: context)
    if !isValidIdentifier(left) { return .error(message: "Invalid assignment") }
    // r33: global constants are IMMUTABLE in a sheet.
    if env.isConstant(display: left) {
        return .error(message: "Cannot assign to constant")
    }
    if right.isEmpty { return .error(message: "Missing expression") }
    do {
        let raw = try evaluateExpression(right, variables: env.scalarDict(), context: context)
        let v = roundResult(raw, decimalPlaces: decimalPlaces)
        env.set(display: left, qty: .scalar(v))
        return .variable(name: left, value: v)
    } catch {
        // r47: a function-shaped RHS is STRICT — it never degrades to a
        // word-stripped parenthesized operand (no `(9)` from `sqr(9)`)
        // and the environment is left untouched. The route already
        // surfaces LocalizedError messages, so the precise syntax/domain
        // failure stays visible here.
        if FunctionCalls.hasCallHead(rightRaw) {
            return .error(message: (error as? LocalizedError)?.errorDescription ?? "Invalid expression")
        }
        if let cleaned = tryEvaluateCleaned(right, variables: env.scalarDict(), context: context) {
            let v = roundResult(cleaned, decimalPlaces: decimalPlaces)
            env.set(display: left, qty: .scalar(v))
            return .variable(name: left, value: v)
        }
        return .error(message: (error as? LocalizedError)?.errorDescription ?? "\(error)")
    }
}

private func evalFreeExpression(line: String, variables: [String: Double], decimalPlaces: Int,
                                         context: NumberFormatContext = .legacy) -> LineResult? {
    let trimmed = normalizeExprCorrect(line.trimmingCharacters(in: .whitespaces), context: context)
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
        let raw = try evaluateExpression(trimmed, variables: variables, context: context)
        return .number(value: roundResult(raw, decimalPlaces: decimalPlaces), unit: nil)
    } catch {
        // r47: a function-shaped line is STRICT on the free-expression
        // route too: unknown, malformed or domain-failing calls never
        // fall back to a word-stripped parenthesized operand and never
        // mutate the environment. The free-line presentation stays the
        // generic message (the precise failure is visible on the
        // assignment route, which surfaces LocalizedError).
        if FunctionCalls.hasCallHead(line) {
            return .error(message: "Invalid expression")
        }
        if let cleaned = tryEvaluateCleaned(trimmed, variables: variables, context: context) {
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
func namedExprCore(_ line: String, env: TypedEnv,
                   context: NumberFormatContext = .legacy) -> (value: Double, codes: Set<String>)? {
    strictExprCore(line, env: env, extraVars: [:])
}

/// The SHARED strict named-expression core with OPTIONAL extra scalar
/// variables (r47: the unitless token route feeds its marker
/// placeholders through here, so function semantics are never
/// duplicated outside the one shared engine). `extraVars` win over env
/// entries on key collision (the placeholders are collision-proof).
func strictExprCore(_ line: String,
                    env: TypedEnv,
                    extraVars: [String: Double],
                    context: NumberFormatContext = .legacy) -> (value: Double, codes: Set<String>)? {
    let matches = NamedValues.matches(in: line, env: env)
    var expr = line
    var vars: [String: Double] = [:]
    vars.merge(extraVars) { _, new in new }
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
    // r47: a function call NEVER carries money — a same-currency named
    // money argument would otherwise silently keep its currency through
    // sqrt/log/.... Hidden generic error, nothing is stripped.
    if FunctionCalls.hasCallHead(line), !codes.isEmpty {
        return nil
    }
    for (idx, m) in matches.enumerated().reversed() {
        expr = (expr as NSString).replacingCharacters(in: m.range,
                                                      with: namePlaceholder(idx))
    }
    let trimmed = expr.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    do {
        let normalized = normalizeExprCorrect(trimmed, context: context)
        // Residual guard: every identifier must be a placeholder (or a
        // value the environment knows), the `of` infix, or a KNOWN
        // builtin in call position — a builtin call head is grammar,
        // never an unknown word, while its arguments stay guarded.
        for t in try tokenize(normalized, context: context) {
            if case .identifier(let n) = t,
               n != "of", vars[n] == nil, !MathFunctions.isKnown(n) {
                return nil
            }
        }
        let raw = try evaluateExpression(normalized, variables: vars, context: context)
        guard raw.isFinite else { return nil }
        return (raw, codes)
    } catch {
        return nil
    }
}

/// Evaluates an expression that may reference DECLARED named values,
/// with the line-pipeline's display rounding (10 decimals) applied.
func evaluateNamedExpr(_ line: String, env: TypedEnv,
                        context: NumberFormatContext = .legacy) -> (value: Double, codes: Set<String>)? {
    guard let r = namedExprCore(line, env: env, context: context) else { return nil }
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
                           decimalPlaces: Int,
                   context: NumberFormatContext = .legacy) -> LineResult? {
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
        case .scalar, .bool:
            break  // unitless/boolean name: not convertible, fall to reference
        }
    }
    // 2. Named reference expression: `monthly rent × 12`,
    //    `monthly rent + phone bill`, `monthly rent + 5%`.
    if let (v, codes) = evaluateNamedExpr(line, env: env, context: context) {
        if let c = codes.first {
            return .money(value: v, code: c)
        }
        return .number(value: v, unit: nil)
    }
    // r53: the strict core above rejects bounded neutral prose (a line
    // like `5 people × apple` after `apple = 5$`), so before failing,
    // hand the line to the natural money core: the currency comes from
    // an explicit marker/ISO or from a referenced typed money name. A
    // line that is neither strict nor natural (unknown prose, mixed
    // currencies, function calls on money) stays a hidden generic
    // error — no word-stripping fallback is introduced.
    switch NaturalCalculation.moneyOutcome(line, env: env, context: context) {
    case .money(let v, let c):
        return .money(value: v, code: c)
    case .malformed, .none:
        break
    }
    // r82: a boolean line that references a declared name (a compound
    // boolean name, or a single-identifier boolean variable) is
    // finished by the strict boolean core — money/scalar routes above
    // never see it, and a boolean line never degrades to the generic
    // numeric fallback.
    switch BooleanLogic.boolOutcome(line, env: env, context: context) {
    case .value(let b):
        return .boolean(value: b)
    case .error(let m):
        return .error(message: m)
    case .notBool:
        break
    }
    return .error(message: "Invalid expression")
}

// MARK: - Weather lines (r55)

/// Resolves a strict `weather in <place>` query against the pure
/// weather context (no network, no mutation): a ready snapshot
/// becomes an ordinary temperature number (`C°`, full precision up to
/// 10 decimals like conversions); loading stays quiet (`.skip`, never
/// a false error); a terminal failure with no cache is the stable
/// `Weather unavailable` sentinel the view localizes at render time.
private func evalWeatherLine(_ query: WeatherQuery,
                              weather: WeatherContext,
                              decimalPlaces: Int) -> LineResult {
    switch weather.lookup(query) {
    case .ready(let snap):
        return .number(value: roundResult(snap.temperatureCelsius,
                                          decimalPlaces: max(decimalPlaces, 10)),
                       unit: WeatherQuery.celsiusUnitLabel)
    case .loading:
        return .skip
    case .unavailable:
        return .error(message: WeatherQuery.unavailableMessage)
    }
}

// MARK: - The shared line pipeline

/// The full line pipeline in strict order, over the SHARED typed
/// environment (named unitless values AND money):
/// 0. weather queries (`weather in <place>`, strict grammar only);
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
                   calendar: Calendar,
                   weather: WeatherContext = .empty,
                   context: NumberFormatContext = .legacy) -> LineResult? {
    // r55: weather detection runs FIRST so `weather in London` can
    // never be misclassified as conversion or prose — but ONLY the
    // strict grammar activates it, the environment is never mutated,
    // and variables/constants named `weather` keep working outside
    // this exact shape.
    if let query = WeatherQuery.parse(line) {
        return evalWeatherLine(query, weather: weather, decimalPlaces: decimalPlaces)
    }
    // r33: assignment to an ACTIVE global constant is a visible error on
    // EVERY route (single identifier, multiword natural, money RHS,
    // boolean RHS) — no fallback, no partial mutation. Constants never
    // shadow or get shadowed: an invalid/inactive constant row reserves
    // no name.
    if BooleanLogic.hasAssignment(line), let lhs = assignmentLHSName(line),
       env.isConstant(display: lhs) {
        return .error(message: "Cannot assign to constant")
    }
    if let conv = tryConversion(line, rates: rates, decimalPlaces: decimalPlaces, context: context) {
        return conv
    }
    // Named assignment (any valid LHS, money right-hand side, a
    // multiword name with a scalar right-hand side, or — r82 — ANY
    // valid LHS with a boolean right-hand side): the answer is the
    // assigned quantity and the name is recorded typed.
    if BooleanLogic.hasAssignment(line),
       let a = NaturalCalculation.tryAssignment(line: line, env: env, context: context) {
        switch a.value {
        case .error(let m):
            // r82: a rejected boolean-looking right-hand side fails
            // strictly — no numeric/money fallback.
            return .error(message: m)
        case .money(let v, let c):
            env.set(display: a.name, qty: .money(v, code: c))
            return .money(value: v, code: c)
        case .scalar(let v) where a.name.contains(" "):
            env.set(display: a.name, qty: .scalar(v))
            return .variable(name: a.name, value: v)
        case .scalar(let v):
            // r82: a single identifier that earned its scalar through
            // the boolean/conditional route (`x = if … then … else …`)
            // is recorded like any named value. (Legacy single-
            // identifier scalar assignments never produce this case —
            // they keep the path below.)
            env.set(display: a.name, qty: .scalar(v))
            return .variable(name: a.name, value: v)
        case .bool(let b):
            // r82: a boolean right-hand side (single- OR multiword
            // LHS) records a real boolean — never a 0/1 scalar.
            env.set(display: a.name, qty: .bool(b))
            return .boolean(value: b)
        }
    }
    if NamedValues.referencesTypedName(line, env: env) {
        return evalNamedLine(line, env: &env, rates: rates, decimalPlaces: decimalPlaces,
                             context: context)
    }
    switch NaturalCalculation.tryMoney(line: line, env: env, context: context) {
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
    // r82: boolean and conditional lines — comparisons, logical
    // expressions, boolean literals/variables and `if … then … else`
    // (value or conditional-assignment form). Boolean-looking lines
    // NEVER fall through to the word-stripping or numeric routes;
    // every other line (booleanShape false) is untouched by this
    // stage.
    if BooleanLogic.booleanShape(line, env: env) {
        // Conditional lines come first: the conditional-assignment form
        // (`if c then x = a else x = b`) DOES carry an `=`, so it must
        // be resolved before the assignment-aware skip below.
        if let cond = BooleanLogic.conditionalLine(line, env: &env, context: context) {
            return cond
        }
        // Lines with a single assignment `=` are owned by the
        // assignment routes (boolean right-hand sides included) — the
        // free-expression boolean core never re-parses them.
        if !BooleanLogic.hasAssignment(line) {
            switch BooleanLogic.boolOutcome(line, env: env, context: context) {
            case .value(let b):
                return .boolean(value: b)
            case .error(let m):
                return .error(message: m)
            case .notBool:
                break
            }
        }
    }
    if BooleanLogic.hasAssignment(line) {
        return evalAssignment(line: line, env: &env, decimalPlaces: decimalPlaces, context: context)
    }
    return evalFreeExpression(line: line, variables: env.scalarDict(), decimalPlaces: decimalPlaces, context: context)
}

// MARK: - Backward-compatible public wrappers

public func evalLine(_ line: String, variables: inout [String: Double], rates: Rates, decimalPlaces: Int, constants: [UserConstant] = [], weather: WeatherContext = .empty, context: NumberFormatContext = .legacy) -> LineResult? {
    // Fresh reference clock/calendar per single-line call; sheet
    // evaluation captures ONE context for the whole sheet.
    evalLine(line, variables: &variables, rates: rates, decimalPlaces: decimalPlaces,
             now: Date(), calendar: Calendar.current, constants: constants, weather: weather,
             context: context)
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
                     constants: [UserConstant] = [], weather: WeatherContext = .empty,
                     context: NumberFormatContext = .legacy) -> LineResult? {
    var env = TypedEnv(seed: variables)
    env.seedConstants(constants)
    let result = evalLineTyped(line, env: &env, rates: rates,
                               decimalPlaces: decimalPlaces,
                               now: now, calendar: calendar, weather: weather,
                               context: context)
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
public func evaluateSheet(_ source: String, variables: inout [String: Double], rates: Rates, decimalPlaces: Int, constants: [UserConstant] = [], weather: WeatherContext = .empty, context: NumberFormatContext = .legacy) -> [SheetLine] {
    evaluateSheet(source, variables: &variables, rates: rates, decimalPlaces: decimalPlaces,
                  now: Date(), calendar: Calendar.current, constants: constants, weather: weather,
                  context: context)
}

/// Sheet evaluation with ONE captured date context and ONE shared typed
/// environment per sheet: `today`/`tomorrow`/`yesterday`, implicit
/// years and named values (unitless and money) are consistent across
/// the whole sheet.
public func evaluateSheet(_ source: String, variables: inout [String: Double], rates: Rates,
                          decimalPlaces: Int, now: Date, calendar: Calendar,
                          constants: [UserConstant] = [], weather: WeatherContext = .empty,
                          context: NumberFormatContext = .legacy) -> [SheetLine] {
    var env = TypedEnv(seed: variables)
    // r33: global constants are available BEFORE logical line 1; local
    // values still accumulate strictly top-down.
    env.seedConstants(constants)
    // r57/r58: one shared inline-total SECTION accumulator for the
    // whole sheet — each command sums its section only and resets,
    // never mutates the env, and prior total rows never enter a new
    // section.
    var totals = TotalAccumulator()
    var rows: [SheetLine] = []
    let lines = source.components(separatedBy: "\n")
    for (index, line) in lines.enumerated() {
        let result: LineResult
        var isTotalRow = false
        if line.trimmingCharacters(in: .whitespaces).isEmpty || line.hasPrefix("#") {
            result = .blank
        } else if line.hasPrefix("// ") {
            result = .title(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
        } else if line.hasPrefix("//") {
            result = .blank
        } else if InlineTotal.isCommand(line, env: env) {
            result = totals.total(decimalPlaces: decimalPlaces)
            if case .number = result { isTotalRow = true }
        } else if let eval = evalLineTyped(line, env: &env, rates: rates,
                                           decimalPlaces: decimalPlaces,
                                           now: now, calendar: calendar, weather: weather,
                                           context: context) {
            result = eval
        } else {
            result = .skip
        }
        totals.observe(result: result, isTotalRow: isTotalRow)
        rows.append(SheetLine(sourceLineIndex: index, result: result, isTotal: isTotalRow))
    }
    for (k, v) in env.scalarDict() { variables[k] = v }
    return rows
}

/// Declared names, legacy and natural: single ASCII identifiers
/// (`x = 1`) AND bounded multiword natural names (`monthly rent = $5`)
/// — the same LHS grammar the evaluator accepts (r82: through the
/// shared `=` recognizer, so `==`/`!=`/`<=`/`>=` never declare).
public func declaredVariables(_ source: String) -> [String: Bool] {
    var dict: [String: Bool] = [:]
    for line in source.components(separatedBy: "\n") {
        if let split = BooleanLogic.assignmentSplit(line) {
            let lhs = split.lhs
            if let natural = NaturalCalculation.naturalLHS(lhs) {
                dict[natural] = true
                continue
            }
            let trimmed = lhs.trimmingCharacters(in: .whitespaces)
            if isValidIdentifier(trimmed) {
                dict[trimmed] = true
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
