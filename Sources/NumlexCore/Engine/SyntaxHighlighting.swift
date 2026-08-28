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
                             decimalPlaces: Int) -> [[SyntaxSpan]] {
        var result: [[SyntaxSpan]] = []
        // ONE shared typed environment for the whole document — the same
        // flow `evaluateSheet` and the answer column use, so declared
        // money names stay visible to later lines on every edit tick.
        var env = TypedEnv()
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
            let evaluation = evalLineTyped(line, env: &env,
                                           rates: rates, decimalPlaces: decimalPlaces,
                                           now: Date(), calendar: Calendar.current)
            let isNatural = lineIsNatural(line, env: env)
            var isMath = false
            let spans: [SyntaxSpan]
            switch evaluation {
            case nil:
                // Skip/prose: a trailing-colon label line keeps an
                // explicit label span; everything else keeps none.
                spans = labelSpans(line)
            case .number(_, .some):
                isMath = true
                spans = conversionSpans(line)
            case .number(_, .none):
                isMath = true
                spans = isNatural
                    ? naturalSpans(line, env: env)
                    : expressionSpans(line, variables: env.scalarDict())
            case .variable(let name, _):
                isMath = true
                spans = isNatural || name.contains(" ")
                    ? naturalSpans(line, env: env)
                    : assignmentSpans(line, name: name, variables: env.scalarDict())
            case .money:
                isMath = true
                spans = naturalSpans(line, env: env)
            case .date:
                isMath = true
                spans = dateSpans(line)
            case .blank, .skip, .title, .brokenToken:
                spans = []
            case .error:
                // A natural line that fails (uncancelled rate, partial
                // marker, unknown word) keeps its intentional palette;
                // everything else stays lexical (numbers and known
                // variables only).
                isMath = true
                spans = isNatural
                    ? naturalSpans(line, env: env)
                    : errorSpans(line, variables: env.scalarDict())
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
    /// (possibly incomplete while typing), or references a declared
    /// compound name.
    private static func lineIsNatural(_ line: String, env: TypedEnv) -> Bool {
        if !NaturalCalculation.markerOccurrences(in: line).isEmpty { return true }
        if line.contains("=") {
            guard let eq = line.firstIndex(of: "=") else { return false }
            let lhs = String(line[..<eq])
            guard NaturalCalculation.naturalLHS(lhs) != nil else { return false }
            let rhs = String(line[line.index(after: eq)...])
            if !NaturalCalculation.markerOccurrences(in: rhs).isEmpty { return true }
            if rhs.range(of: #"\d\s+[A-Z]{3}\b"#, options: .regularExpression) != nil {
                return true
            }
            // Incomplete marker while typing (`monthly rent = $`).
            if rhs.range(of: #"[$€£¥₽]"#, options: .regularExpression) != nil {
                return true
            }
            return false
        }
        return NamedValues.matches(in: line, env: env).contains {
            !TypedEnv.isLegacyIdentifier($0.display)
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
    private static func naturalSpans(_ line: String, env: TypedEnv) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []

        // Whole natural LHS (grammar-valid), as one span.
        if let eq = line.firstIndex(of: "=") {
            let lhs = String(line[..<eq])
            if NaturalCalculation.naturalLHS(lhs) != nil {
                var end = eq.utf16Offset(in: line)
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
        for m in matches(
            #"(?<![A-Za-z0-9_])(?:\d{1,3}(?:,\d{3})+|\d+|\.\d+)(?:\.\d+)?(?:[eE][+-]?\d+)?[kKmM]?(?![A-Za-z0-9_])"#,
            in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        // Currency markers: the SHARED boundary grammar (prefix and
        // postfix, doubled/malformed rejected) — letter markers like
        // `Rp`/`RM`/`zł`/`Kč` only tint at real marker positions,
        // never inside prose words.
        for r in CurrencyPresentation.markerOccurrences(in: line) {
            spans.append(SyntaxSpan(role: .moneyMarker, range: r))
        }
        for m in matches(#"\b[A-Z]{3}\b"#, in: ns) where isCurrencyCode(ns.substring(with: m)) {
            spans.append(SyntaxSpan(role: .moneyMarker, range: m))
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
    private static func conversionSpans(_ line: String) -> [SyntaxSpan] {
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
        if let m = firstMatch(#"(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+\.?\d*|\.\d+)"#,
                              in: ns) {
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
    private static func dateSpans(_ line: String) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []
        for m in matches(#"(?:\d{1,3}(?:,\d{3})+|\d+\.?\d*|\.\d+)"#, in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        for m in matches(#"\b(?:days?|weeks?|months?|years?)\b"#, in: ns) {
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
                                   variables: [String: Double]) -> [SyntaxSpan] {
        let ns = line as NSString
        // Any conversion-shaped line (incompatible units, unknown units,
        // unavailable rates) keeps the conversion treatment: number plus
        // both unit expressions, base `to`.
        if conversionShape(line.trimmingCharacters(in: .whitespaces)) != nil {
            return conversionSpans(line)
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
        for m in matches(#"(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+\.?\d*|\.\d+)"#, in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        for m in matches(#"[A-Za-z_]\w*"#, in: ns)
        where variables[ns.substring(with: m)] != nil && (lhsRange == nil || m != lhsRange) {
            spans.append(SyntaxSpan(role: .variable, range: m))
        }
        return spans
    }

    /// Free numeric expression: literals are numbers, identifiers are
    /// variables only when the current variable state knows them (the
    /// line evaluated to `.number`, so unknown words were never painted
    /// — prose lines never reach here at all).
    private static func expressionSpans(_ line: String,
                                        variables: [String: Double]) -> [SyntaxSpan] {
        let ns = line as NSString
        var spans: [SyntaxSpan] = []
        for m in matches(#"(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+\.?\d*|\.\d+)"#, in: ns) {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        for m in matches(#"[A-Za-z_]\w*"#, in: ns) where variables[ns.substring(with: m)] != nil {
            spans.append(SyntaxSpan(role: .variable, range: m))
        }
        return spans
    }

    /// Assignment `name = expr`: the left-hand identifier is a variable;
    /// on the right side, literals are numbers and known identifiers are
    /// variables. The `=` and any unknown words stay base.
    private static func assignmentSpans(_ line: String,
                                        name: String,
                                        variables: [String: Double]) -> [SyntaxSpan] {
        let ns = line as NSString
        let eqRange = ns.range(of: "=")
        guard eqRange.location != NSNotFound else { return [] }
        var spans: [SyntaxSpan] = []
        // Left-hand name.
        for m in matches(#"[A-Za-z_]\w*"#, in: ns) where m.location < eqRange.location {
            spans.append(SyntaxSpan(role: .variable, range: m))
        }
        // Right-hand expression.
        for m in matches(#"(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+\.?\d*|\.\d+)"#, in: ns)
        where m.location > eqRange.location {
            spans.append(SyntaxSpan(role: .number, range: m))
        }
        for m in matches(#"[A-Za-z_]\w*"#, in: ns)
        where m.location > eqRange.location && variables[ns.substring(with: m)] != nil {
            spans.append(SyntaxSpan(role: .variable, range: m))
        }
        return spans
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
        for m in matches(#"[+\-−×÷*/=]+"#, in: ns) {
            spans.append(SyntaxSpan(role: .operatorGlyph, range: m))
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
}
