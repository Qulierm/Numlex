import Foundation

// MARK: - Duration presentation (natural compound time)
//
// A duration is NEVER a string and never a unitless second count: it stays a
// real `Quantity` whose dimension is exactly T^1 and whose display unit is a
// real time unit from the catalog. What travels alongside it is a
// PRESENTATION marker (`QuantityPresentation`), which decides whether the
// answer is rendered as a natural compound (`2 h 15 min`) or in the ordinary
// single-unit form. The marker is derived from the source syntax on every
// evaluation pass and is never persisted: no store, sheet, settings,
// reference or `.nlx` field carries it.

/// How a quantity wants to be PRESENTED. Purely presentational: it never
/// changes the value, the dimension, the display unit or the algebra.
public enum QuantityPresentation: Equatable, Sendable {
    /// The ordinary single-unit presentation (`90 min`, `1.5 h`).
    case standard
    /// The natural compound duration presentation (`1 h 30 min`).
    case duration
}

/// One fixed duration component. Only these six units participate in
/// compound literals and in the natural decomposition: the calendar
/// AVERAGES (`mo`, `yr`, `quarter (time)`) and non-time units never do.
public enum DurationComponent: String, CaseIterable, Sendable {
    case week
    case day
    case hour
    case minute
    case second
    case millisecond

    /// The catalog id of this component.
    public var unitID: String {
        switch self {
        case .week: return "week"
        case .day: return "day"
        case .hour: return "hour"
        case .minute: return "minute"
        case .second: return "second"
        case .millisecond: return "millisecond"
        }
    }
    /// The catalog's canonical label — the natural display label too.
    public var label: String {
        switch self {
        case .week: return "week"
        case .day: return "day"
        case .hour: return "h"
        case .minute: return "min"
        case .second: return "s"
        case .millisecond: return "ms"
        }
    }
    /// Exact seconds in this component (the catalog's linear factor).
    public var seconds: Double {
        switch self {
        case .week: return 604_800
        case .day: return 86_400
        case .hour: return 3_600
        case .minute: return 60
        case .second: return 1
        case .millisecond: return 1e-3
        }
    }
    /// Largest first: the canonical decomposition order.
    public static let descending: [DurationComponent] =
        [.week, .day, .hour, .minute, .second, .millisecond]
}

/// The fixed duration vocabulary: which unit a written component denotes.
///
/// The table is deliberately a WHITELIST. `m` alone is never minutes (it
/// stays metres, and glued `5m` stays five million) and a bare glued `s` is
/// never accepted as a component, so no existing notation changes meaning.
public enum DurationUnits {
    /// Spaced/word aliases: `<number> <alias>`.
    public static let aliases: [String: DurationComponent] = [
        "ms": .millisecond, "millisecond": .millisecond, "milliseconds": .millisecond,
        "s": .second, "sec": .second, "secs": .second,
        "second": .second, "seconds": .second,
        "min": .minute, "mins": .minute, "minute": .minute, "minutes": .minute,
        "h": .hour, "hr": .hour, "hrs": .hour, "hour": .hour, "hours": .hour,
        "day": .day, "days": .day,
        "week": .week, "weeks": .week, "wk": .week, "wks": .week,
    ]

    /// GLUED aliases: `<number><alias>`. Bare `m` and bare `s` are absent on
    /// purpose (see the type comment); single-letter `h` is included because
    /// `h` has no competing meaning.
    public static let gluedAliases: [String: DurationComponent] = [
        "ms": .millisecond, "millisecond": .millisecond, "milliseconds": .millisecond,
        "sec": .second, "secs": .second, "second": .second, "seconds": .second,
        "min": .minute, "mins": .minute, "minute": .minute, "minutes": .minute,
        "h": .hour, "hr": .hour, "hrs": .hour, "hour": .hour, "hours": .hour,
        "day": .day, "days": .day,
        "week": .week, "weeks": .week, "wk": .week, "wks": .week,
    ]

    /// The component a resolved display label denotes (nil for anything
    /// else, including the calendar averages).
    public static func component(forLabel label: String) -> DurationComponent? {
        let key = label.lowercased()
        guard let c = aliases[key] else { return nil }
        return c
    }

    /// True when a display label is one of the six fixed components.
    public static func isFixed(_ label: String) -> Bool {
        component(forLabel: label) != nil
    }

    /// The long-form alias the glued scanner is matching at `index`, if any.
    /// Longest match wins so `mins` is preferred over `min`.
    public static func gluedMatch(_ text: String, from index: String.Index)
        -> (DurationComponent, String.Index)? {
        var best: (DurationComponent, String.Index)?
        for (alias, component) in gluedAliases {
            guard text[index...].hasPrefix(alias) else { continue }
            let end = text.index(index, offsetBy: alias.count)
            // The alias must END at a component boundary: a following letter
            // means a longer word (`5hz`, `2minsX`), which is not ours.
            if end < text.endIndex, text[end].isLetter { continue }
            if let current = best, current.1 > end { continue }
            best = (component, end)
        }
        return best
    }
}

/// The SHARED semantic core of a fixed-duration literal, used by BOTH the
/// mixed-unit line scanner and the reference-token expression parser: the
/// whitelist lookup, the fixed-unit validation, the summation of components
/// and the choice of display unit live here exactly once, so the two parsers
/// can never disagree about what a duration literal means. Each parser only
/// walks its own text representation.
public enum DurationLiteral {

    /// The component a spaced/word alias denotes (nil when the word is not a
    /// fixed duration alias at all).
    public static func component(forWord word: String) -> DurationComponent? {
        DurationUnits.aliases[word.lowercased()]
    }

    /// The longest glued alias starting at a string index.
    public static func gluedComponent(_ text: String, from index: String.Index)
        -> (DurationComponent, String.Index)? {
        DurationUnits.gluedMatch(text, from: index)
    }

    /// The unit expression for one component in the ACTIVE unit context, but
    /// only when it really is the catalog's fixed unit: a custom unit that
    /// merely shares a name or a factor must never gain implicit adjacency.
    public static func unitExpr(_ component: DurationComponent,
                                unitContext: UnitContext) -> UnitExpr? {
        guard let u = unitContext.resolveLabel(component.label) else { return nil }
        guard u.vector == DimensionVector(t: 1), u.isLinear else { return nil }
        guard abs(u.toBase - component.seconds) <= max(component.seconds * 1e-9, 1e-12) else {
            return nil
        }
        return u
    }

    /// Builds the marked duration quantity from the parsed components.
    ///
    /// - Parameters:
    ///   - components: the `(value, component)` pairs in SOURCE order.
    ///   - glued: whether any component came from a glued form (`45min`).
    ///   - unitContext: the active unit context.
    ///   - singleComponentAllowed: true for a parser that has no OTHER way to
    ///     express a unit operand (the reference-expression parser), so a
    ///     lone `30 min` is a valid operand there. The line scanner keeps
    ///     the default, where a single SPACED component stays on the
    ///     ordinary path (and keeps its old presentation).
    /// - Returns: nil unless the literal is genuinely a duration form (two or
    ///   more components, or a single GLUED one) and every component resolves
    ///   to its real fixed catalog unit. Components are summed whatever their
    ///   order and the LARGEST one becomes the display unit.
    public static func quantity(_ components: [(value: Double, component: DurationComponent)],
                                glued: Bool,
                                unitContext: UnitContext,
                                singleComponentAllowed: Bool = false) -> Quantity? {
        guard !components.isEmpty,
              components.count >= 2 || glued || singleComponentAllowed else { return nil }
        var totalSeconds = 0.0
        for entry in components {
            guard entry.value.isFinite,
                  unitExpr(entry.component, unitContext: unitContext) != nil else { return nil }
            totalSeconds += entry.value * entry.component.seconds
            guard totalSeconds.isFinite else { return nil }
        }
        guard let display = components.map({ $0.component })
                .max(by: { $0.seconds < $1.seconds }),
              let unit = unitExpr(display, unitContext: unitContext) else { return nil }
        let value = totalSeconds / display.seconds
        guard value.isFinite else { return nil }
        return Quantity(value: value, display: unit, presentation: .duration)
    }

    /// The display label a duration token quantity carries (its display unit
    /// label, e.g. `h`), or nil when the label is not a fixed duration unit.
    public static func isDurationLabel(_ label: String?) -> Bool {
        guard let label else { return false }
        return DurationUnits.isFixed(label)
    }
}

/// The single natural-duration formatter, shared by the visible answer, Copy
/// Answer, Answer Tokens and assignment results, so all four can never drift.
///
/// The input is the quantity's OWN value plus its display label; the result
/// is the canonical decomposition into weeks, days, hours, minutes and
/// seconds (milliseconds for a sub-second residual), with a single leading
/// minus, no zero components and `0 s` for zero.
public enum DurationPresentation {

    /// The dimension signature of a duration: exactly T^1, nothing else.
    public static let timeSignature = DimensionSignature(
        base: DimensionVector(l: 0, m: 0, t: 1, a: 0, i: 0))

    /// True when a quantity is a fixed time duration.
    public static func isDuration(_ q: Quantity) -> Bool {
        q.signature == timeSignature && DurationUnits.isFixed(q.display.label) && q.value.isFinite
    }

    /// The canonical natural string for a duration value.
    ///
    /// - Parameters:
    ///   - value: the value in the display unit's scale.
    ///   - unitLabel: the quantity's display label (`min`, `h`, ...).
    ///   - decimalPlaces: the global/row precision bound for a FRACTIONAL
    ///     smallest component.
    ///   - context: the regional number context (decimal separator,
    ///     grouping, compact notation suppressed).
    public static func text(value: Double, unitLabel: String,
                            decimalPlaces: Int,
                            context: NumberFormatContext) -> String {
        if let component = DurationUnits.component(forLabel: unitLabel),
           value.isFinite,
           let natural = text(seconds: value * component.seconds,
                              decimalPlaces: decimalPlaces, context: context,
                              // The engine stores the value quantized to the
                              // display unit's decimals; a residue smaller
                              // than that quantization is not real.
                              snapTolerance: max(1e-9, 0.6e-10 * component.seconds)) {
            return natural
        }
        // Not a fixed duration unit (or a non-finite value): the ordinary
        // single-unit presentation, so the algebra never prints garbage.
        let s = formatDisplayValue(value, decimalPlaces: decimalPlaces,
                                   context: context.withoutCompactNotation)
        return "\(s) \(unitLabel)"
    }

    /// The canonical natural string for an exact number of seconds. Returns
    /// nil when the input is not finite (the caller falls back).
    public static func text(seconds: Double, decimalPlaces: Int,
                            context: NumberFormatContext,
                            snapTolerance: Double = 1e-9) -> String? {
        guard seconds.isFinite else { return nil }
        let output = components(seconds: seconds, decimalPlaces: decimalPlaces,
                                context: context, snapTolerance: snapTolerance)
        guard !output.parts.isEmpty else { return "0 s" }
        return (output.negative ? "-" : "") + output.parts.joined(separator: " ")
    }

    public struct Decomposition: Equatable, Sendable {
        public var negative: Bool
        public var parts: [String]
        /// The signed seconds the parts represent.
        public var seconds: Double
    }

    /// Decompose a duration into its canonical components.
    ///
    /// Rules, in order:
    /// - the sign is taken once, on the whole duration;
    /// - whole components are peeled largest-first;
    /// - a fractional remainder is carried into the SMALLEST component: the
    ///   seconds component keeps up to `decimalPlaces` decimals, and a
    ///   sub-second residual renders as milliseconds;
    /// - rounding the smallest component can CARRY into the next one
    ///   (59.9999… s becomes the next minute), which is normalised here so a
    ///   boundary value is never printed as `59.999… s`;
    /// - zero components are omitted entirely.
    public static func components(seconds: Double, decimalPlaces: Int,
                                  context: NumberFormatContext,
                                  snapTolerance: Double = 1e-9) -> Decomposition {
        guard seconds.isFinite else { return Decomposition(negative: false, parts: [], seconds: 0) }
        let negative = seconds < 0
        var t = abs(seconds)
        let places = min(max(decimalPlaces, 0), AnswerDisplay.maxPlaces)

        var parts: [String] = []
        // Sub-second durations present in milliseconds (integer when exact).
        if t < 1 {
            let roundedMs = roundToPlaces(t * 1000, places: 3 + places)
            if roundedMs == 0 {
                return Decomposition(negative: negative, parts: [], seconds: seconds)
            }
            if roundedMs < 1000 {
                let msText = number(roundedMs, places: places, context: context,
                                    allowFraction: !isExact(roundedMs))
                return Decomposition(negative: negative, parts: ["\(msText) ms"],
                                     seconds: negative ? -t : t)
            }
            // 999.999… ms rounds up to a full second: fall through to the
            // whole-second decomposition (the carry is normalised below).
            t = roundedMs / 1000
        }

        var whole: [DurationComponent: Double] = [:]
        for component in DurationComponent.descending
            where component != .millisecond && component != .second {
            let count = floor(t / component.seconds)
            if count > 0 {
                whole[component] = count
                t -= count * component.seconds
            }
        }
        // `t` now holds the remaining seconds (0 <= t < 60), possibly
        // fractional. Round the smallest component and carry if it lands on a
        // unit boundary.
        var secondsPart = roundToPlaces(t, places: places)
        // A residue within the storage quantization is not real: snap it to
        // the whole second (this is what makes a 10-decimal day value come
        // back as exactly 3 h 30 min instead of 59.9999971 s).
        if abs(secondsPart - secondsPart.rounded()) <= snapTolerance {
            secondsPart = secondsPart.rounded()
        }
        // A strictly sub-second residual presents in milliseconds, so a
        // compound input like `1 min 250 ms` round-trips as such.
        let subSecond = secondsPart > 0 && secondsPart < 1
        if secondsPart >= 60 {
            // The rounded smallest component carried: normalise minute ->
            // hour -> day -> week so a boundary value never prints as
            // `60 s` (or `60 min`, `24 h`, `7 day`).
            secondsPart -= 60
            var minutes = (whole[.minute] ?? 0) + 1
            var carry = false
            if minutes >= 60 { minutes -= 60; carry = true }
            whole[.minute] = minutes
            if carry {
                var hours = (whole[.hour] ?? 0) + 1
                carry = false
                if hours >= 24 { hours -= 24; carry = true }
                whole[.hour] = hours
                if carry {
                    var days = (whole[.day] ?? 0) + 1
                    carry = false
                    if days >= 7 { days -= 7; carry = true }
                    whole[.day] = days
                    if carry { whole[.week] = (whole[.week] ?? 0) + 1 }
                }
            }
        }
        for component in DurationComponent.descending {
            if component == .second {
                guard secondsPart != 0 else { continue }
                if subSecond {
                    let ms = roundToPlaces(secondsPart * 1000, places: 3 + places)
                    parts.append("\(number(ms, places: places, context: context, allowFraction: !isExact(ms))) ms")
                } else if isExact(secondsPart) {
                    parts.append("\(number(secondsPart, places: 0, context: context, allowFraction: false)) \(component.label)")
                } else {
                    // A whole-second part plus an EXACT millisecond residue
                    // (`5 s 6 ms`) is printed as components instead of a
                    // fractional second, and the quantization snap keeps
                    // storage noise (5.0060093 s) out of the output.
                    let wholeSeconds = floor(secondsPart)
                    let residueMs = (secondsPart - wholeSeconds) * 1000
                    let snappedMs = residueMs.rounded()
                    if abs(residueMs - snappedMs) <= snapTolerance * 1000,
                       snappedMs > 0, snappedMs < 1000 {
                        if wholeSeconds > 0 {
                            parts.append("\(number(wholeSeconds, places: 0, context: context, allowFraction: false)) s")
                        }
                        parts.append("\(number(snappedMs, places: 0, context: context, allowFraction: false)) ms")
                    } else {
                        parts.append("\(number(secondsPart, places: places, context: context, allowFraction: true)) \(component.label)")
                    }
                }
                continue
            }
            guard let count = whole[component], count > 0 else { continue }
            parts.append("\(number(count, places: 0, context: context, allowFraction: false)) \(component.label)")
        }
        return Decomposition(negative: negative, parts: parts, seconds: negative ? -abs(seconds) : abs(seconds))
    }

    // MARK: helpers

    /// Rounds to a decimal-place count with a tiny relative epsilon, so
    /// 59.99999999999 s is 60 s (and carries) instead of staying fractional.
    static func roundToPlaces(_ value: Double, places: Int) -> Double {
        guard value.isFinite else { return value }
        let scale = pow(10.0, Double(min(max(places, 0), 12)))
        let scaled = value * scale
        let rounded = (scaled).rounded()
        let result = rounded / scale
        return result.isFinite ? result : value
    }

    /// True when the value is an exact (integral) number within a hair.
    static func isExact(_ value: Double) -> Bool {
        guard value.isFinite else { return false }
        return abs(value - value.rounded()) < 1e-9
    }

    private static func number(_ value: Double, places: Int,
                               context: NumberFormatContext,
                               allowFraction: Bool) -> String {
        formatDisplayValue(value, decimalPlaces: allowFraction ? places : 0,
                           context: context.withoutCompactNotation)
    }

}

// MARK: - NumericKind.duration support

extension DurationPresentation {
    /// The natural string for a `.duration` numeric kind, or nil when the
    /// kind is not a duration.
    public static func naturalText(value: Double, unit: String?,
                                   kind: NumericKind, decimalPlaces: Int,
                                   context: NumberFormatContext) -> String? {
        guard kind == .duration, let unit else { return nil }
        return text(value: value, unitLabel: unit, decimalPlaces: decimalPlaces,
                    context: context)
    }
}
