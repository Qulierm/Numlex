import Foundation

// MARK: - r85: geography queries (strict grammar)

/// r85: one geography ENDPOINT of a `distance between` query: either a
/// named place (resolved through the geocode context — cached or
/// pending) or an EXPLICIT coordinate pair component (resolved
/// offline, no network ever).
public enum GeoEndpoint: Equatable, Hashable, Sendable {
    case place(key: String, display: String)
    case coordinate(GeoCoordinate)

    /// The canonical signature component (dedupe + task identity).
    var signature: String {
        switch self {
        case .place(let key, _): return "p:" + key
        case .coordinate(let c):
            return "c:\(c.latitude),\(c.longitude)"
        }
    }
}

/// r85: one strict geography query line.
public struct GeoQuery: Equatable, Sendable, Hashable {
    public enum Kind: Equatable, Sendable, Hashable {
        case location
        case latitude
        case longitude
        case distance(a: GeoEndpoint, b: GeoEndpoint)
    }

    public let kind: Kind
    /// Canonical dedupe key (casefolded place names; coordinates at
    /// their parsed values).
    public let key: String

    public init(kind: Kind, key: String) {
        self.kind = kind
        self.key = key
    }

    /// The geocodeable place of a place-endpoint kind (nil for
    /// distance queries — those carry their own endpoints).
    public var placeDisplay: String? {
        switch kind {
        case .distance: return nil
        case .location, .latitude, .longitude:
            // The key is the display casefolded; the display is
            // carried alongside through the parse (stored in the key
            // map by the parser via `display` below).
            return display
        }
    }

    /// The display form used for the geocode URL (trimmed place).
    public var display: String = ""

    public mutating func setDisplay(_ s: String) {
        display = s
    }
}

/// Strict place-name scanning shared by every geo line: the same
/// allowlist discipline as the weather grammar (letters/numbers of any
/// script, safe disambiguation punctuation, at most 100 characters,
/// no operators or token markers). Quoted names (`"Trinidad and
/// Tobago"`) strip their quotes; a lone quote pair or an unbalanced
/// quote is a parse failure (the line is NOT a geo line).
public enum GeoPlaceScan {
    public static let maxPlaceLength = 100

    /// The canonical (casefolded, whitespace-collapsed) place key plus
    /// its display form, or nil.
    public static func scan(_ s: String) -> (key: String, display: String)? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") {
            let inner = String(t.dropFirst().dropLast())
            guard !inner.contains("\"") else { return nil }
            t = inner.trimmingCharacters(in: .whitespaces)
        } else if t.contains("\"") {
            return nil // unbalanced quotes: not a place
        }
        guard !t.isEmpty, t.count <= maxPlaceLength else { return nil }
        guard !t.contains(answerTokenMarker) else { return nil }
        guard t.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        let allowedExtra: Set<Character> = [",", ".", "'", "’", "-"]
        var hasAlnum = false
        for ch in t {
            if ch.isLetter || ch.isNumber { hasAlnum = true; continue }
            if ch == " " { continue }
            guard allowedExtra.contains(ch) else { return nil }
        }
        guard hasAlnum else { return nil }
        if t.contains(" -") || t.contains("- ") { return nil }
        let display = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return (key: display.lowercased(), display: display)
    }
}

/// r85: the STRICT geography line grammar (case-insensitive keywords,
/// anchored at line start, flexible spacing):
///
/// - `location of <place>`
/// - `latitude of <place>`
/// - `longitude of <place>`
/// - `distance between <end1> and <end2>`
///
/// Distance endpoints are, in order of precedence: a QUOTED place
/// (`"Trinidad and Tobago"` — quotes remove the `and` ambiguity), an
/// EXPLICIT coordinate pair (`48.8566, 2.3522` — comma separator in
/// dot-decimal modes, `;` in decimal-comma modes; each component may
/// carry `° N/S/E/W` cardinals; a sign and a conflicting cardinal
/// reject the line), or a bare place. The default split is the LAST
/// standalone ` and ` of the unquoted text.
public enum GeoQueryParse {
    /// Parses one logical line. Returns nil for anything that is not
    /// exactly one of the four strict shapes (comments/headings never
    /// reach here from sheet evaluation; token lines, assignments and
    /// prose are rejected too).
    public static func parse(_ line: String, context: NumberFormatContext = .legacy) -> GeoQuery? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains(answerTokenMarker) else { return nil }

        if let rest = keywordPrefix(trimmed, "location of") {
            guard let p = GeoPlaceScan.scan(rest) else { return nil }
            var q = GeoQuery(kind: .location, key: "loc:" + p.key)
            q.display = p.display
            return q
        }
        if let rest = keywordPrefix(trimmed, "latitude of") {
            guard let p = GeoPlaceScan.scan(rest) else { return nil }
            var q = GeoQuery(kind: .latitude, key: "lat:" + p.key)
            q.display = p.display
            return q
        }
        if let rest = keywordPrefix(trimmed, "longitude of") {
            guard let p = GeoPlaceScan.scan(rest) else { return nil }
            var q = GeoQuery(kind: .longitude, key: "lon:" + p.key)
            q.display = p.display
            return q
        }
        if let rest = keywordPrefix(trimmed, "distance between") {
            guard let endpoints = parseEndpoints(rest, context: context) else { return nil }
            let key = "dist:\(endpoints.0.signature);\(endpoints.1.signature)"
            return GeoQuery(kind: .distance(a: endpoints.0, b: endpoints.1), key: key)
        }
        return nil
    }

    /// The text after a leading `keyword` (case-insensitive, the
    /// keyword standalone, flexible spacing), or nil.
    private static func keywordPrefix(_ s: String, _ keyword: String) -> String? {
        let lower = s.lowercased()
        guard lower.hasPrefix(keyword) else { return nil }
        let rest = s.dropFirst(keyword.count)
        guard let f = rest.first, f.isWhitespace else { return nil }
        let tail = rest.drop(while: { $0.isWhitespace })
        guard !tail.isEmpty else { return nil }
        return String(tail)
    }

    /// The sheet-level geography query scan (r85): every geo line of the
    /// content, deduplicated by query key and in sheet order.
    public static func scanQueries(in content: String,
                                   context: NumberFormatContext = .legacy) -> [GeoQuery] {
        var seen = Set<String>()
        var out: [GeoQuery] = []
        for line in content.components(separatedBy: "\n") {
            if let q = parse(line, context: context), seen.insert(q.key).inserted {
                out.append(q)
            }
        }
        return out
    }

    /// The deterministic refresh identity of a geo query set (sheet
    /// order preserved, duplicates already collapsed by the scan).
    public static func signature(for queries: [GeoQuery]) -> String {
        queries.map { $0.key }.joined(separator: "\n")
    }

    /// The r85 geo unavailable message marker (view-layer localizes it
    /// as `locationUnavailable`, exactly like the weather message).
    public static func isUnavailableMessage(_ message: String) -> Bool {
        message == geoUnavailableMessage
    }

    /// Splits the `distance between` remainder into two endpoints on
    /// the LAST standalone ` and ` of the UNQUOTED text; each side is
    /// a quoted place, an explicit coordinate pair, or a bare place.
    static func parseEndpoints(_ s: String, context: NumberFormatContext) -> (GeoEndpoint, GeoEndpoint)? {
        // Deterministic scan: collect indices of standalone lowercase
        // ` and ` occurrences OUTSIDE double quotes.
        let ns = s as NSString
        var lo = 0
        var candidates: [Int] = []
        while true {
            let r = ns.range(of: " and ", options: [.caseInsensitive],
                             range: NSRange(location: lo, length: ns.length - lo))
            if r.location == NSNotFound { break }
            lo = r.location + 1
            if quoteParity(s, before: r.location) == 0 {
                candidates.append(r.location)
            }
        }
        guard let last = candidates.last else { return nil }
        let a = String(ns.substring(to: last)).trimmingCharacters(in: .whitespaces)
        let b = String(ns.substring(from: last + 5)).trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty, !b.isEmpty else { return nil }
        guard let ea = endpoint(a, context: context),
              let eb = endpoint(b, context: context) else { return nil }
        return (ea, eb)
    }

    /// Whether the quote count before `pos` is odd (inside quotes).
    private static func quoteParity(_ s: String, before pos: Int) -> Int {
        let ns = s as NSString
        var count = 0
        for i in 0..<min(pos, ns.length) {
            if ns.character(at: i) == 0x22 { count += 1 }
        }
        return count % 2
    }

    /// One endpoint: quoted place, explicit coordinate pair, bare place.
    static func endpoint(_ s: String, context: NumberFormatContext) -> GeoEndpoint? {
        // Quoted place (quotes already validated by the split side).
        if s.hasPrefix("\""), s.hasSuffix("\""), s.count >= 2 {
            let inner = String(s.dropFirst().dropLast())
            guard !inner.contains("\""), let p = GeoPlaceScan.scan(inner) else { return nil }
            return .place(key: p.key, display: p.display)
        }
        // Explicit coordinate pair: `<num> <sep> <num>` where sep is
        // `,` (dot-decimal modes) or `;` (decimal-comma modes); each
        // component may carry `°` and a cardinal.
        if let pair = coordinatePair(s, context: context) {
            let full = GeoCoordinate(latitude: pair.0.latitude, longitude: pair.1.longitude)
            return .coordinate(full)
        }
        // A bare token marker is an endpoint only through the token
        // route (resolved by the evaluator, not here).
        // Bare place.
        guard let p = GeoPlaceScan.scan(s) else { return nil }
        return .place(key: p.key, display: p.display)
    }

    /// `<num>[° [N|S]] ;? <num>[° [E|W]]` — the explicit offline pair.
    /// A sign conflicting with the cardinal (e.g. `-0.1278 W`) and an
    /// out-of-range value reject the pair.
    static func coordinatePair(_ s: String, context: NumberFormatContext) -> (GeoCoordinate, GeoCoordinate)? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let sep: String = context.decimalComma ? ";" : ","
        guard t.contains(sep), !t.contains(context.decimalComma ? "," : ";") else { return nil }
        let parts = t.components(separatedBy: sep)
        guard parts.count == 2 else { return nil }
        guard let lat = coordinateComponent(parts[0], kind: .latitude, context: context),
              let lon = coordinateComponent(parts[1], kind: .longitude, context: context)
        else { return nil }
        return (lat, lon)
    }

    enum CoordKind { case latitude, longitude }

    /// `48.8566`, `-0.1278`, `48.8566° N`, `30 S` — one signed
    /// coordinate component with an optional cardinal.
    static func coordinateComponent(_ s: String, kind: CoordKind,
                                    context: NumberFormatContext) -> GeoCoordinate? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        // Split off an optional `°` and a cardinal letter.
        var numberPart = t
        var cardinal: Character? = nil
        let upper = t.uppercased()
        if let di = upper.firstIndex(of: "°") {
            let after = upper[upper.index(after: di)...].trimmingCharacters(in: .whitespaces)
            if let c = after.first, after.count == 1, "NSEW".contains(c) {
                cardinal = c
                numberPart = String(t[t.startIndex..<di])
            } else if after.isEmpty {
                numberPart = String(t[t.startIndex..<di])
            } else {
                return nil // garbage after the degree sign
            }
        } else if upper.count >= 2, let c = upper.last, "NSEW".contains(c),
                  (upper[upper.index(before: upper.endIndex)] == " ") {
            // Spaced cardinal without a degree sign: `30 N`.
            cardinal = c
            numberPart = String(t.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        var v = DMSTools.decimalNumber(numberPart, context: context)
        guard v != nil else { return nil }
        if let c = cardinal {
            switch (kind, c) {
            case (.latitude, "N"), (.latitude, "S"),
                 (.longitude, "E"), (.longitude, "W"):
                break
            default:
                return nil // wrong axis cardinal
            }
            if v! < 0 { return nil } // sign vs cardinal conflict
            if c == "S" || c == "W" { v = -v! }
        } else {
            // No cardinal: latitude bounds ±90, longitude ±180.
            let bound = (kind == .latitude) ? 90.0 : 180.0
            guard abs(v!) <= bound else { return nil }
        }
        let c = GeoCoordinate(latitude: (kind == .latitude) ? v! : 0,
                               longitude: (kind == .longitude) ? v! : 0)
        guard c.isValid else { return nil }
        return c
    }
}

// MARK: - Pure evaluation context

/// One validated place reading for a canonical place key. Never
/// persisted in Sheet/.nlx/StorePayload — only in the separate
/// `locations.json` cache owned by `GeoStore`.
public struct GeoSnapshot: Codable, Equatable, Sendable {
    public let placeKey: String
    public let displayPlace: String
    public let placeName: String
    public let country: String?
    public let latitude: Double
    public let longitude: Double
    public let fetchedAt: Date

    public init(placeKey: String, displayPlace: String, placeName: String,
                country: String?, latitude: Double, longitude: Double,
                fetchedAt: Date) {
        self.placeKey = placeKey
        self.displayPlace = displayPlace
        self.placeName = placeName
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.fetchedAt = fetchedAt
    }

    /// Defensive validation: finite in-range coordinates, non-empty
    /// key. Invalid values never become answers or cache entries.
    public var isValid: Bool {
        guard !placeKey.isEmpty, !placeName.trimmingCharacters(in: .whitespaces).isEmpty
        else { return false }
        guard latitude.isFinite, latitude >= -90, latitude <= 90 else { return false }
        guard longitude.isFinite, longitude >= -180, longitude <= 180 else { return false }
        return true
    }

    public var coordinate: GeoCoordinate {
        GeoCoordinate(latitude: latitude, longitude: longitude)
    }
}

/// The pure evaluation context for geography lines: last-good place
/// snapshots by canonical place key plus pending/terminal-failure
/// marks. Owned and published by the app layer; the engine only reads.
public struct GeoContext: Equatable, Sendable {
    public var snapshots: [String: GeoSnapshot]
    public var pendingKeys: Set<String>
    public var failedKeys: Set<String>

    public init(snapshots: [String: GeoSnapshot] = [:],
                pendingKeys: Set<String> = [],
                failedKeys: Set<String> = []) {
        self.snapshots = snapshots
        self.pendingKeys = pendingKeys
        self.failedKeys = failedKeys
    }

    public static let empty = GeoContext()

    /// Whether a place's coordinate is known RIGHT NOW (any age —
    /// staleness belongs to the refresher).
    public func coordinate(forPlaceKey key: String) -> GeoCoordinate? {
        guard let s = snapshots[key], s.isValid else { return nil }
        return s.coordinate
    }
}
