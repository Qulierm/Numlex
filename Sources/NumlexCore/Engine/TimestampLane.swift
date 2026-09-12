import Foundation

// MARK: - Timestamp / ISO date-time lane (temporal Task 2)
//
// A strict lane that owns timestamp- and ISO-shaped lines BEFORE the
// generic unit conversion and the ordinary date fallback:
//
//   current timestamp                    -> 1,742,561,345.67
//   1559740303.48 to date                -> Apr 5, 2019 2:31 pm
//   1733823083000 to date                -> Dec 10, 2024 11:31 am
//   April 1, 2019 3:30pm as iso8601      -> 2019-04-01T15:30:00+02:00
//   2019-04-01T15:30:00 to date          -> Apr 1, 2019 3:30 pm
//   April 1, 2019 to timestamp           -> 1,554,074,400
//
// No loose word stripping: every accepted shape is fully consumed. An
// ISO/date-time value is a TYPED result (`LineResult.dateTime` /
// `LineResult.timestamp`), never a number-suffixed string, and it never
// enters either total or the numeric previous-answer chain.

enum TimestampLane {

    /// A resolution failure is a strict error for a shape-owned line.
    enum Outcome {
        case result(LineResult)
        case error(String)
        case notMine
    }

    /// The documented magnitude threshold: |n| >= 1e12 reads as
    /// milliseconds, everything below as seconds.
    static let millisecondThreshold = 1e12
    /// Foundation's representable epoch bound (±8.64e15 seconds).
    static let maxEpoch = 8.64e15

    // MARK: entry

    static func tryLine(_ line: String,
                        context: NumberFormatContext,
                        temporal: TemporalContext) -> Outcome {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 160 else { return .notMine }
        let lower = trimmed.lowercased()

        // 1. `current timestamp` — the ONE captured TemporalContext.now.
        if lower == "current timestamp" || lower == "current unix timestamp" {
            return .result(.timestamp(seconds: temporal.now.timeIntervalSince1970))
        }

        // 2. `… as iso8601` / `… as timestamp` bridge. A matched suffix
        //    owns the line: an unparsable body is a strict error, never a
        //    silently stripped conversion.
        for suffix in [" as iso8601", " as iso 8601", " as iso", " as timestamp"] {
            guard lower.hasSuffix(suffix) else { continue }
            let body = String(trimmed.dropLast(suffix.count))
                .trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return .notMine }
            return bridge(body: body, wantsISO: suffix != " as timestamp",
                          temporal: temporal)
        }

        // 3. `<epoch number> to|in date` — Unix seconds/milliseconds.
        if let left = rightSide(trimmed, equals: "date") {
            if let seconds = epochSeconds(left) {
                return epochDate(seconds: seconds, temporal: temporal)
            }
            if let iso = parseISO(left, temporal: temporal) {
                return .result(makeDateTime(iso, temporal: temporal, iso: false))
            }
            if let (date, clock) = parseEnglishDateTime(left, now: temporal.now) {
                return .result(localDateTime(date, clock, temporal: temporal, iso: false))
            }
            if let date = parseEnglishDate(left, now: temporal.now) {
                return .result(localDateTime(date, (0, 0, 0, false),
                                             temporal: temporal, iso: false))
            }
            return .notMine
        }

        // 4. `<ISO> to|in timestamp` and `<English date-time> to timestamp`.
        if let left = rightSide(trimmed, equals: "timestamp") {
            if let iso = parseISO(left, temporal: temporal) {
                return .result(.timestamp(seconds: iso.epoch))
            }
            if let seconds = englishEpoch(left, temporal: temporal) {
                return .result(.timestamp(seconds: seconds))
            }
            if let date = parseEnglishDate(left, now: temporal.now),
               let seconds = localNoonEpoch(date, temporal: temporal) {
                return .result(.timestamp(seconds: seconds))
            }
            return .notMine
        }
        return .notMine
    }

    // MARK: bridge (`as iso8601` / `as timestamp`)

    static func bridge(body: String, wantsISO: Bool,
                       temporal: TemporalContext) -> Outcome {
        // ISO body: normalized as-is (explicit offsets preserved).
        if let iso = parseISO(body, temporal: temporal) {
            if wantsISO { return .result(makeDateTime(iso, temporal: temporal, iso: true)) }
            return .result(.timestamp(seconds: iso.epoch))
        }
        // English date-time phrase.
        if let (date, clock) = parseEnglishDateTime(body, now: temporal.now) {
            if wantsISO {
                return .result(localDateTime(date, clock, temporal: temporal, iso: true))
            }
            if let seconds = englishEpoch(date, clock, temporal: temporal) {
                return .result(.timestamp(seconds: seconds))
            }
            return .error("Invalid date-time")
        }
        // Bare English date: timestamp uses the DST-safe noon anchor.
        if let date = parseEnglishDate(body, now: temporal.now) {
            if wantsISO {
                return .result(localDateTime(date, (0, 0, 0, false),
                                             temporal: temporal, iso: true))
            }
            if let seconds = localNoonEpoch(date, temporal: temporal) {
                return .result(.timestamp(seconds: seconds))
            }
            return .error("Invalid date-time")
        }
        return .error("Invalid date-time")
    }

    // MARK: ISO parsing

    struct ISOParsed {
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var minute: Int
        var second: Int
        var hasSeconds: Bool
        /// The explicit offset in seconds; nil means "use the local zone".
        var offsetSeconds: Int?
        var epoch: Double
    }

    /// Strict ISO-8601 against the injected context: `yyyy-MM-dd`,
    /// optionally `THH:mm`, `THH:mm:ss`, an optional fraction and an
    /// optional `Z` / `±HH:MM` zone. Everything must be consumed; the
    /// tolerated non-strict forms are `t` and `±HHMM`/`±HH`.
    static func parseISO(_ raw: String, temporal: TemporalContext) -> ISOParsed? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        var i = text.startIndex
        func end() -> Bool { i == text.endIndex }
        func digits(_ n: Int) -> Int? {
            var value = 0
            for _ in 0..<n {
                guard i < text.endIndex, text[i].isASCII, text[i].isNumber else { return nil }
                value = value * 10 + (Int(String(text[i])) ?? 0)
                i = text.index(after: i)
            }
            return value
        }
        func peek() -> Character? { i < text.endIndex ? text[i] : nil }
        func take(_ c: Character) -> Bool {
            guard i < text.endIndex, text[i] == c else { return false }
            i = text.index(after: i)
            return true
        }
        guard let year = digits(4), take("-"), let month = digits(2), take("-"),
              let day = digits(2) else { return nil }
        var hour = 0, minute = 0, second = 0, hasSeconds = false
        var fraction = 0.0
        if !end() {
            guard take("T") || take("t"), let h = digits(2), take(":"),
                  let m = digits(2) else { return nil }
            hour = h; minute = m
            if take(":") {
                guard let s = digits(2) else { return nil }
                second = s
                hasSeconds = true
            }
            if take(".") {
                var micro = ""
                while let c = peek(), c.isASCII, c.isNumber {
                    if micro.count < 9 { micro.append(c) }
                    i = text.index(after: i)
                }
                guard !micro.isEmpty else { return nil }
                fraction = Double("0." + micro) ?? 0
            }
        }
        var offset: Int? = nil
        if !end() {
            if take("Z") || take("z") {
                offset = 0
            } else if peek() == "+" || peek() == "-" {
                let negative = peek() == "-"
                i = text.index(after: i)
                guard let h = digits(2) else { return nil }
                var m = 0
                if take(":") {
                    guard let mm = digits(2) else { return nil }
                    m = mm
                } else if peek()?.isNumber == true {
                    guard let mm = digits(2) else { return nil }
                    m = mm
                }
                guard h <= 18, m <= 59, h * 3600 + m * 60 <= 18 * 3600 else { return nil }
                offset = (negative ? -1 : 1) * (h * 3600 + m * 60)
            }
            guard end() else { return nil }
        }
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...DateArithmetic.daysInMonth(year, month)).contains(day),
              (0...23).contains(hour), (0...59).contains(minute),
              (0...59).contains(second) else { return nil }
        var calendar = temporal.calendar
        calendar.timeZone = offset.map { TimeZone(secondsFromGMT: $0)! } ?? temporal.timeZone
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        guard let date = calendar.date(from: components) else { return nil }
        if offset == nil {
            // A local wall time that does not exist (DST gap) is a strict
            // error rather than a silent shift.
            let check = calendar.dateComponents([.hour, .minute], from: date)
            guard check.hour == hour, check.minute == minute else { return nil }
        }
        return ISOParsed(year: year, month: month, day: day,
                         hour: hour, minute: minute, second: second,
                         hasSeconds: hasSeconds, offsetSeconds: offset,
                         epoch: date.timeIntervalSince1970 + fraction)
    }

    // MARK: epoch helpers

    /// `<number>` (seconds) or `>= 1e12` (milliseconds → /1000). Strict
    /// decimal literal only; nil for anything else.
    static func epochSeconds(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty,
              text.range(of: #"^[+-]?(\d+(\.\d*)?|\.\d+)$"#,
                         options: .regularExpression) != nil,
              let value = Double(text), value.isFinite else { return nil }
        let seconds = abs(value) >= millisecondThreshold ? value / 1000 : value
        guard seconds.isFinite, abs(seconds) <= maxEpoch else { return nil }
        return seconds
    }

    private static func epochDate(seconds: Double, temporal: TemporalContext) -> Outcome {
        guard seconds.isFinite, abs(seconds) <= maxEpoch else {
            return .error("Invalid timestamp")
        }
        return .result(dateTimeForEpoch(seconds, in: temporal.timeZone,
                                        temporal: temporal))
    }

    /// The typed date-time for one absolute instant in a zone.
    static func dateTimeForEpoch(_ seconds: Double, in zone: TimeZone,
                                 temporal: TemporalContext) -> LineResult {
        var calendar = temporal.calendar
        calendar.timeZone = zone
        let date = Date(timeIntervalSince1970: seconds)
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                        from: date)
        let fraction = seconds - seconds.rounded(.towardZero)
        return .dateTime(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1,
                         hour: c.hour ?? 0, minute: c.minute ?? 0, second: c.second ?? 0,
                         hasSeconds: (c.second ?? 0) != 0 || abs(fraction) > 1e-9,
                         utcOffsetSeconds: zone.secondsFromGMT(for: date), iso: false)
    }

    // MARK: English date-time phrases

    struct EnglishDate {
        var year: Int
        var month: Int
        var day: Int
    }

    /// `April 1, 2019 3:30pm` style phrases (also `1 April 2019 15:30`).
    /// Returns nil unless the date AND a clock are fully consumed.
    static func parseEnglishDateTime(_ raw: String, now: Date)
        -> (EnglishDate, (h: Int, m: Int, s: Int, hasSeconds: Bool))? {
        let tokens = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var consumed = 0
        guard let date = parseEnglishDateTokens(tokens, consumed: &consumed, now: now),
              consumed < tokens.count else { return nil }
        let clockText = tokens[consumed...].joined(separator: " ")
        guard let clock = ClockLane.parseClock(clockText) else { return nil }
        return (date, (clock.hour, clock.minute, clock.second, clock.hasSeconds))
    }

    /// A bare English date (`April 1, 2019`, `1 April 2019`, `Apr 1`).
    static func parseEnglishDate(_ raw: String, now: Date) -> EnglishDate? {
        let tokens = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var consumed = 0
        guard let date = parseEnglishDateTokens(tokens, consumed: &consumed, now: now),
              consumed == tokens.count else { return nil }
        return date
    }

    private static func parseEnglishDateTokens(_ tokens: [String], consumed: inout Int,
                                               now: Date) -> EnglishDate? {
        func clean(_ token: String) -> String {
            token.hasSuffix(",") ? String(token.dropLast()) : token
        }
        guard !tokens.isEmpty else { return nil }
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: now)
        if let month = DateArithmetic.monthIndex[clean(tokens[0]).lowercased()] {
            guard tokens.count >= 2, let day = Int(clean(tokens[1])) else { return nil }
            var year = currentYear
            consumed = 2
            if tokens.count > 2, let y = Int(clean(tokens[2])), clean(tokens[2]).count == 4 {
                year = y
                consumed = 3
            }
            return EnglishDate(year: year, month: month, day: day)
        }
        guard let day = Int(clean(tokens[0])), tokens.count >= 2,
              let month = DateArithmetic.monthIndex[clean(tokens[1]).lowercased()] else {
            return nil
        }
        var year = currentYear
        consumed = 2
        if tokens.count > 2, let y = Int(clean(tokens[2])), clean(tokens[2]).count == 4 {
            year = y
            consumed = 3
        }
        return EnglishDate(year: year, month: month, day: day)
    }

    /// The epoch of an English date-time phrase (nil for a DST gap or an
    /// impossible date).
    static func englishEpoch(_ raw: String, temporal: TemporalContext) -> Double? {
        guard let (date, clock) = parseEnglishDateTime(raw, now: temporal.now) else { return nil }
        return englishEpoch(date, clock, temporal: temporal)
    }

    static func englishEpoch(_ date: EnglishDate,
                             _ clock: (h: Int, m: Int, s: Int, hasSeconds: Bool),
                             temporal: TemporalContext) -> Double? {
        guard valid(date), (0...23).contains(clock.h), (0...59).contains(clock.m),
              (0...59).contains(clock.s) else { return nil }
        var calendar = temporal.calendar
        calendar.timeZone = temporal.timeZone
        var components = DateComponents()
        components.year = date.year; components.month = date.month; components.day = date.day
        components.hour = clock.h; components.minute = clock.m; components.second = clock.s
        guard let instant = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.hour, .minute], from: instant)
        guard check.hour == clock.h, check.minute == clock.m else { return nil }
        return instant.timeIntervalSince1970
    }

    /// The typed date-time of an English date-time phrase in the local
    /// zone.
    static func localDateTime(_ date: EnglishDate,
                              _ clock: (h: Int, m: Int, s: Int, hasSeconds: Bool),
                              temporal: TemporalContext, iso: Bool) -> LineResult {
        let offset: Int
        if let epoch = englishEpoch(date, clock, temporal: temporal) {
            offset = temporal.timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: epoch))
        } else {
            offset = temporal.timeZone.secondsFromGMT(for: temporal.now)
        }
        return .dateTime(year: date.year, month: date.month, day: date.day,
                         hour: clock.h, minute: clock.m, second: clock.s,
                         hasSeconds: clock.hasSeconds,
                         utcOffsetSeconds: offset, iso: iso)
    }

    /// The DST-safe local-noon anchor for a date-only → timestamp.
    static func localNoonEpoch(_ date: EnglishDate, temporal: TemporalContext) -> Double? {
        guard valid(date) else { return nil }
        var calendar = temporal.calendar
        calendar.timeZone = temporal.timeZone
        var components = DateComponents()
        components.year = date.year; components.month = date.month; components.day = date.day
        components.hour = 12
        guard let anchor = calendar.date(from: components) else { return nil }
        return anchor.timeIntervalSince1970
    }

    private static func valid(_ date: EnglishDate) -> Bool {
        (1...9999).contains(date.year) && (1...12).contains(date.month)
            && (1...DateArithmetic.daysInMonth(date.year, date.month)).contains(date.day)
    }

    // MARK: ISO → typed result

    /// The typed date-time for a parsed ISO body. A present explicit offset
    /// is preserved as the presentation zone; otherwise the value renders
    /// in the local TemporalContext zone (DST-aware offset lookup).
    static func makeDateTime(_ iso: ISOParsed, temporal: TemporalContext,
                             iso wantsISO: Bool) -> LineResult {
        let offset: Int
        if let explicit = iso.offsetSeconds {
            offset = explicit
        } else {
            offset = temporal.timeZone.secondsFromGMT(for: Date(timeIntervalSince1970: iso.epoch))
        }
        return .dateTime(year: iso.year, month: iso.month, day: iso.day,
                         hour: iso.hour, minute: iso.minute, second: iso.second,
                         hasSeconds: iso.hasSeconds, utcOffsetSeconds: offset,
                         iso: wantsISO)
    }

    /// The right-hand side of a trailing `to`/`in <keyword>`, or nil when
    /// the keyword does not match exactly.
    private static func rightSide(_ line: String, equals keyword: String) -> String? {
        let lower = line.lowercased()
        for separator in [" to ", " in "] {
            guard lower.hasSuffix(separator + keyword) else { continue }
            let left = String(line.dropLast(separator.count + keyword.count))
                .trimmingCharacters(in: .whitespaces)
            guard !left.isEmpty else { continue }
            return left
        }
        return nil
    }
}
