import Foundation
import NumlexCore

// MARK: - temporal Task 2: timestamps and ISO date-times

/// Injected now: 2019-04-01 12:00 Paris (CEST, UTC+2) — the exact source
/// zone of the ISO example. All cases are independent of the host locale.
private func tsNow() -> (Date, Calendar) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let date = cal.date(from: DateComponents(year: 2019, month: 4, day: 1,
                                             hour: 12, minute: 0))!
    return (date, cal)
}

private let tsContext24 = NumberFormatContext(
    locale: Locale(identifier: "fr_FR"),
    decimalSeparator: ",",
    groupingSeparator: " ",
    argumentSeparator: ";",
    displayGrouping: true,
    compactNotation: false,
    convertForeignOnPaste: false)

private func tsEval(_ line: String, context: NumberFormatContext = .legacy) -> LineResult? {
    let (now, cal) = tsNow()
    var v: [String: Double] = [:]
    return evalLine(line, variables: &v, rates: Rates(), decimalPlaces: 10,
                    now: now, calendar: cal, context: context,
                    unitContext: .builtIns)
}

private func tsText(_ line: String, context: NumberFormatContext = .legacy) -> String? {
    guard let r = tsEval(line, context: context) else { return nil }
    return AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: context)
}

private func expectTS(_ line: String, _ expected: String,
                      context: NumberFormatContext = .legacy) throws {
    guard let text = tsText(line, context: context) else {
        throw CaseFailure(message: "no timestamp text for \(line)", location: "Timestamp")
    }
    try expectEqual(text, expected, "\(line)")
}

public let timestampCases: [EngineCase] = [

    EngineCase("timestamp-official-examples") {
        // The six user examples under the injected zone (UTC+2 in April).
        try expectTS("April 1, 2019 3:30pm as iso8601",
                     "2019-04-01T15:30:00+02:00")
        try expectTS("2019-04-01T15:30:00 to date",
                     "Apr 1, 2019 3:30:00 pm")
        try expectTS("April 1, 2019 to timestamp",
                     "1,554,112,800")
        try expectTS("current timestamp",
                     "1,554,112,800")
        // 1559740303.48 = 2019-06-05T13:11:43.48Z -> Paris 15:11:43.48.
        guard let epochRow = tsEval("1559740303.48 to date"),
              case .dateTime(let y, let mo, let d, _, _, _, _, _, _) = epochRow else {
            throw CaseFailure(message: "epoch to date is typed", location: "Timestamp")
        }
        try expectEqual(y, 2019, "epoch year")
        try expectEqual(mo, 6, "epoch month")
        try expectEqual(d, 5, "epoch day")
        // 1733823083000 ms = 2024-12-10T09:31:23Z -> Paris 10:31:23.
        guard let msRow = tsEval("1733823083000 to date"),
              case .dateTime(let my, let mm, let md, let mh, let mmin, let ms, _, _, _) = msRow else {
            throw CaseFailure(message: "milliseconds to date is typed", location: "Timestamp")
        }
        try expect(my == 2024 && mm == 12 && md == 10 && mh == 10 && mmin == 31 && ms == 23,
                   "millisecond threshold conversion got \(my)-\(mm)-\(md) \(mh):\(mmin):\(ms)")
    },

    EngineCase("timestamp-iso-forms") {
        // Z, explicit offsets, optional seconds and fraction.
        try expectTS("2019-04-01T15:30:00Z to date", "Apr 1, 2019 3:30:00 pm")
        try expectTS("2019-04-01T15:30:00+05:30 to date", "Apr 1, 2019 3:30:00 pm")
        try expectTS("2019-04-01T15:30 to date", "Apr 1, 2019 3:30 pm")
        try expectTS("2019-04-01T15:30:00.500Z to date",
                     "Apr 1, 2019 3:30:00 pm")
        // A lowercase separator and ±HHMM offsets are tolerated.
        try expectTS("2019-04-01t15:30:00Z to date", "Apr 1, 2019 3:30:00 pm")
        try expectTS("2019-04-01T15:30:00+0530 to date", "Apr 1, 2019 3:30:00 pm")
        // Normalizing an ISO input preserves its explicit offset.
        try expectTS("2019-04-01T15:30:00+05:30 as iso8601",
                     "2019-04-01T15:30:00+05:30")
        try expectTS("2019-04-01T15:30:00Z as iso8601",
                     "2019-04-01T15:30:00Z")
        // ISO to timestamp is symmetric with timestamp to date.
        guard let row = tsEval("2019-04-01T12:00:00+02:00 to timestamp"),
              case .timestamp(let seconds) = row else {
            throw CaseFailure(message: "ISO to timestamp is typed", location: "Timestamp")
        }
        try expectClose(seconds, 1_554_112_800, 1e-6, "ISO epoch")
    },

    EngineCase("timestamp-threshold-and-negative") {
        // The documented >= 1e12 magnitude threshold, boundary included.
        guard let below = tsEval("999999999999 to date"),
              case .dateTime = below else {
            throw CaseFailure(message: "below threshold is seconds", location: "Timestamp")
        }
        guard let above = tsEval("1000000000000 to date"),
              case .dateTime(let y, _, _, _, _, _, _, _, _) = above else {
            throw CaseFailure(message: "at threshold is milliseconds", location: "Timestamp")
        }
        try expectEqual(y, 2001, "1e12 ms = 2001-09-09")
        // Fractional milliseconds divide by 1000 exactly.
        guard let frac = tsEval("1733823083000.5 to date"),
              case .dateTime = frac else {
            throw CaseFailure(message: "fractional milliseconds", location: "Timestamp")
        }
        // Pre-1970 negatives are valid epochs.
        try expectTS("-86400 to date", "Dec 31, 1969 1:00 am")
        try expectTS("1900-01-01T00:00:00Z to date", "Jan 1, 1900 12:00:00 am")
    },

    EngineCase("timestamp-symmetry-and-dst") {
        // seconds -> date -> local noon; the reverse composes.
        try expectTS("1554112800 to date", "Apr 1, 2019 12:00 pm")
        try expectTS("April 1, 2019 12:00pm as timestamp", "1,554,112,800")
        // Leap date.
        try expectTS("2020-02-29T12:00:00Z to date", "Feb 29, 2020 12:00:00 pm")
        // A DST offset change: April 1 2019 is CEST (+02:00); the explicit
        // winter offset is preserved on iso output.
        try expectTS("2019-03-31T01:30:00+01:00 as iso8601",
                     "2019-03-31T01:30:00+01:00")
        // Local-zone DST lookup: a January noon in Paris is +01:00.
        try expectTS("2019-01-15T12:00:00 as iso8601",
                     "2019-01-15T12:00:00+01:00")
        // A nonexistent local wall time (spring-forward gap) fails closed.
        guard let gap = tsEval("2019-03-31T02:30:00 to date") else {
            return
        }
        if case .dateTime = gap {
            throw CaseFailure(message: "the DST gap must not resolve", location: "Timestamp")
        }
    },

    EngineCase("timestamp-regional-24h-and-ordering") {
        // 24-hour clock style, deterministic English date ordering.
        try expectTS("2019-04-01T15:30:00 to date", "Apr 1, 2019 15:30:00",
                     context: tsContext24)
        try expectTS("2019-04-01T15:30:00Z to date", "Apr 1, 2019 15:30:00",
                     context: tsContext24)
        // The timestamp number uses the regional separators.
        try expectTS("current timestamp", "1 554 112 800", context: tsContext24)
    },

    EngineCase("timestamp-strictness-and-overflow") {
        // Malformed ISO shapes never resolve to a date-time.
        for line in ["2019-13-01T15:30:00 to date",
                     "2019-04-32T15:30:00 to date",
                     "2019-04-01T25:30:00 to date",
                     "2019-04-01T15:30:00+25:00 to date",
                     "2019-04-01T15:30:00 extra to date",
                     "not-a-date to date"] {
            if let r = tsEval(line), case .dateTime = r {
                throw CaseFailure(message: "\(line) must not resolve to date-time",
                                  location: "Timestamp")
            }
        }
        // Overflow / non-finite epochs never produce a typed row.
        for line in ["9999999999999999999 to date", "1e20 to date", "nan to date"] {
            if let r = tsEval(line), case .dateTime = r {
                throw CaseFailure(message: "\(line) must not resolve", location: "Timestamp")
            }
            if let r = tsEval(line), case .timestamp = r {
                throw CaseFailure(message: "\(line) must not resolve", location: "Timestamp")
            }
        }
        // An unparsable `as iso8601` body is a strict error, not silence.
        guard let bad = tsEval("hello world as iso8601"), case .error = bad else {
            throw CaseFailure(message: "unparsable iso body errors", location: "Timestamp")
        }
    },

    EngineCase("timestamp-totals-and-previous-answer-exclusion") {
        let dt = LineResult.dateTime(year: 2019, month: 4, day: 1, hour: 15, minute: 30,
                                     second: 0, hasSeconds: false,
                                     utcOffsetSeconds: 7200, iso: true)
        let epoch = LineResult.timestamp(seconds: 1_554_112_800)
        // No numerical contribution anywhere.
        try expect(SheetFooterTotal.contribution(of: dt, isTotalRow: false) == nil,
                   "date-time never enters the footer")
        try expect(SheetFooterTotal.contribution(of: epoch, isTotalRow: false) == nil,
                   "timestamp never enters the footer")
        try expect(InlineTotal.contribution(of: dt, isTotalRow: false) == nil,
                   "date-time never enters inline totals")
        try expect(InlineTotal.contribution(of: epoch, isTotalRow: false) == nil,
                   "timestamp never enters inline totals")
        try expect(!PreviousAnswerPlan.isAnswerable(dt), "date-time is not an answer source")
        try expect(!PreviousAnswerPlan.isAnswerable(epoch), "timestamp is not an answer source")
        // Copy/Delete menu, but no notation and no rounding.
        try expectEqual(AnswerDisplay.menu(for: dt),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                        "date-time menu")
        try expectEqual(AnswerDisplay.menu(for: epoch),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                        "timestamp menu")
        try expect(AnswerDisplay.notationOptions(for: dt) == nil, "no notation for date-time")
        try expect(AnswerDisplay.notationOptions(for: epoch) == nil, "no notation for timestamp")
        // Copy == visible.
        try expectEqual(AnswerDisplay.text(for: dt, decimalPlaces: 10, context: .legacy),
                        "2019-04-01T15:30:00+02:00", "date-time copy")
        try expectEqual(AnswerDisplay.text(for: epoch, decimalPlaces: 10, context: .legacy),
                        "1,554,112,800", "timestamp copy")
        // A token referencing a date-time source stays broken, never a
        // smuggled numeric value.
        let marker = "\u{FFFC}"
        let id0 = UUID(), id1 = UUID()
        let content = "April 1, 2019 3:30pm as iso8601\n\(marker)"
        let resolved = resolveSheet(content: content, lineIDs: [id0, id1],
                                    references: [AnswerReference(sourceLineID: id0,
                                                                 labelLine: 1, location: 40)],
                                    rates: Rates(), decimalPlaces: 10)
        guard case .dateTime = resolved.lines[0].result else {
            throw CaseFailure(message: "the source row is a date-time", location: "Timestamp")
        }
        guard case .brokenToken = resolved.lines[1].result else {
            throw CaseFailure(message: "the token stays broken", location: "Timestamp")
        }
    },
]
