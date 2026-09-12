import Foundation

// MARK: - Timespan presentation (temporal Task 3)
//
// The ONE timespan formatter: a greedy, carry-safe decomposition into
// average years (365.2425 d), average months (30.436875 d), weeks,
// days, hours, minutes, seconds and milliseconds, with ONE leading sign
// and zero components omitted. It is used by:
//   * the explicit `as timespan` expression suffix (kind `.timespan`),
//   * the global/per-line Timespan NOTATION on time-dimension
//     quantities,
// and by nothing else — the pre-existing natural duration presentation
// (`DurationPresentation`) stays byte-identical.
//
// Label style: a duration of an hour or more uses full pluralized
// words (`4 hours 32 minutes 24 seconds`, `10 weeks 2 days`); a shorter
// one uses the compact labels (`5 min 30 s`). The average-year/month
// labels stay `yr`/`mo` in both styles (they are linear averages, not
// calendar months).
public enum TimespanPresentation {

    public enum Style: Equatable, Sendable {
        case full
        case short
    }

    struct Piece {
        let seconds: Double
        let fullSingular: String
        let fullPlural: String
        let short: String
    }

    /// The decomposition order: largest first.
    static let pieces: [Piece] = [
        Piece(seconds: UnitCatalog.resolveExpression("yr")?.unit.toBase ?? 31_556_952,
              fullSingular: "yr", fullPlural: "yr", short: "yr"),
        Piece(seconds: UnitCatalog.resolveExpression("mo")?.unit.toBase ?? 2_629_746,
              fullSingular: "mo", fullPlural: "mo", short: "mo"),
        Piece(seconds: 604_800,
              fullSingular: "week", fullPlural: "weeks", short: "wk"),
        Piece(seconds: 86_400,
              fullSingular: "day", fullPlural: "days", short: "d"),
        Piece(seconds: 3_600,
              fullSingular: "hour", fullPlural: "hours", short: "h"),
        Piece(seconds: 60,
              fullSingular: "minute", fullPlural: "minutes", short: "min"),
        Piece(seconds: 1,
              fullSingular: "second", fullPlural: "seconds", short: "s"),
    ]

    /// The style rule: an hour or more is "full", anything shorter is
    /// "short".
    public static func style(forSeconds seconds: Double) -> Style {
        abs(seconds) >= 3_600 ? .full : .short
    }

    /// True when a unit label denotes a T^1 (time) quantity in the
    /// built-in catalog — the only rows Timespan notation applies to.
    public static func isTimeUnit(_ label: String) -> Bool {
        guard let parsed = UnitCatalog.resolveExpression(label) else { return false }
        return parsed.unit.vector == DimensionVector(t: 1) && parsed.unit.isLinear
    }

    /// The timespan text for a quantity, or nil when the unit is not a
    /// T^1 time unit (the caller deterministically falls back to
    /// Automatic) or the value is non-finite.
    public static func text(value: Double, unitLabel: String,
                            decimalPlaces: Int,
                            context: NumberFormatContext) -> String? {
        guard value.isFinite,
              let parsed = UnitCatalog.resolveExpression(unitLabel),
              parsed.unit.vector == DimensionVector(t: 1),
              parsed.unit.isLinear else { return nil }
        let seconds = value * parsed.unit.toBase
        guard seconds.isFinite else { return nil }
        return text(seconds: seconds, decimalPlaces: decimalPlaces, context: context)
    }

    /// The timespan text for an exact number of seconds.
    public static func text(seconds: Double, decimalPlaces: Int,
                            context: NumberFormatContext) -> String? {
        guard seconds.isFinite, abs(seconds) <= 8.64e15 else { return nil }
        return text(seconds: seconds, style: style(forSeconds: seconds),
                    decimalPlaces: decimalPlaces, context: context)
    }

    /// The timespan text with an explicit label style.
    public static func text(seconds: Double, style: Style, decimalPlaces: Int,
                            context: NumberFormatContext) -> String? {
        guard seconds.isFinite else { return nil }
        let places = min(max(decimalPlaces, 0), AnswerDisplay.maxPlaces)
        let negative = seconds < 0
        var total = abs(seconds)
        // Round the SMALLEST component (the sub-second residual lives only
        // in the seconds place) BEFORE decomposing, so the carry into the
        // next component is automatic and safe.
        let roundedTotal = roundToPlaces(total, places: places)
        if abs(roundedTotal - roundedTotal.rounded()) <= 1e-9 {
            total = roundedTotal.rounded()
        } else {
            total = roundedTotal
        }
        var parts: [String] = []
        // A pure sub-second duration presents in milliseconds.
        if total > 0 && total < 1 {
            let ms = roundToPlaces(total * 1000, places: 3 + places)
            if ms >= 1000 {
                total = 1
            } else if ms > 0 {
                parts.append("\(number(ms, places: places, context: context)) ms")
            }
        }
        if total >= 1 {
            var rest = total
            // Month peeling applies only at YEAR scale: below one year the
            // decomposition uses weeks (72 days is `10 weeks 2 days`, not
            // `2 mo 11 days`), while average months keep 1.5 yr exact.
            let useMonths = total >= pieces[0].seconds
            for piece in pieces where useMonths || piece.fullSingular != "mo" {
                let count = floor(rest / piece.seconds)
                if count > 0 {
                    rest -= count * piece.seconds
                    parts.append(component(count, piece: piece, style: style,
                                           context: context, places: places))
                }
            }
            // A fractional seconds residual that survived the decomposition.
            if rest > 0 {
                // `rest` is the residual seconds (< 60). When it is below
                // one second the earlier millisecond branch did not run
                // (the total was >= 1), so present the residue in ms.
                if rest < 1 {
                    let ms = roundToPlaces(rest * 1000, places: 3 + places)
                    if ms > 0, ms < 1000 {
                        parts.append("\(number(ms, places: places, context: context)) ms")
                    }
                } else {
                    parts.append(component(rest, piece: pieces[pieces.count - 1],
                                           style: style, context: context,
                                           places: places))
                }
            }
        }
        guard !parts.isEmpty else { return "0 s" }
        return (negative ? "-" : "") + parts.joined(separator: " ")
    }

    // MARK: helpers

    static func roundToPlaces(_ value: Double, places: Int) -> Double {
        guard value.isFinite else { return value }
        let scale = pow(10.0, Double(min(max(places, 0), 12)))
        let rounded = (value * scale).rounded() / scale
        return rounded.isFinite ? rounded : value
    }

    private static func component(_ count: Double, piece: Piece, style: Style,
                                  context: NumberFormatContext,
                                  places: Int) -> String {
        let text = number(count, places: places, context: context)
        switch style {
        case .full:
            let exactOne = abs(count - 1) < 1e-9
            return "\(text) \(exactOne ? piece.fullSingular : piece.fullPlural)"
        case .short:
            return "\(text) \(piece.short)"
        }
    }

    private static func number(_ value: Double, places: Int,
                               context: NumberFormatContext) -> String {
        formatDisplayValue(value, decimalPlaces: places,
                           context: context.withoutCompactNotation)
    }
}
