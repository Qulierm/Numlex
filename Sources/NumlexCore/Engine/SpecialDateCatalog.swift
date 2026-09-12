import Foundation

// MARK: - Special dates (temporal Task 6)
//
// A BOUNDED catalog of named calendar dates, integrated into the
// ordinary date lane:
//
//   Easter            -> this year's Gregorian Easter Sunday
//   Easter 2027       -> Mar 28, 2027
//   Christmas         -> Dec 25 (this year)
//   days until Christmas -> the whole-day count to the next occurrence
//
// Gregorian Easter uses the anonymous computus algorithm, verified
// against known years in the tests. The Christmas rule is the SAME
// `12-25` the bundled holiday profiles carry, so the date lane and the
// work-calendar lane can never disagree about the day.

public enum SpecialDateCatalog {

    public struct Day: Equatable, Sendable {
        public var year: Int
        public var month: Int
        public var day: Int
        public init(year: Int, month: Int, day: Int) {
            self.year = year
            self.month = month
            self.day = day
        }
    }

    /// The canonical alias table (case/whitespace-insensitive).
    private static let aliases: [String: String] = [
        "christmas": "christmas",
        "christmas day": "christmas",
        "xmas": "christmas",
        "easter": "easter",
        "easter sunday": "easter",
        "easter day": "easter",
    ]

    /// The canonical name for an alias, or nil for an unknown holiday.
    public static func canonicalName(_ raw: String) -> String? {
        let key = raw.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return aliases[key]
    }

    /// The Gregorian Easter Sunday (anonymous computus). Bounded to the
    /// algorithm's validity range.
    public static func easter(year: Int) -> (month: Int, day: Int)? {
        guard year >= 1583, year <= 4099 else { return nil }
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return (month, day)
    }

    /// The date of a named holiday in one year.
    public static func day(named raw: String, year: Int) -> Day? {
        guard let name = canonicalName(raw) else { return nil }
        switch name {
        case "christmas":
            return Day(year: year, month: 12, day: 25)
        case "easter":
            guard let e = easter(year: year) else { return nil }
            return Day(year: year, month: e.month, day: e.day)
        default:
            return nil
        }
    }

    /// The next occurrence strictly after `now` (this year's date when it
    /// is still in the future, otherwise next year's).
    public static func nextOccurrence(named raw: String, after now: Date,
                                      calendar: Calendar) -> (date: Date, day: Day)? {
        let today = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = today.year, let month = today.month, let day = today.day else {
            return nil
        }
        guard let thisYear = self.day(named: raw, year: year) else { return nil }
        let candidateIsFuture = (thisYear.month, thisYear.day) > (month, day)
        guard let target = candidateIsFuture ? thisYear : self.day(named: raw, year: year + 1) else {
            return nil
        }
        var components = DateComponents()
        components.year = target.year
        components.month = target.month
        components.day = target.day
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        return (date, target)
    }

    /// Whole days from `now`'s day to the next occurrence.
    public static func daysUntil(named raw: String, from now: Date,
                                 calendar: Calendar) -> Int? {
        guard let next = nextOccurrence(named: raw, after: now, calendar: calendar) else {
            return nil
        }
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: next.date)
        return calendar.dateComponents([.day], from: start, to: end).day
    }
}
