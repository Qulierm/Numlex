import Foundation

/// Range-aware syntax roles for notebook lines.
///
/// The classifier is strictly read-only: it reuses the shared typed
/// evaluator to learn how each line is treated, then projects spans
/// back onto the original text. It never mutates parser, evaluator or
/// tokenizer semantics. Every produced list is SANITIZED against the
/// line's UTF-16 length (zero-length, `NSNotFound` and out-of-bounds
/// ranges are dropped, ranges are sorted and no character is ever
/// styled twice), so a malformed range can never reach the text
/// storage.
public enum SyntaxRole: Equatable, Sendable {
    /// A numeric literal (including the leading value of a conversion).
    case number
    /// An operator glyph (`+`, `-`, `−`, `×`, `÷`, `*`, `/`, `=`) on a
    /// line the evaluator actually treats as math — canonical and
    /// accepted input alike, never the answer-token marker U+FFFC and
    /// never inside a unit expression (the unit span wins). `operator`
    /// is a Swift keyword, hence the `operatorGlyph` case name.
    case operatorGlyph
    /// A variable identifier — single or a whole multiword natural name.
    case variable
    /// A unit word of a conversion (the `to` keyword carries no role).
    case conversion
    /// One contextual syntax word (`to`, `in`, `per`, `as`) on a
    /// conversion/natural/money/date line only — never in prose or
    /// identifiers.
    case specifier
    /// A currency marker (`$`, `€`, `CA$`, ... or an ISO code on a
    /// money line).
    case moneyMarker
    /// The `#` marker character of a hash heading line.
    case hashMarker
    /// The heading body: every character after the `#` on the line.
    case hashBody
    /// A prose label line ending with `:` (evaluated as skip) — the
    /// whole trimmed line, e.g. `Total:`.
    case label
}

/// One classified span. `range` is a UTF-16 `NSRange` inside a single
/// logical line; callers add the line's document offset for whole-text
/// ranges. Operators, parentheses, `=`, signs, trailing dots and prose
/// carry no span and therefore keep the base (white/primary) color.
public struct SyntaxSpan: Equatable, Sendable {
    public let role: SyntaxRole
    public let range: NSRange
    public init(role: SyntaxRole, range: NSRange) {
        self.role = role
        self.range = range
    }
}

public enum SyntaxClassifier {

    /// Classifies every logical line of `source` (top to bottom with the
    /// same typed environment flow the evaluator uses) into role spans.
    ///
    /// Lines the evaluator treats as title, blank or skip (prose) carry
    /// no spans: prose must never be painted as variables. Error lines
    /// are classified lexically (numbers and known variables only).
    public static func spans(for source: String,
                             rates: Rates,
                             decimalPlaces: Int,
                             constants: [UserConstant] = [],
                             context: NumberFormatContext = .legacy,
                             unitContext: UnitContext = .builtIns,
                             financial: FinancialContext = .defaults) -> [[SyntaxSpan]] {
        var result: [[SyntaxSpan]] = []
        // ONE shared typed environment for the whole document — the same
        // flow `evaluateSheet` and the answer column use, so declared
        // money names stay visible to later lines on every edit tick.
        // r33: global constants are seeded first and paint `.variable`
        // (green) exactly like declared names.
        var env = TypedEnv()
        env.seedConstants(constants)
        for line in source.components(separatedBy: "\n") {
            let lineLength = (line as NSString).length
            // Mirror evaluateSheet's line-kind handling: empty and `//`
            // lines never carry token spans.
            if line.trimmingCharacters(in: .whitespaces).isEmpty
                || line.hasPrefix("//") {
                result.append([])
                continue
            }
            // Hash heading: the evaluator treats `#` lines as
            // non-evaluated blanks, but they carry explicit heading
            // spans — the single `#` marker and the whole body after it
            // (UTF-16 lengths via NSString, so surrogate pairs in the
            // body stay consistent with the text storage).
            if line.hasPrefix("#") {
                var heading: [SyntaxSpan] = [
                    SyntaxSpan(role: .hashMarker, range: NSRange(location: 0, length: 1))
                ]
                if lineLength > 1 {
                    heading.append(SyntaxSpan(
                        role: .hashBody,
                        range: NSRange(location: 1, length: lineLength - 1)
                    ))
                }
                result.append(heading)
                continue
            }
            // r55 amendment: a strict weather query paints ONLY the
            // city/place span with the existing unit role
            // (`.conversion` — the same palette custom Styling drives
            // for measurement units, never a new role or color).
            // The range comes from the shared parser (`placeRange` is
            // nil exactly when `parse` is nil), so highlight and eval
            // cannot drift; `in` takes the normal `.specifier` path
            // below and `weather` stays base text. Anything the parser
            // rejects (prose, incomplete, operators, emoji, comments,
            // token lines) falls through to the ordinary pipeline with
            // no unit paint. Weather never mutates the environment, so
            // skipping the evaluator call here changes no later line.
            if let cityRange = WeatherQuery.placeRange(in: line) {
                var weatherSpans: [SyntaxSpan] = [
                    SyntaxSpan(role: .conversion, range: cityRange)
                ]
                weatherSpans += specifierSpans(line)
                result.append(sanitize(weatherSpans, lineLength: lineLength))
                continue
            }
            let evaluation = evalLineTyped(line, env: &env,
                                           rates: rates, decimalPlaces: decimalPlaces,
                                           now: Date(), calendar: Calendar.current,
                                           unitContext: unitContext,
                                           financial: financial)
            let isNatural = lineIsNatural(line, env: env)
            var isMath = false
            let spans: [SyntaxSpan]
            switch evaluation {
            case nil:
                // Skip/prose: a trailing-colon label line keeps an
                // explicit label span; everything else keeps none.
                spans = labelSpans(line)
            case .number(_, .some, _, _):
                isMath = true
                // r84: a mixed-unit line paints its OWN token roles
                // (every quantity literal, unit word and operator) —
                // the conversion painter only understands the
                // single-value `N unit` shape.
                spans = PixelConversion.match(line, context: context,
                                              unitContext: unitContext, env: env) != nil
                        || DensityConversion.match(line, context: context,
                                                   unitContext: unitContext, env: env) != nil
                        || MixedUnitLine.shape(line, context: context,
                                              unitContext: unitContext, env: env)
                    ? mixedUnitSpans(line, context: context, unitContext: unitContext, env: env)
                    : conversionSpans(line, context: context)
            case .number(_, .none, _, _):
                isMath = true
                spans = isNatural
                    ? naturalSpans(line, env: env, context: context)
                    : BooleanLogic.booleanShape(line, env: env)
                        // r82: a conditional VALUE line (`if c then 1
                        // else 0`) evaluates to a number but is boolean
                        // syntax: it keeps the boolean palette (keyword
                        // specifiers, comparison operators, boolean
                        // names) instead of the lexical expression one.
                        ? booleanSpans(line, env: env, context: context)
                        : PercentageGrammar.percentShape(line, env: env)
                            // r83: a percentage phrase line (`15% of
                            // 490`, `100 is 50% of what`) keeps the
                            // phrase palette — live phrase keywords as
                            // specifiers, operands as numbers/variables.
                            ? percentageSpans(line, env: env, context: context)
                            : expressionSpans(line, variables: env.scalarDict(), context: context)
            case .variable(let name, _, _, _):
                isMath = true
                spans = isNatural || name.contains(" ")
                    ? naturalSpans(line, env: env, context: context)
                    : assignmentSpans(line, name: name, variables: env.scalarDict(), context: context)
            case .money:
                isMath = true
                spans = naturalSpans(line, env: env, context: context)
            case .integer, .variableInt:
                // r85: base rows render like ordinary expressions
                // (numbers incl. radix literals, operators) until the
                // dedicated base palette lands.
                isMath = true
                spans = expressionSpans(line, variables: env.scalarDict(), context: context)
            case .clock, .laptime:
                isMath = true
                spans = expressionSpans(line, variables: env.scalarDict(), context: context)
            case .location, .dms:
                // r85: geo/DMS rows take the geo palette (task-7
                // placeholder: specifier words + place spans).
                isMath = true
                spans = geoSpans(line, context: context)
            case .boolean:
                isMath = true
                spans = booleanSpans(line, env: env, context: context)
            case .date:
                isMath = true
                spans = dateSpans(line, context: context)
            case .dateTime, .timestamp:
                // temporal Task 2: timestamp/ISO rows paint numbers and
                // their specifier keywords (current, timestamp, iso8601,
                // to/in, date).
                isMath = true
                spans = timestampSpans(line, context: context)
            case .timecode, .frameCount:
                // temporal Task 4: timecode/frame rows paint their numbers
                // and fps/frames vocabulary.
                isMath = true
                spans = timestampSpans(line, context: context)
            case .blank, .skip, .title, .brokenToken:
                spans = []
            case .error:
                // A natural line that fails (uncancelled rate, partial
                // marker, unknown word) keeps its intentional palette;
                // everything else stays lexical (numbers and known
                // variables only).
                isMath = true
                spans = isNatural
                    ? naturalSpans(line, env: env, context: context)
                    : errorSpans(line, variables: env.scalarDict(), context: context)
            }
            // r21: operator glyphs and contextual syntax words are painted
            // ONLY on lines the evaluator treated as math (isMath — the
            // conversion/expression/natural/money/date/error cases above).
            // Prose/skip lines (label rows included) and the
            // comment/heading branches never receive them. Overlaps (e.g.
            // `/` inside a `km/h` unit span) are resolved by sanitize:
            // the longer/earlier unit span wins, so a unit expression is
            // never split by an operator color.
            var withGrammar = spans
            if isMath && !spans.isEmpty {
                withGrammar += operatorSpans(line)
                withGrammar += specifierSpans(line)
            }
            result.append(sanitize(withGrammar, lineLength: lineLength))
        }
        return result
    }

    // MARK: - Natural (money / named) lines

    /// Activation rule for the intentional natural palette: the line
    /// carries a currency marker, is a grammar-valid natural assignment
    /// (possibly incomplete while typing), references a declared
    /// compound name, or references a global constant (r33 — so a plain
    /// `PI` or `pi × 2` paints the constant name green through the
    /// same shared matcher).
    private static func lineIsNatural(_ line: String, env: TypedEnv) -> Bool {
        if !NaturalCalculation.markerOccurrences(in: line).isEmpty { return true }
        // An ISO-annotated line is money-shaped — unless it is a
        // conversion (`10 USD to RUB`), which keeps its dedicated
        // conversion palette exactly as before.
        if CurrencyAnnotations.hasAnnotation(in: line),
           conversionShape(line.trimmingCharacters(in: .whitespaces)) == nil {
            return true
        }
        // r82: the shared `=` recognizer — `==`, `!=`, `<=`, `>=`
        // comparison lines can never look like natural assignments.
        if let split = BooleanLogic.assignmentSplit(line) {
            let lhs = split.lhs
            guard NaturalCalculation.naturalLHS(lhs) != nil else { return false }
            let rhs = split.rhs
            if !NaturalCalculation.markerOccurrences(in: rhs).isEmpty { return true }
            if CurrencyAnnotations.hasAnnotation(in: rhs) { return true }
            // Incomplete marker while typing (`monthly rent = $`).
            if rhs.range(of: #"[$€£¥₽]"#, options: .regularExpression) != nil {
                return true
            }
            return false
        }
        return NamedValues.matches(in: line, env: env).contains {
            $0.entry.isConstant || !TypedEnv.isLegacyIdentifier($0.display)
        }
    }

    /// The intentional palette for natural money/named lines:
    /// - the WHOLE grammar-valid natural LHS is one variable (green)
    ///   span, whatever the words;
    /// - declared names (compound or money) are variables (green);
    /// - currency markers (symbols and ISO codes) are moneyMarker
    ///   (purple);
    /// - numeric literals — plain, decimal, grouped, scientific, with
    ///   the money `k`/`M` suffix — are numbers (cyan), classified ONCE
    ///   each by a single unified pattern;
    /// - time UNIT aliases (`day`, `days`, `hr`, `hrs`, `hours`, `weeks`,
    ///   ...) are conversion content; `per` is grammar prose and, like
    ///   `=`, operators, trailing dots and other prose, stays base
    ///   white.
    /// r73: the context-aware number span pattern (DISPLAY ONLY —
    /// highlighting, never evaluation). Legacy keeps the exact pre-r73
    /// strings; decimal-comma modes use the context's grouping set and
    /// the `,`/`.` decimal characters, decimal-point modes the
    /// context's grouping set and `.`.
    private static func numberPattern(_ context: NumberFormatContext) -> String {
        guard !context.legacy else {
            return #"(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+\.?\d*|\.\d+)"#
        }
        func esc(_ str: String) -> String {
            str.unicodeScalars.map { c -> String in
                "\\\\.\\[\\](){}*+?|^$-".unicodeScalars.contains(c)
                    ? "\\\(String(Character(c)))" : String(Character(c))
            }.joined()
        }
        var grps: [String] = []
        func add(_ str: String) { if !str.isEmpty { grps.append(esc(str)) } }
        add(context.groupingSeparator)
        context.inputGroupingSeparators.forEach(add)
        let g = grps.joined(separator: "|")
        if context.decimalComma {
            let groupBranch = grps.isEmpty ? "" : "(?:\\d{1,3}(?:[\(g)]\\d{3})+|"
            return "(?:(?:\(groupBranch)\\d+)(?:[,.]\\d+)?|\\d+[,.]|[,.]\\d+|\\.\\d+)"
        }
        let groupBranch = grps.isEmpty ? "" : "(?:\\d{1,3}(?:[\(g)]\\d{3})+|"
        return "(?:(?:\(groupBranch)\\d+)\\.?\\d*|\\.\\d+)"
    }

    /// The natural-line number variant (grouped | plain | leading-dot,
    /// optional decimal, optional scientific part, optional money
    /// suffix) — context-aware like `numberPattern`.
    private static func naturalNumberPattern(_ context: NumberFormatContext) -> String {
        guard !context.legacy else {
            return #"(?<![A-Za-z0-9_])(?:\d{1,3}(?:,\d{3})+|\d+|\.\d+)(?:\.\d+)?(?:[eE][+-]?\d+)?[kKmM]?(?![A-Za-z0-9_])"#
        }
        func esc(_ str: String) -> String {
            str.unicodeScalars.map { c -> String in
                "\\\\.\\[\\](){}*+?|^$-".unicodeScalars.contains(c)
                    ? "\\\(String(Character(c)))" : String(Character(c))
            }.joined()
        }
        var grps: [String] = []
        func add(_ str: String) { if !str.isEmpty { grps.append(esc(str)) } }
        add(context.groupingSeparator)
        context.inputGroupingSeparators.forEach(add)
        let g = grps.joined(separator: "|")
        let grpAlt = grps.isEmpty ? "" : "\\d{1,3}(?:[\(g)]\\d{3})+|"
        let dec = context.decimalComma ? "[,.]" : "\\."
        return "(?<![A-Za-z0-9_])(?:\(grpAlt)\\d+|\\.\\d+)(?:\(dec)\\d+)?(?:[eE][+-]?\\d+)?[kKmM]?(?![A-Za-z0-9_])"
    }

    private static func naturalSpans(_ line: String, env: TypedEnv, context: NumberFormatContext) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []

        // Whole natural LHS (grammar-valid), as one span. r82: the
        // shared `=` recognizer — a comparison line (`x == 5`) is
        // never a natural assignment, so no LHS span is painted.
        if let split = BooleanLogic.assignmentSplit(line) {
            let lhs = split.lhs
            if NaturalCalculation.naturalLHS(lhs) != nil {
                var end = (lhs as NSString).length
                var start = 0
                while start < end, ns.character(at: start) == 0x20 { start += 1 }
                while end > start, ns.character(at: end - 1) == 0x20 { end -= 1 }
                if end > start {
                    spans.append(SyntaxSpan(role: .variable,
                                            range: NSRange(location: start, length: end - start)))
                }
            }
        }
        // Declared names (compound or money) anywhere on the line.
        for m in NamedValues.matches(in: line, env: env) {
            spans.append(SyntaxSpan(role: .variable, range: m.range))
        }
        // Numbers: one unified pattern (grouped | plain | leading-dot),
        // optional decimal, optional scientific part, optional money
        // k/M suffix — each literal matches exactly once.
        for m in matches(Self.naturalNumberPattern(context), in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        // Currency markers: the SHARED boundary grammar (prefix and
        // postfix, doubled/malformed rejected) — letter markers like
        // `Rp`/`RM`/`zł`/`Kč` only tint at real marker positions,
        // never inside prose words.
        for r in CurrencyPresentation.markerOccurrences(in: line) {
            spans.append(SyntaxSpan(role: .moneyMarker, range: r))
        }
        // ISO codes annotate case-insensitively (`500 usd`): the ONE
        // shared scanner supplies the exact ranges, so highlight and
        // evaluation can never disagree. The source text is untouched.
        for o in CurrencyAnnotations.isoOccurrences(in: line) {
            spans.append(SyntaxSpan(role: .moneyMarker, range: o.range))
        }
        // Time UNIT aliases (singular and plural) are conversion
        // content; `per` is grammar prose and stays base white.
        for m in matches(
            #"\b(?:s|sec|secs|second|seconds|min|mins|minute|minutes|h|hr|hrs|hour|hours|day|days|wk|week|weeks)\b"#,
            in: ns) {
            spans.append(SyntaxSpan(role: .conversion, range: m))
        }
        return spans
    }

    // MARK: - Legacy span builders

    /// Conversion grammar: the leading number stays a number; the whole
    /// from-unit expression and the whole to-unit expression are each
    /// ONE conversion span (multi-word units like `US mpg`, slashed
    /// units like `km/h` and `N·m` stay unsplit); the `to` keyword
    /// carries no role.
    private static func conversionSpans(_ line: String, context: NumberFormatContext) -> [SyntaxSpan] {
        let ns = line as NSString
        // Leading-whitespace offset (the shape detector trims).
        var offset = 0
        while offset < ns.length {
            let c = ns.character(at: offset)
            if c == 0x20 || c == 0x09 { offset += 1 } else { break }
        }
        let trimmed = ns.substring(from: offset)
        if let shape = conversionShape(trimmed) {
            var spans: [SyntaxSpan] = []
            if let sym = shape.symbolRange {
                // The currency symbol source (`$`, `€`, `CA$`, ...) is
                // conversion content, not a numeric glyph.
                spans.append(SyntaxSpan(role: .conversion,
                                        range: NSRange(location: sym.location + offset,
                                                       length: sym.length)))
            }
            spans.append(SyntaxSpan(role: .number,
                                    range: NSRange(location: shape.numberRange.location + offset,
                                                   length: shape.numberRange.length)))
            if let from = shape.fromRange {
                spans.append(SyntaxSpan(role: .conversion,
                                        range: NSRange(location: from.location + offset,
                                                       length: from.length)))
            }
            spans.append(SyntaxSpan(role: .conversion,
                                    range: NSRange(location: shape.toRange.location + offset,
                                                   length: shape.toRange.length)))
            return spans
        }
        // Fallback for unit-bearing results without a plain shape (most
        // notably reference-token conversion lines): the numeric literal
        // is a number, every identifier after it (except `to`/`in`) is a
        // conversion word.
        var spans: [SyntaxSpan] = []
        var unitStart = 0
        if let m = firstMatch(Self.numberPattern(context), in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
            unitStart = m.location + m.length
        }
        for m in matches(#"[A-Za-z_]\w*"#, in: ns)
        where m.location >= unitStart
            && !["to", "in"].contains(ns.substring(with: m).lowercased()) {
            spans.append(SyntaxSpan(role: .conversion, range: m))
        }
        return spans
    }

    /// Date line: the day/year/duration numbers are numbers; duration
    /// unit words (`days`, `weeks`, ...) are conversion content; month
    /// names, `today`/`tomorrow`/`yesterday`, operators and signs stay
    /// base white.
    private static func dateSpans(_ line: String, context: NumberFormatContext) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []
        for m in matches(Self.numberPattern(context), in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        for m in matches(#"\b(?:days?|weeks?|months?|years?)\b"#, in: ns) {
            spans.append(SyntaxSpan(role: .conversion, range: m))
        }
        return spans
    }

    /// temporal Task 2: numbers plus the timestamp/ISO specifier words.
    private static func timestampSpans(_ line: String, context: NumberFormatContext) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []
        for m in matches(Self.numberPattern(context), in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        for m in matches(#"\b(?:current|timestamp|iso8601|to|in|date)\b"#, in: ns) {
            spans.append(SyntaxSpan(role: .conversion, range: m))
        }
        return spans
    }

    /// Lines that failed to evaluate (division by zero, partial
    /// expressions, unavailable-rate currency, ...): numeric literals
    /// are numbers, identifiers are variables only when the current
    /// variable state knows them. A line that still matches the
    /// conversion grammar (number, unit, `to`, unit) — typically an
    /// unavailable-rate currency — keeps the conversion treatment with
    /// the unit words and a base `to`. Purely lexical — no parser
    /// result is involved, so no unsafe range assumptions are made.
    private static func errorSpans(_ line: String,
                                   variables: [String: Double],
                                   context: NumberFormatContext) -> [SyntaxSpan] {
        let ns = line as NSString
        // Any conversion-shaped line (incompatible units, unknown units,
        // unavailable rates) keeps the conversion treatment: number plus
        // both unit expressions, base `to`.
        if conversionShape(line.trimmingCharacters(in: .whitespaces)) != nil {
            return conversionSpans(line, context: context)
        }
        var spans: [SyntaxSpan] = []
        // Partial assignment: a valid ASCII identifier directly before
        // the first `=` (leading whitespace allowed, exactly like the
        // evaluator's LHS parse) is a variable even without a valid
        // RHS — `hello =` paints `hello` on the same tick the `=` is
        // typed. Visual only: the evaluator still decides when the
        // variable is really set; a bare `hello` (no `=`) never reaches
        // here (it is .skip prose) and an invalid LHS (`2hello =`) does
        // not match the identifier pattern.
        let lhsRange = firstMatchGroup(#"^\s*([A-Za-z_]\w*)\s*="#, group: 1, in: ns)
        if let lhsRange {
            spans.append(SyntaxSpan(role: .variable, range: lhsRange))
        }
        for m in matches(Self.numberPattern(context), in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        for m in matches(#"[A-Za-z_]\w*"#, in: ns)
        where variables[ns.substring(with: m)] != nil && (lhsRange == nil || m != lhsRange)
        && !isBuiltinCallHead(at: m, in: ns) {
            spans.append(SyntaxSpan(role: .variable, range: m))
        }
        return spans
    }

    /// Free numeric expression: literals are numbers, identifiers are
    /// variables only when the current variable state knows them (the
    /// line evaluated to `.number`, so unknown words were never painted
    /// — prose lines never reach here at all).
    private static func expressionSpans(_ line: String,
                                        variables: [String: Double],
                                        context: NumberFormatContext) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []
        for m in matches(Self.numberPattern(context), in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        for m in matches(#"[A-Za-z_]\w*"#, in: ns)
        where variables[ns.substring(with: m)] != nil && !isBuiltinCallHead(at: m, in: ns) {
            spans.append(SyntaxSpan(role: .variable, range: m))
        }
        return spans
    }

    /// Assignment `name = expr`: the left-hand identifier is a variable;
    /// on the right side, literals are numbers and known identifiers are
    /// variables. The `=` and any unknown words stay base.
    private static func assignmentSpans(_ line: String,
                                        name: String,
                                        variables: [String: Double],
                                        context: NumberFormatContext) -> [SyntaxSpan] {
        let ns = line as NSString
        let eqRange = ns.range(of: "=")
        guard eqRange.location != NSNotFound else { return [] }
        var spans: [SyntaxSpan] = []
        // Left-hand name.
        for m in matches(#"[A-Za-z_]\w*"#, in: ns) where m.location < eqRange.location {
            spans.append(SyntaxSpan(role: .variable, range: m))
        }
        // Right-hand expression.
        for m in matches(Self.numberPattern(context), in: ns)
        where m.location > eqRange.location {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        for m in matches(#"[A-Za-z_]\w*"#, in: ns)
        where m.location > eqRange.location && variables[ns.substring(with: m)] != nil
        && !isBuiltinCallHead(at: m, in: ns) {
            spans.append(SyntaxSpan(role: .variable, range: m))
        }
        return spans
    }

    /// r47: whether the identifier at `range` is a KNOWN builtin in
    /// call position (optional whitespace then `(`). Such a name is
    /// grammar, not a variable reference — it stays base text even
    /// when a same-named variable or constant exists (the builtin wins
    /// at the call head, so painting it green would mislead).
    private static func isBuiltinCallHead(at range: NSRange, in ns: NSString) -> Bool {
        guard MathFunctions.isKnown(ns.substring(with: range)) else { return false }
        var k = NSMaxRange(range)
        while k < ns.length, ns.character(at: k) == 0x20 { k += 1 }
        return k < ns.length && ns.character(at: k) == 0x28
    }

    // MARK: - r21 grammar spans (operators, specifiers, labels)

    /// Operators on one math-classified line: canonical (`+`, `-`, `−`,
    /// `×`, `÷`, `=`) and accepted input (`*`, `/`) glyph runs. The
    /// answer-token marker U+FFFC is not an operator character and can
    /// never match; unit-span overlaps are resolved by `sanitize`
    /// (the unit spans win).
    private static func operatorSpans(_ line: String) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []
        // r82: the comparison/logical glyphs are operator-color too —
        // `==`, `<=`, `&&` and friends match as single contiguous
        // runs. Prose lines never reach this helper (isMath gate).
        for m in matches(#"[+\-−×÷*/=!<>&|]+"#, in: ns) {
            spans.append(SyntaxSpan(role: .operatorGlyph, range: m))
        }
        return spans
    }

    /// r82: the boolean palette. Numeric literals take the number role;
    /// declared BOOLEAN names (single or multiword) take the variable
    /// role through the shared matcher (so highlighting and evaluation
    /// cannot drift); the keyword/literal words — `true`, `false`,
    /// `and`, `or`, `not`, `if`, `then`, `else` — take the existing
    /// specifier role, UNLESS an active variable/constant carries that
    /// name (keyword compatibility). Comparison/logical glyphs are
    /// painted by `operatorSpans` on the shared isMath path.
    private static func booleanSpans(_ line: String,
                                     env: TypedEnv,
                                     context: NumberFormatContext) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []
        for m in matches(Self.numberPattern(context), in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        for m in NamedValues.matches(in: line, env: env) {
            guard case .bool = m.entry.qty else { continue }
            spans.append(SyntaxSpan(role: .variable, range: m.range))
        }
        let keywordPattern = "(?<![A-Za-z0-9_])(?:true|false|and|or|not|if|then|else)(?![A-Za-z0-9_])"
        for m in matches(keywordPattern, in: ns) {
            let word = ns.substring(with: m).lowercased()
            // An active variable/constant named like a keyword wins.
            if env.entries.contains(where: {
                canonicalNameKey($0.display) == canonicalNameKey(word)
            }) {
                continue
            }
            spans.append(SyntaxSpan(role: .specifier, range: m))
        }
        return spans
    }

    /// r83: a percentage phrase line (`15% of 490`, `100 is 50% of
    /// what`, `2/10 as fraction`, `10 to 15 as x`): operand literals
    /// (numbers, fractions, the glued `%`, currency amounts) keep the
    /// number role; declared named operands (compound and single
    /// identifiers) keep the variable role; the LIVE phrase keywords
    /// take the specifier role. Active variables named like keywords
    /// keep the variable read; a suffix `x` glued to a literal (`1.5x`)
    /// is not a keyword; the `%`/operator glyphs stay base — the same
    /// convention as the boolean palette.
    private static func percentageSpans(_ line: String,
                                        env: TypedEnv,
                                        context: NumberFormatContext) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []
        for m in matches(Self.numberPattern(context), in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        // Money operand runs: a shared currency marker glued (or
        // one-spaced) in front of an amount (`$500`, `€1,200`).
        func esc(_ str: String) -> String {
            str.unicodeScalars.map { c -> String in
                "\\.\\[\\](){}*+?|^$-".unicodeScalars.contains(c)
                    ? "\\\(String(Character(c)))" : String(Character(c))
            }.joined()
        }
        let markerAlt = CurrencyPresentation.orderedMarkers
            .sorted { $0.count > $1.count }
            .map(esc)
            .joined(separator: "|")
        if !markerAlt.isEmpty {
            let moneyPattern = "(?:\(markerAlt))\\s*(?:\(Self.numberPattern(context)))"
            for m in matches(moneyPattern, in: ns) {
                spans.append(SyntaxSpan(role: .number, range: m))
            }
        }
        // Declared named operands: compound names through the shared
        // matcher, single identifiers through the environment.
        for m in NamedValues.matches(in: line, env: env) {
            spans.append(SyntaxSpan(role: .variable, range: m.range))
        }
        for m in matches(#"[A-Za-z_]\w*"#, in: ns)
        where env.entry(display: ns.substring(with: m)) != nil {
            spans.append(SyntaxSpan(role: .variable, range: m))
        }
        // The phrase keywords, whole-word and case-insensitive, live in
        // the environment (an `of = 5` assignment keeps its variable
        // read); a suffix `x` after a literal is excluded by the
        // lookbehind.
        let keywordPattern = "(?i)(?<![A-Za-z0-9_])(?:of|on|off|is|what|as|a|to|percent|percentage|fraction|x|multiple|multiplier|if)(?![A-Za-z0-9_])"
        for m in matches(keywordPattern, in: ns) {
            let word = ns.substring(with: m).lowercased()
            guard PercentageGrammar.keywordLive(word, env: env) else { continue }
            spans.append(SyntaxSpan(role: .specifier, range: m))
        }
        return spans
    }

    /// Contextual syntax words on a conversion/natural/money/date line:
    /// standalone `to`, `in`, `per`, `as` (case-insensitive, whole-word).
    /// Callers only add these to lines the evaluator already classified
    /// as math, so prose and identifiers never match.
    private static func specifierSpans(_ line: String) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []
        for m in matches(#"(?i)\b(?:to|in|per|as)\b"#, in: ns) {
            spans.append(SyntaxSpan(role: .specifier, range: m))
        }
        return spans
    }

    /// A skip/prose label line ending with `:` — the whole trimmed line
    /// is one label span (`Total:`). Prose without the trailing colon,
    /// comment/heading prefixes (handled earlier) and evaluated lines
    /// never become labels.
    private static func labelSpans(_ line: String) -> [SyntaxSpan] {
        let ns = line as NSString
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.hasSuffix(":") else { return [] }
        let start = ns.range(of: trimmed).location
        guard start != NSNotFound else { return [] }
        return [SyntaxSpan(role: .label,
                           range: NSRange(location: start, length: (trimmed as NSString).length))]
    }

    // MARK: - Sanitizing

    /// Defensive projection of a span list against a real document line:
    /// drops zero-length, `NSNotFound` and out-of-bounds ranges, sorts
    /// deterministically (location ascending, length descending) and
    /// resolves overlaps so no character is styled twice. Whatever the
    /// input, the output is a list of valid, disjoint UTF-16 ranges
    /// inside `[0, lineLength]`.
    public static func sanitize(_ spans: [SyntaxSpan], lineLength: Int) -> [SyntaxSpan] {
        guard lineLength > 0 else { return [] }
        let valid = spans.filter { s in
            s.range.location >= 0
                && s.range.location != NSNotFound
                && s.range.length > 0
                && NSMaxRange(s.range) <= lineLength
        }
        let sorted = valid.sorted {
            ($0.range.location, -$0.range.length) < ($1.range.location, -$1.range.length)
        }
        var used = [Bool](repeating: false, count: lineLength)
        var out: [SyntaxSpan] = []
        for s in sorted {
            var loc = s.range.location
            var end = NSMaxRange(s.range)
            while loc < end && used[loc] { loc += 1 }
            while end > loc && used[end - 1] { end -= 1 }
            if end <= loc { continue }
            for i in loc..<end { used[i] = true }
            out.append(SyntaxSpan(role: s.role,
                                  range: NSRange(location: loc, length: end - loc)))
        }
        return out
    }

    // MARK: - Regex helpers (UTF-16 ranges via NSString)

    private static func matches(_ pattern: String, in ns: NSString) -> [NSRange] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let full = NSRange(location: 0, length: ns.length)
        return re.matches(in: ns as String, range: full).map(\.range)
    }

    private static func firstMatch(_ pattern: String, in ns: NSString) -> NSRange? {
        matches(pattern, in: ns).first
    }

    /// The range of a capture group of the first match (UTF-16 offsets).
    private static func firstMatchGroup(_ pattern: String, group: Int = 1,
                                        in ns: NSString) -> NSRange? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let full = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: ns as String, range: full),
              m.numberOfRanges > group else { return nil }
        let g = m.range(at: group)
        return g.location == NSNotFound ? nil : g
    }

    // MARK: - Mixed-unit spans (r84)

    /// The r84 token-role painting for a mixed-unit line: quantity
    /// numbers paint `.number`, their unit words `.conversion` (the
    /// same role weather and unit conversions paint), operators
    /// `.operator`, and named word operands `.variable`.
    static func mixedUnitSpans(_ line: String, context: NumberFormatContext,
                               unitContext: UnitContext, env: TypedEnv) -> [SyntaxSpan] {
        guard let tokens = MixedUnitScanner.tokenize(line, context: context,
                                                     unitContext: unitContext, env: env)
        else { return [] }
        var spans: [SyntaxSpan] = []
        for t in tokens {
            switch t {
            case .quantity(let q, range: let r):
                // The literal paints as number + unit sub-spans (the
                // legacy conversion painter's exact role layout).
                if !q.display.label.isEmpty {
                    let u = unitRange(of: q, in: line, tokenRange: r)
                    // The number span stops BEFORE the space that
                    // separates number and unit (`10 km` -> `10`).
                    var numberEnd = u.location - r.location
                    if numberEnd > 0,
                       (line as NSString).character(at: u.location - 1) == 32 {
                        numberEnd -= 1
                    }
                    if numberEnd > 0 {
                        spans.append(SyntaxSpan(role: .number,
                            range: NSRange(location: r.location, length: numberEnd)))
                    }
                    if u.length > 0 {
                        spans.append(SyntaxSpan(role: .conversion, range: u))
                    }
                } else {
                    spans.append(SyntaxSpan(role: .number, range: r))
                }
            case .number(_, range: let r):
                spans.append(SyntaxSpan(role: .number, range: r))
            case .unit(let u, range: let r):
                // The unit WORD inside the token's span.
                let wordStart = r.location + max(0, r.length - u.label.count)
                spans.append(SyntaxSpan(role: .conversion,
                                        range: NSRange(location: wordStart,
                                                       length: u.label.count)))
            case .op(_, range: let r):
                spans.append(SyntaxSpan(role: .operatorGlyph, range: r))
            case .paren(_, range: let r):
                spans.append(SyntaxSpan(role: .operatorGlyph, range: r))
            case .word(let w, range: let r):
                if w == "to" || w == "in" || w == "as" {
                    // The target keyword keeps the conversion role.
                    spans.append(SyntaxSpan(role: .specifier, range: r))
                } else if w.lowercased() == "per" {
                    // `per` is UNIT grammar in this painter (the spelled
                    // division inside a unit expression), so it takes the
                    // unit role and never the arithmetic operator colour.
                    spans.append(SyntaxSpan(role: .conversion, range: r))
                } else if env.entry(display: w) != nil {
                    // A known name is a variable.
                    spans.append(SyntaxSpan(role: .variable, range: r))
                }
            case .percent(range: let r):
                spans.append(SyntaxSpan(role: .operatorGlyph, range: r))
            }
        }
        return spans
    }

    // MARK: - r85: base / geo palette

    /// The r85 palette for base (integer) and geography rows. Base
    /// rows: radix literals (`0x…`, `0b…`, `0o…`) as numbers, bitwise
    /// glyphs (`&`, `|`, `<<`, `>>`) and the word operators `xor` (and
    /// `and`/`or` only when numeric math actually neighbors them) as
    /// operators, ordinary numbers and known names through the
    /// expression path. Geo rows: the query keywords (`location of`,
    /// `latitude of`, `longitude of`, `distance between`, `as DMS`,
    /// `as decimal`) as specifiers, quoted place names and DMS/degree
    /// numbers as their roles. Deterministic.
    private static func geoSpans(_ line: String, context: NumberFormatContext) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []
        let lower = line.lowercased()
        let isGeoLine = lower.contains("location of") || lower.contains("latitude of")
            || lower.contains("longitude of") || lower.contains("distance between")
            || lower.contains(" as dms") || lower.contains(" as decimal")
        // Radix literals are numbers.
        let radixSpans = matches(#"\b0[xbo][0-9a-zA-Z]*[0-9a-zA-Z]?"#, in: ns)
            .map { SyntaxSpan(role: .number, range: $0) }
        spans.append(contentsOf: radixSpans)
        // Bitwise glyphs are operators.
        for m in matches("<<<|>>>|&|\\|", in: ns) {
            // `<<`/`>>` first: the alternation prefers the longest at
            // each position via the scan.
            spans.append(SyntaxSpan(role: .operatorGlyph, range: m))
        }
        // Word operators: `xor` always (it is a base word); `and`/`or`
        // only when a number actually neighbors the word on both sides.
        for m in matches(#"\b(xor|and|or)\b"#, in: ns) {
            let w = ns.substring(with: m)
            if w == "xor" || wordHasMathNeighbors(line: line, range: m) {
                spans.append(SyntaxSpan(role: .operatorGlyph, range: m))
            }
        }
        // Ordinary numbers (and degree/DMS numbers) and known names.
        for sp in expressionSpans(line, variables: [:], context: context) {
            if sp.role == .number {
                let extended = extendOverDegreeGlyphs(sp.range, in: line)
                guard !spans.contains(where: { overlaps($0.range, extended) }) else { continue }
                spans.append(SyntaxSpan(role: .number, range: extended))
            }
        }
        guard isGeoLine else { return spans }
        // Geo keywords are specifiers.
        let keywords = ["location of", "latitude of", "longitude of",
                        "distance between", "as dms", "as decimal"]
        for kw in keywords {
            var from = 0
            while true {
                let r = ns.range(of: kw, options: [.caseInsensitive],
                                 range: NSRange(location: from, length: ns.length - from))
                if r.location == NSNotFound { break }
                if quoteParityZero(line, before: r.location) {
                    spans.append(SyntaxSpan(role: .specifier, range: r))
                }
                from = r.location + r.length
            }
        }
        // Quoted place names are conversion spans.
        var from = 0
        while true {
            let r = ns.range(of: "\"", range: NSRange(location: from, length: ns.length - from))
            if r.location == NSNotFound { break }
            let r2 = ns.range(of: "\"",
                              range: NSRange(location: r.location + 1,
                                             length: ns.length - r.location - 1))
            if r2.location == NSNotFound { break }
            let inner = NSRange(location: r.location + 1, length: r2.location - r.location - 1)
            spans.append(SyntaxSpan(role: .conversion, range: inner))
            from = r2.location + 1
        }
        return spans
    }

    /// `true` when a number (digit, `0x…`, `(`, `.`) touches the word
    /// at `range` on both sides — the `and`/`or` operator test.
    private static func wordHasMathNeighbors(line: String, range: NSRange) -> Bool {
        let ns = line as NSString
        func isMathChar(_ c: UInt16) -> Bool {
            (c >= 48 && c <= 57) || c == 40 || c == 41 || c == 46
                || c == 120 // x (hex digit / 0x prefix)
        }
        let before = range.location > 0
            ? ns.character(at: range.location - 1) : 0
        let afterIdx = range.location + range.length
        let after = afterIdx < ns.length ? ns.character(at: afterIdx) : 0
        return isMathChar(before) && isMathChar(after)
    }

    private static func overlaps(_ a: NSRange, _ b: NSRange) -> Bool {
        let aEnd = a.location + a.length
        let bEnd = b.location + b.length
        return a.location < bEnd && b.location < aEnd
    }

    /// Grows a number span to cover a directly-attached degree/prime
    /// glyph (`48.8566°`, `31.2″`).
    private static func extendOverDegreeGlyphs(_ r: NSRange, in line: String) -> NSRange {
        let ns = line as NSString
        var end = r.location + r.length
        while end < ns.length {
            let c = ns.character(at: end)
            if c == 0x00B0 || c == 0x2032 || c == 0x2033 { end += 1 } else { break }
        }
        return NSRange(location: r.location, length: end - r.location)
    }

    /// Whether the character at `before` is outside any double quote
    /// pair (even quote count before it).
    private static func quoteParityZero(_ s: String, before: Int) -> Bool {
        var q = 0
        let chars = Array(s)
        for i in 0..<min(before, chars.count) where chars[i] == "\u{0022}" { q += 1 }
        return q % 2 == 0
    }

    /// The unit-word range inside a quantity literal's NSRange (the
    /// scanner's span may include one trailing whitespace character).
    static func unitRange(of q: Quantity, in line: String,
                          tokenRange r: NSRange) -> NSRange {
        let ns = line as NSString
        let start = r.location
        var i = r.location + r.length
        while i > start, ns.character(at: i - 1) == 32 {
            i -= 1
        }
        if !q.display.label.isEmpty, i - q.display.label.count >= start,
           ns.substring(with: NSRange(location: i - q.display.label.count,
                                      length: q.display.label.count))
            .caseInsensitiveCompare(q.display.label) == .orderedSame {
            return NSRange(location: i - q.display.label.count,
                           length: q.display.label.count)
        }
        // The canonical label is not literally present (a natural `km per
        // hour` literal, or a rate whose label was derived): the unit part is
        // everything after the leading numeric run and the space that
        // separates it, so the WHOLE natural unit span is painted.
        var numberEnd = start
        while numberEnd < i {
            let c = ns.character(at: numberEnd)
            if (0x30...0x39).contains(c) || c == 0x2E || c == 0x2C {
                numberEnd += 1
            } else {
                break
            }
        }
        if numberEnd < i, ns.character(at: numberEnd) == 32 {
            numberEnd += 1
        }
        guard numberEnd < i else {
            return NSRange(location: r.location + r.length, length: 0)
        }
        return NSRange(location: numberEnd, length: i - numberEnd)
    }
}
