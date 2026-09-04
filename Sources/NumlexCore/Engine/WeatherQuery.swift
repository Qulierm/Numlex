import Foundation

/// r55: natural current-weather queries — `weather in London`.
///
/// Strict one-line grammar (case-insensitive keyword, flexible spaces):
/// `weather in <place>`. The place may be multiword and may carry safe
/// human punctuation for disambiguation (`New York`, `Paris, France`,
/// `St. Louis`, `Côte d'Ivoire`), at most 100 characters. Anything with
/// an empty place, control characters, the token marker, `#`, `=` or
/// operator/trailing-calculation syntax (`+ - * / × ÷ − ^ % ( )`) is NOT
/// a weather query and keeps flowing through the ordinary pipeline.
///
/// The engine NEVER fetches: it resolves the line against a
/// caller-supplied `WeatherContext` (a snapshot map owned by the app
/// layer), so parsing, scanning and result mapping stay pure with no
/// AppKit/SwiftUI/network dependency.
public struct WeatherQuery: Equatable, Sendable, Hashable {
    /// Maximum display-query length (characters).
    public static let maxQueryLength = 100

    /// Canonical lookup key: whitespace-collapsed, casefolded.
    public let key: String
    /// Display form: trimmed, inner whitespace collapsed, case kept —
    /// used for the geocode URL and diagnostics.
    public let display: String

    public init(key: String, display: String) {
        self.key = key
        self.display = display
    }

    /// The canonical Celsius display label for weather answers. This
    /// MUST stay the UnitCatalog temperature label (`C°`, never an
    /// ad-hoc `°C`) so Copy, the rounding slider, Answer Tokens and
    /// `<token> to fahrenheit` keep working through the existing
    /// quantity system. Pinned by test against
    /// `UnitCatalog.resolveLabel`.
    public static let celsiusUnitLabel = "C°"

    /// Stable sentinel for the terminal no-cache failure state. The
    /// evaluator emits `.error(message:)` with exactly this text; the
    /// view localizes it at render time (`weatherUnavailable`).
    public static let unavailableMessage = "Weather unavailable"

    public static func isUnavailableMessage(_ message: String) -> Bool {
        message == unavailableMessage
    }

    /// Strict parse of one logical line. Returns nil for anything that
    /// is not exactly `weather in <place>` (comments/headings never
    /// reach here from sheet evaluation, but token lines, assignments
    /// and prose are rejected here too).
    public static func parse(_ line: String) -> WeatherQuery? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // Token lines have their own route; a marker can never be part
        // of a place name.
        guard !trimmed.contains(answerTokenMarker) else { return nil }
        guard trimmed.lowercased().hasPrefix("weather") else { return nil }
        var rest = trimmed.dropFirst("weather".count)
        guard let f = rest.first, f.isWhitespace else { return nil }
        rest = rest.drop(while: { $0.isWhitespace })
        guard rest.count >= 2, rest.prefix(2).lowercased() == "in" else { return nil }
        rest = rest.dropFirst(2)
        guard let g = rest.first, g.isWhitespace else { return nil }
        let display = rest.drop(while: { $0.isWhitespace })
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !display.isEmpty, display.count <= maxQueryLength else { return nil }
        guard display.unicodeScalars.allSatisfy({
            !CharacterSet.controlCharacters.contains($0)
        }) else { return nil }
        // Allowlist: letters/numbers of any script, spaces, and the
        // safe disambiguation punctuation (`,`, `.`, apostrophes,
        // hyphen). Operators, `=`, `#`, symbols and emoji are rejected,
        // so `weather in London + 5` stays an ordinary line, never a
        // fetch.
        let allowedExtra: Set<Character> = [",", ".", "'", "’", "-"]
        var hasAlnum = false
        for ch in display {
            if ch.isLetter || ch.isNumber { hasAlnum = true; continue }
            if ch == " " { continue }
            guard allowedExtra.contains(ch) else { return nil }
        }
        guard hasAlnum else { return nil }
        // A hyphen glued inside a word is a name (`Aix-en-Provence`);
        // a hyphen beside a space is calculation syntax (`London - 5`)
        // and the line stays an ordinary (non-weather) line.
        if display.contains(" -") || display.contains("- ") { return nil }
        return WeatherQuery(key: display.lowercased(), display: display)
    }

    /// The exact UTF-16 range of the city/place span inside the
    /// ORIGINAL line, derived from the same strict grammar as
    /// `parse` (nil exactly when `parse` is nil, so highlighting and
    /// evaluation cannot drift). Covers the full meaningful place —
    /// leading whitespace, the `weather`/`in` keywords and trailing
    /// whitespace are excluded; internal whitespace of a multiword
    /// place (`New York`, `Paris, France`) is included. The syntax
    /// classifier paints exactly this range with the existing unit
    /// role (`.conversion`); `weather` stays base text and `in` takes
    /// the normal `.specifier` path.
    public static func placeRange(in line: String) -> NSRange? {
        guard parse(line) != nil else { return nil }
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isWhitespace { idx = line.index(after: idx) }
        guard line[idx...].lowercased().hasPrefix("weather") else { return nil }
        idx = line.index(idx, offsetBy: 7)
        guard idx < line.endIndex, line[idx].isWhitespace else { return nil }
        while idx < line.endIndex, line[idx].isWhitespace { idx = line.index(after: idx) }
        guard line[idx...].lowercased().hasPrefix("in") else { return nil }
        idx = line.index(idx, offsetBy: 2)
        guard idx < line.endIndex, line[idx].isWhitespace else { return nil }
        while idx < line.endIndex, line[idx].isWhitespace { idx = line.index(after: idx) }
        let start = idx
        var end = line.endIndex
        while end > start, line[line.index(before: end)].isWhitespace {
            end = line.index(before: end)
        }
        guard end > start else { return nil }
        let loc = start.utf16Offset(in: line)
        let len = end.utf16Offset(in: line) - loc
        guard len > 0 else { return nil }
        return NSRange(location: loc, length: len)
    }

    /// Pure scan of logical source lines returning the UNIQUE valid
    /// weather queries in first-seen order. Comments, headings,
    /// token-containing and malformed lines never produce requests.
    /// Deduplication means duplicate lines share one logical lookup.
    public static func scanQueries(in content: String) -> [WeatherQuery] {
        var seen: Set<String> = []
        var out: [WeatherQuery] = []
        for raw in content.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#"), !t.hasPrefix("//") else { continue }
            guard let q = parse(raw) else { continue }
            guard seen.insert(q.key).inserted else { continue }
            out.append(q)
        }
        return out
    }

    /// Deterministic signature of a query set (sorted canonical keys)
    /// for the SwiftUI `.task(id:)` trigger: identical sets refetch
    /// nothing, any query change re-runs exactly once.
    public static func signature(for queries: [WeatherQuery]) -> String {
        queries.map(\.key).sorted().joined(separator: "\n")
    }
}

/// One validated current-temperature reading for a canonical query.
/// Never persisted in Sheet/.nlx/StorePayload — only in the separate
/// `weather.json` cache owned by `WeatherStore`.
public struct WeatherSnapshot: Codable, Equatable, Sendable {
    /// Plausible provider range for 2m air temperature (°C). Values
    /// outside never become answers or cache entries.
    public static let minCelsius = -100.0
    public static let maxCelsius = 70.0

    public let queryKey: String
    public let displayQuery: String
    /// Resolved place label from the geocoder (e.g. `London`).
    public let placeName: String
    public let country: String?
    public let latitude: Double
    public let longitude: Double
    public let temperatureCelsius: Double
    public let fetchedAt: Date

    public init(queryKey: String, displayQuery: String, placeName: String,
                country: String?, latitude: Double, longitude: Double,
                temperatureCelsius: Double, fetchedAt: Date) {
        self.queryKey = queryKey
        self.displayQuery = displayQuery
        self.placeName = placeName
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.temperatureCelsius = temperatureCelsius
        self.fetchedAt = fetchedAt
    }

    /// Defensive validation: finite in-range temperature and
    /// coordinates, non-empty key. Invalid values never become
    /// answers or cache entries.
    public var isValid: Bool {
        guard !queryKey.isEmpty else { return false }
        guard temperatureCelsius.isFinite,
              temperatureCelsius >= Self.minCelsius,
              temperatureCelsius <= Self.maxCelsius else { return false }
        guard latitude.isFinite, latitude >= -90, latitude <= 90,
              longitude.isFinite, longitude >= -180, longitude <= 180 else { return false }
        return true
    }
}

/// The pure evaluation context for weather lines: last-good snapshots
/// by canonical key plus the terminal-failure set. Owned and published
/// by the app layer; the engine only reads.
public struct WeatherContext: Equatable, Sendable {
    /// Last-good snapshot per canonical query (any age — staleness and
    /// refresh policy belong to the refresher, not the evaluator).
    public var snapshots: [String: WeatherSnapshot]
    /// Queries the app has requested and is still loading.
    public var pendingKeys: Set<String>
    /// Queries with a terminal failure AND no cached snapshot.
    public var failedKeys: Set<String>

    public init(snapshots: [String: WeatherSnapshot] = [:],
                pendingKeys: Set<String> = [],
                failedKeys: Set<String> = []) {
        self.snapshots = snapshots
        self.pendingKeys = pendingKeys
        self.failedKeys = failedKeys
    }

    public static let empty = WeatherContext()

    public enum Lookup: Equatable, Sendable {
        /// A valid cached snapshot is available: render it.
        case ready(WeatherSnapshot)
        /// Requested (or never seen): stay quiet, no spinner, no error.
        case loading
        /// Terminal failure with no cache: show the localized
        /// `Weather unavailable` status.
        case unavailable
    }

    /// Pure lookup: a valid snapshot wins over a failure mark (stale
    /// last-good data stays usable when a refresh fails); anything
    /// without a valid snapshot and without a failure mark is quiet
    /// loading — so the default empty context renders weather lines
    /// exactly like prose, never a false error.
    public func lookup(_ query: WeatherQuery) -> Lookup {
        if let s = snapshots[query.key], s.isValid { return .ready(s) }
        if failedKeys.contains(query.key) { return .unavailable }
        return .loading
    }
}
