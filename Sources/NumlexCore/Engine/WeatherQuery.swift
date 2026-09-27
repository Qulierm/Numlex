import Foundation

/// r55 / Package 8: natural weather queries.
///
/// Strict one-line grammar (case-insensitive keywords, flexible spaces):
///
/// ```text
/// weather in <place>      → current temperature
/// <place> temperature     → current temperature (suffix form)
/// high in <place>         → today's maximum
/// low in <place>          → today's minimum
/// feels like in <place>   → current apparent temperature
/// ```
///
/// The place may be multiword and may carry safe human punctuation for
/// disambiguation (`New York`, `Paris, France`, `St. Louis`,
/// `Côte d'Ivoire`), at most 100 characters. Anything with an empty
/// place, control characters, the token marker, `#`, `=` or
/// operator/trailing-calculation syntax (`+ - * / × ÷ − ^ % ( )`) is NOT
/// a weather query and keeps flowing through the ordinary pipeline.
///
/// The canonical `key` is PLACE-ONLY, so every metric of one place shares
/// one network request and one cache entry; `kind` stays per line.
///
/// The engine NEVER fetches: it resolves the line against a
/// caller-supplied `WeatherContext` (a snapshot map owned by the app
/// layer), so parsing, scanning and result mapping stay pure with no
/// AppKit/SwiftUI/network dependency.
public struct WeatherQuery: Equatable, Sendable, Hashable {
    /// Maximum display-query length (characters).
    public static let maxQueryLength = 100

    /// Which metric of the place's snapshot this line asks for.
    public enum Kind: String, Codable, CaseIterable, Sendable, Equatable {
        case current
        case high
        case low
        case apparent

        /// The snapshot field this kind reads.
        public var metric: WeatherMetric {
            switch self {
            case .current: return .current
            case .high: return .high
            case .low: return .low
            case .apparent: return .apparent
            }
        }
    }

    /// Canonical lookup key: whitespace-collapsed, casefolded — the PLACE
    /// only, so all metrics of one place share a fetch and a cache entry.
    public let key: String
    /// Display form: trimmed, inner whitespace collapsed, case kept —
    /// used for the geocode URL and diagnostics.
    public let display: String
    /// The metric this line requests (default `.current`, the r55 form).
    public let kind: Kind

    public init(key: String, display: String, kind: Kind = .current) {
        self.key = key
        self.display = display
        self.kind = kind
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

    /// The strict grammar over one line: the requested kind plus the
    /// place's CHARACTER range inside the ORIGINAL line. `parse` and
    /// `placeRange` both consume exactly this function, so highlighting
    /// can never drift from evaluation.
    static func grammar(_ line: String) -> (kind: Kind, range: Range<String.Index>)? {
        var start = line.startIndex
        while start < line.endIndex, line[start].isWhitespace { start = line.index(after: start) }
        guard start < line.endIndex else { return nil }
        var end = line.endIndex
        while end > start, line[line.index(before: end)].isWhitespace {
            end = line.index(before: end)
        }
        let trimmed = line[start..<end]
        guard !trimmed.contains(answerTokenMarker) else { return nil }

        /// Consumes one keyword (one or more words) from `from`,
        /// tolerating any whitespace runs between its words — the
        /// grammar is case-insensitive and whitespace-flexible.
        func consumeKeyword(_ keyword: String, from from: String.Index) -> String.Index? {
            var cursor = from
            for (n, word) in keyword.split(separator: " ").enumerated() {
                if n > 0 {
                    guard cursor < trimmed.endIndex, trimmed[cursor].isWhitespace else { return nil }
                    while cursor < trimmed.endIndex, trimmed[cursor].isWhitespace {
                        cursor = trimmed.index(after: cursor)
                    }
                }
                guard let end = trimmed.index(cursor, offsetBy: word.count,
                                              limitedBy: trimmed.endIndex),
                      trimmed[cursor..<end].lowercased() == word else { return nil }
                cursor = end
            }
            return cursor
        }

        /// A prefix form: `<keyword> in <place>`.
        func prefix(_ keyword: String, _ kind: Kind) -> (Kind, Range<String.Index>)? {
            guard var idx = consumeKeyword(keyword, from: trimmed.startIndex) else { return nil }
            guard idx < trimmed.endIndex, trimmed[idx].isWhitespace else { return nil }
            while idx < trimmed.endIndex, trimmed[idx].isWhitespace {
                idx = trimmed.index(after: idx)
            }
            guard trimmed[idx...].lowercased().hasPrefix("in") else { return nil }
            let afterIn = trimmed.index(idx, offsetBy: 2)
            guard afterIn < trimmed.endIndex, trimmed[afterIn].isWhitespace else { return nil }
            var place = afterIn
            while place < trimmed.endIndex, trimmed[place].isWhitespace {
                place = trimmed.index(after: place)
            }
            guard place < trimmed.endIndex else { return nil }
            return (kind, place..<trimmed.endIndex)
        }

        /// The suffix form: `<place> temperature`.
        func suffix(_ keyword: String, _ kind: Kind) -> (Kind, Range<String.Index>)? {
            let lower = trimmed.lowercased()
            guard lower.hasSuffix(keyword), trimmed.count > keyword.count else { return nil }
            guard !keyword.contains(" ") else { return nil }
            let placeEnd = trimmed.index(trimmed.endIndex, offsetBy: -keyword.count)
            // The keyword must be preceded by whitespace (a whole word).
            guard placeEnd > trimmed.startIndex else { return nil }
            guard trimmed[trimmed.index(before: placeEnd)].isWhitespace else { return nil }
            var place = placeEnd
            while place > trimmed.startIndex {
                let prev = trimmed.index(before: place)
                if trimmed[prev].isWhitespace { place = prev } else { break }
            }
            guard place > trimmed.startIndex else { return nil }
            return (kind, trimmed.startIndex..<place)
        }

        let candidate = prefix("feels like", .apparent)
            ?? prefix("weather", .current)
            ?? prefix("high", .high)
            ?? prefix("low", .low)
            ?? suffix("temperature", .current)
        guard let candidate else { return nil }
        guard Self.isSafePlace(String(trimmed[candidate.1])) else { return nil }
        return (candidate.0, candidate.1)
    }

    /// The bounded, safe place validator shared by every form: letters
    /// and numbers of any script, single spaces, and the disambiguation
    /// punctuation (`,`, `.`, apostrophes, inner hyphen). Operators, `=`,
    /// `#`, control characters, symbols and emoji are rejected, so
    /// `high in London + 5` stays an ordinary line and never a fetch.
    static func isSafePlace(_ raw: String) -> Bool {
        let display = raw.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !display.isEmpty, display.count <= maxQueryLength else { return false }
        guard display.unicodeScalars.allSatisfy({
            !CharacterSet.controlCharacters.contains($0)
        }) else { return false }
        let allowedExtra: Set<Character> = [",", ".", "'", "’", "-"]
        var hasAlnum = false
        for ch in display {
            if ch.isLetter || ch.isNumber { hasAlnum = true; continue }
            if ch == " " { continue }
            guard allowedExtra.contains(ch) else { return false }
        }
        guard hasAlnum else { return false }
        // A hyphen glued inside a word is a name (`Aix-en-Provence`);
        // a hyphen beside a space is calculation syntax (`London - 5`).
        if display.contains(" -") || display.contains("- ") { return false }
        // A comma introduces a country/region name, never a number:
        // `Paris, France` stays a place, `London, 5` is calculation
        // syntax and the line keeps flowing through the ordinary lanes.
        var chars = Array(display)
        for (i, ch) in chars.enumerated() where ch == "," {
            var j = i + 1
            while j < chars.count, chars[j] == " " { j += 1 }
            guard j < chars.count, chars[j].isLetter else { return false }
        }
        return true
    }

    /// Strict parse of one logical line. Returns nil for anything that is
    /// not exactly one of the five documented forms (comments/headings
    /// never reach here from sheet evaluation, but token lines,
    /// assignments and prose are rejected here too).
    public static func parse(_ line: String) -> WeatherQuery? {
        guard let g = grammar(line) else { return nil }
        let display = String(line[g.range])
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !display.isEmpty else { return nil }
        return WeatherQuery(key: display.lowercased(), display: display, kind: g.kind)
    }

    /// The exact UTF-16 range of the city/place span inside the
    /// ORIGINAL line, derived from the same strict grammar as `parse`
    /// (nil exactly when `parse` is nil, so highlighting and evaluation
    /// cannot drift). Covers the full meaningful place — leading
    /// whitespace, the keywords and trailing whitespace are excluded;
    /// internal whitespace of a multiword place (`New York`,
    /// `Paris, France`) is included. The syntax classifier paints exactly
    /// this range with the existing unit role (`.conversion`); `weather`
    /// (and the other keywords) stay base text and `in` takes the normal
    /// `.specifier` path.
    public static func placeRange(in line: String) -> NSRange? {
        guard let g = grammar(line) else { return nil }
        let loc = g.range.lowerBound.utf16Offset(in: line)
        let len = g.range.upperBound.utf16Offset(in: line) - loc
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
            // Package 7: scan the tag-stripped evaluation body so a
            // trailing `#travel` never becomes part of a place name.
            let analysis = SheetLineAnalysis.parse(raw)
            switch analysis.kind {
            case .blank, .heading, .comment, .commentTitle, .divider, .tagOnly:
                continue
            case .totalCommand, .expression:
                break
            }
            guard let q = parse(analysis.evaluationProjection) else { continue }
            // ONE lookup per PLACE: every metric of the same place shares
            // this query (and therefore one fetch and one cache entry).
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
    /// The current 2m air temperature (the r55 field).
    public let temperatureCelsius: Double
    /// The current apparent ("feels like") temperature. OPTIONAL on
    /// decode so pre-Package-8 cache bytes are readable — and then
    /// rejected by `isValid`, so a legacy entry is refetched instead of
    /// fabricating a metric it never stored.
    public let apparentCelsius: Double?
    /// Today's daily maximum / minimum. Same optional-on-decode contract.
    public let highCelsius: Double?
    public let lowCelsius: Double?
    public let fetchedAt: Date

    /// Source-created snapshots populate every metric: a caller that
    /// omits the new values (an existing fixture) gets the current
    /// temperature for them, which keeps such a snapshot valid. Decoded
    /// legacy bytes instead carry nil and are invalidated.
    public init(queryKey: String, displayQuery: String, placeName: String,
                country: String?, latitude: Double, longitude: Double,
                temperatureCelsius: Double, fetchedAt: Date,
                apparentCelsius: Double? = nil,
                highCelsius: Double? = nil,
                lowCelsius: Double? = nil) {
        self.queryKey = queryKey
        self.displayQuery = displayQuery
        self.placeName = placeName
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.temperatureCelsius = temperatureCelsius
        self.apparentCelsius = apparentCelsius ?? temperatureCelsius
        self.highCelsius = highCelsius ?? temperatureCelsius
        self.lowCelsius = lowCelsius ?? temperatureCelsius
        self.fetchedAt = fetchedAt
    }

    /// The Celsius value a query kind reads, or nil when this snapshot
    /// does not carry it (a legacy entry; `isValid` already rejects it).
    public func celsius(for kind: WeatherQuery.Kind) -> Double? {
        switch kind {
        case .current: return temperatureCelsius
        case .apparent: return apparentCelsius
        case .high: return highCelsius
        case .low: return lowCelsius
        }
    }

    private func isPlausible(_ value: Double?) -> Bool {
        guard let value, value.isFinite else { return false }
        return value >= Self.minCelsius && value <= Self.maxCelsius
    }

    /// Defensive validation: finite, in-range values for EVERY metric
    /// (low <= high), finite coordinates and a non-empty key. Invalid
    /// values never become answers or cache entries — which is exactly
    /// what invalidates a legacy cache entry that carries no
    /// apparent/high/low values, so it is refetched.
    public var isValid: Bool {
        guard !queryKey.isEmpty else { return false }
        guard isPlausible(temperatureCelsius),
              isPlausible(apparentCelsius),
              isPlausible(highCelsius),
              isPlausible(lowCelsius) else { return false }
        guard let high = highCelsius, let low = lowCelsius, low <= high else { return false }
        guard latitude.isFinite, latitude >= -90, latitude <= 90,
              longitude.isFinite, longitude >= -180, longitude <= 180 else { return false }
        return true
    }
}

/// One metric of a place's snapshot: the field a weather line reads.
public enum WeatherMetric: String, CaseIterable, Sendable, Equatable {
    case current
    case high
    case low
    case apparent
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
