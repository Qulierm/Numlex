import Foundation

// MARK: - Work-calendar lane (temporal Task 5)
//
// The strict lane behind the app-global Dates & Times work preferences:
//
//   workdays in 3 weeks                       -> 15 workdays
//   10 March to 17 March in workdays          -> 5 workdays
//   workdays from April 12 to June 15         -> N workdays
//   $500/workday × 4 weeks                    -> $10,000.00
//   work hours in June                        -> 176 h
//   work hours between March 12 and March 25  -> 72 h
//   55h in work days                          -> 6.875 workdays
//   December 24 + 2 workdays                  -> Dec 29
//
// Work definition: Monday-Friday minus the region's public holidays.
// Generic undated weeks use 5 workdays per week. Dated ranges are
// start-exclusive/end-inclusive and fail strictly for an unsupported
// region or year. Aliases: workday(s), work day(s), business day(s),
// weekday(s) — the lane only owns timecode/frame-free, work-shaped
// lines, so `weekday on <date>` prose is never stolen.
enum WorkCalendarLane {

    enum Outcome {
        case result(LineResult)
        case error(String)
        case notMine
    }

    static let countAliases: [String] = [
        "business days", "business day", "work days", "work day",
        "workdays", "workday", "weekdays", "weekday",
    ]

    static let countUnitLabel = "workdays"

    // MARK: entry

    static func tryLine(_ line: String,
                        context: NumberFormatContext,
                        temporal: TemporalContext,
                        unitContext: UnitContext) -> Outcome {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 140 else { return .notMine }
        let lower = trimmed.lowercased()
        guard lower.contains("workday") || lower.contains("work day")
                || lower.contains("business day") || lower.contains("weekday")
                || lower.contains("work hour") else { return .notMine }

        // 1. Money/workday rate: `$500/workday × 4 weeks`.
        if let money = moneyRate(trimmed) { return money }
        // 2. Date arithmetic: `<date> ± N workdays`.
        if let arithmetic = dateArithmetic(trimmed, temporal: temporal) { return arithmetic }
        // 3. `55h in work days` conversion.
        if let conversion = durationConversion(trimmed, temporal: temporal) { return conversion }
        // 4. Work hours over a month or a range.
        if let hours = workHours(trimmed, temporal: temporal) { return hours }
        // 5. Dated workday ranges.
        if let range = dateRange(trimmed, temporal: temporal) { return range }
        // 6. Generic undated `workdays in N weeks`.
        if let generic = genericWeeks(trimmed) { return generic }
        return .notMine
    }

    // MARK: 1. money rate

    private static func moneyRate(_ line: String) -> Outcome? {
        // The currency marker must open the line.
        var marker: String?
        var code: String?
        for entry in CurrencyPresentation.markers {
            if line.hasPrefix(entry.marker) {
                marker = entry.marker
                code = entry.code
                break
            }
        }
        guard let marker, let code else { return nil }
        var rest = String(line.dropFirst(marker.count))
        // The rate amount.
        var numberText = ""
        for c in rest {
            if c.isNumber || c == "." || c == "," { numberText.append(c) } else { break }
        }
        rest = String(rest.dropFirst(numberText.count)).trimmingCharacters(in: .whitespaces)
        guard !numberText.isEmpty,
              let amount = Double(numberText.replacingOccurrences(of: ",", with: "")),
              amount.isFinite else { return .error("Invalid work rate") }
        // `/workday` (or `per workday`).
        let lowered = rest.lowercased()
        var consumedPer = false
        for per in ["/workday", "/workdays", "per workday", "per workdays",
                    "/work day", "/work days", "per work day", "per work days"] {
            if lowered.hasPrefix(per) {
                rest = String(rest.dropFirst(per.count)).trimmingCharacters(in: .whitespaces)
                consumedPer = true
                break
            }
        }
        guard consumedPer else { return nil }
        // `× N weeks` / `* N workdays`.
        guard let split = splitBinary(rest), split.op == "×" || split.op == "*" else {
            return .error("Invalid work rate")
        }
        let right = split.right.trimmingCharacters(in: .whitespaces)
        guard let (count, unit) = parseCountMaybe(right) else {
            return .error("Invalid work rate")
        }
        let workdays: Double
        switch unit {
        case "weeks", "week", "wk", "wks":
            workdays = count * WorkCalendar.workdaysPerWeek
        default:
            guard countAliases.contains(unit) else { return .error("Invalid work rate") }
            workdays = count
        }
        let value = amount * workdays
        guard value.isFinite else { return .error("Invalid work rate") }
        return .result(.money(value: value, code: code))
    }

    // MARK: 2. date ± workdays

    private static func dateArithmetic(_ line: String,
                                       temporal: TemporalContext) -> Outcome? {
        guard let split = splitPlusMinus(line) else { return nil }
        let right = split.right.trimmingCharacters(in: .whitespaces)
        guard let (count, unit) = parseCountMaybe(right), countAliases.contains(unit) else {
            return nil
        }
        guard abs(count - count.rounded()) < 1e-9, count <= 100_000 else {
            return .error("Invalid workday count")
        }
        guard let date = parseDate(split.left, temporal: temporal) else { return nil }
        let catalog = HolidayCatalog.shared
        let country = WorkCalendar.resolvedCountry(temporal)
        do {
            let base = noon(date, temporal: temporal)
            let signed = split.negative ? -Int(count.rounded()) : Int(count.rounded())
            let target = try WorkCalendar.addWorkdays(signed, to: base,
                                                      country: country,
                                                      catalog: catalog,
                                                      calendar: temporal.calendar)
            let c = temporal.calendar.dateComponents([.year, .month, .day], from: target)
            return .result(.date(year: c.year ?? date.year, month: c.month ?? date.month,
                                 day: c.day ?? date.day,
                                 showYear: date.explicitYear || (c.year ?? date.year) != date.year))
        } catch let error as WorkCalendarError {
            return .error(error.errorDescription ?? "Unsupported holiday calendar")
        } catch {
            return .error("Unsupported holiday calendar")
        }
    }

    // MARK: 3. `55h in work days`

    private static func durationConversion(_ line: String,
                                           temporal: TemporalContext) -> Outcome? {
        let lower = line.lowercased()
        for suffix in [" in workdays", " in work days", " in business days",
                       " in weekday", " in weekdays", " to workdays"] {
            guard lower.hasSuffix(suffix) else { continue }
            let left = String(line.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            guard !left.isEmpty,
                  let chain = DurationLiteral.parseChain(left, unitContext: .builtIns) else {
                return nil
            }
            let hours = chain.seconds / 3600
            let perDay = temporal.preferences.hoursPerWorkday
            guard perDay > 0, hours.isFinite else { return .error("Invalid workday conversion") }
            return .result(.number(value: hours / perDay, unit: countUnitLabel,
                                   kind: .plain, fraction: nil))
        }
        return nil
    }

    // MARK: 4. work hours

    private static func workHours(_ line: String,
                                  temporal: TemporalContext) -> Outcome? {
        let lower = line.lowercased()
        var body: String?
        if lower.hasPrefix("work hours in ") {
            body = String(line.dropFirst("work hours in ".count))
            guard let month = parseMonth(body!, temporal: temporal) else { return .error("Invalid work hours range") }
            return hoursResult(start: dayBefore(month.first, temporal: temporal),
                               end: month.last, temporal: temporal)
        }
        for prefix in ["work hours between ", "work hours from "] {
            guard lower.hasPrefix(prefix) else { continue }
            body = String(line.dropFirst(prefix.count))
            break
        }
        guard let rangeText = body else { return nil }
        let separator = lower.hasPrefix("work hours between ") ? " and " : " to "
        guard let range = splitRange(rangeText, separator: separator),
              let start = parseDate(range.0, temporal: temporal),
              let end = parseDate(range.1, temporal: temporal) else {
            return .error("Invalid work hours range")
        }
        return hoursResult(start: noon(start, temporal: temporal),
                           end: noon(end, temporal: temporal), temporal: temporal)
    }

    private static func hoursResult(start: Date, end: Date,
                                    temporal: TemporalContext) -> Outcome {
        let catalog = HolidayCatalog.shared
        let country = WorkCalendar.resolvedCountry(temporal)
        do {
            let days = try WorkCalendar.workdays(from: start, to: end,
                                                 country: country, catalog: catalog,
                                                 calendar: temporal.calendar)
            let hours = Double(days) * temporal.preferences.hoursPerWorkday
            return .result(.number(value: hours, unit: "h", kind: .duration, fraction: nil))
        } catch let error as WorkCalendarError {
            return .error(error.errorDescription ?? "Unsupported holiday calendar")
        } catch {
            return .error("Unsupported holiday calendar")
        }
    }

    // MARK: 5. dated workday ranges

    private static func dateRange(_ line: String,
                                  temporal: TemporalContext) -> Outcome? {
        let lower = line.lowercased()
        // `<date> to <date> in workdays`.
        for suffix in [" in workdays", " in work days", " in business days",
                       " in weekdays"] {
            guard lower.hasSuffix(suffix) else { continue }
            let body = String(line.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            guard let range = splitRange(body, separator: " to ") else { return nil }
            return rangeCount(range.0, range.1, temporal: temporal)
        }
        // `workdays from A to B` / `workdays between A and B`.
        for (prefix, separator) in [("workdays from ", " to "),
                                    ("work days from ", " to "),
                                    ("business days from ", " to "),
                                    ("weekdays from ", " to "),
                                    ("workdays between ", " and "),
                                    ("work days between ", " and "),
                                    ("business days between ", " and "),
                                    ("weekdays between ", " and ")] {
            guard lower.hasPrefix(prefix) else { continue }
            let body = String(line.dropFirst(prefix.count))
            guard let range = splitRange(body, separator: separator) else {
                return .error("Invalid workday range")
            }
            return rangeCount(range.0, range.1, temporal: temporal)
        }
        return nil
    }

    private static func rangeCount(_ startText: String, _ endText: String,
                                   temporal: TemporalContext) -> Outcome? {
        guard let start = parseDate(startText, temporal: temporal),
              let end = parseDate(endText, temporal: temporal) else { return nil }
        let catalog = HolidayCatalog.shared
        let country = WorkCalendar.resolvedCountry(temporal)
        do {
            let days = try WorkCalendar.workdays(from: noon(start, temporal: temporal),
                                                 to: noon(end, temporal: temporal),
                                                 country: country, catalog: catalog,
                                                 calendar: temporal.calendar)
            return .result(.number(value: Double(days), unit: countUnitLabel,
                                   kind: .plain, fraction: nil))
        } catch let error as WorkCalendarError {
            return .error(error.errorDescription ?? "Unsupported holiday calendar")
        } catch {
            return .error("Unsupported holiday calendar")
        }
    }

    // MARK: 6. generic undated weeks

    private static func genericWeeks(_ line: String) -> Outcome? {
        let lower = line.lowercased()
        for prefix in ["workdays in ", "work days in ", "business days in ",
                       "weekdays in "] {
            guard lower.hasPrefix(prefix) else { continue }
            let body = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard let chain = DurationLiteral.parseChain(body, unitContext: .builtIns) else {
                return .error("Invalid workday range")
            }
            // Only week-scale units participate in the generic rule.
            let seconds = chain.seconds
            let weeks = seconds / 604_800
            guard weeks.isFinite, weeks >= 0 else { return .error("Invalid workday range") }
            return .result(.number(value: weeks * WorkCalendar.workdaysPerWeek,
                                   unit: countUnitLabel, kind: .plain, fraction: nil))
        }
        return nil
    }

    // MARK: parsing helpers

    /// `<number> <alias>` (`2 workdays`, `2 work days`, `2 business days`).
    /// Returns the numeric value and the NORMALIZED alias.
    static func parseCountMaybe(_ text: String) -> (Double, String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        for alias in countAliases {
            guard trimmed.hasSuffix(alias) else { continue }
            let numberText = String(trimmed.dropLast(alias.count))
                .trimmingCharacters(in: .whitespaces)
            guard let value = Double(numberText), value.isFinite, value >= 0 else { continue }
            return (value, alias)
        }
        // Week aliases (generic weeks and the money rate).
        for alias in ["weeks", "week", "wks", "wk"] {
            guard trimmed.hasSuffix(" " + alias) else { continue }
            let numberText = String(trimmed.dropLast(alias.count + 1))
                .trimmingCharacters(in: .whitespaces)
            guard let value = Double(numberText), value.isFinite, value >= 0 else { continue }
            return (value, alias)
        }
        return nil
    }

    struct ParsedDate {
        var year: Int
        var month: Int
        var day: Int
        var explicitYear: Bool
    }

    static func parseDate(_ text: String, temporal: TemporalContext) -> ParsedDate? {
        switch DateArithmetic.detect(line: text, now: temporal.now,
                                     calendar: temporal.calendar) {
        case .value(let v):
            return ParsedDate(year: v.year, month: v.month, day: v.day,
                              explicitYear: v.showYear)
        case .malformed, .none:
            return nil
        }
    }

    private static func parseMonth(_ text: String, temporal: TemporalContext)
        -> (first: Date, last: Date)? {
        let tokens = text.split(whereSeparator: { $0 == " " }).map(String.init)
        guard let first = tokens.first,
              let month = DateArithmetic.monthIndex[first.lowercased()] else { return nil }
        var year = temporal.calendar.component(.year, from: temporal.now)
        if tokens.count > 1, let explicit = Int(tokens[1]), tokens[1].count == 4 {
            year = explicit
        }
        guard (1...9999).contains(year) else { return nil }
        var components = DateComponents()
        components.year = year; components.month = month; components.day = 1; components.hour = 12
        guard let start = temporal.calendar.date(from: components) else { return nil }
        let dayCount = DateArithmetic.daysInMonth(year, month)
        components.day = dayCount
        guard let end = temporal.calendar.date(from: components) else { return nil }
        return (start, end)
    }

    private static func noon(_ date: ParsedDate, temporal: TemporalContext) -> Date {
        var components = DateComponents()
        components.year = date.year; components.month = date.month
        components.day = date.day; components.hour = 12
        return temporal.calendar.date(from: components) ?? temporal.now
    }

    private static func dayBefore(_ date: Date, temporal: TemporalContext) -> Date {
        temporal.calendar.date(byAdding: .day, value: -1, to: date) ?? date
    }

    private static func splitRange(_ text: String, separator: String)
        -> (String, String)? {
        guard let range = text.range(of: separator, options: [.backwards]) else { return nil }
        let left = String(text[text.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let right = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        return (left, right)
    }

    /// The last top-level `+`/`-` followed by a digit.
    private static func splitPlusMinus(_ line: String)
        -> (left: String, right: String, negative: Bool)? {
        let chars = Array(line)
        var i = chars.count - 1
        while i > 0 {
            let c = chars[i]
            if c == "+" || c == "-" {
                var j = i + 1
                while j < chars.count, chars[j] == " " { j += 1 }
                if j < chars.count, chars[j].isNumber {
                    let left = String(chars[0..<i])
                    let right = String(chars[(i + 1)...])
                    guard !left.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                    return (left, right, c == "-")
                }
            }
            i -= 1
        }
        return nil
    }

    private static func splitBinary(_ line: String)
        -> (left: String, right: String, op: Character)? {
        let chars = Array(line)
        var i = chars.count - 1
        while i >= 0 {
            let c = chars[i]
            if c == "×" || c == "*" {
                let left = String(chars[0..<i])
                let right = String(chars[(i + 1)...])
                return (left, right, c)
            }
            i -= 1
        }
        return nil
    }
}
