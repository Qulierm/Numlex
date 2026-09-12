import Foundation

// MARK: - Work-calendar core (temporal Task 5)
//
// Work definition: Monday-Friday minus the public holidays of the
// resolved region. Date ranges are START-EXCLUSIVE / END-INCLUSIVE; the
// holiday catalog is bundled and offline. An unsupported region or an
// out-of-coverage year is a strict error rather than a silent
// ignore-holidays result.

public enum WorkCalendarError: Error, Equatable, LocalizedError, Sendable {
    case unsupportedRegion(String)
    case unsupportedYear(String, Int)
    case invalidRange

    public var errorDescription: String? {
        switch self {
        case .unsupportedRegion(let region):
            return "Unsupported holiday region: \(region)"
        case .unsupportedYear(let region, let year):
            return "No holiday calendar for \(region) \(year)"
        case .invalidRange:
            return "Invalid date range"
        }
    }
}

public enum WorkCalendar {
    /// Generic undated weeks use 5 workdays per week.
    public static let workdaysPerWeek: Double = 5

    /// True for Monday-Friday.
    public static func isWeekday(_ date: Date, calendar: Calendar) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday >= 2 && weekday <= 6
    }

    /// The number of business days in the START-EXCLUSIVE /
    /// END-INCLUSIVE range `(start, end]`.
    public static func workdays(from start: Date, to end: Date,
                                country: String?,
                                catalog: HolidayCatalog?,
                                calendar: Calendar) throws -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard startDay < endDay else { throw WorkCalendarError.invalidRange }
        var count = 0
        var cursor = startDay
        while cursor < endDay {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else {
                throw WorkCalendarError.invalidRange
            }
            cursor = next
            if isWeekday(cursor, calendar: calendar),
               try !isHoliday(cursor, country: country, catalog: catalog, calendar: calendar) {
                count += 1
            }
        }
        return count
    }

    /// The date `count` workdays after (positive) or before (negative)
    /// `date`, skipping weekends and public holidays.
    public static func addWorkdays(_ count: Int, to date: Date,
                                   country: String?,
                                   catalog: HolidayCatalog?,
                                   calendar: Calendar) throws -> Date {
        guard count != 0 else { return date }
        let step = count > 0 ? 1 : -1
        var remaining = abs(count)
        var cursor = date
        // A bounded walk: far more than any realistic request.
        var guard_ = 0
        while remaining > 0 {
            guard_ += 1
            guard guard_ < 100_000 else { throw WorkCalendarError.invalidRange }
            guard let next = calendar.date(byAdding: .day, value: step, to: cursor) else {
                throw WorkCalendarError.invalidRange
            }
            cursor = next
            if isWeekday(cursor, calendar: calendar),
               try !isHoliday(cursor, country: country, catalog: catalog, calendar: calendar) {
                remaining -= 1
            }
        }
        return cursor
    }

    /// The holiday check with the strict region/year contract: a nil
    /// country (no region resolved) never consults holidays; a named
    /// region without catalog support is an error.
    public static func isHoliday(_ date: Date, country: String?,
                                 catalog: HolidayCatalog?,
                                 calendar: Calendar) throws -> Bool {
        guard let country, !country.isEmpty else { return false }
        guard let catalog, catalog.isSupported(country) else {
            throw WorkCalendarError.unsupportedRegion(country)
        }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = c.year, let month = c.month, let day = c.day else { return false }
        guard catalog.supports(country: country, year: year) else {
            throw WorkCalendarError.unsupportedYear(country, year)
        }
        return catalog.isHoliday(country: country, year: year, month: month, day: day)
    }

    /// The resolved holiday country for a temporal context: an explicit
    /// `holidayRegion`, else the number context's region for
    /// `automatic`. Nil when nothing usable is available.
    public static func resolvedCountry(_ temporal: TemporalContext) -> String? {
        let region = temporal.preferences.holidayRegion
        if region != TemporalPreferences.automaticHolidayRegion {
            return region.uppercased()
        }
        return temporal.localeRegion?.uppercased()
    }
}
