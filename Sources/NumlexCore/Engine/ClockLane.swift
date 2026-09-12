import Foundation

// MARK: - Clock / laptime lane (Task 2)
//
// A strict, bounded lane that owns clock-shaped lines BEFORE the mixed-unit
// and date fallbacks:
//
//   * `3:30pm + 2 hours 15 minutes`   -> `5:45 pm`
//   * `now + 3 hours 25 minutes`      -> today's wall time plus those minutes
//   * `01:02:03 + 01:09:54`           -> `02:11:57`   (elapsed/laptime)
//   * `7:30am to 8:45pm`              -> `13 h 15 min` (forward interval)
//
// Wall-clock arithmetic is done on COMPONENTS (a minute count carried through
// midnight), never on an absolute offset, so a DST transition can never move
// the requested minutes. Clock + clock is a strict error; a bare `h:mm:ss`
// without AM/PM stays on its previous path unless the line asks for the
// elapsed reading (`as laptime`, or laptime arithmetic).
enum ClockLane {

    /// One parsed clock (an instant-of-day) or elapsed value.
    struct ClockValue {
        var hour: Int
        var minute: Int
        var second: Int
        /// Whether the source carried a seconds field (display detail).
        var hasSeconds: Bool
        /// Whether the source carried am/pm (12-hour form).
        var isTwelveHour: Bool
    }

    static func tryLine(_ line: String,
                        context: NumberFormatContext,
                        temporal: TemporalContext,
                        unitContext: UnitContext) -> LineResult? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return nil }

        // 1. The `as laptime` / `as timespan` bridge.
        if let bridge = bridgeShape(trimmed, context: context, temporal: temporal,
                                    unitContext: unitContext) {
            return bridge
        }
        // 2. `now` arithmetic.
        if let now = nowShape(trimmed, context: context, temporal: temporal,
                              unitContext: unitContext) {
            return now
        }
        // 3. `X to Y` interval.
        if let interval = intervalShape(trimmed, context: context, temporal: temporal) {
            return interval
        }
        // 4. Runtime arithmetic (clock ± duration, laptime ± laptime,
        //    clock ± clock error, duration + clock).
        if let runtime = arithmeticShape(trimmed, context: context, temporal: temporal,
                                         unitContext: unitContext) {
            return runtime
        }
        // 5. A bare 12-hour clock (`3:30pm`) is owned; a bare 24-hour clock
        //    keeps its previous path (the lane never steals `10:30`).
        if let clock = parseClock(trimmed), clock.isTwelveHour {
            return .clock(hour: clock.hour, minute: clock.minute, second: clock.second,
                          hasSeconds: clock.hasSeconds, dayOffset: 0)
        }
        // 6. A strict range error for an impossible 24-hour clock (`25:00`).
        if let bad = impossibleClock(trimmed) { return .error(message: bad) }
        return nil
    }

    // MARK: - parsing

    /// A strict clock: `h:mm`, `h:mm:ss`, optionally followed by am/pm
    /// (glued or spaced, case-insensitive, optional trailing dot).
    static func parseClock(_ text: String) -> ClockValue? {
        var body = text
        var twelve = false
        if let (stripped, marker) = stripAMPM(body) {
            body = stripped
            twelve = true
            _ = marker
        }
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        // `4pm` / `4 pm`: an hour alone is allowed only in the 12-hour form.
        if parts.count == 1 {
            guard twelve, let hour = Int(parts[0]), hour >= 1, hour <= 12 else { return nil }
            let h = hour % 12 + (hasPMMarker(text) ? 12 : 0)
            return ClockValue(hour: h, minute: 0, second: 0,
                              hasSeconds: false, isTwelveHour: true)
        }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        for p in parts where p.isEmpty || !p.allSatisfy({ $0.isNumber }) { return nil }
        guard let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        var second = 0
        if parts.count == 3 {
            guard let s = Int(parts[2]) else { return nil }
            second = s
        }
        guard minute >= 0, minute <= 59, second >= 0, second <= 59 else { return nil }
        if twelve {
            guard hour >= 1, hour <= 12 else { return nil }
            let isPM = hasPMMarker(text)
            let h = hour % 12 + (isPM ? 12 : 0)
            return ClockValue(hour: h, minute: minute, second: second,
                              hasSeconds: parts.count == 3, isTwelveHour: true)
        }
        guard hour >= 0, hour <= 23 else { return nil }
        return ClockValue(hour: hour, minute: minute, second: second,
                          hasSeconds: parts.count == 3, isTwelveHour: false)
    }

    /// A strict elapsed value: exactly three colon fields, no am/pm.
    static func parseLaptime(_ text: String) -> (seconds: Double, text: String)? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        guard minutes >= 0, minutes <= 59 else { return nil }
        // The seconds field may carry a fractional part (`00:00:01.5`).
        let secText = String(parts[2])
        let pieces = secText.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2, let secs = Int(pieces[0]), secs >= 0, secs <= 59 else { return nil }
        var fraction = 0.0
        if pieces.count == 2 {
            let digits = pieces[1]
            guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber }), digits.count <= 3 else {
                return nil
            }
            fraction = Double("0." + digits) ?? 0
        }
        guard hours >= 0 else { return nil }
        let total = Double(hours) * 3600 + Double(minutes) * 60 + Double(secs) + fraction
        return (total, text)
    }

    /// The clock reading of one operand: an explicitly 12-hour value
    /// (`3:30pm`, `4pm`) or an `h:mm` pair. A bare 3-field 24-hour value
    /// (`01:02:03`) is an ELAPSED value, never a clock, so laptime arithmetic
    /// is never mistaken for clock+clock.
    static func parseClockOperand(_ text: String) -> ClockValue? {
        guard let clock = parseClock(text) else { return nil }
        if clock.isTwelveHour { return clock }
        let body = stripAMPM(text)?.0 ?? text
        return body.split(separator: ":", omittingEmptySubsequences: false).count == 2
            ? clock : nil
    }

    /// The AM/PM marker of a clock text (case-insensitive, glued or spaced).
    static func hasPMMarker(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.hasSuffix("pm") || lower.hasSuffix("p.m.")
    }

    private static func stripAMPM(_ text: String) -> (String, String)? {
        let lower = text.lowercased()
        for suffix in ["a.m.", "p.m.", "am", "pm"] {
            guard lower.hasSuffix(suffix) else { continue }
            var body = String(text.dropLast(suffix.count))
            while body.hasSuffix(" ") { body.removeLast() }
            return (body, suffix)
        }
        return nil
    }

    /// A clock with an out-of-range HOUR (`25:00`, `99:30`): the lane owns it
    /// as a strict error instead of letting it fall through to prose.
    private static func impossibleClock(_ text: String) -> String? {
        let body = stripAMPM(text)?.0 ?? text
        let parts = body.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let hour = Int(parts[0]) else { return nil }
        guard let minute = Int(parts[1]), minute >= 0, minute <= 59 else { return nil }
        if parts.count == 3 {
            guard let second = Int(parts[2]), second >= 0, second <= 59 else { return nil }
            _ = second
        }
        return hour > 23 ? "Invalid clock value" : nil
    }

    /// A duration phrase: `2 hours 15 minutes`, `3h 25m`, `45 min`, `90 s`.
    /// The whitelist and the components come from the SHARED duration core.
    static func parseDuration(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 80 else { return nil }
        var i = trimmed.startIndex
        var total = 0.0
        var found = false
        while i < trimmed.endIndex {
            while i < trimmed.endIndex, trimmed[i] == " " { i = trimmed.index(after: i) }
            guard i < trimmed.endIndex, trimmed[i].isNumber || trimmed[i] == "." else { return nil }
            var numText = ""
            while i < trimmed.endIndex, trimmed[i].isNumber || trimmed[i] == "." {
                numText.append(trimmed[i])
                i = trimmed.index(after: i)
            }
            guard let value = Double(numText), value.isFinite else { return nil }
            // Glued alias first (`3h`, `25m`), then a spaced word.
            var component: DurationComponent?
            var consumed = i
            if i < trimmed.endIndex, trimmed[i].isLetter {
                if let (c, end) = DurationLiteral.gluedComponent(trimmed, from: i) {
                    component = c
                    consumed = end
                }
            }
            if component == nil {
                while i < trimmed.endIndex, trimmed[i] == " " { i = trimmed.index(after: i) }
                var word = ""
                var end = i
                while end < trimmed.endIndex, trimmed[end].isLetter {
                    word.append(trimmed[end])
                    end = trimmed.index(after: end)
                }
                if let c = DurationLiteral.component(forWord: word) {
                    component = c
                    consumed = end
                }
            }
            guard let component, let unit = DurationLiteral.unitExpr(component, unitContext: .builtIns),
                  unit.isLinear else { return nil }
            _ = unit
            total += value * component.seconds
            found = true
            i = consumed
        }
        return found ? total : nil
    }

    // MARK: - shapes

    private static func clockResult(hour: Int, minute: Int, second: Int,
                                    hasSeconds: Bool, dayOffset: Int) -> LineResult {
        .clock(hour: hour, minute: minute, second: second,
               hasSeconds: hasSeconds, dayOffset: dayOffset)
    }

    private static func bridgeShape(_ line: String, context: NumberFormatContext,
                                    temporal: TemporalContext,
                                    unitContext: UnitContext) -> LineResult? {
        guard let range = line.range(of: " as ", options: [.backwards]) else { return nil }
        let body = String(line[line.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespaces)
        let target = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard target.caseInsensitiveCompare("laptime") == .orderedSame
                || target.caseInsensitiveCompare("elapsed") == .orderedSame else { return nil }
        if let clock = parseClockOperand(body) {
            let day = clock.hour * 3600 + clock.minute * 60 + clock.second
            return .laptime(seconds: Double(day))
        }
        if let lap = parseLaptime(body) { return .laptime(seconds: lap.seconds) }
        if let duration = parseDuration(body) { return .laptime(seconds: duration) }
        return nil
    }

    private static func nowShape(_ line: String, context: NumberFormatContext,
                                 temporal: TemporalContext,
                                 unitContext: UnitContext) -> LineResult? {
        let lower = line.lowercased()
        guard lower == "now" || lower.hasPrefix("now ")
                || lower.hasPrefix("now+") || lower.hasPrefix("now-") else { return nil }
        let rest = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        var added = 0.0
        if !rest.isEmpty {
            var body = rest
            var sign = 1.0
            if body.hasPrefix("+") {
                body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else if body.hasPrefix("-") {
                sign = -1
                body = String(body.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            guard let d = parseDuration(body) else { return nil }
            added = d * sign
        }
        let cal = temporal.calendar
        var comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                       from: temporal.now)
        let baseMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let baseSeconds = (comps.second ?? 0)
        let totalMinutes = Double(baseMinutes) + added / 60
        let dayCarry = Int(floor(totalMinutes / 1440))
        let wallMinutes = Int(totalMinutes - Double(dayCarry) * 1440)
        let hasSeconds = added.rounded().truncatingRemainder(dividingBy: 60) != 0 || baseSeconds != 0
        return clockResult(hour: wallMinutes / 60, minute: wallMinutes % 60,
                           second: Int(baseSeconds), hasSeconds: hasSeconds,
                           dayOffset: dayCarry)
    }

    private static func intervalShape(_ line: String, context: NumberFormatContext,
                                      temporal: TemporalContext) -> LineResult? {
        guard let range = line.range(of: " to ", options: [.backwards]) else { return nil }
        let left = String(line[line.startIndex..<range.lowerBound])
        let right = String(line[range.upperBound...])
        guard let a = parseClockOperand(left.trimmingCharacters(in: .whitespaces)),
              let b = parseClockOperand(right.trimmingCharacters(in: .whitespaces)) else { return nil }
        // A forward CIRCULAR interval: `4pm to 3am` is 11 hours.
        let startMinutes = a.hour * 60 + a.minute
        let endMinutes = b.hour * 60 + b.minute
        var delta = endMinutes - startMinutes
        if delta < 0 { delta += 1440 }
        let seconds = Double(delta) * 60 + Double(b.second - a.second)
        if seconds < 0 { return .error(message: "Invalid clock interval") }
        return .number(value: seconds, unit: "s", kind: .duration, fraction: nil)
    }

    private static func arithmeticShape(_ line: String, context: NumberFormatContext,
                                        temporal: TemporalContext,
                                        unitContext: UnitContext) -> LineResult? {
        // Find the LAST top-level +/- that is not part of a clock's sign.
        guard let split = splitBinary(line) else { return nil }
        let left = split.left.trimmingCharacters(in: .whitespaces)
        let right = split.right.trimmingCharacters(in: .whitespaces)
        let leftClock = parseClockOperand(left)
        let rightClock = parseClockOperand(right)
        let leftLap = parseLaptime(left)
        let rightLap = parseLaptime(right)
        let leftDuration = leftClock == nil && leftLap == nil ? parseDuration(left) : nil
        let rightDuration = parseDuration(right)

        // clock ± clock is a strict error (the plan's deliberate rule).
        if leftClock != nil && rightClock != nil {
            return .error(message: "Clock values cannot be combined directly")
        }
        // clock ± duration -> clock, on WALL components (seconds carried
        // through midnight, so DST can never move the requested minutes).
        if let clock = leftClock, let duration = rightDuration {
            let signed = split.negative ? -duration : duration
            return clockResult(adding: signed, to: clock)
        }
        // duration + clock (either order) is the same wall arithmetic.
        if let duration = leftDuration, let clock = rightClock {
            return arithmeticShapeFrom(duration: duration, clock: clock,
                                       negative: split.negative)
        }
        // laptime arithmetic (elapsed): `01:02:03 + 01:09:54`.
        if let a = leftLap, let b = rightLap {
            let value = split.negative ? a.seconds - b.seconds : a.seconds + b.seconds
            guard value.isFinite else { return .error(message: "Invalid laptime") }
            return .laptime(seconds: value)
        }
        // laptime ± duration.
        if let a = leftLap, let d = rightDuration {
            let value = split.negative ? a.seconds - d : a.seconds + d
            return .laptime(seconds: value)
        }
        _ = context
        _ = temporal
        _ = unitContext
        return nil
    }

    private static func arithmeticShapeFrom(duration: Double, clock: ClockValue,
                                            negative: Bool) -> LineResult {
        clockResult(adding: negative ? -duration : duration, to: clock)
    }

    /// Wall-clock addition: the duration is added to the wall seconds and the
    /// carry advances the calendar day. The requested minutes are preserved
    /// exactly (a DST transition in the source day never shifts them).
    private static func clockResult(adding seconds: Double, to clock: ClockValue) -> LineResult {
        let base = Double(clock.hour * 3600 + clock.minute * 60 + clock.second) + seconds
        let dayCarry = Int(floor(base / 86_400))
        let mod = base - Double(dayCarry) * 86_400
        let hour = Int(mod / 3600)
        let minute = Int(mod.truncatingRemainder(dividingBy: 3600) / 60)
        let second = Int(mod.truncatingRemainder(dividingBy: 60))
        let carriesSeconds = abs(seconds.truncatingRemainder(dividingBy: 60)) > 1e-9
        return clockResult(hour: hour, minute: minute, second: second,
                           hasSeconds: clock.hasSeconds || carriesSeconds,
                           dayOffset: dayCarry)
    }

    /// Splits at the LAST top-level `+`/`-` that separates two operands (the
    /// sign must be followed by a digit or `now`).
    private static func splitBinary(_ line: String) -> (left: String, right: String, negative: Bool)? {
        let chars = Array(line)
        var index: Int? = nil
        var negative = false
        var i = chars.count - 1
        while i > 0 {
            let c = chars[i]
            if c == "+" || c == "-" {
                var j = i + 1
                while j < chars.count, chars[j] == " " { j += 1 }
                if j < chars.count, chars[j].isNumber {
                    index = i
                    negative = (c == "-")
                    break
                }
            }
            i -= 1
        }
        guard let at = index else { return nil }
        let left = String(chars[0..<at])
        let right = String(chars[(at + 1)...])
        guard !left.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return (left, right, negative)
    }
}
