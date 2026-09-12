import Foundation
import NumlexCore

// MARK: - Temporal foundations (Task 1)
//
// The one immutable temporal context, its preferences, and the presentation
// rules that the clock/timezone/calendar lanes build on.

private func json(_ text: String) -> Data { Data(text.utf8) }

public let temporalCases: [EngineCase] = [

    EngineCase("temporal-preferences-defaults-and-clamp") {
        let d = TemporalPreferences.defaults
        try expectEqual(d.hoursPerWorkday, 8, "default workday")
        try expectEqual(d.holidayRegion, "automatic", "default holiday region")
        try expectEqual(d.customTimeZones.count, 0, "no custom zones by default")
        try expectEqual(TemporalPreferences.clampedHours(0), 1, "clamped low")
        try expectEqual(TemporalPreferences.clampedHours(99), 24, "clamped high")
        try expectEqual(TemporalPreferences.clampedHours(.nan), 8, "NaN falls back")
        try expectEqual(TemporalPreferences.clampedHours(.infinity), 8, "infinity falls back")
        // The constructor clamps and caps.
        let many = (0..<150).map {
            CustomTimeZone(name: "z\($0)", identifier: "Europe/Paris")
        }
        let p = TemporalPreferences(hoursPerWorkday: 12, holidayRegion: "", customTimeZones: many)
        try expectEqual(p.hoursPerWorkday, 12, "explicit hours kept")
        try expectEqual(p.holidayRegion, "automatic", "empty region falls back")
        try expectEqual(p.customTimeZones.count, TemporalPreferences.maxCustomTimeZones,
                        "zones capped at 100")
    },

    EngineCase("temporal-preferences-tolerant-decode") {
        let decoder = JSONDecoder()
        // A missing block, an empty object, a malformed value and a wrong
        // JSON type all fall back to the defaults (never losing the store).
        try expectEqual(try decoder.decode(TemporalPreferences.self, from: json("{}")),
                        TemporalPreferences.defaults, "empty object")
        try expectEqual(try decoder.decode(TemporalPreferences.self,
                                           from: json(#"{"hoursPerWorkday": "eight"}"#)),
                        TemporalPreferences.defaults, "wrong type")
        let clamped = try decoder.decode(TemporalPreferences.self,
                                         from: json(#"{"hoursPerWorkday": 80}"#))
        try expectEqual(clamped.hoursPerWorkday, 24, "decoded value clamped")
        let partial = try decoder.decode(TemporalPreferences.self,
                                         from: json(#"{"holidayRegion": "US"}"#))
        try expectEqual(partial.holidayRegion, "US", "explicit region kept")
        try expectEqual(partial.hoursPerWorkday, 8, "missing key defaulted")
        // A malformed custom-zone entry cannot lose the whole block.
        let zones = try decoder.decode(TemporalPreferences.self,
                                       from: json(#"{"customTimeZones": [{"nope": 1}]}"#))
        try expectEqual(zones.customTimeZones.count, 1, "the entry survives")
        try expectEqual(zones.customTimeZones[0].isValid, false, "but is invalid")
        var valid = CustomTimeZone(name: "Paris", identifier: "Europe/Paris")
        valid = CustomTimeZone(id: valid.id, name: "Paris", identifier: "Europe/Paris")
        try expectEqual(valid.isValid, true, "a real IANA id validates")
        try expectEqual(CustomTimeZone(name: "Nowhere", identifier: "Not/AZone").isValid,
                        false, "an unknown id never validates")
    },

    EngineCase("temporal-settings-additive-and-failure-proof") {
        // A legacy store (no `temporal` key) keeps every other setting and
        // gains the defaults.
        let legacy = json(#"{"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en", "sheetName": "Sheet", "lineNumbers": true, "hideSidebarButtonWhenCollapsed": false, "showTotalBar": true, "fontColor": "white"}"#)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        try expectEqual(decoded.temporal, TemporalPreferences.defaults,
                        "missing temporal block defaults")
        try expectEqual(decoded.decimalPlaces, 10, "the rest of the store survives")
        // A malformed temporal block cannot lose the store either.
        let malformed = json(#"{"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en", "sheetName": "Sheet", "lineNumbers": true, "hideSidebarButtonWhenCollapsed": false, "showTotalBar": true, "fontColor": "white", "temporal": 42}"#)
        let recovered = try JSONDecoder().decode(AppSettings.self, from: malformed)
        try expectEqual(recovered.temporal, TemporalPreferences.defaults,
                        "a malformed block is ignored")
        // Round-trip through Codable keeps the preferences byte-stable.
        var settings = AppSettings()
        settings.temporal.hoursPerWorkday = 7.5
        settings.temporal.holidayRegion = "US"
        settings.temporal.customTimeZones = [CustomTimeZone(name: "Paris", identifier: "Europe/Paris")]
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(back.temporal, settings.temporal, "round-trip")
    },

    EngineCase("temporal-clock-style-from-context") {
        try expectEqual(ClockStyle.forContext(.legacy), .twelveHour, "legacy is 12-hour")
        let northAmerica = NumberFormatContext(
            locale: Locale(identifier: "en_US"), decimalSeparator: ".",
            groupingSeparator: ",", argumentSeparator: ",", displayGrouping: true,
            compactNotation: true, convertForeignOnPaste: false, legacy: false)
        try expectEqual(ClockStyle.forContext(northAmerica), .twelveHour,
                        "northAmerica is 12-hour")
        let europe = NumberFormatContext(
            locale: Locale(identifier: "de_DE"), decimalSeparator: ",",
            groupingSeparator: ".", argumentSeparator: ";", displayGrouping: true,
            compactNotation: false, convertForeignOnPaste: true, legacy: false)
        try expectEqual(ClockStyle.forContext(europe), .twentyFourHour,
                        "westernEurope is 24-hour")
        // The SYSTEM context follows the injected locale's hour cycle.
        let system24 = NumberFormatContext(
            locale: Locale(identifier: "fr_FR"), decimalSeparator: ",",
            groupingSeparator: " ", argumentSeparator: ";", displayGrouping: true,
            compactNotation: false, convertForeignOnPaste: false, legacy: false)
        try expectEqual(ClockStyle.forContext(system24), .twentyFourHour,
                        "the system context honors the locale hour cycle")
    },

    EngineCase("temporal-clock-and-laptime-presentation") {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Paris") ?? .current
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twelve = TemporalContext(now: now, calendar: cal,
                                     timeZone: cal.timeZone, clockStyle: .twelveHour)
        let twentyFour = TemporalContext(now: now, calendar: cal,
                                         timeZone: cal.timeZone, clockStyle: .twentyFourHour)
        // 12-hour: no leading zero on the hour, lowercase am/pm, seconds only
        // when the value carries them.
        try expectEqual(twelve.clockText(hour: 17, minute: 45, second: 0, hasSeconds: false),
                        "5:45 pm", "12-hour evening")
        try expectEqual(twelve.clockText(hour: 9, minute: 5, second: 0, hasSeconds: false),
                        "9:05 am", "12-hour morning pads minutes")
        try expectEqual(twelve.clockText(hour: 0, minute: 0, second: 0, hasSeconds: false),
                        "12:00 am", "midnight")
        try expectEqual(twelve.clockText(hour: 12, minute: 30, second: 7, hasSeconds: true),
                        "12:30:07 pm", "noon with seconds")
        // 24-hour.
        try expectEqual(twentyFour.clockText(hour: 17, minute: 45, second: 0, hasSeconds: false),
                        "17:45", "24-hour")
        try expectEqual(twentyFour.clockText(hour: 5, minute: 5, second: 0, hasSeconds: false),
                        "05:05", "24-hour pads hours")
        // Day qualification when the wall date changes.
        try expectEqual(twelve.clockText(hour: 2, minute: 0, second: 0, hasSeconds: false,
                                         dayOffset: 1),
                        "Tomorrow 2:00 am", "tomorrow qualification")
        try expectEqual(twentyFour.clockText(hour: 23, minute: 30, second: 0, hasSeconds: false,
                                             dayOffset: -1),
                        "Yesterday 23:30", "yesterday qualification")
        // Laptime: always HH:MM:SS, fractional seconds preserved, one sign.
        try expectEqual(TemporalContext.laptimeText(seconds: 2 * 3600 + 11 * 60 + 57),
                        "02:11:57", "laptime")
        try expectEqual(TemporalContext.laptimeText(seconds: 1.5), "00:00:01.50",
                        "fractional seconds")
        try expectEqual(TemporalContext.laptimeText(seconds: -90), "-00:01:30", "negative")
        try expectEqual(TemporalContext.laptimeText(seconds: 0), "00:00:00", "zero")
        // The captured context exposes the injected now and its calendar day.
        let today = twelve.today
        let expected = cal.dateComponents([.year, .month, .day], from: now)
        try expectEqual(today.year, expected.year ?? 0, "captured year")
        try expectEqual(today.month, expected.month ?? 0, "captured month")
        try expectEqual(today.day, expected.day ?? 0, "captured day")
        try expectEqual(TemporalContext.maxYearSpan, 5000, "bounded span")
    }
]


// MARK: - temporal Task 7: the consolidated official-example corpus

/// ONE end-to-end pass over every official temporal example, each under
/// an explicit injected context (never the host locale).
private func corpusEval(_ line: String, now: Date, calendar: Calendar,
                        preferences: TemporalPreferences = .defaults,
                        hours: Double = 8) -> LineResult? {
    var prefs = preferences
    prefs.hoursPerWorkday = hours
    var v: [String: Double] = [:]
    return evalLine(line, variables: &v, rates: Rates(), decimalPlaces: 10,
                    now: now, calendar: calendar, context: .legacy,
                    unitContext: .builtIns, preferences: prefs)
}

private func corpusText(_ line: String, now: Date, calendar: Calendar,
                        preferences: TemporalPreferences = .defaults,
                        hours: Double = 8) -> String? {
    guard let r = corpusEval(line, now: now, calendar: calendar,
                             preferences: preferences, hours: hours) else { return nil }
    return AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: .legacy)
}

private func corpusParis(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12)
    -> (Date, Calendar) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Europe/Paris")!
    let date = cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    return (date, cal)
}

private func corpusExpect(_ line: String, _ expected: String,
                          now: Date, calendar: Calendar,
                          preferences: TemporalPreferences = .defaults,
                          hours: Double = 8) throws {
    guard let text = corpusText(line, now: now, calendar: calendar,
                                preferences: preferences, hours: hours) else {
        throw CaseFailure(message: "corpus: no text for \(line)", location: "TemporalCorpus")
    }
    try expectEqual(text, expected, "corpus \(line)")
}

public let temporalCorpusCases: [EngineCase] = [

        EngineCase("temporal-corpus-timezone-and-clock") {
            let (now, cal) = corpusParis(2024, 6, 15)
            try corpusExpect("time in Paris", "12:00 pm", now: now, calendar: cal)
            try corpusExpect("Tokyo time", "7:00 pm", now: now, calendar: cal)
            try corpusExpect("6pm Sydney in Chicago", "3:00 am", now: now, calendar: cal)
            try corpusExpect("2am PST to GMT", "10:00 am", now: now, calendar: cal)
            try corpusExpect("7:30am LAX to Japan", "11:30 pm", now: now, calendar: cal)
            try corpusExpect("3:30pm + 2 hours 15 minutes", "5:45 pm", now: now, calendar: cal)
            try corpusExpect("01:02:03 + 01:09:54", "02:11:57", now: now, calendar: cal)
        },

        EngineCase("temporal-corpus-timestamps-and-iso") {
            let (now, cal) = corpusParis(2019, 4, 1)
            try corpusExpect("April 1, 2019 3:30pm as iso8601",
                             "2019-04-01T15:30:00+02:00", now: now, calendar: cal)
            try corpusExpect("2019-04-01T15:30:00 to date",
                             "Apr 1, 2019 3:30:00 pm", now: now, calendar: cal)
            try corpusExpect("April 1, 2019 to timestamp", "1,554,112,800",
                             now: now, calendar: cal)
            try corpusExpect("current timestamp", "1,554,112,800", now: now, calendar: cal)
            try corpusExpect("1559740303.48 to date",
                             "Jun 5, 2019 3:11:43 pm", now: now, calendar: cal)
            try corpusExpect("1733823083000 to date",
                             "Dec 10, 2024 10:31:23 am", now: now, calendar: cal)
        },

        EngineCase("temporal-corpus-timespan") {
            let (now, cal) = corpusParis(2025, 1, 15)
            try corpusExpect("5.5 minutes as timespan", "5 min 30 s", now: now, calendar: cal)
            try corpusExpect("4.54 hours as timespan",
                             "4 hours 32 minutes 24 seconds", now: now, calendar: cal)
            try corpusExpect("72 days as timespan", "10 weeks 2 days", now: now, calendar: cal)
            try corpusExpect("3 hours 5 minutes 10 seconds", "3 h 5 min 10 s",
                             now: now, calendar: cal)
            try corpusExpect("3h 5m 10s in seconds", "11,110 s", now: now, calendar: cal)
        },

        EngineCase("temporal-corpus-timecode") {
            let (now, cal) = corpusParis(2025, 1, 15)
            let examples: [(String, String)] = [
                ("03:10:20:05 at 30 fps + 50 frames", "03:10:21:25"),
                ("00:10:20:50 @ 60 fps + 10 minutes", "00:20:20:50"),
                ("00:30:10:00 @ 24 fps in frames", "43,440 frames"),
                ("43,440 frames @ 24 fps", "00:30:10:00"),
                ("03:10:20:05 at 30 fps + 03:10:20:010", "06:20:40:15"),
                ("03:10:20:05 at 12 fps - 00:20:35:00", "02:49:45:05"),
                ("30 fps × 3 minutes", "5,400 frames"),
                ("15.6k frames / 24 fps", "650 s"),
            ]
            for (line, expected) in examples {
                try corpusExpect(line, expected, now: now, calendar: cal)
            }
        },

        EngineCase("temporal-corpus-work-calendars") {
            let (now, cal) = corpusParis(2025, 1, 15)
            var prefs = TemporalPreferences.defaults
            prefs.holidayRegion = "US"
            let examples: [(String, String)] = [
                ("workdays in 3 weeks", "15 workdays"),
                ("10 March to 17 March in workdays", "5 workdays"),
                ("$500/workday × 4 weeks", "$10,000.00"),
                ("55h in work days", "6.875 workdays"),
                ("December 24 + 2 workdays", "Dec 29"),
            ]
            for (line, expected) in examples {
                try corpusExpect(line, expected, now: now, calendar: cal,
                                 preferences: prefs)
            }
            guard let span = corpusText("workdays from April 12 to June 15",
                                        now: now, calendar: cal, preferences: prefs) else {
                throw CaseFailure(message: "corpus workday range", location: "TemporalCorpus")
            }
            try expectEqual(span, "44 workdays", "corpus workday range")
            guard let hours = corpusText("work hours in June", now: now, calendar: cal,
                                         preferences: prefs) else {
                throw CaseFailure(message: "corpus work hours", location: "TemporalCorpus")
            }
            try expectEqual(hours, "6 day 16 h", "corpus work hours")
            guard let rangeHours = corpusText("work hours between March 12 and March 25",
                                              now: now, calendar: cal,
                                              preferences: prefs) else {
                throw CaseFailure(message: "corpus work hours range", location: "TemporalCorpus")
            }
            try expectEqual(rangeHours, "3 day", "corpus work hours range")
        },

        EngineCase("temporal-corpus-official-whats-new") {
            let (now, cal) = corpusParis(2025, 1, 15)
            try corpusExpect("Easter 2027", "Mar 28, 2027", now: now, calendar: cal)
            try corpusExpect("days until Christmas", "344 days", now: now, calendar: cal)
            try corpusExpect("March 12 + 3 weeks 2 days", "Apr 4", now: now, calendar: cal)
        },
    ]
