import Foundation

/// The temporal preferences: the ONLY persisted temporal state. Sources and
/// user preferences live here; every derived value (clocks, zoned instants,
/// work calendars, timecodes) is re-derived per evaluation and is never
/// persisted (`StorePayload.version` is not bumped).
public struct TemporalPreferences: Codable, Equatable, Sendable {
    /// Working hours in one workday (1...24, default 8).
    public var hoursPerWorkday: Double
    /// The public-holiday profile: `automatic` (derive from the active
    /// regional/system country) or an explicit profile key.
    public var holidayRegion: String
    /// User-defined timezone aliases (max 100).
    public var customTimeZones: [CustomTimeZone]

    /// The hard cap on custom timezones.
    public static let maxCustomTimeZones = 100

    public static let automaticHolidayRegion = "automatic"

    public static let defaults = TemporalPreferences(
        hoursPerWorkday: 8,
        holidayRegion: automaticHolidayRegion,
        customTimeZones: [])

    public init(hoursPerWorkday: Double = 8,
                holidayRegion: String = TemporalPreferences.automaticHolidayRegion,
                customTimeZones: [CustomTimeZone] = []) {
        self.hoursPerWorkday = TemporalPreferences.clampedHours(hoursPerWorkday)
        self.holidayRegion = holidayRegion.isEmpty
            ? TemporalPreferences.automaticHolidayRegion : holidayRegion
        self.customTimeZones = Array(customTimeZones.prefix(TemporalPreferences.maxCustomTimeZones))
    }

    /// Finite clamp to 1...24; anything non-finite falls back to 8.
    public static func clampedHours(_ value: Double) -> Double {
        guard value.isFinite else { return 8 }
        return min(max(value, 1), 24)
    }

    /// Tolerant per-key decode: a missing key (legacy store), a malformed
    /// value or a wrong JSON type falls back to the default instead of
    /// failing the whole store.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hoursPerWorkday = (try? c.decodeIfPresent(Double.self, forKey: .hoursPerWorkday))
            .flatMap { $0 }
            .map(TemporalPreferences.clampedHours) ?? 8
        let region = (try? c.decodeIfPresent(String.self, forKey: .holidayRegion)) ?? nil
        holidayRegion = (region?.isEmpty == false)
            ? region! : TemporalPreferences.automaticHolidayRegion
        let zones = (try? c.decodeIfPresent([CustomTimeZone].self, forKey: .customTimeZones)) ?? nil
        customTimeZones = Array((zones ?? []).prefix(TemporalPreferences.maxCustomTimeZones))
    }
}

/// One user-defined timezone alias: a stable UUID, a user-facing name and a
/// validated IANA identifier. App-global only — never part of `.nlx`.
public struct CustomTimeZone: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var identifier: String

    public init(id: UUID = UUID(), name: String, identifier: String) {
        self.id = id
        self.name = name
        self.identifier = identifier
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? nil ?? UUID()
        name = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
        identifier = ((try? c.decodeIfPresent(String.self, forKey: .identifier)) ?? nil) ?? ""
    }

    /// Validated: a timezone alias is usable only with a name AND an
    /// identifier Foundation actually knows.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && TimeZone(identifier: identifier) != nil
    }
}

/// The clock presentation style: 12-hour with am/pm, or 24-hour.
public enum ClockStyle: Equatable, Sendable {
    case twelveHour
    case twentyFourHour

    /// The style derived from the number context: the legacy (pre-regional)
    /// context is 12-hour (the pre-r73 US behavior); a regional context uses
    /// the injected locale's hour cycle, so the SYSTEM setting is honored.
    public static func forContext(_ context: NumberFormatContext) -> ClockStyle {
        if context.legacy { return .twelveHour }
        let cycle = context.locale.hourCycle
        switch cycle {
        case .zeroToTwentyThree, .oneToTwentyFour:
            return .twentyFourHour
        default:
            return .twelveHour
        }
    }
}

/// ONE immutable temporal context captured per sheet: the injected `now`, the
/// Gregorian calendar, the local timezone, the clock style and the temporal
/// preferences. Nothing here is global state and nothing is persisted; every
/// evaluation pass builds it deterministically.
public struct TemporalContext: Equatable, Sendable {
    public let now: Date
    public let calendar: Calendar
    public let timeZone: TimeZone
    public let clockStyle: ClockStyle
    public let preferences: TemporalPreferences
    /// The sheet language (day qualification words).
    public let language: AppLanguage
    /// A finite hard bound for any temporal arithmetic (years).
    public static let maxYearSpan = 5000

    public init(now: Date,
                calendar: Calendar,
                timeZone: TimeZone,
                clockStyle: ClockStyle,
                language: AppLanguage = .en,
                preferences: TemporalPreferences = .defaults) {
        self.now = now
        self.calendar = calendar
        self.timeZone = timeZone
        self.clockStyle = clockStyle
        self.language = language
        self.preferences = preferences
    }

    /// The default context for a number context and a captured date.
    public static func standard(now: Date,
                                calendar: Calendar = .current,
                                timeZone: TimeZone = .current,
                                context: NumberFormatContext = .legacy,
                                language: AppLanguage = .en,
                                preferences: TemporalPreferences = .defaults) -> TemporalContext {
        TemporalContext(now: now, calendar: calendar, timeZone: timeZone,
                        clockStyle: ClockStyle.forContext(context),
                        language: language,
                        preferences: preferences)
    }

    /// Today's component triple in the captured calendar/zone.
    public var today: (year: Int, month: Int, day: Int) {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return (c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// The clock text for a wall time: 12-hour (`5:45 pm`) or 24-hour
    /// (`17:45`), with the seconds field only when the value carries one, and
    /// a Today/Tomorrow/Yesterday qualification when the day differs.
    public func clockText(hour: Int, minute: Int, second: Int,
                          hasSeconds: Bool, dayOffset: Int = 0) -> String {
        var time: String
        switch clockStyle {
        case .twelveHour:
            let displayHour = hour % 12 == 0 ? 12 : hour % 12
            let suffix = hour < 12 ? "am" : "pm"
            time = "\(displayHour):\(String(format: "%02d", minute))"
            if hasSeconds { time += ":\(String(format: "%02d", second))" }
            time += " \(suffix)"
        case .twentyFourHour:
            time = "\(String(format: "%02d", hour)):\(String(format: "%02d", minute))"
            if hasSeconds { time += ":\(String(format: "%02d", second))" }
        }
        switch dayOffset {
        case 1: return "\(dayLabel("tomorrow")) \(time)"
        case -1: return "\(dayLabel("yesterday")) \(time)"
        case 0: return time
        default:
            return "\(dayOffset > 0 ? "+" : "")\(dayOffset) \(dayLabel("days")) \(time)"
        }
    }

    /// The elapsed/laptime text: always `HH:MM:SS` with at least two digits
    /// per field, fractional seconds when present.
    public static func laptimeText(seconds: Double) -> String {
        let negative = seconds < 0
        let total = abs(seconds)
        let hours = Int(total / 3600)
        let minutes = Int(total.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = total.truncatingRemainder(dividingBy: 60)
        let secsText: String
        if abs(secs - secs.rounded()) < 1e-9 {
            secsText = String(format: "%02d", Int(secs.rounded()))
        } else {
            secsText = String(format: "%05.2f", secs)
        }
        return "\(negative ? "-" : "")\(String(format: "%02d", hours)):\(String(format: "%02d", minutes)):\(secsText)"
    }

    /// The day qualification, localized through the app's shared table.
    private func dayLabel(_ key: String) -> String {
        // The shared table carries the localized words; an absent key falls
        // back to the capitalized English word (deterministic, never empty).
        let text = L10n.t(key, language: language)
        guard text.lowercased() == key else { return text }
        return key.prefix(1).uppercased() + key.dropFirst()
    }
}
