import Foundation
import NumlexCore

// MARK: - temporal Task 6: special dates

/// Injected now: 2025-01-15 12:00 UTC (a Wednesday).
private func sdNow() -> (Date, Calendar) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let date = cal.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12))!
    return (date, cal)
}

private func sdEval(_ line: String, now: Date? = nil) -> LineResult? {
    let (baseNow, cal) = sdNow()
    var v: [String: Double] = [:]
    return evalLine(line, variables: &v, rates: Rates(), decimalPlaces: 10,
                    now: now ?? baseNow, calendar: cal,
                    context: .legacy, unitContext: .builtIns)
}

private func sdText(_ line: String, now: Date? = nil) -> String? {
    guard let r = sdEval(line, now: now) else { return nil }
    return AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: .legacy)
}

private func expectSD(_ line: String, _ expected: String, now: Date? = nil) throws {
    guard let text = sdText(line, now: now) else {
        throw CaseFailure(message: "no special-date text for \(line)", location: "SpecialDate")
    }
    try expectEqual(text, expected, "\(line)")
}

public let specialDateCases: [EngineCase] = [

    EngineCase("special-date-official-examples") {
        // `days until Christmas` from 2025-01-15 -> 344 days.
        try expectSD("days until Christmas", "344 days")
        // Easter 2027 is March 28.
        try expectSD("Easter 2027", "Mar 28, 2027")
        // A bare Easter uses the captured year (2025-04-20).
        try expectSD("Easter", "Apr 20")
        // Bare Christmas uses the captured year.
        try expectSD("Christmas", "Dec 25")
        try expectSD("christmas day", "Dec 25")
        // Special dates participate in the supported date arithmetic.
        try expectSD("Easter 2027 + 2 days", "Mar 30, 2027")
        try expectSD("Christmas + 5 days", "Dec 30")
        // `days until` chooses this year when it is still future.
        try expectSD("days until Easter", "95 days")
        // Case/whitespace-insensitive alias.
        try expectSD("DAYS UNTIL   christmas  day", "344 days")
    },

    EngineCase("special-date-computus-known-years") {
        let known: [(Int, Int, Int)] = [
            (1583, 4, 10), (1900, 4, 15), (2000, 4, 23), (2016, 3, 27),
            (2021, 4, 4), (2022, 4, 17), (2023, 4, 9), (2024, 3, 31),
            (2025, 4, 20), (2026, 4, 5), (2027, 3, 28), (2030, 4, 21),
            (2038, 4, 25), (2100, 3, 28),
        ]
        for (year, month, day) in known {
            guard let e = SpecialDateCatalog.easter(year: year) else {
                throw CaseFailure(message: "\(year) computus", location: "SpecialDate")
            }
            try expect(e.month == month && e.day == day,
                       "\(year) Easter \(month)/\(day), got \(e.month)/\(e.day)")
        }
        // Out-of-range years are bounded, never fabricated.
        try expect(SpecialDateCatalog.easter(year: 1500) == nil, "before the range")
        try expect(SpecialDateCatalog.easter(year: 5000) == nil, "after the range")
    },

    EngineCase("special-date-multi-component-arithmetic") {
        // The extended calendar duration grammar.
        try expectSD("March 12 + 3 weeks 2 days", "Apr 4")
        try expectSD("May 5 + 43 days", "Jun 17")
        try expectSD("March 12 + 1 month 2 days", "Apr 14")
        try expectSD("March 12 - 3 weeks 2 days", "Feb 17")
        // Leap-year preservation.
        try expectSD("February 28 2024 + 1 day", "Feb 29, 2024")
        try expectSD("February 29 2024 + 1 year", "Feb 28, 2025")
        // Month-end behavior stays Calendar-component based.
        try expectSD("January 31 + 1 month", "Feb 28")
        // Magnitude bounds remain strict.
        guard let huge = sdEval("March 12 + 99999999 days"), case .error = huge else {
            throw CaseFailure(message: "huge compounds error", location: "SpecialDate")
        }
    },

    EngineCase("special-date-strictness-and-no-theft") {
        // An unknown named holiday is a strict error for `days until`.
        guard let unknown = sdEval("days until Festivus"), case .error = unknown else {
            throw CaseFailure(message: "unknown holiday errors", location: "SpecialDate")
        }
        // Prose mentioning a holiday is never stolen.
        for prose in ["christmas plans", "easter eggs are tasty", "christmas in Paris"] {
            if let r = sdEval(prose), case .date = r {
                throw CaseFailure(message: "\(prose) must not be a date", location: "SpecialDate")
            }
        }
        // `Easter` as an assignment target keeps its variable semantics.
        var v: [String: Double] = [:]
        let (now, cal) = sdNow()
        let assigned = evalLine("Easter = 5", variables: &v, rates: Rates(),
                                decimalPlaces: 10, now: now, calendar: cal,
                                context: .legacy, unitContext: .builtIns)
        guard case .variable? = assigned else {
            throw CaseFailure(message: "assignment wins", location: "SpecialDate")
        }
    },

    EngineCase("special-date-christmas-link") {
        // Christmas is the SAME 12-25 in the special-date catalog and in
        // every bundled holiday profile that carries it.
        guard let christmas = SpecialDateCatalog.day(named: "christmas", year: 2026),
              christmas.month == 12, christmas.day == 25 else {
            throw CaseFailure(message: "catalog Christmas", location: "SpecialDate")
        }
        if let holidays = HolidayCatalog.shared {
            for country in ["US", "DE", "FR", "GB", "IT"] {
                try expect(holidays.isHoliday(country: country, year: 2026,
                                              month: 12, day: 25),
                           "\(country) Christmas matches the special date")
            }
        }
    },
]
