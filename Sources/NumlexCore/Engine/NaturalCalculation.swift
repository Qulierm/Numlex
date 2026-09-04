import Foundation

/// Typed natural-calculation detection for money lines.
///
/// Replaces the old blind word-stripping fallback for currency-looking
/// input: a line that carries a currency marker (a symbol adjacent to a
/// number, or an uppercase ISO code annotating a number) MUST parse as a
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
/// - one currency per line: a second, different currency is a hidden
///   error (`$10 + €5`);
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
    private static let isoAnnotationRe = try? NSRegularExpression(
        pattern: #"(?<=[0-9.])\s+([A-Z]{3})(?![A-Za-z0-9_])"#)

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
        case scalar(Double)
    }

    /// A named assignment: `<name> = <money expression>` (and, for
    /// multiword names, `<name> = <scalar expression>`). Returns the
    /// display name plus the evaluated quantity; nil when the line is
    /// not a natural assignment (or the right-hand side is malformed).
    /// The caller records the name in the environment.
    public static func tryAssignment(line: String, env: TypedEnv) -> (name: String, value: AssignmentValue)? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let lhsRaw = String(line[..<eq])
        guard let name = naturalLHS(lhsRaw) else { return nil }
        let rhsRaw = String(line[line.index(after: eq)...])
        guard !rhsRaw.contains("=") else { return nil }
        // A money right-hand side is always recorded as money.
        switch moneyOutcome(rhsRaw, env: env) {
        case .money(let v, let c):
            return (name, .money(value: v, code: c))
        case .malformed, .none:
            break
        }
        // Multiword names may also hold plain (possibly named) scalars;
        // single identifiers keep the legacy assignment path.
        guard name.contains(" ") else { return nil }
        if let (v, codes) = evaluateNamedExpr(rhsRaw, env: env) {
            guard codes.count <= 1 else { return nil }
            if let c = codes.first {
                return (name, .money(value: v, code: c))
            }
            return (name, .scalar(v))
        }
        return nil
    }

    // MARK: - Money detection

    /// Detects and evaluates a natural money line against the typed
    /// environment (declared names resolve to their values).
    public static func tryMoney(line: String, env: TypedEnv) -> Outcome {
        if line.contains("=") { return .none }  // assignments own their `=`
        return moneyOutcome(line, env: env)
    }

    /// The money core. `.none` when the line is NOT money-looking (no
    /// valid marker/ISO annotation); `.malformed` when it IS
    /// money-looking but cannot complete (mixed currencies, unknown
    /// words, uncancelled rates, non-finite) — the caller turns
    /// `.malformed` into a hidden generic error, never a number.
    static func moneyOutcome(_ line: String, env: TypedEnv) -> Outcome {
        guard let wordRe else { return .none }
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)

        // --- Locate currency markers (prefix AND postfix) --------------
        let symbolRanges = markerOccurrences(in: line)
        var codes: Set<String> = []
        for r in symbolRanges {
            let marker = ns.substring(with: r)
            if let code = CurrencyPresentation.code(forMarker: marker) {
                codes.insert(code)
            }
        }

        // --- ISO code annotations: `100 USD` ---------------------------
        var isoRanges: [NSRange] = []
        if codes.isEmpty, let isoRe = isoAnnotationRe {
            for m in isoRe.matches(in: line, range: full) where m.numberOfRanges >= 2 {
                let code = ns.substring(with: m.range(at: 1))
                guard FiatCurrencies.codes.contains(code) else { continue }
                codes.insert(code)
                isoRanges = [m.range(at: 1)]
                break
            }
        }

        // r53: a line can be money-context SOLELY because it references
        // a declared typed money name — even when no explicit marker/ISO
        // occurs on the line (`5 people × apple` after `apple = 5$`).
        // The derivation is expression-shaped (a digit or operator):
        // plain prose mentioning a money name stays prose, and the full
        // grammar below still has to complete for anything to evaluate.
        // Multiple names with DIFFERENT codes are malformed; one code
        // (or several names agreeing on it) opens the context. An
        // explicit marker/ISO plus a named money still must agree —
        // the same-currency checks below apply to both sources.
        if codes.isEmpty {
            guard isExpressionLike(line) else { return .none }
            var nameCodes: Set<String> = []
            for m in NamedValues.matches(in: line, env: env) {
                if case .money(_, let c) = m.entry.qty {
                    nameCodes.insert(c.uppercased())
                }
            }
            guard nameCodes.count == 1 else {
                return nameCodes.isEmpty ? .none : .malformed
            }
            codes = nameCodes
        }
        guard !codes.isEmpty else { return .none }
        // Two different currencies are never silently combined.
        guard codes.count == 1, let code = codes.first else { return .malformed }
        // r47: a money line carrying a function call is REJECTED — a
        // currency must never be preserved through sqrt/log/... (no
        // implicit stripping, no currency conversion). Hidden generic
        // error, exactly like the other malformed money shapes.
        if FunctionCalls.hasCallHead(line) { return .malformed }

        // --- Clean the expression ---------------------------------------
        var cleaned = line
        for r in symbolRanges.sorted(by: { $0.location > $1.location }) {
            cleaned = (cleaned as NSString).replacingCharacters(in: r, with: "")
        }
        if symbolRanges.isEmpty {
            for r in isoRanges.sorted(by: { $0.location > $1.location }) {
                let loc = r.location > 0
                    && (cleaned as NSString).character(at: r.location - 1) == 0x20
                    ? r.location - 1 : r.location
                let len = r.length + (loc == r.location ? 0 : 1)
                cleaned = (cleaned as NSString).replacingCharacters(
                    in: NSRange(location: loc, length: len), with: "")
            }
        }

        // --- Declared names resolve to their values ---------------------
        // Scalar entries stay usable under their display name; compound
        // names are substituted with tokenizer placeholders (a
        // multiword name can never be a single identifier token).
        var placeholderVars: [String: Double] = [:]
        for e in env.entries {
            switch e.qty {
            case .scalar(let v) where v.isFinite:
                placeholderVars[e.display] = v
            case .money(let v, _) where v.isFinite:
                // A single-word money name may appear as a plain word
                // in another money line; the word loop enforces the
                // same-currency rule for names the line actually uses.
                placeholderVars[e.display] = v
            default:
                break
            }
        }
        let matches = NamedValues.matches(in: cleaned, env: env)
        for (idx, m) in matches.enumerated() {
            switch m.entry.qty {
            case .scalar(let v) where v.isFinite:
                // r53: every match (scalar AND money) is substituted
                // with a placeholder below, so the placeholder itself
                // must carry the value — exactly like `strictExprCore`.
                placeholderVars[namePlaceholder(idx)] = v
            case .money(let v, let c):
                guard c.caseInsensitiveCompare(code) == .orderedSame else { return .malformed }
                placeholderVars[namePlaceholder(idx)] = v
            default:
                break
            }
        }
        if !matches.isEmpty {
            var substituted = cleaned
            for (idx, m) in matches.enumerated().reversed() {
                substituted = (substituted as NSString)
                    .replacingCharacters(in: m.range, with: namePlaceholder(idx))
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
            } else if lower == "of" || placeholderVars[word] != nil {
                // A single-word MONEY name used on this line must agree
                // with the line's currency.
                if case .money(_, let c)? = env.entry(display: word)?.qty,
                   c.caseInsensitiveCompare(code) != .orderedSame {
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

        do {
            let raw = try evaluateExpression(normalizeExprCorrect(trimmed),
                                             variables: placeholderVars)
            guard raw.isFinite else { return .malformed }
            return .money(value: roundResult(raw, decimalPlaces: 10), code: code)
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
        for m in wordRe.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: m.range)
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
