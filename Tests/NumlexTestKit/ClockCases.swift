import Foundation
import NumlexCore

// MARK: - Clock / laptime lane (Task 2)

private func clockLine(_ line: String,
                       context: NumberFormatContext = .legacy,
                       now: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> LineResult? {
    var variables: [String: Double] = [:]
    return evalLine(line, variables: &variables, rates: Rates(), decimalPlaces: 10,
             now: now, calendar: Calendar(identifier: .gregorian),
             context: context, unitContext: .builtIns)
}

private func clockText(_ line: String,
                       context: NumberFormatContext = .legacy,
                       now: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws -> String {
    guard let r = clockLine(line, context: context, now: now),
          let text = AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: context) else {
        throw CaseFailure(message: "no temporal text for \(line)", location: "Clock")
    }
    return text
}

private func expectClock(_ line: String, _ expected: String,
                         context: NumberFormatContext = .legacy,
                         now: Date = Date(timeIntervalSince1970: 1_700_000_000)) throws {
    let got = try clockText(line, context: context, now: now)
    try expectEqual(got, expected, "\(line) -> \(expected)")
}

private func expectClockError(_ line: String) throws {
    guard let r = clockLine(line) else {
        throw CaseFailure(message: "line must evaluate: \(line)", location: "Clock")
    }
    guard case .error = r else {
        throw CaseFailure(message: "\(line) must be a strict error, got \(r)", location: "Clock")
    }
}

private var europeanContext: NumberFormatContext {
    NumberFormatContext(locale: Locale(identifier: "de_DE"), decimalSeparator: ",",
                        groupingSeparator: ".", argumentSeparator: ";",
                        displayGrouping: true, compactNotation: false,
                        convertForeignOnPaste: true, legacy: false)
}

public let clockCases: [EngineCase] = [

    EngineCase("clock-arithmetic-with-durations") {
        try expectClock("3:30pm + 2 hours 15 minutes", "5:45 pm")
        try expectClock("3:30pm - 2 hours 15 minutes", "1:15 pm")
        try expectClock("3:30pm + 45 min", "4:15 pm")
        try expectClock("3:30pm + 3h 25min", "6:55 pm")
        try expectClock("11:30pm + 45 min", "Tomorrow 12:15 am")
        try expectClock("12:30am - 45 min", "Yesterday 11:45 pm")
        try expectClock("9:05am + 0 min", "9:05 am")
        // The seconds field is preserved when the clock carried one.
        try expectClock("3:30:15pm + 2 hours", "5:30:15 pm")
    },

    EngineCase("clock-wall-minutes-survive-dst") {
        // Wall-component arithmetic: the requested minutes are added to the
        // WALL clock, so a DST transition can never move them.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        // 2024-03-10 is the US spring-forward day (2 am -> 3 am).
        let dstNow = cal.date(from: DateComponents(year: 2024, month: 3, day: 10,
                                                   hour: 1, minute: 30))!
        var v: [String: Double] = [:]
        let result = evalLine("1:30am + 2 hours", variables: &v, rates: Rates(),
                              decimalPlaces: 10, now: dstNow, calendar: cal,
                              context: .legacy, unitContext: .builtIns)
        guard let r = result else { throw CaseFailure(message: "no result", location: "Clock") }
        try expectEqual(r, .clock(hour: 3, minute: 30, second: 0, hasSeconds: false, dayOffset: 0),
                        "1:30am + 2 h is 3:30am wall time across the DST jump")
    },

    EngineCase("clock-now-arithmetic-is-deterministic") {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        let now = cal.date(from: DateComponents(year: 2024, month: 6, day: 1,
                                                hour: 10, minute: 20, second: 0))!
        var v: [String: Double] = [:]
        let r = evalLine("now + 3 hours 25 minutes", variables: &v, rates: Rates(),
                         decimalPlaces: 10, now: now, calendar: cal,
                         context: .legacy, unitContext: .builtIns)
        try expectEqual(r, .clock(hour: 13, minute: 45, second: 0,
                                  hasSeconds: false, dayOffset: 0),
                        "10:20 + 3 h 25 min = 1:45 pm")
        let next = evalLine("now + 20 hours", variables: &v, rates: Rates(),
                            decimalPlaces: 10, now: now, calendar: cal,
                            context: .legacy, unitContext: .builtIns)
        try expectEqual(next, .clock(hour: 6, minute: 20, second: 0,
                                     hasSeconds: false, dayOffset: 1),
                        "20 hours later is tomorrow 6:20 am")
    },

    EngineCase("clock-clock-is-a-strict-error") {
        try expectClockError("3:30pm + 3:30pm")
        try expectClockError("3:30pm - 3:30pm")
    },

    EngineCase("laptime-arithmetic") {
        try expectClock("01:02:03 + 01:09:54", "02:11:57")
        try expectClock("01:02:03 - 00:00:03", "01:02:00")
        try expectClock("00:00:01.5 + 00:00:01", "00:00:02.50")
        try expectClock("00:00:01.5 + 00:00:01.5", "00:00:03")
        try expectClock("10:00:00 - 12:30:00", "-02:30:00")
        // The explicit bridge.
        try expectClock("01:02:03 as laptime", "01:02:03")
        try expectClock("2 hours as laptime", "02:00:00")
        try expectClock("3:30pm as laptime", "15:30:00")
    },

    EngineCase("clock-intervals-are-forward-and-circular") {
        try expectClock("7:30am to 8:45pm", "13 h 15 min")
        try expectClock("4pm to 3am", "11 h")
        try expectClock("9am to 5pm", "8 h")
        try expectClock("10:00am to 10:30am", "30 min")
        try expectClock("10:00:30am to 10:01:00am", "30 s")
    },

    EngineCase("clock-validation-and-region-display") {
        try expectClockError("25:00")
        try expectClockError("25:00 + 1 hour")
        try expectClockError("13:00pm")
        try expectClockError("10:75")
        try expectClockError("10:10:75")
        // A bare 12-hour clock is owned; a bare 24-hour clock is untouched.
        try expectClock("3:30pm", "3:30 pm")
        try expectClock("12:00am", "12:00 am")
        try expectClock("12:00pm", "12:00 pm")
        // AM/PM is case-insensitive, glued or spaced.
        try expectClock("3:30PM", "3:30 pm")
        try expectClock("3:30 pm", "3:30 pm")
        // Region display: the European context renders 24-hour.
        try expectClock("17:45 + 2 hours", "19:45", context: europeanContext)
        try expectClock("3:30pm + 2 hours 15 minutes", "17:45", context: europeanContext)
        // Visible/copy parity for every clock form.
        for line in ["3:30pm + 2 hours 15 minutes", "01:02:03 + 01:09:54",
                     "7:30am to 8:45pm", "3:30pm"] {
            guard let r = clockLine(line) else {
                throw CaseFailure(message: "\(line) must evaluate", location: "Clock")
            }
            try expectEqual(AnswerDisplay.text(for: r, decimalPlaces: 10, context: .legacy),
                            AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: .legacy),
                            "\(line): copy == visible")
            // A temporal row offers Copy/Delete only and never a notation.
            try expectEqual(AnswerDisplay.notationOptions(for: r), nil,
                            "\(line): no notation")
            try expectEqual(AnswerDisplay.menu(for: r),
                            AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                            "\(line): Copy/Delete only")
            // A clock/laptime value is never numeric; an interval returns an
            // ordinary time QUANTITY (`13 h 15 min`), which follows the
            // pre-existing unit-bearing duration policy.
            if case .clock = r {
                try expectEqual(SheetFooterTotal.contribution(of: r, isTotalRow: false), nil,
                                "\(line): a clock never enters the Total")
            } else if case .laptime = r {
                try expectEqual(SheetFooterTotal.contribution(of: r, isTotalRow: false), nil,
                                "\(line): a laptime never enters the Total")
            }
        }
    },

    EngineCase("clock-does-not-steal-other-lanes") {
        // Dates, durations, units, money and 5m/5 m keep their lanes.
        try expectClock("May 5 + 43 days", "Jun 17")
        try expectClock("1 h 45 min + 30 min", "2 h 15 min")
        try expectClock("5m", "5,000,000")
        try expectClock("5 m", "5 m")
        try expectClock("$24 per day × 12 hrs", "$12.00")
        try expectClock("90 km / 3 h", "30 km/h")
        try expectClock("500 ms to s", "0.5 s")
        try expectClock("2 h 30 min / 5", "30 min")
    }
]
