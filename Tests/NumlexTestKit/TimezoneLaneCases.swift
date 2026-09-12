import Foundation
import NumlexCore

private func tzNow(_ zone: String = "Europe/Paris") -> (Date, Calendar) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: zone) ?? .current
    let date = cal.date(from: DateComponents(year: 2024, month: 6, day: 15,
                                             hour: 12, minute: 0))!
    return (date, cal)
}

private func tzLine(_ line: String, zone: String = "Europe/Paris") -> LineResult? {
    let (now, cal) = tzNow(zone)
    var v: [String: Double] = [:]
    return evalLine(line, variables: &v, rates: Rates(), decimalPlaces: 10,
                    now: now, calendar: cal, context: .legacy, unitContext: .builtIns)
}

private func expectTz(_ line: String, _ expected: String,
                      zone: String = "Europe/Paris") throws {
    guard let r = tzLine(line, zone: zone),
          let text = AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: .legacy) else {
        throw CaseFailure(message: "no timezone text for \(line)", location: "TimezoneLane")
    }
    try expectEqual(text, expected, "\(line) -> \(expected)")
}

public let timezoneLaneCases: [EngineCase] = [

    EngineCase("timezone-lane-exact-user-corpus") {
        // Injected now: 2024-06-15 12:00 Paris (CEST, UTC+2).
        try expectTz("time in Paris", "12:00 pm")
        try expectTz("Tokyo time", "7:00 pm")
        try expectTz("date in Vancouver", "Jun 15")
        try expectTz("6pm Sydney in Chicago", "3:00 am")
        try expectTz("2am PST to GMT", "10:00 am")
        try expectTz("3pm GMT+8 to Paris", "9:00 am")
        try expectTz("7:30am LAX to Japan", "11:30 pm")
        try expectTz("time difference between Chicago and Paris", "7 h")
        try expectTz("difference between PDT & AEST", "17 h")
        try expectTz("difference between Chicago and Paris", "7 h")
    },

    EngineCase("timezone-lane-anchoring-and-round-trip") {
        // The source wall time is anchored on the CAPTURED date in its zone;
        // the conversion preserves the instant.
        try expectTz("6pm Sydney in Paris", "10:00 am")
        // Round-trip: the instant (and therefore the wall time) survives.
        let out = tzLine("6pm Sydney in Paris")
        guard case .clock(let h, let m, _, _, let day)? = out else {
            throw CaseFailure(message: "a clock result", location: "TimezoneLane")
        }
        try expectEqual(h, 10, "Sydney 6pm is Paris 10am")
        try expectEqual(m, 0, "minutes preserved")
        try expectEqual(day, 0, "same local day")
        // The reverse conversion returns to the original instant.
        try expectTz("10am Paris in Sydney", "6:00 pm")
    },

    EngineCase("timezone-lane-resolution-sources") {
        // IANA id, city, country name, country code, IATA and ICAO all resolve.
        try expectTz("time in Europe/Paris", "12:00 pm")
        try expectTz("time in Paris, FR", "12:00 pm")
        try expectTz("time in Tokyo", "7:00 pm")
        try expectTz("time in Japan", "7:00 pm")
        try expectTz("time in JP", "7:00 pm")
        try expectTz("time in LAX", "3:00 am")
        try expectTz("time in KLAX", "3:00 am")
        // A validated custom alias resolves through the catalog (the
        // resolution order is covered by the catalog tests); an unknown
        // place still fails closed on a timezone-shaped line.
        var preferences = TemporalPreferences.defaults
        preferences.customTimeZones = [CustomTimeZone(name: "HQ", identifier: "Asia/Tokyo")]
        try expectEqual(preferences.customTimeZones[0].isValid, true, "the alias is valid")
        guard let unknown = tzLine("time in HQ") else {
            throw CaseFailure(message: "a custom alias is not a bundled city",
                              location: "TimezoneLane")
        }
        if case .error = unknown {
            // expected: the bundled catalog does not know `HQ` on its own
        } else {
            throw CaseFailure(message: "HQ must not resolve without the live preferences",
                              location: "TimezoneLane")
        }
    },

    EngineCase("timezone-lane-strictness-and-no-theft") {
        for line in ["time in Nowhereville", "date in Not/AZone", "time in Atlantis"] {
            guard let r = tzLine(line) else {
                throw CaseFailure(message: "\(line) must evaluate to an error", location: "TimezoneLane")
            }
            guard case .error = r else {
                throw CaseFailure(message: "\(line) must be a strict error, got \(r)",
                                  location: "TimezoneLane")
            }
        }
        // Plain clocks, dates, conversions and geo lines keep their lanes.
        try expectTz("6pm", "6:00 pm")
        try expectTz("3pm", "3:00 pm")
        try expectTz("May 5 + 2 days", "May 7")
        try expectTz("5 parsecs to m", "1.542839e+17 m")
        try expectTz("5 km to m", "5,000 m")
        try expectTz("3:30pm + 2 hours", "5:30 pm")
        try expectTz("1 h 45 min + 30 min", "2 h 15 min")
    },

    EngineCase("timezone-lane-display-and-total-behavior") {
        let cases = ["time in Paris", "date in Vancouver", "6pm Sydney in Chicago",
                     "time difference between Chicago and Paris"]
        for line in cases {
            guard let r = tzLine(line) else {
                throw CaseFailure(message: "\(line) must evaluate", location: "TimezoneLane")
            }
            try expectEqual(AnswerDisplay.text(for: r, decimalPlaces: 10, context: .legacy),
                            AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: .legacy),
                            "\(line): copy == visible")
            try expectEqual(AnswerDisplay.notationOptions(for: r), nil,
                            "\(line): no number notation")
            if case .clock = r {
                try expectEqual(SheetFooterTotal.contribution(of: r, isTotalRow: false), nil,
                                "\(line): a clock never enters the Total")
                try expectEqual(AnswerDisplay.menu(for: r),
                                AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                                "\(line): Copy/Delete only")
            }
            if case .date = r {
                try expectEqual(SheetFooterTotal.contribution(of: r, isTotalRow: false), nil,
                                "\(line): a date never enters the Total")
            }
        }
    }
]
