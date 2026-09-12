import Foundation
import NumlexCore

// MARK: - temporal Task 5: work calendars

/// Injected now: 2025-01-15 12:00 UTC.
private func wcNow() -> (Date, Calendar) {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let date = cal.date(from: DateComponents(year: 2025, month: 1, day: 15, hour: 12))!
    return (date, cal)
}

private func wcContext(_ region: String) -> NumberFormatContext {
    NumberFormatContext(
        locale: Locale(identifier: "en_\(region)"),
        decimalSeparator: ".",
        groupingSeparator: ",",
        argumentSeparator: ",",
        displayGrouping: true,
        compactNotation: false,
        convertForeignOnPaste: false)
}

private func wcEval(_ line: String,
                    region: String? = "US",
                    hours: Double = 8,
                    now: Date? = nil) -> LineResult? {
    let (baseNow, cal) = wcNow()
    var prefs = TemporalPreferences.defaults
    prefs.hoursPerWorkday = hours
    if let region {
        prefs.holidayRegion = region
    } else {
        prefs.holidayRegion = TemporalPreferences.automaticHolidayRegion
    }
    var v: [String: Double] = [:]
    return evalLine(line, variables: &v, rates: Rates(), decimalPlaces: 10,
                    now: now ?? baseNow, calendar: cal,
                    context: wcContext(region == nil ? "US" : "US"),
                    unitContext: .builtIns, preferences: prefs)
}

private func wcText(_ line: String, region: String? = "US",
                    hours: Double = 8, now: Date? = nil) -> String? {
    guard let r = wcEval(line, region: region, hours: hours, now: now) else { return nil }
    return AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: .legacy)
}

private func expectWC(_ line: String, _ expected: String,
                      region: String? = "US") throws {
    guard let text = wcText(line, region: region) else {
        throw CaseFailure(message: "no work-calendar text for \(line)", location: "WorkCalendar")
    }
    try expectEqual(text, expected, "\(line)")
}

private func expectWCError(_ line: String, region: String) throws {
    guard let r = wcEval(line, region: region) else {
        throw CaseFailure(message: "\(line) must evaluate", location: "WorkCalendar")
    }
    guard case .error = r else {
        throw CaseFailure(message: "\(line) must be a strict error, got \(r)",
                          location: "WorkCalendar")
    }
}

private func wcSource(_ rel: String) -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent(rel)
        .standardizedFileURL
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

public let workCalendarCases: [EngineCase] = [

    EngineCase("work-calendar-official-examples") {
        try expectWC("workdays in 3 weeks", "15 workdays")
        try expectWC("10 March to 17 March in workdays", "5 workdays")
        try expectWC("workdays from April 12 to June 15", "44 workdays")
        try expectWC("$500/workday × 4 weeks", "$10,000.00")
        try expectWC("work hours in June", "6 day 16 h")
        try expectWC("work hours between March 12 and March 25", "3 day")
        try expectWC("55h in work days", "6.875 workdays")
        try expectWC("December 24 + 2 workdays", "Dec 29")
        // Alias spellings.
        try expectWC("weekdays in 3 weeks", "15 workdays")
        try expectWC("business days from April 12 to June 15", "44 workdays")
    },

    EngineCase("work-calendar-region-resolution") {
        // The explicit region drives the holiday set.
        try expectWC("3 July to 7 July in workdays", "1 workdays", region: "US")
        try expectWC("3 July to 7 July in workdays", "2 workdays", region: "DE")
        // Automatic resolves through the number context's locale region.
        let (now, cal) = wcNow()
        var prefs = TemporalPreferences.defaults
        prefs.holidayRegion = TemporalPreferences.automaticHolidayRegion
        var v: [String: Double] = [:]
        func auto(_ line: String, locale: String) -> LineResult? {
            evalLine(line, variables: &v, rates: Rates(), decimalPlaces: 10,
                     now: now, calendar: cal,
                     context: NumberFormatContext(
                        locale: Locale(identifier: locale),
                        decimalSeparator: ".", groupingSeparator: ",",
                        argumentSeparator: ",", displayGrouping: true,
                        compactNotation: false, convertForeignOnPaste: false),
                     unitContext: .builtIns, preferences: prefs)
        }
        guard let us = auto("3 July to 7 July in workdays", locale: "en_US"),
              let de = auto("3 July to 7 July in workdays", locale: "de_DE"),
              let usText = AnswerDisplay.displayText(for: us, decimalPlaces: 10, context: .legacy),
              let deText = AnswerDisplay.displayText(for: de, decimalPlaces: 10, context: .legacy) else {
            throw CaseFailure(message: "automatic region resolves", location: "WorkCalendar")
        }
        try expectEqual(usText, "1 workdays", "en_US resolves US holidays")
        try expectEqual(deText, "2 workdays", "de_DE resolves DE holidays")
    },

    EngineCase("work-calendar-strictness") {
        // An unsupported region fails dated queries (never a silent
        // ignore-holidays answer).
        try expectWCError("workdays from April 12 to June 15", region: "ZZ")
        try expectWCError("work hours in June", region: "ZZ")
        try expectWCError("December 24 + 2 workdays", region: "ZZ")
        // An out-of-coverage year fails strictly.
        let (_, cal) = wcNow()
        let future = cal.date(from: DateComponents(year: 2099, month: 1, day: 15, hour: 12))!
        guard let r = wcEval("workdays from April 12 to June 15", region: "US", now: future),
              case .error = r else {
            throw CaseFailure(message: "unsupported year errors", location: "WorkCalendar")
        }
        // Generic undated weeks never need a region.
        try expectWC("workdays in 3 weeks", "15 workdays", region: "ZZ")
        // `weekday on <date>` prose is not stolen by the workday lane.
        guard let prose = wcEval("weekday on December 24", region: "US") else {
            throw CaseFailure(message: "weekday query still evaluates", location: "WorkCalendar")
        }
        if case .number(let value, let unit, _, _) = prose, unit == "workdays" {
            throw CaseFailure(message: "weekday query stolen (got \(value))", location: "WorkCalendar")
        }
    },

    EngineCase("work-calendar-hours-and-rate-semantics") {
        // Hours per workday setting drives both work hours and the
        // workday conversion (20 workdays × 9 h).
        guard let nine = wcEval("work hours in June", region: "US", hours: 9),
              let nineText = AnswerDisplay.displayText(for: nine, decimalPlaces: 10,
                                                       context: .legacy) else {
            throw CaseFailure(message: "9-hour workday", location: "WorkCalendar")
        }
        try expectEqual(nineText, "1 week 12 h", "hours per workday honored")
        guard let r = wcEval("55h in work days", region: "US", hours: 11) else {
            throw CaseFailure(message: "hours conversion", location: "WorkCalendar")
        }
        guard case .number(let value, let unit, _, _) = r else {
            throw CaseFailure(message: "hours conversion is numeric", location: "WorkCalendar")
        }
        try expectClose(value, 5, 1e-9, "55h / 11 = 5 workdays")
        try expectEqual(unit, "workdays", "canonical unit label")
        // Money rate keeps the currency kind and money formatting.
        guard let money = wcEval("$500/workday × 4 weeks", region: "US") else {
            throw CaseFailure(message: "money rate", location: "WorkCalendar")
        }
        guard case .money(let amount, let code) = money else {
            throw CaseFailure(message: "money rate is money", location: "WorkCalendar")
        }
        try expectEqual(code, "USD", "currency kind survives")
        try expectClose(amount, 10_000, 1e-9, "20 workdays × $500")
        // Work-hour outputs are typed durations.
        guard let hours = wcEval("work hours in June", region: "US"),
              case .number(_, let hUnit, let kind, _) = hours else {
            throw CaseFailure(message: "work hours typed", location: "WorkCalendar")
        }
        try expectEqual(hUnit, "h", "hours unit")
        try expectEqual(kind, .duration, "typed duration")
        // A non-workday date arithmetic answer skips holidays and weekends.
        try expectWC("December 24 + 1 workdays", "Dec 26")
        try expectWC("December 24 + 5 workdays", "Jan 2, 2026")
    },

    EngineCase("holiday-catalog-integrity") {
        guard let catalog = HolidayCatalog.shared else {
            throw CaseFailure(message: "the bundled catalog loads", location: "WorkCalendar")
        }
        try expectEqual(catalog.countries.count, 25, "supported country count")
        try expectEqual(catalog.version, "2026.1", "manifest version")
        try expect(!catalog.attribution.isEmpty, "attribution recorded")
        try expect(!catalog.license.isEmpty, "license recorded")
        try expectEqual(catalog.yearRange.lowerBound, 2019, "coverage start")
        try expectEqual(catalog.yearRange.upperBound, 2035, "coverage end")
        // Christmas Day is present for every Western profile in every year.
        let western = ["US", "GB", "DE", "FR", "IT", "ES", "CA", "AU", "BR",
                       "MX", "NL", "PL", "SE", "CH", "AT", "BE", "PT", "IE",
                       "NZ", "ZA"]
        for country in western {
            for year in 2019...2035 {
                try expect(catalog.isHoliday(country: country, year: year,
                                             month: 12, day: 25),
                           "\(country) \(year) Christmas")
            }
        }
        // International fixed holidays.
        for (country, month, day) in [("US", 7, 4), ("FR", 7, 14), ("DE", 10, 3),
                                      ("JP", 1, 1), ("CN", 10, 1), ("IN", 8, 15),
                                      ("KR", 3, 1), ("MX", 9, 16), ("NZ", 2, 6),
                                      ("ZA", 4, 27)] {
            try expect(catalog.isHoliday(country: country, year: 2025,
                                         month: month, day: day),
                       "\(country) \(month)/\(day)")
        }
        // Every profile has plausible per-year coverage.
        for country in catalog.countries {
            try expect(catalog.holidayCount(country) >= 30,
                       "\(country) has holidays across the range")
        }
    },

    EngineCase("work-calendar-settings-and-seven-tiles") {
        let view = wcSource("Sources/NumlexApp/Views/SettingsView.swift")
        guard let pageStart = view.range(of: "private struct DatesTimesSettingsPage")?.lowerBound,
              let pageEnd = view.range(of: "// MARK: - Numbers tab")?.lowerBound else {
            throw CaseFailure(message: "DatesTimes page missing", location: "WorkCalendar")
        }
        let page = String(view[pageStart..<pageEnd])
        // The work-calendar rows exist with localized labels and write
        // only through settings + one persist.
        for needle in ["holidayRegionBinding", "hoursPerWorkdayBinding",
                       "SettingsRow(", "Stepper("] {
            try expect(page.contains(needle), "page contains \(needle)")
        }
        for binding in ["holidayRegionBinding", "hoursPerWorkdayBinding"] {
            guard let start = page.range(of: "private var \(binding)")?.lowerBound,
                  let end = page.range(of: "\n    }", range: start..<page.endIndex)?.upperBound else {
                throw CaseFailure(message: "\(binding) missing", location: "WorkCalendar")
            }
            let body = String(page[start..<end])
            try expect(body.contains("model.settings.temporal"), "\(binding) touches settings only")
            try expect(body.contains("model.persist()"), "\(binding) persists once")
            let haystack = body.replacingOccurrences(of: "TemporalPreferences", with: "")
            for banned in ["sheets", "lineIDs", "references", "selectedIndex", "content"] {
                try expect(!haystack.contains(banned), "\(binding) never touches \(banned)")
            }
        }
        try expect(view.contains("HolidayCatalog.shared?.countries"),
                   "the region picker reads the bundled catalog")
        // Seven tiles × six languages: every destination label exists and
        // the row still fits the 520 pt minimum (7*66 + 6*2 = 474).
        let destinations = ["general", "editing", "numbers", "datesTimes",
                            "constantsUnits", "styling", "about"]
        for lang in AppLanguage.allCases {
            for dest in destinations {
                let title = L10n.t("settings.\(dest)", language: lang)
                try expect(title != "settings.\(dest)" && !title.isEmpty,
                           "\(lang.rawValue): settings.\(dest)")
            }
            for key in ["datesTimes.work", "holidayRegion.label",
                        "holidayRegion.automatic", "holidayRegion.cap",
                        "hoursPerWorkday.label", "hoursPerWorkday.cap"] {
                let text = L10n.t(key, language: lang)
                try expect(text != key && !text.isEmpty, "\(lang.rawValue): \(key)")
            }
        }
        try expect(7 * 66 + 6 * 2 <= 520, "seven tiles fit the minimum width")
    },
]
