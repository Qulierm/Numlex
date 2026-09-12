import Foundation

// MARK: - Timezone lane (Task 4)
//
// A strict lane that resolves the places the bundled TimezoneCatalog knows and
// evaluates the timezone shapes BEFORE the ordinary clock/date/geo lanes:
//
//   time in Paris            Tokyo time          date in Vancouver
//   6pm Sydney in Chicago    2am PST to GMT      3pm GMT+8 to Paris
//   7:30am LAX to Japan      time difference between Chicago and Paris
//
// A source wall time is anchored on the CAPTURED date in its own zone, turned
// into ONE absolute instant and then rendered in the target zone, so
// A -> B -> A preserves the instant. Plain clocks (`6pm`), dates and geo lines
// are never stolen; an unknown place on a timezone-shaped line is a strict
// error.
enum TimezoneLane {

    /// A resolution failure is a strict error for a timezone-shaped line.
    enum Outcome {
        case result(LineResult)
        case error(String)
        case notMine
    }

    private static let monthNames = ["january", "february", "march", "april", "may", "june",
                                     "july", "august", "september", "october", "november",
                                     "december"]

    // MARK: entry

    static func tryLine(_ line: String,
                        context: NumberFormatContext,
                        temporal: TemporalContext) -> Outcome {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return .notMine }
        guard let catalog = TimezoneCatalog.shared else { return .notMine }

        // `time difference between A and B` / `difference between A & B`.
        if let difference = differenceShape(trimmed, catalog: catalog, temporal: temporal) {
            return difference
        }
        // `time in <place>` / `<place> time` / `date in <place>`.
        if let query = queryShape(trimmed, catalog: catalog, temporal: temporal) {
            return query
        }
        // `<clock> <source> in|to <target>`.
        if let converted = conversionShape(trimmed, catalog: catalog, temporal: temporal) {
            return converted
        }
        return .notMine
    }

    // MARK: zone resolution

    /// Resolves a place phrase to an IANA zone: a validated CUSTOM alias wins,
    /// then IANA id/alias, city (with an explicit `City, CC` disambiguation),
    /// country name, country code, IATA/ICAO code, and the fixed
    /// abbreviations/`GMT±H` offsets. Returns nil for an unknown place.
    static func resolveZone(_ raw: String, catalog: TimezoneCatalog,
                            preferences: TemporalPreferences) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let key = TimezoneCatalog.normalizedName(text)
        // A validated user alias (app-global, never in `.nlx`) wins over
        // other custom aliases — but never over the BUNDLED sources: a
        // name the built-in catalog already answers (city, country,
        // IATA/ICAO, IANA id/alias, fixed abbreviation, GMT/UTC syntax)
        // keeps its bundled meaning, so a stale persisted row can never
        // steal it.
        if builtInZone(text, catalog: catalog) == nil {
            for custom in preferences.customTimeZones where custom.isValid {
                if TimezoneCatalog.normalizedName(custom.name) == key {
                    return catalog.canonicalZone(custom.identifier) ?? custom.identifier
                }
            }
        }
        return builtInZone(text, catalog: catalog)
    }

    /// The BUNDLED resolution sources only (no custom aliases): fixed
    /// abbreviations and GMT offsets, IANA id/alias, city (with an explicit
    /// `City, CC` disambiguation), country name, country code, IATA/ICAO.
    static func builtInZone(_ raw: String, catalog: TimezoneCatalog) -> String? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        // Fixed abbreviations and GMT offsets first: they are not IANA ids.
        if let fixed = fixedOffsetZone(text) { return fixed }
        // IANA id / alias.
        if let iana = catalog.canonicalZone(text) { return iana }
        // City, with an explicit country qualifier.
        switch catalog.zone(forCity: text) {
        case .zone(let zone): return zone
        case .ambiguous: return nil
        case .unknown: break
        }
        // Country name, country code, then airport codes.
        if let country = catalog.zone(forCountryName: text) { return country }
        if text.count == 2, let country = catalog.zone(forCountry: text) { return country }
        if let airport = catalog.zone(forAirportCode: text) { return airport }
        return nil
    }

    /// The fixed abbreviations and offsets: standard/daylight US zones plus
    /// `GMT`/`UTC`/`GMT±H[:MM]`. These are FIXED offsets (no DST) by design.
    static func fixedOffsetZone(_ raw: String) -> String? {
        let upper = raw.uppercased().replacingOccurrences(of: " ", with: "")
        switch upper {
        case "GMT", "UTC", "Z": return "UTC"
        case "EST": return "Etc/GMT+5"
        case "EDT": return "Etc/GMT+4"
        case "CST": return "Etc/GMT+6"
        case "CDT": return "Etc/GMT+5"
        case "MST": return "Etc/GMT+7"
        case "MDT": return "Etc/GMT+6"
        case "PST": return "Etc/GMT+8"
        case "PDT": return "Etc/GMT+7"
        case "AKST": return "Etc/GMT+9"
        case "AKDT": return "Etc/GMT+8"
        case "HST": return "Etc/GMT+10"
        // Other common fixed-name abbreviations (all fixed offsets).
        case "AEST": return "UTC+10"
        case "AEDT": return "UTC+11"
        case "ACST": return "UTC+9:30"
        case "ACDT": return "UTC+10:30"
        case "AWST": return "UTC+8"
        case "NZST": return "UTC+12"
        case "NZDT": return "UTC+13"
        case "BST": return "UTC+1"
        case "CET": return "UTC+1"
        case "CEST": return "UTC+2"
        case "EET": return "UTC+2"
        case "EEST": return "UTC+3"
        case "MSK": return "UTC+3"
        case "JST": return "UTC+9"
        case "KST": return "UTC+9"
        case "HKT": return "UTC+8"
        case "SGT": return "UTC+8"
        default: break
        }
        guard upper.hasPrefix("GMT") else { return nil }
        let rest = String(upper.dropFirst(3))
        guard rest.hasPrefix("+") || rest.hasPrefix("-") else { return nil }
        let sign = rest.hasPrefix("-") ? -1 : 1
        let body = rest.dropFirst()
        let parts = body.split(separator: ":")
        guard parts.count <= 2, let hours = Int(parts[0]), hours <= 14 else { return nil }
        var minutes = 0
        if parts.count == 2 {
            guard let m = Int(parts[1]), m >= 0, m <= 59 else { return nil }
            minutes = m
        }
        // Etc/GMT zones are POSIX-inverted (GMT+5 = UTC-5); a fractional
        // offset has no Etc zone, so only whole hours map to one.
        if minutes == 0, hours != 0 {
            let inverted = -sign * hours
            return "Etc/GMT\(inverted > 0 ? "+" : "-")\(abs(inverted))"
        }
        // A fractional or zero offset: use the fixed-offset seconds form.
        let seconds = sign * (hours * 3600 + minutes * 60)
        return seconds == 0 ? "UTC" : "UTC\(sign > 0 ? "+" : "-")\(hours):\(String(format: "%02d", minutes))"
    }

    /// The real zone a resolution produced (a fixed-offset pseudo id becomes a
    /// `TimeZone(secondsFromGMT:)`, so Foundation applies it exactly).
    static func timeZone(_ identifier: String) -> TimeZone? {
        if let zone = TimeZone(identifier: identifier) { return zone }
        if identifier.hasPrefix("GMT") || identifier.hasPrefix("UTC") {
            let upper = identifier
            guard upper.hasPrefix("GMT") || upper.hasPrefix("UTC") else { return nil }
            let rest = String(upper.dropFirst(3))
            guard rest.hasPrefix("+") || rest.hasPrefix("-") else {
                return rest.isEmpty ? TimeZone(secondsFromGMT: 0) : nil
            }
            let sign = rest.hasPrefix("-") ? -1 : 1
            let parts = rest.dropFirst().split(separator: ":")
            guard let hours = Int(parts.first ?? "0") else { return nil }
            let minutes = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            return TimeZone(secondsFromGMT: sign * (hours * 3600 + minutes * 60))
        }
        return nil
    }

    // MARK: shapes

    private static func differenceShape(_ line: String, catalog: TimezoneCatalog,
                                        temporal: TemporalContext) -> Outcome? {
        let lower = line.lowercased()
        var rest: String?
        for prefix in ["time difference between ", "difference between ",
                       "time difference from "] where lower.hasPrefix(prefix) {
            rest = String(line.dropFirst(prefix.count))
            break
        }
        guard let body = rest else { return nil }
        let separators = [" and ", " & ", " vs "]
        for separator in separators {
            guard let range = body.range(of: separator) else { continue }
            let left = String(body[body.startIndex..<range.lowerBound])
            let right = String(body[range.upperBound...])
            guard let a = resolveZone(left, catalog: catalog,
                                      preferences: temporal.preferences),
                  let b = resolveZone(right, catalog: catalog,
                                      preferences: temporal.preferences) else {
                return .error("Unknown timezone")
            }
            guard let za = timeZone(a), let zb = timeZone(b) else {
                return .error("Unknown timezone")
            }
            // The CURRENT offset difference at the captured instant, which is
            // what "time difference between X and Y" asks for.
            let offsetA = Double(za.secondsFromGMT(for: temporal.now))
            let offsetB = Double(zb.secondsFromGMT(for: temporal.now))
            return .result(.number(value: offsetB - offsetA, unit: "s",
                                   kind: .duration, fraction: nil))
        }
        return nil
    }

    private static func queryShape(_ line: String, catalog: TimezoneCatalog,
                                   temporal: TemporalContext) -> Outcome? {
        let lower = line.lowercased()
        var place: String?
        var wantsDate = false
        if lower.hasPrefix("time in ") {
            place = String(line.dropFirst("time in ".count))
        } else if lower.hasPrefix("date in ") {
            place = String(line.dropFirst("date in ".count))
            wantsDate = true
        } else if lower.hasSuffix(" time") {
            place = String(line.dropLast(" time".count))
        } else if lower == "date" || lower == "today" || lower == "time" || lower == "now" {
            return nil  // the ordinary clock/date lanes own these
        }
        guard let phrase = place?.trimmingCharacters(in: .whitespaces), !phrase.isEmpty else {
            return nil
        }
        guard let zoneID = resolveZone(phrase, catalog: catalog,
                                       preferences: temporal.preferences) else {
            return .error("Unknown timezone")
        }
        guard let zone = timeZone(zoneID), let catalogZone = catalog.canonicalZone(zoneID)
                ?? (TimeZone(identifier: zoneID) != nil ? zoneID : nil) else {
            return .error("Unknown timezone")
        }
        _ = catalogZone
        return .result(render(instant: temporal.now, in: zone, wantsDate: wantsDate,
                              localZone: temporal.timeZone, temporal: temporal))
    }

    private static func conversionShape(_ line: String, catalog: TimezoneCatalog,
                                        temporal: TemporalContext) -> Outcome? {
        // `<clock> <source> in|to <target>`
        var separatorRange: Range<String.Index>?
        for separator in [" in ", " to "] {
            if let range = line.range(of: separator, options: [.backwards]) {
                if separatorRange == nil
                    || range.lowerBound > separatorRange!.lowerBound {
                    separatorRange = range
                }
            }
        }
        guard let range = separatorRange else { return nil }
        let left = String(line[line.startIndex..<range.lowerBound])
        let target = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        // A UNIT target is never a place: the conversion/unit lanes own it.
        if UnitCatalog.resolveExpression(target) != nil { return nil }
        guard let zoneB = resolveZone(target, catalog: catalog,
                                      preferences: temporal.preferences) else {
            return nil
        }
        // The left side must carry an explicit clock AND a source zone.
        let words = left.split(separator: " ").map(String.init)
        guard words.count >= 2 else { return nil }
        // Find the longest leading clock (`6pm`, `7:30am`, `3pm`) — the clock
        // text may be a single spaced word (`3 pm`).
        var clockText: String?
        var sourceWords: [String] = []
        for count in stride(from: min(words.count - 1, 2), through: 1, by: -1) {
            let candidate = words.prefix(count).joined(separator: " ")
            if ClockLane.parseClockOperand(candidate) != nil {
                clockText = candidate
                sourceWords = Array(words.dropFirst(count))
                break
            }
        }
        guard let clockText, let clock = ClockLane.parseClockOperand(clockText),
              !sourceWords.isEmpty else { return nil }
        let sourcePhrase = sourceWords.joined(separator: " ")
        guard let zoneA = resolveZone(sourcePhrase, catalog: catalog,
                                      preferences: temporal.preferences) else {
            return .error("Unknown timezone")
        }
        guard let za = timeZone(zoneA), let zb = timeZone(zoneB) else {
            return .error("Unknown timezone")
        }
        // One absolute instant: the wall time read in the SOURCE zone on the
        // captured date.
        let today = temporal.calendar.dateComponents([.year, .month, .day], from: temporal.now)
        var components = DateComponents()
        components.year = today.year
        components.month = today.month
        components.day = today.day
        components.hour = clock.hour
        components.minute = clock.minute
        components.second = clock.second
        var sourceCalendar = temporal.calendar
        sourceCalendar.timeZone = za
        guard let instant = sourceCalendar.date(from: components) else {
            return .error("Invalid timezone conversion")
        }
        // DST gaps: a wall time that does not exist in the source zone is a
        // strict error rather than a silent shift.
        let verify = sourceCalendar.dateComponents([.hour, .minute], from: instant)
        if verify.hour != clock.hour || verify.minute != clock.minute {
            return .error("Invalid timezone conversion")
        }
        return .result(render(instant: instant, in: zb, wantsDate: false,
                              localZone: temporal.timeZone, temporal: temporal))
    }

    // MARK: rendering

    /// Renders an instant in `zone` as a clock (or a date), with the
    /// Yesterday/Today/Tomorrow qualification relative to the LOCAL context.
    private static func render(instant: Date, in zone: TimeZone, wantsDate: Bool,
                               localZone: TimeZone, temporal: TemporalContext) -> LineResult {
        var calendar = temporal.calendar
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                            from: instant)
        if wantsDate {
            return .date(year: parts.year ?? 1970, month: parts.month ?? 1,
                         day: parts.day ?? 1, showYear: false)
        }
        // The day qualification is relative to the LOCAL date (the context the
        // user is reading in), so a same-day local time shows no qualifier.
        var localCalendar = temporal.calendar
        localCalendar.timeZone = localZone
        let localDay = localCalendar.ordinality(of: .day, in: .era, for: instant) ?? 0
        let localToday = localCalendar.ordinality(of: .day, in: .era, for: temporal.now) ?? 0
        let dayOffset = localDay - localToday
        return .clock(hour: parts.hour ?? 0, minute: parts.minute ?? 0,
                      second: parts.second ?? 0,
                      hasSeconds: false, dayOffset: dayOffset)
    }
}
