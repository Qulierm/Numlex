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
