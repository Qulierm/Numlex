import Foundation
import NumlexCore

/// Date arithmetic: the pure bounded English parser with an injected
/// reference date/calendar (deterministic tests), Gregorian component
/// arithmetic (never 86,400-second multiples), real-date validation,
/// compact English display, malformed-no-fallback guarantees, and the
/// non-tokenizable `.date` result type.

private let M = "\u{FFFC}"

private func ctx(_ y: Int, _ m: Int, _ d: Int,
                 tzID: String = "America/New_York") -> (now: Date, calendar: Calendar) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: tzID)!
    let now = cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    return (now, cal)
}

private func dLine(_ line: String, now: (now: Date, calendar: Calendar)) -> LineResult? {
    var vars: [String: Double] = [:]
    return evalLine(line, variables: &vars, rates: Rates(), decimalPlaces: 7,
                    now: now.now, calendar: now.calendar)
}

private func expectDate(_ line: String, now: (now: Date, calendar: Calendar),
                        _ y: Int, _ m: Int, _ d: Int, _ showYear: Bool,
                        file: String = #fileID, lineNo: Int = #line) throws {
    guard let r = dLine(line, now: now) else {
        throw CaseFailure(message: "\(line) produced no result", location: "\(file):\(lineNo)")
    }
    if case .date(let gy, let gm, let gd, let gs) = r {
        try expect(gy == y && gm == m && gd == d && gs == showYear,
                   "\(line) → \(gy)-\(gm)-\(gd) showYear=\(gs)")
    } else {
        throw CaseFailure(message: "\(line) → \(r), expected date \(y)-\(m)-\(d)",
                          location: "\(file):\(lineNo)")
    }
}

private func expectDateError(_ line: String,
                             now: (now: Date, calendar: Calendar) = ctx(2026, 8, 26),
                             file: String = #fileID, lineNo: Int = #line) throws {
    guard let r = dLine(line, now: now) else {
        throw CaseFailure(message: "\(line) produced no result (must be a hidden error)",
                          location: "\(file):\(lineNo)")
    }
    if case .error = r { return }
    throw CaseFailure(message: "\(line) → \(r), expected hidden error",
                      location: "\(file):\(lineNo)")
}

// MARK: - Case bodies

private func bodyRefMay5() throws {
    let now = ctx(2026, 8, 26)
    try expectDate("May 5 + 43 days", now: now, 2026, 6, 17, false)
    try expectEqual(DateArithmetic.display(year: 2026, month: 6, day: 17, showYear: false),
                    "Jun 17", "compact display")
}

private func bodyForms() throws {
    let now = ctx(2026, 8, 26)
    try expectDate("May 5, 2026 + 43 days", now: now, 2026, 6, 17, true)
    try expectDate("5 May 2026 + 43 days", now: now, 2026, 6, 17, true)
    try expectDate("5 May + 43 days", now: now, 2026, 6, 17, false)
    try expectDate("May 5", now: now, 2026, 5, 5, false)
    try expectEqual(DateArithmetic.display(year: 2026, month: 6, day: 17, showYear: true),
                    "Jun 17, 2026", "explicit year renders")
    try expectDate("MAY 5 + 43 DAYS", now: now, 2026, 6, 17, false)
}

private func bodyRelativeWords() throws {
    let now = ctx(2026, 8, 26)
    try expectDate("today", now: now, 2026, 8, 26, false)
    try expectDate("tomorrow + 1 day", now: now, 2026, 8, 28, false)
    try expectDate("yesterday - 1 day", now: now, 2026, 8, 24, false)
}

private func bodyYearCrossing() throws {
    let now = ctx(2026, 8, 26)
    try expectDate("Dec 25 + 10 days", now: now, 2027, 1, 4, true)
    try expectEqual(DateArithmetic.display(year: 2027, month: 1, day: 4, showYear: true),
                    "Jan 4, 2027", "crossed year renders")
    try expectDate("Jan 1 - 1 day", now: now, 2025, 12, 31, true)
    try expectDate("May 5 + 2 years", now: now, 2028, 5, 5, true)
}

private func bodyLeapDay() throws {
    let now = ctx(2026, 8, 26)
    try expectDate("February 28, 2024 + 1 day", now: now, 2024, 2, 29, true)
    try expectDate("February 28, 2026 + 1 day", now: now, 2026, 3, 1, true)
    try expectDateError("February 29 + 1 day", now: now)
    try expectDate("Feb 28 2000 + 1 day", now: now, 2000, 2, 29, true)
    try expectDateError("Feb 29 1900")
}

private func bodyDurations() throws {
    let now = ctx(2026, 8, 26)
    try expectDate("May 5 + 4 weeks", now: now, 2026, 6, 2, false)
    try expectDate("May 5 + 1 week", now: now, 2026, 5, 12, false)
    try expectDate("May 5 - 10 days", now: now, 2026, 4, 25, false)
    try expectDate("May 31 + 1 month", now: now, 2026, 6, 30, false)
    try expectDate("Jan 31 + 1 month", now: now, 2026, 2, 28, false)
    try expectDate("Aug 31 - 1 month", now: now, 2026, 7, 31, false)
    try expectDate("May 5 - 1 week", now: now, 2026, 4, 28, false)
}

private func bodyDst() throws {
    let now = ctx(2026, 3, 7)
    try expectDate("Mar 7 + 1 day", now: now, 2026, 3, 8, false)
    try expectDate("Mar 8 + 1 day", now: now, 2026, 3, 9, false)
    let now2 = ctx(2026, 10, 31)
    try expectDate("Oct 31 + 1 day", now: now2, 2026, 11, 1, false)
}

private func bodyInvalid() throws {
    let now = ctx(2026, 8, 26)
    try expectDateError("May 32 + 1 day", now: now)
    try expectDateError("Feb 30 2026")
    try expectDateError("May 5 + 1000001 days", now: now)
    try expectDateError("May 5 + 99999999999999999999 days", now: now)
    try expectDateError("9999 Dec 31 + 1 day", now: now)
    try expectDateError("Dec 31 + 1000000 years", now: now)
}

private func bodyMalformed() throws {
    let now = ctx(2026, 8, 26)
    try expectDateError("May 5 + 43", now: now)
    try expectDateError("May 5 + 43 days extra", now: now)
    try expectDate("May 5 + -3 days", now: now, 2026, 5, 2, false)
    try expectDateError("May 5, 2026, 2027")
    for prose in ["may the force be with you", "May", "spring cleaning"] {
        var vars: [String: Double] = [:]
        let r = evalLine(prose, variables: &vars, rates: Rates(), decimalPlaces: 7,
                         now: now.now, calendar: now.calendar)
        if case .error? = r {
            try expect(false, "prose must not error: \(prose)")
        }
        if case .number(let v, nil)? = r {
            try expect(false, "prose must not be a number: \(prose) → \(v)")
        }
    }
}

private func bodyResultType() throws {
    let now = ctx(2026, 8, 26)
    let src = "May 5 + 43 days"
    let content = src + "\n" + M
    let ids = [UUID(), UUID()]
    let refs = [AnswerReference(sourceLineID: ids[0], labelLine: 1,
                                location: (src as NSString).length + 1)]
    let (lines, tokens) = resolveSheet(content: content, lineIDs: ids, references: refs,
                                       rates: Rates(), decimalPlaces: 7,
                                       now: now.now, calendar: now.calendar)
    if case .date = lines[0].result {
        try expect(true, "source line is .date")
    } else {
        try expect(false, "source must be .date, got \(lines[0].result)")
    }
    if case .brokenToken = lines[1].result {
        try expect(true, "date source cannot mint a numeric token")
    } else {
        try expect(false, "token over a date must be broken, got \(lines[1].result)")
    }
    try expectEqual(tokens.count, 1, "one token state")
    if case .broken = tokens[0].state {
        try expect(true, "token state is broken")
    } else {
        try expect(false, "token state must be broken")
    }
}

private func bodySheetNow() throws {
    let now = ctx(2026, 8, 26)
    var vars: [String: Double] = [:]
    let rows = evaluateSheet("today\ntomorrow\nyesterday", variables: &vars,
                             rates: Rates(), decimalPlaces: 7,
                             now: now.now, calendar: now.calendar)
    try expectEqual(rows.count, 3, "three lines")
    if case .date(let y, let m, let d, _) = rows[0].result {
        try expect(y == 2026 && m == 8 && d == 26, "today")
    } else { try expect(false, "today row") }
    if case .date(let y, let m, let d, _) = rows[1].result {
        try expect(y == 2026 && m == 8 && d == 27, "tomorrow")
    } else { try expect(false, "tomorrow row") }
    if case .date(let y, let m, let d, _) = rows[2].result {
        try expect(y == 2026 && m == 8 && d == 25, "yesterday")
    } else { try expect(false, "yesterday row") }
}

public let dateCases: [EngineCase] = [
    EngineCase("date-ref-may-5-plus-43") { try bodyRefMay5() },
    EngineCase("date-forms") { try bodyForms() },
    EngineCase("date-relative-words") { try bodyRelativeWords() },
    EngineCase("date-year-crossing") { try bodyYearCrossing() },
    EngineCase("date-leap-day") { try bodyLeapDay() },
    EngineCase("date-durations") { try bodyDurations() },
    EngineCase("date-dst-boundary") { try bodyDst() },
    EngineCase("date-invalid-and-overflow") { try bodyInvalid() },
    EngineCase("date-malformed-never-numeric-fallback") { try bodyMalformed() },
    EngineCase("date-result-type-and-no-token") { try bodyResultType() },
    EngineCase("date-sheet-captures-one-now") { try bodySheetNow() },
]
