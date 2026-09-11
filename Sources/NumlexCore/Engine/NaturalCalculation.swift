import Foundation

/// Typed natural-calculation detection for money lines.
///
/// Replaces the old blind word-stripping fallback for currency-looking
/// input: a line that carries a currency marker (a symbol adjacent to a
/// number, or an ISO code annotating a number) MUST parse as a
/// complete money expression or return a hidden generic error — it can
/// never fall through to a leading-number result.
///
/// Grammar (English natural words only):
/// - currency markers: the SHARED CurrencyPresentation table —
///   `CA$`/`NZ$`/`HK$`/`MX$`/`NT$`/`A$`/`S$`/`R$`, bare `$` (→ USD),
///   `€` `£` `¥` `₽` `CN¥` `₩` `₹` `₺` `₴` `₫` `₱` `฿` `₪` `₦` `₾`
///   `₸` `₮` `₯` `៛` `₡` `₲` `₵`, letter markers `Rp` `RM` `zł`
///   `Kč` — PREFIX (`$45`, `Rp25000`, `zł100`) or POSTFIX (`45$`,
///   `2.5K$`, `100zł`); a doubled/malformed marker is never a marker;
/// - amounts: grouping (`$3,400`), decimals, and the shared compact
///   suffixes (`$3k`);
/// - time rates: `per <time>` and `/ <time>` open a money/time rate
///   (`per day` == `/ 1 day`); a numeric duration (`30 days`, `8 hrs`)
///   carries the same time and cancels the rate when multiplied —
///   exact catalog time factors, so `$24 per day × 12 hrs` = $12.
///   Uncancelled rates are a hidden error, never a number;
/// - a terminal prose period after a completed expression is accepted
///   (`8 hrs.`) — a decimal dot is never stripped;
/// - one currency per line is NO LONGER required: a line may combine
///   currencies with additive/subtractive arithmetic (`500 usd - 300 eur`,
///   `$500 - 300 eur`, `500 usd + €300`). The FIRST money operand in
///   source order anchors the result and every other currency operand is
///   converted into it through the supplied `Rates` before `+`/`-`; a
///   missing pair is an explicit `Rates unavailable` state, never a
///   numeric fallback. Currency ×/÷ currency stays rejected (no implicit
///   `USD²`), while money × scalar and money ÷ scalar keep working.
///   Same-currency lines are byte-for-byte the legacy behavior;
/// - ISO annotations are ASCII-case-insensitive (`usd`, `Usd`, `USD` all
///   canonicalize to `USD`) through the ONE shared
///   `CurrencyAnnotations` scanner, which the highlighter and the shape
///   probes use too. The source text is never rewritten;
/// - prose: a BOUNDED neutral word list (`lunch was`, `earnings`,
///   `people`, `tip`, `sales tax`, ...) is dropped; declared named
///   values (single or multiword) keep their values; any other word
///   makes the line malformed;
/// - arithmetic: everything the shared expression engine does — `+`,
///   `-`, `×`, `÷`, contextual percentages, `of`, parentheses — with
///   the ISO code carried through the result.
public enum NaturalCalculation {

    public enum Outcome: Equatable {
        case money(value: Double, code: String)
        case malformed
        /// The line IS money and needs cross-currency rates the supplied
        /// table cannot provide (a missing/invalid pair, or a table-less
        /// context). Surfaced distinctly so callers show
        /// `Rates unavailable` — never a numeric fallback, a partial
        /// result or a fabricated rate.
        case ratesUnavailable
        case none
    }

    /// Bounded neutral prose words that may surround money amounts.
    /// Count annotations like `people` stay dimensionless.
    static let neutralWords: Set<String> = [
        "was", "is", "lunch", "dinner", "breakfast", "earnings", "income",
        "salary", "people", "person", "tip", "tips", "tax", "taxes",
        "sales", "total", "bill", "order", "cost", "price", "item",
        "items", "each", "spent", "paid", "got", "for", "the",
        "food", "material", "materials",
    ]

    /// Time words that open a rate or a duration (`per day`, `8 hrs`).
    /// Resolved through the UnitCatalog for EXACT factors (base second);
    /// a word the catalog does not resolve as pure time is ignored here
    /// (it then fails the word loop as a hidden error).
    static let timeWords: Set<String> = [
        "s", "sec", "secs", "second", "seconds",
        "min", "mins", "minute", "minutes",
        "h", "hr", "hrs", "hour", "hours",
        "d", "day", "days",
        "w", "wk", "wks", "week", "weeks",
    ]

    private static let wordRe = try? NSRegularExpression(
        pattern: #"(?<![0-9])[A-Za-z_]\w*"#)

    // MARK: - Time factors

    /// The exact seconds factor of a time word via the UnitCatalog
    /// (pure time vector, linear factor), or nil when the word is not a
    /// resolvable time unit.
    public static func timeFactor(word: String) -> Double? {
        let w = word.lowercased()
        guard timeWords.contains(w) else { return nil }
        guard let p = UnitCatalog.resolveExpression(w) else { return nil }
        guard case .factor = p.unit.kind, p.unit.isLinear else { return nil }
        let v = p.unit.vector
        guard v.l == 0, v.m == 0, v.t != 0, v.a == 0, v.i == 0 else { return nil }
        return p.unit.toBase
    }

    // MARK: - Marker detection

    /// Every valid currency marker occurrence — the SHARED boundary
    /// grammar in `CurrencyPresentation` (prefix `Rp25000`/`$45`,
    /// postfix `240$`/`2.5K$`/`100zł`, doubled/malformed markers
    /// rejected, uppercase `K`/`M` compact suffixes included, `km$5`
    /// never a marker).
    static func markerOccurrences(in line: String) -> [NSRange] {
        CurrencyPresentation.markerOccurrences(in: line)
    }

    /// r53: an arithmetic expression shape — a digit or an operator.
    /// A line that references a money name is money-context only when
    /// it carries this shape; plain prose mentioning the name is not.
    /// MUST stay in sync with the `expressionLike` guard in
    /// `NamedValues.referencesTypedName` (the pipeline activation rule).
    static func isExpressionLike(_ line: String) -> Bool {
        line.unicodeScalars.contains {
            ("0123456789+-*/^%(".unicodeScalars.contains($0))
                || $0 == "×" || $0 == "÷"
        }
    }

    // MARK: - Named money assignment

    /// Validates a natural assignment LHS: bounded English words
    /// (ASCII letters, digits after the first, `_`), 1–6 words, total
    /// ≤ 40 chars, no digits-first word, no operators. Returns the
    /// trimmed display name or nil.
    static func naturalLHS(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count <= 40 else { return nil }
        guard s.range(of: #"[^A-Za-z_0-9 ]"#, options: .regularExpression) == nil else {
            return nil
        }
        let words = s.split(whereSeparator: { $0.isWhitespace })
        guard (1...6).contains(words.count) else { return nil }
        for w in words {
            guard w.count >= 1, w.count <= 24 else { return nil }
            guard let first = w.first, first.isLetter else { return nil }
            guard w.allSatisfy({ ($0.isLetter || $0.isNumber) && $0.isASCII || $0 == "_" }) else {
                return nil
            }
        }
        return words.joined(separator: " ")
    }

    /// The evaluated quantity of a named value.
    public enum AssignmentValue: Equatable {
        case money(value: Double, code: String)
        /// r83: the assigned scalar with its SEMANTIC kind (a percent/
        /// multiplier/fraction right-hand side propagates the kind into
        /// the environment and the displayed answer).
        case scalar(value: Double, kind: NumericKind, fraction: Rational?)
        /// r82: a boolean right-hand side (`flag = 2 < 3`).
        case bool(Bool)
        /// r82: a boolean-looking right-hand side the strict engine
        /// rejected — surfaced verbatim, never degraded to the
        /// numeric/money routes (a money name can never silently
        /// become the assignment's value in a boolean context).
        /// r85: an exact Int64 right-hand side (base literals, bitwise
        /// expressions, base converters) — the environment records the
        /// exact integer with its presentation radix.
        case intValue(value: Int64, radix: Int)
        case error(String)
        /// r84: a mixed-unit right-hand side (`x = 1 km + 2 km`).
        case quantity(Quantity)
    }

    /// A named assignment: `<name> = <money expression>` (and, for
    /// multiword names, `<name> = <scalar expression>`; r82: ANY
    /// grammar-valid LHS may also hold `<name> = <boolean expression>`).
    /// Returns the display name plus the evaluated quantity; nil when
    /// the line is not a natural assignment (or the right-hand side is
    /// malformed). The caller records the name in the environment.
    public static func tryAssignment(line: String, env: TypedEnv,
                                   context: NumberFormatContext = .legacy,
                                   rates: Rates = Rates(),
                                   unitContext: UnitContext = .builtIns,
                                   now: Date = Date(),
                                   calendar: Calendar = .current) -> (name: String, value: AssignmentValue)? {
        guard let split = BooleanLogic.assignmentSplit(line) else { return nil }
        let lhsRaw = split.lhs
        guard let name = naturalLHS(lhsRaw) else { return nil }
        let rhsRaw = split.rhs
        guard BooleanLogic.assignmentSplit(rhsRaw) == nil else { return nil }
        // r85: an exact integer right-hand side (radix literals,
        // bitwise expressions, base converters) records the EXACT
        // Int64 — never a Double projection.
        if IntegerLane.hasStrongTrigger(rhsRaw, env: env),
           let ir = IntegerLane.tryLine(rhsRaw, env: env, context: context, decimalPlaces: 10),
           case .integer(let v, let radix) = ir {
            return (name, .intValue(value: v, radix: radix))
        }
        // A money right-hand side is always recorded as money; a
        // cross-currency right-hand side the table cannot convert is an
        // explicit `Rates unavailable` value (never a scalar fallback).
        switch moneyOutcome(rhsRaw, env: env, context: context, rates: rates) {
        case .money(let v, let c):
            return (name, .money(value: v, code: c))
        case .ratesUnavailable:
            return (name, .error("Rates unavailable"))
        case .malformed, .none:
            break
        }
        // r83: a percentage phrase right-hand side (`x = 20% of 500`,
        // `x = 20/200 %`, `x = 1.5x`) records its semantic kind —
        // checked before the boolean stage so a phrase never degrades
        // to a boolean read (and the two grammars never overlap: a
        // boolean-looking line matches no phrase form).
        switch PercentageGrammar.percentOutcome(rhsRaw, env: env, context: context) {
        case .value(let r):
            switch r {
            case .number(let v, nil, let kind, let fraction):
                return (name, .scalar(value: v, kind: kind, fraction: fraction))
            case .money(let v, let code):
                return (name, .money(value: v, code: code))
            default:
                break
            }
        case .error(let m):
            return (name, .error(m))
        case .notPercent:
            break
        }
        // r84: a mixed-unit right-hand side (`x = 1 km + 2 km`,
        // `speed = 90 km / 3 day`) evaluates in the unit algebra and
        // records the quantity; a shape-owned right-hand side that
        // fails is a strict error.
        if MixedUnitLine.shape(rhsRaw, context: context, unitContext: unitContext, env: env,
                               now: now, calendar: calendar) {
            if let q = MixedUnitLine.evaluate(rhsRaw, env: env, context: context,
                                              rates: rates, unitContext: unitContext,
                                              now: now, calendar: calendar) {
                return (name, .quantity(q))
            }
            return (name, .error("Invalid expression"))
        }
        // r82: a boolean-looking right-hand side (explicit syntax, a
        // logical word, or a boolean name) is decided by the ONE
        // shared typed engine — conditional values included. A scalar
        // outcome records a scalar, a boolean outcome a real boolean,
        // and a REJECTED boolean-looking right-hand side errors
        // straight away: it never degrades to the numeric/money
        // routes (no silent money coercion).
        if BooleanLogic.isBoolLikely(rhsRaw, env: env) {
            if let r = BooleanLogic.branchValue(rhsRaw, env: env, context: context) {
                switch r {
                case .boolean(let b):
                    return (name, .bool(b))
                case .number(let v, nil, let kind, let fraction):
                    return (name, .scalar(value: v, kind: kind, fraction: fraction))
                default:
                    break
                }
            }
            return (name, .error("Invalid expression"))
        }
        // Multiword names may also hold plain (possibly named) scalars;
        // single identifiers keep the legacy assignment path.
        guard name.contains(" ") else { return nil }
        if let (v, codes) = evaluateNamedExpr(rhsRaw, env: env, context: context) {
            guard codes.count <= 1 else { return nil }
            if let c = codes.first {
                return (name, .money(value: v, code: c))
            }
            return (name, .scalar(value: v, kind: .plain, fraction: nil))
        }
        return nil
    }

    // MARK: - Money detection

    /// Detects and evaluates a natural money line against the typed
    /// environment (declared names resolve to their values).
    public static func tryMoney(line: String, env: TypedEnv,
                                   context: NumberFormatContext = .legacy,
                                   rates: Rates = Rates()) -> Outcome {
        if BooleanLogic.hasAssignment(line) { return .none }  // assignments own their `=`
        return moneyOutcome(line, env: env, context: context, rates: rates)
    }

    /// The money core. `.none` when the line is NOT money-looking (no
    /// valid marker/ISO annotation); `.malformed` when it IS
    /// money-looking but cannot complete (unknown words, uncancelled
    /// rates, currency ×/÷ currency, non-finite); `.ratesUnavailable`
    /// when a cross-currency pair is missing from the table. Callers
    /// turn `.malformed` into a hidden generic error and
    /// `.ratesUnavailable` into the explicit `Rates unavailable` state
    /// — never a number.
    static func moneyOutcome(_ line: String, env: TypedEnv,
                            context: NumberFormatContext = .legacy,
                            rates: Rates = Rates()) -> Outcome {
        guard let wordRe else { return .none }
        let ns = line as NSString

        // --- Every currency occurrence (shared scanner) ----------------
        // Symbol markers AND case-insensitive ISO annotations, each
        // canonical UPPERCASE with exact UTF-16 ranges. The source text
        // is never rewritten.
        let occurrences = CurrencyAnnotations.occurrences(in: line)
        let nameMatches = NamedValues.matches(in: line, env: env)
        var namedMoney: [(range: NSRange, value: Double, code: String)] = []
        for m in nameMatches {
            if case .money(let v, let c) = m.entry.qty, v.isFinite {
                namedMoney.append((m.range, v, c.uppercased()))
            }
        }

        // r53: a line can be money-context SOLELY because it references
        // a declared typed money name — even when no explicit marker/ISO
        // occurs on the line (`5 people × apple` after `apple = 5$`).
        // The derivation is expression-shaped (a digit or operator):
        // plain prose mentioning a money name stays prose, and the full
        // grammar below still has to complete for anything to evaluate.
        if occurrences.isEmpty {
            guard !namedMoney.isEmpty, isExpressionLike(line) else { return .none }
        }

        var codes = Set(occurrences.map(\.code))
        codes.formUnion(namedMoney.map(\.code))
        // The result anchor: the FIRST money operand in source order
        // (explicit or named) — never an unordered `Set.first`.
        guard let anchor = CurrencyArithmetic.anchor(
            occurrences: occurrences,
            namedMoney: namedMoney.map { (location: $0.range.location, code: $0.code) })
        else { return .none }

        // r47: a money line carrying a function call is REJECTED — a
        // currency must never be preserved through sqrt/log/... (no
        // implicit stripping, no currency conversion). Hidden generic
        // error, exactly like the other malformed money shapes.
        if FunctionCalls.hasCallHead(line) { return .malformed }

        // --- Cross-currency factors ------------------------------------
        // One code: legacy path (no conversion, no rates required).
        // Several codes: every operand converts into the anchor through
        // the supplied table; a missing pair is explicit.
        let mixed = codes.count > 1
        var factorsByCode: [String: Double] = [:]
        if mixed {
            guard let f = CurrencyArithmetic.factors(codes: codes, anchor: anchor,
                                                     rates: rates) else {
                return .ratesUnavailable
            }
            factorsByCode = f
        }
        var factorVars: [String: Double] = [:]
        var nextFactor = 0
        func factorName(for code: String) -> String {
            let name = "__fx\(nextFactor)"
            nextFactor += 1
            factorVars[name] = factorsByCode[code] ?? 1
            return name
        }

        // --- Clean the expression ---------------------------------------
        var cleaned = line
        if mixed {
            // Rewrite every annotated amount into an explicit conversion
            // product `(AMOUNT * factor)`, so the shared expression
            // engine keeps its exact precedence and the anchor stays the
            // numeric result's currency. The annotation text is removed;
            // the amount digits are never re-parsed.
            var edits: [(range: NSRange, text: String)] = []
            for o in occurrences {
                let start = CurrencyAnnotations.amountStart(in: line, amountEnd: o.amountEnd)
                guard start < o.amountEnd else { return .malformed }
                let name = factorName(for: o.code)
                edits.append((o.range, ""))                                  // drop the annotation
                edits.append((NSRange(location: start, length: 0), "("))
                edits.append((NSRange(location: o.amountEnd, length: 0), " * \(name))"))
            }
            for e in edits.sorted(by: { $0.range.location > $1.range.location }) {
                cleaned = (cleaned as NSString).replacingCharacters(in: e.range, with: e.text)
            }
        } else {
            // Legacy single-currency deletion: symbols and ISO codes are
            // removed in ONE descending pass (a two-phase deletion would
            // apply stale offsets after the first mutation).
            var deletions: [NSRange] = occurrences.filter { $0.shape == .symbolMarker }
                .map(\.range)
            for o in occurrences where o.shape == .isoCode {
                let loc = o.range.location > 0
                    && ns.character(at: o.range.location - 1) == 0x20
                    ? o.range.location - 1 : o.range.location
                let len = o.range.length + (loc == o.range.location ? 0 : 1)
                deletions.append(NSRange(location: loc, length: len))
            }
            for r in deletions.sorted(by: { $0.location > $1.location }) {
                cleaned = (cleaned as NSString).replacingCharacters(in: r, with: "")
            }
        }

        // --- Declared names resolve to their values ---------------------
        // Scalar entries stay usable under their display name; compound
        // names are substituted with tokenizer placeholders (a
        // multiword name can never be a single identifier token). In the
        // cross-currency path a money name also carries its own factor.
        var placeholderVars: [String: Double] = [:]
        for e in env.entries {
            switch e.qty {
            case .scalar(let v, _, _) where v.isFinite:
                placeholderVars[e.display] = v
            case .money(let v, _) where v.isFinite:
                placeholderVars[e.display] = v
            default:
                break
            }
        }
        let matches = NamedValues.matches(in: cleaned, env: env)
        var replacements: [Int: String] = [:]
        for (idx, m) in matches.enumerated() {
            let ph = namePlaceholder(idx)
            switch m.entry.qty {
            case .scalar(let v, _, _) where v.isFinite:
                placeholderVars[ph] = v
                replacements[idx] = ph
            case .money(let v, let c):
                let code = c.uppercased()
                guard mixed || code == anchor else { return .malformed }
                placeholderVars[ph] = v
                replacements[idx] = mixed ? "(\(ph) * \(factorName(for: code)))" : ph
            default:
                replacements[idx] = ph
            }
        }
        if !matches.isEmpty {
            var substituted = cleaned
            for (idx, m) in matches.enumerated().reversed() {
                substituted = (substituted as NSString)
                    .replacingCharacters(in: m.range, with: replacements[idx] ?? namePlaceholder(idx))
            }
            cleaned = substituted
        }

        // --- Typed time-rate expansion -----------------------------------
        var rateCount = 0
        var durationCount = 0
        cleaned = expandTimeRates(cleaned, rateCount: &rateCount,
                                  durationCount: &durationCount)
        guard rateCount == durationCount else { return .malformed }

        // Bounded prose stripping: neutral words drop, declared names
        // stay (already substituted), `of` (the percent infix) stays,
        // anything else malformed.
        var badWord = false
        let cleanedNS = cleaned as NSString
        for m in wordRe.matches(in: cleaned, range: NSRange(location: 0, length: cleanedNS.length))
            .reversed() {
            let word = cleanedNS.substring(with: m.range)
            let lower = word.lowercased()
            if neutralWords.contains(lower) {
                let loc = m.range.location > 0
                    && cleanedNS.character(at: m.range.location - 1) == 0x20
                    ? m.range.location - 1 : m.range.location
                let len = m.range.length + (loc == m.range.location ? 0 : 1)
                cleaned = (cleaned as NSString).replacingCharacters(
                    in: NSRange(location: loc, length: len), with: "")
            } else if lower == "of" || placeholderVars[word] != nil || factorVars[word] != nil {
                // A single-word MONEY name used on this line must agree
                // with the line's currency — unless the line is
                // cross-currency, where the name carries its own factor.
                if !mixed, case .money(_, let c)? = env.entry(display: word)?.qty,
                   c.caseInsensitiveCompare(anchor) != .orderedSame {
                    badWord = true
                    break
                }
                continue
            } else {
                badWord = true
                break
            }
        }
        if badWord { return .malformed }

        let trimmed = stripTerminalDot(cleaned).trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: #"\d"#, options: .regularExpression) != nil else {
            return .malformed
        }
        // Currency ×/÷ currency never silently squares a currency.
        if mixed, CurrencyArithmetic.hasCurrencyProductOrQuotient(trimmed) {
            return .malformed
        }

        var vars = placeholderVars
        vars.merge(factorVars) { _, new in new }
        do {
            let raw = try evaluateExpression(trimmed, variables: vars, context: context)
            guard raw.isFinite else { return .malformed }
            return .money(value: roundResult(raw, decimalPlaces: 10), code: anchor)
        } catch {
            return .malformed
        }
    }

    /// Rewrites the typed time-rate forms with exact catalog seconds
    /// factors: `per day` → `/ 86400`, `/ hr` → `/ 3600`,
    /// `30 days` → `(30 * 86400)`. Reports how many rates were opened
    /// and how many durations supplied (uncancelled ⇒ rejected).
    public static func expandTimeRates(_ input: String,
                                rateCount: inout Int,
                                durationCount: inout Int) -> String {
        var s = input
        // 1. `per <time>` (word boundary, case-insensitive).
        for w in timeWords.sorted(by: { $0.count > $1.count }) {
            guard let f = timeFactor(word: w), f.isFinite, f > 0 else { continue }
            let re = try? NSRegularExpression(
                pattern: "(?<![A-Za-z0-9_])per\\s+" + w + "(?![a-z0-9])",
                options: .caseInsensitive)
            guard let re else { continue }
            let full = NSRange(location: 0, length: (s as NSString).length)
            let hits = re.matches(in: s, range: full).count
            guard hits > 0 else { continue }
            s = re.stringByReplacingMatches(in: s, range: full,
                                            withTemplate: "/ \(literal(f))")
            rateCount += hits
        }
        // 2. `<time>` right after a slash: `$85 / hr`.
        for w in timeWords.sorted(by: { $0.count > $1.count }) {
            guard let f = timeFactor(word: w), f.isFinite, f > 0 else { continue }
            let re = try? NSRegularExpression(
                pattern: "/\\s*" + w + "(?![a-z0-9])", options: .caseInsensitive)
            guard let re else { continue }
            let full = NSRange(location: 0, length: (s as NSString).length)
            let hits = re.matches(in: s, range: full).count
            guard hits > 0 else { continue }
            s = re.stringByReplacingMatches(in: s, range: full,
                                            withTemplate: "/ \(literal(f))")
            rateCount += hits
        }
        // 3. `<number> <time>` durations.
        for w in timeWords.sorted(by: { $0.count > $1.count }) {
            guard let f = timeFactor(word: w), f.isFinite, f > 0 else { continue }
            let re = try? NSRegularExpression(
                pattern: "(\\d+(?:\\.\\d+)?)\\s+" + w + "(?![a-z0-9])",
                options: .caseInsensitive)
            guard let re else { continue }
            let full = NSRange(location: 0, length: (s as NSString).length)
            let hits = re.matches(in: s, range: full).count
            guard hits > 0 else { continue }
            s = re.stringByReplacingMatches(in: s, range: full,
                                            withTemplate: "($1 * \(literal(f)))")
            durationCount += hits
        }
        return s
    }

    private static func literal(_ f: Double) -> String {
        f.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(f)) : String(f)
    }

    /// A terminal prose period (a `.` at the very end, NOT a decimal
    /// dot: the previous character must not be a digit) is dropped for
    /// evaluation only — the source line is never rewritten.
    static func stripTerminalDot(_ s: String) -> String {
        guard let last = s.last, last == "." else { return s }
        guard let prev = s.dropLast().last else { return s }
        if (0x30...0x39).contains(prev.asciiValue ?? 0xFF) { return s }
        return String(s.dropLast())
    }

    /// Money-aware prose stripping for reference-token lines: the same
    /// bounded neutral-word list as `tryMoney`, applied only when the
    /// line is money-context (a currency marker, or the token quantity
    /// carrying a currency unit). Returns nil when a non-whitelisted
    /// word would survive (hidden error), or a RANGE-PRESERVING masked
    /// line otherwise.
    ///
    /// The mask REPLACES each neutral word with spaces of the same
    /// length instead of deleting it: the line keeps its exact UTF-16
    /// length, so every U+FFFC marker (and the caller's `location`
    /// map) stays at the same offset — prose BEFORE a marker can never
    /// shift the marker lookup.
    public static func stripTokenProse(
        line: String,
        variables: [String: Double],
        moneyContext: Bool
    ) -> String? {
        guard moneyContext, let wordRe else { return line }
        let ns = line as NSString
        var hasBadWord = false
        var chars = [unichar](repeating: 0, count: ns.length)
        for u in 0..<ns.length { chars[u] = ns.character(at: u) }
        // Currency annotations (symbols and case-insensitive ISO codes)
        // are GRAMMAR, not prose: a word inside one is never a bad word
        // (`TOKEN - 300 eur` must survive this pass untouched).
        let annotationRanges = CurrencyAnnotations.occurrences(in: line).map(\.range)
        for m in wordRe.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: m.range)
            if annotationRanges.contains(where: { m.range.location >= $0.location
                && NSMaxRange(m.range) <= NSMaxRange($0) }) { continue }
            let lower = word.lowercased()
            if neutralWords.contains(lower) {
                for u in m.range.location..<NSMaxRange(m.range) {
                    chars[u] = 0x20
                }
            } else if lower == "of" || variables[word] != nil {
                continue
            } else {
                hasBadWord = true
                break
            }
        }
        guard !hasBadWord else { return nil }
        return String(utf16CodeUnits: chars, count: chars.count)
    }

    /// Whether a token line is in money context: a currency marker is
    /// present, or the resolved token quantities carry currency units.
    public static func isMoneyContext(line: String, tokenUnits: [String?]) -> Bool {
        if !markerOccurrences(in: line).isEmpty { return true }
        let currencyUnits = tokenUnits.filter { unit in
            unit.map(isCurrencyCode) ?? false
        }
        guard !currencyUnits.isEmpty else { return false }
        return tokenUnits.allSatisfy { unit in
            unit == nil || isCurrencyCode(unit)
        }
    }
}

extension NaturalCalculation.AssignmentValue {
    /// The plain-scalar factory (pre-r83 call-site compatibility).
    public static func scalar(_ value: Double) -> NaturalCalculation.AssignmentValue {
        .scalar(value: value, kind: .plain, fraction: nil)
    }
}
