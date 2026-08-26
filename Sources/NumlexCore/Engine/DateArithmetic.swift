import Foundation

/// Pure, bounded English date arithmetic.
///
/// The parser is a word scanner (no regex backtracking over prose):
///
///     <date> [ <sign> <integer> <duration> ]
///     <date>   := today | tomorrow | yesterday
///                | May 5 | May 5, 2026 | 5 May 2026 | 5 May
///     <duration> := day(s) | week(s) | month(s) | year(s)
///
/// Three outcomes keep the evaluator honest:
/// - `.none`: the line is not date-shaped (a bare month word without a
///   day, prose, ...) — it flows on as normal prose;
/// - `.value`: a fully parsed, validated date result;
/// - `.malformed`: date-LOOKING text that cannot be a real date
///   (Feb 30, `May 5 + 43` without a duration, `May 5 + 43 days extra`)
///   — the caller returns a hidden generic error. Date-looking input is
///   NEVER allowed to fall through to a numeric word-stripping fallback.
///
/// Durations are applied with Gregorian `Calendar` COMPONENT arithmetic
/// (never 86,400-second multiples), anchored at local noon so DST
/// transitions cannot shift the day. The reference "now" and the
/// calendar/timezone are injected: the app passes the user's current
/// context, tests pass fixed deterministic values.
public enum DateArithmetic {

    /// A fully parsed date line result (component form — a date answer
    /// carries no time of day and is never a Double).
    public struct Value: Equatable, Sendable {
        public let year: Int
        public let month: Int
        public let day: Int
        /// Render the year when the input supplied one explicitly, or
        /// when the result leaves the input's year.
        public let showYear: Bool
    }

    public enum Detect {
        case none
        case value(Value)
        case malformed
    }

    /// Bounded duration word table (lowercased, full and plural).
    public static let durationWords: [String: String] = [
        "day": "day", "days": "day",
        "week": "week", "weeks": "week",
        "month": "month", "months": "month",
        "year": "year", "years": "year",
    ]

    /// English month names (abbreviated and full), lowercased.
    public static let monthIndex: [String: Int] = [
        "jan": 1, "january": 1,
        "feb": 2, "february": 2,
        "mar": 3, "march": 3,
        "apr": 4, "april": 4,
        "may": 5,
        "jun": 6, "june": 6,
        "jul": 7, "july": 7,
        "aug": 8, "august": 8,
        "sep": 9, "sept": 9, "september": 9,
        "oct": 10, "october": 10,
        "nov": 11, "november": 11,
        "dec": 12, "december": 12,
    ]

    private static let shortMonths = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    /// Duration magnitudes beyond this are overflow: hidden error.
    private static let maxDuration = 1_000_000

    public static func detect(line: String, now: Date, calendar: Calendar) -> Detect {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Split on runs of spaces/tabs only (punctuation stays with words).
        let tokens = trimmed.split { $0 == " " || $0 == "\t" }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: " ")) }
        guard !tokens.isEmpty else { return .none }

        // --- Parse the date prefix -------------------------------------
        var yearExplicit = false
        var start: (y: Int, m: Int, d: Int)?
        var rest = 0

        let first = tokens[0].lowercased()
        if first == "today" || first == "tomorrow" || first == "yesterday" {
            let delta = first == "tomorrow" ? 1 : (first == "yesterday" ? -1 : 0)
            let anchor = noon(now, calendar: calendar)
            guard let shifted = calendar.date(byAdding: .day, value: delta, to: anchor) else {
                return .malformed
            }
            start = (calendar.component(.year, from: shifted),
                     calendar.component(.month, from: shifted),
                     calendar.component(.day, from: shifted))
            rest = 1
        } else if let m = monthIndex[first], tokens.count >= 2,
                  let d = Int(tokens[1].hasSuffix(",") ? String(tokens[1].dropLast()) : tokens[1]) {
            // `May 5` / `May 5, 2026`
            var y = calendar.component(.year, from: now)
            var idx = 2
            if tokens.count > 2, !tokens[2].hasPrefix("+"), !tokens[2].hasPrefix("-") {
                let t2 = tokens[2]
                if Int(t2) != nil, t2.count == 4 {
                    y = Int(t2)!
                    yearExplicit = true
                    idx = 3
                } else if t2.hasPrefix(",") {
                    // `May 5, 2026` split as `5,` `2026` handled above;
                    // a comma without a following 4-digit year is malformed.
                    return .malformed
                }
            }
            start = (y, m, d)
            rest = idx
        } else if let d = Int(tokens[0]), tokens.count >= 2, let m = monthIndex[tokens[1].lowercased()] {
            // `5 May 2026` / `5 May`
            var y = calendar.component(.year, from: now)
            var idx = 2
            if tokens.count > 2, let yv = Int(tokens[2]), tokens[2].count == 4 {
                y = yv
                yearExplicit = true
                idx = 3
            }
            start = (y, m, d)
            rest = idx
        } else {
            // Not date-shaped: bare month word, prose, math, ...
            return .none
        }
        guard let s = start else { return .malformed }

        // --- Parse the optional duration --------------------------------
        var delta: (unit: String, n: Int)?
        if rest < tokens.count {
            guard tokens.count == rest + 3 else { return .malformed }
            let signToken = tokens[rest]
            guard signToken == "+" || signToken == "-" else { return .malformed }
            let numToken = tokens[rest + 1].replacingOccurrences(of: ",", with: "")
            guard let n = Int(numToken), numToken.count <= 7 else { return .malformed }
            guard let unit = durationWords[tokens[rest + 2].lowercased()] else {
                return .malformed
            }
            delta = (unit, signToken == "-" ? -n : n)
        }

        // --- Validate the real date --------------------------------------
        guard (1...9999).contains(s.y), (1...12).contains(s.m),
              (1...daysInMonth(s.y, s.m)).contains(s.d) else {
            return .malformed
        }
        guard let anchor = calendar.date(from: DateComponents(
            calendar: calendar, year: s.y, month: s.m, day: s.d, hour: 12
        )) else { return .malformed }

        var resultDate = anchor
        if let (unit, n) = delta {
            guard abs(n) <= maxDuration else { return .malformed }
            let comp: Calendar.Component
            switch unit {
            case "day": comp = .day
            case "week": comp = .day
            case "month": comp = .month
            case "year": comp = .year
            default: return .malformed
            }
            let value = (unit == "week") ? n * 7 : n
            guard let shifted = calendar.date(byAdding: comp, value: value, to: anchor) else {
                return .malformed
            }
            resultDate = shifted
        }

        let y = calendar.component(.year, from: resultDate)
        let m = calendar.component(.month, from: resultDate)
        let d = calendar.component(.day, from: resultDate)
        guard (1...9999).contains(y) else { return .malformed }

        let showYear = yearExplicit || (y != s.y)
        return .value(Value(year: y, month: m, day: d, showYear: showYear))
    }

    /// Compact English display: `Jun 17`, or `Jun 17, 2026` when the
    /// year is explicit in the input or the result crossed out of it.
    public static func display(year: Int, month: Int, day: Int, showYear: Bool) -> String {
        display(Value(year: year, month: month, day: day, showYear: showYear))
    }

    public static func display(_ v: Value) -> String {
        guard (1...12).contains(v.month) else { return "" }
        let base = "\(shortMonths[v.month - 1]) \(v.day)"
        return v.showYear ? "\(base), \(v.year)" : base
    }

    // MARK: - Helpers

    private static func noon(_ date: Date, calendar: Calendar) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: date)
        c.hour = 12
        return calendar.date(from: c) ?? date
    }

    static func daysInMonth(_ year: Int, _ month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        default: return 30
        }
    }
}
