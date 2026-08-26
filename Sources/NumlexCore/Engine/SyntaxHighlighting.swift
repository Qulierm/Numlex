import Foundation

/// Range-aware syntax roles for notebook lines.
///
/// The classifier is strictly read-only: it reuses the existing evaluator
/// (`evalLine`) to learn how each line is treated, then projects token
/// spans back onto the original text. It never mutates parser, evaluator
/// or tokenizer semantics.
public enum SyntaxRole: Equatable, Sendable {
    /// A numeric literal (including the leading value of a conversion).
    case number
    /// A variable identifier in an evaluable number/variable expression.
    case variable
    /// A unit word of a conversion (the `to` keyword carries no role).
    case conversion
    /// The `#` marker character of a hash heading line.
    case hashMarker
    /// The heading body: every character after the `#` on the line.
    case hashBody
}

/// One classified span. `range` is a UTF-16 `NSRange` inside a single
/// logical line; callers add the line's document offset for whole-text
/// ranges. Operators, parentheses, `=`, signs and whitespace carry no
/// span and therefore keep the base (white/primary) color.
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
    /// same variable flow the evaluator uses) into role spans.
    ///
    /// Lines the evaluator treats as title, blank or skip (prose) carry
    /// no spans: prose must never be painted as variables. Error lines
    /// are classified lexically (numbers and known variables only).
    public static func spans(for source: String,
                             rates: Rates,
                             decimalPlaces: Int) -> [[SyntaxSpan]] {
        var result: [[SyntaxSpan]] = []
        var vars: [String: Double] = [:]
        for line in source.components(separatedBy: "\n") {
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
                let ns = line as NSString
                var heading: [SyntaxSpan] = [
                    SyntaxSpan(role: .hashMarker, range: NSRange(location: 0, length: 1))
                ]
                if ns.length > 1 {
                    heading.append(SyntaxSpan(
                        role: .hashBody,
                        range: NSRange(location: 1, length: ns.length - 1)
                    ))
                }
                result.append(heading)
                continue
            }
            let evaluation = evalLine(line, variables: &vars,
                                      rates: rates, decimalPlaces: decimalPlaces)
            let spans: [SyntaxSpan]
            switch evaluation {
            case nil:
                spans = []                       // .skip prose
            case .number(_, .some):
                spans = conversionSpans(line)
            case .number(_, .none):
                spans = expressionSpans(line, variables: vars)
            case .variable(let name, _):
                spans = assignmentSpans(line, name: name, variables: vars)
            case .blank, .skip, .title, .brokenToken:
                spans = []
            case .error:
                // Evaluation failures are still lexically classifiable:
                // numeric literals and known variables keep their
                // colors, everything else (including `to`) stays base.
                spans = errorSpans(line, variables: vars)
            }
            result.append(spans)
        }
        return result
    }

    // MARK: - Per-line span extraction

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
            return [
                SyntaxSpan(role: .number,
                           range: NSRange(location: shape.numberRange.location + offset,
                                          length: shape.numberRange.length)),
                SyntaxSpan(role: .conversion,
                           range: NSRange(location: shape.fromRange.location + offset,
                                          length: shape.fromRange.length)),
                SyntaxSpan(role: .conversion,
                           range: NSRange(location: shape.toRange.location + offset,
                                          length: shape.toRange.length))
            ]
        }
        // Fallback for unit-bearing results without a plain shape (most
        // notably reference-token conversion lines): the numeric literal
        // is a number, every identifier after it (except `to`) is a
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
            && ns.substring(with: m).lowercased() != "to" {
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
