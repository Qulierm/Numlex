import Foundation

// MARK: - r85: pure geography models

/// r85: one validated geographic coordinate. Latitude is finite in
/// -90...90, longitude finite in -180...180 (WGS84). The struct is
/// PURE: no network, no AppKit, no state — the engine, the tokens and
/// the distance math all share this single type.
public struct GeoCoordinate: Equatable, Hashable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Defensive validation: finite in-range components. Invalid
    /// coordinates never become answers, cache entries or tokens.
    public var isValid: Bool {
        guard latitude.isFinite, latitude >= -90, latitude <= 90 else { return false }
        guard longitude.isFinite, longitude >= -180, longitude <= 180 else { return false }
        return true
    }
}

/// r85: the great-circle distance contract.
public enum Haversine {
    /// WGS84 MEAN Earth radius (metres) — the deterministic constant
    /// every distance answer and cache entry is measured against.
    public static let earthRadius: Double = 6_371_008.8

    /// The great-circle distance in metres between two coordinates.
    /// The classic haversine form with `asin(min(1, …))` clamps the
    /// floating-point drift that would otherwise push the argument
    /// past 1 (NaN) on near-antipodal pairs; identical points return
    /// exactly 0, and antipodal pairs converge to the half-circumference
    /// deterministically.
    public static func meters(between a: GeoCoordinate, and b: GeoCoordinate) -> Double {
        guard a.isValid, b.isValid else { return .nan }
        // Same point: exact zero (skips the drift-prone trig path).
        if a.latitude == b.latitude && a.longitude == b.longitude { return 0 }
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let Δφ = (b.latitude - a.latitude) * .pi / 180
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let h = sin(Δφ / 2) * sin(Δφ / 2)
            + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        // Clamp the drift: h can exceed 1 by ~1e-16 on antipodes.
        let hc = min(1.0, max(0.0, h))
        let central = 2 * asin(sqrt(hc))
        let d = earthRadius * central
        // Clamp the result into the physical [0, half-circumference].
        let half = earthRadius * .pi
        return min(half, max(0, d))
    }
}

// MARK: - DMS (degrees / minutes / seconds)

/// One decimal-degree value split into degrees, minutes and seconds
/// (the seconds keep their decimal tail). `negative` carries the sign
/// of the ORIGINAL value (signed-magnitude, exactly like the base
/// presentation): `156.742` → `156° 44′ 31.2″`,
/// `-12.5` → `-12° 30′ 0″`.
public struct DMSParts: Equatable, Sendable {
    public var degrees: Int32
    public var minutes: Int32
    public var seconds: Double
    public var negative: Bool
}

public enum DMSTools {
    /// Decimal degrees → DMS with carry-safe rounding: the seconds
    /// round to one decimal place (ties away from zero), then carry
    /// into minutes/degrees (`59.9996°` → `59° 59′ 60″` → `1° 0′ 0″`
    /// never happens — the carry normalizes it to `60° 0′ 0″`).
    public static func fromDecimal(_ degrees: Double) -> DMSParts? {
        guard degrees.isFinite, abs(degrees) <= 180 else { return nil }
        let negative = degrees < 0
        let mag = abs(degrees)
        let totalSeconds = mag * 3600
        let d = Int32(totalSeconds / 3600)
        var rem = totalSeconds - Double(d) * 3600
        let m = Int32(rem / 60)
        rem -= Double(m) * 60
        // One-decimal rounding, ties away from zero.
        let s = (rem * 10).rounded(.toNearestOrAwayFromZero) / 10
        var mm = m
        var dd = d
        var ss = s
        if ss >= 60 {
            ss -= 60
            mm += 1
        }
        if mm >= 60 {
            mm -= 60
            dd += 1
        }
        guard dd <= 180 else { return nil }
        return DMSParts(degrees: dd, minutes: mm, seconds: ss, negative: negative)
    }

    /// DMS → decimal degrees (exact rational arithmetic through Doubles
    /// at these magnitudes — 60/3600 are exact binary rationals'
    /// denominators, so the roundtrip of a one-decimal seconds value
    /// is stable within 1e-9).
    public static func toDecimal(_ p: DMSParts) -> Double {
        let v = Double(p.degrees) + Double(p.minutes) / 60 + p.seconds / 3600
        return p.negative ? -v : v
    }

    /// The canonical display: `156° 44′ 31.2″` — the seconds component
    /// drops its `.0` when whole, decimal-comma locales render
    /// `31,2″`, and a negative value takes the signed-magnitude minus
    /// (`-12° 30′ 0″`).
    public static func display(_ p: DMSParts, context: NumberFormatContext) -> String {
        let sign = p.negative ? "-" : ""
        let s: String
        if p.seconds == p.seconds.rounded() {
            s = String(Int32(p.seconds))
        } else if context.decimalComma {
            s = String(p.seconds).replacingOccurrences(of: ".", with: ",")
        } else {
            s = String(p.seconds)
        }
        return "\(sign)\(p.degrees)° \(p.minutes)′ \(s)″"
    }

    // MARK: DMS scanning (decimal → decimal direction input)

    /// One DMS COMPONENT as typed: an integer degree run plus optional
    /// `′ minutes` and `″ seconds` (one-decimal seconds). Returns the
    /// decimal value, or nil on a malformed component (double symbols,
    /// out-of-range minutes/seconds, missing symbols between parts).
    /// `context` selects the decimal separator of the seconds tail.
    public static func decimalComponent(_ s: String, context: NumberFormatContext) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        var rest = Substring(t)
        // Degrees: integer digits (the sign is handled by the caller
        // for coordinate forms; a leading minus is accepted here too).
        var negative = false
        if rest.hasPrefix("-") { negative = true; rest = rest.dropFirst() }
        guard let d = scanInt(&rest) else { return nil }
        if rest.isEmpty { return negative ? -Double(d) : Double(d) }
        // Minutes: `′` (U+2032) or an ASCII apostrophe.
        guard rest.hasPrefix("′") || rest.hasPrefix("'") else { return nil }
        rest = rest.dropFirst()
        while rest.hasPrefix(" ") || rest.hasPrefix("\t") { rest = rest.dropFirst() }
        guard let m = scanInt(&rest) else { return nil }
        guard (0...59).contains(m) else { return nil }
        if rest.isEmpty {
            let v = Double(d) + Double(m) / 60
            return negative ? -v : v
        }
        // Seconds: `″` (U+2033) or two ASCII apostrophes.
        let hasDouble = rest.hasPrefix("″")
        let hasTwo = rest.count >= 2 && rest.prefix(2) == "''"
        guard hasDouble || hasTwo else { return nil }
        rest = hasDouble ? rest.dropFirst() : rest.dropFirst(2)
        while rest.hasPrefix(" ") || rest.hasPrefix("\t") { rest = rest.dropFirst() }
        guard let s = scanSeconds(rest, context: context) else { return nil }
        guard s < 60 else { return nil }
        let v = Double(d) + Double(m) / 60 + s / 3600
        return negative ? -v : v
    }

    /// `48.8566` / `48,8566` (context decimal) — the decimal part of a
    /// coordinate or a bare angle. Dot modes: the FIRST dot is the
    /// decimal point, further dots are grouping and are stripped. Comma
    /// modes: the first comma is the decimal point, and the context's
    /// grouping glyphs are stripped.
    public static func decimalNumber(_ s: String, context: NumberFormatContext) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        var out = ""
        var seenDecimal = false
        let decimalChar: Character = context.decimalComma ? "," : "."
        let groupChars: Set<Character> = {
            var set: Set<Character> = []
            if !context.legacy {
                context.groupingSeparator.unicodeScalars.forEach { set.insert(Character($0)) }
                context.inputGroupingSeparators.forEach { $0.unicodeScalars.forEach { set.insert(Character($0)) } }
            } else {
                set.insert(",") // dot-mode grouping
            }
            return set
        }()
        for c in t {
            if c == "-" {
                guard out.isEmpty else { return nil }
                out.append(c)
                continue
            }
            if c == decimalChar {
                guard !seenDecimal, t.contains(where: { $0.isNumber }) else { return nil }
                guard out.last?.isNumber == true || out == "-" else { return nil }
                seenDecimal = true
                out.append(".")
                continue
            }
            if c == "." && !context.decimalComma {
                if !seenDecimal { // treat as decimal too (harmless)
                    seenDecimal = true
                    out.append(".")
                }
                // else: grouping dot — stripped
                continue
            }
            if groupChars.contains(c) { continue }
            guard c.isNumber, c.isASCII else { return nil }
            out.append(c)
        }
        guard !out.isEmpty, out != "-" else { return nil }
        guard out.contains(where: { $0.isNumber }) else { return nil }
        guard let v = Double(out), v.isFinite else { return nil }
        return v
    }

    private static func scanInt(_ rest: inout Substring) -> Int32? {
        var n = 0
        var any = false
        var i = rest.startIndex
        while i < rest.endIndex, rest[i].isNumber, rest[i].isASCII {
            n = n * 10 + Int(rest[i].asciiValue! - 48)
            any = true
            i = rest.index(after: i)
            if n > 1_000_000 { return nil }
        }
        guard any else { return nil }
        rest = rest[i...]
        return Int32(n)
    }

    /// `31.2` / `31,2` (context) — a seconds component with at most
    /// ONE decimal place (the grammar's display precision).
    private static func scanSeconds(_ s: Substring, context: NumberFormatContext) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let text = context.decimalComma
            ? t.replacingOccurrences(of: ",", with: ".")
            : t
        var intPart = ""
        var fracPart = ""
        var seenDot = false
        for c in text {
            if c == "." && !seenDot { seenDot = true; continue }
            if seenDot {
                guard c.isNumber, c.isASCII, fracPart.count < 2 else { return nil }
                fracPart.append(c)
            } else {
                guard c.isNumber, c.isASCII else { return nil }
                intPart.append(c)
            }
        }
        guard !intPart.isEmpty else { return nil }
        let v = Double(intPart + (fracPart.isEmpty ? "" : "." + fracPart))
        guard v != nil, v!.isFinite else { return nil }
        return v
    }
}

// MARK: - Coordinate presentation

/// r85: the display/copy text of a coordinate — the REtypeable pair
/// `48.8566° N, 2.3522° E`: each component is its trimmed decimal
/// (up to six decimals), the hemisphere from its sign (negative →
/// S/W), and the pair separator is `, ` in dot-decimal modes and `; `
/// in decimal-comma modes so Copy stays retypeable in every mode.
/// Deterministic for a coordinate + mode.
public enum GeoPresentation {
    /// `48.8566° N, 2.3522° E` (dot) / `48,8566° N ; 2,3522° E` (comma).
    public static func coordinateText(_ c: GeoCoordinate, context: NumberFormatContext) -> String {
        let sep = context.decimalSeparator == "," ? " ; " : ", "
        return componentText(c.latitude, axis: .lat) + sep + componentText(c.longitude, axis: .lon)
    }

    fileprivate enum Axis { case lat, lon }

    /// One component: `48.8566° N`. Zero shows `0.0° N` (deterministic
    /// hemisphere for zero: N/E).
    fileprivate static func componentText(_ v: Double, axis: Axis) -> String {
        let hemi: String
        switch axis {
        case .lat: hemi = v < 0 ? "S" : "N"
        case .lon: hemi = v < 0 ? "W" : "E"
        }
        let digits = Self.trimmedDigits(abs(v), max: 6)
        return "\(digits)\u{00B0} \(hemi)"
    }

    /// Trimmed decimal digits of a non-negative value (up to `max`
    /// decimals; `0.0` keeps one trailing zero for a stable look).
    /// Locale separators (dot or comma) per the input mode.
    static func trimmedDigits(_ v: Double, max: Int,
                              decimalSep: String = ".") -> String {
        let dec = min(max, 6)
        if v >= 1e9 {
            return String(format: "%.3f", v).replacingOccurrences(of: ".", with: decimalSep)
        }
        var s = String(format: "%.\(dec)f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s.replacingOccurrences(of: ".", with: decimalSep)
    }
}

// MARK: - r85: geo line evaluation

/// r85: the geo error message. The view layer maps it to the
/// localized `Location unavailable` (exactly like the weather message)
/// — Copy stays quiet, the line is shown.
public let geoUnavailableMessage = "Location unavailable"

/// r85: evaluates a parsed geo query against the snapshot context.
/// Pure: no I/O. Ready snapshots (keyed by the BARE place key — the
/// parser's `key` is `<kind>:<bare>`) answer synchronously, loading
/// places are `.skip` and failed/unresolvable places are the
/// `Location unavailable` line.
public func evalGeoLine(_ q: GeoQuery, geo: GeoContext,
                        decimalPlaces: Int, context: NumberFormatContext) -> LineResult {
    switch q.kind {
    case .location, .latitude, .longitude:
        let bare = String(q.key.dropFirst(4))
        if let snap = geo.snapshots[bare], snap.isValid {
            switch q.kind {
            case .location:
                return .location(name: snap.placeName, country: snap.country,
                                 coordinate: snap.coordinate)
            case .latitude:
                return .number(value: snap.coordinate.latitude, unit: "°")
            case .longitude:
                return .number(value: snap.coordinate.longitude, unit: "°")
            case .distance:
                break // unreachable
            }
        }
        if geo.pendingKeys.contains(bare) { return .skip }
        return .error(message: geoUnavailableMessage)
    case .distance(let a, let b):
        enum Res { case known(GeoCoordinate); case loading; case failed }
        func resolve(_ e: GeoEndpoint) -> Res {
            switch e {
            case .coordinate(let c): return .known(c)
            case .place(let key, _):
                if let snap = geo.snapshots[key], snap.isValid {
                    return .known(snap.coordinate)
                }
                if geo.pendingKeys.contains(key) { return .loading }
                return .failed
            }
        }
        let ra = resolve(a)
        let rb = resolve(b)
        if case .failed = ra { return .error(message: geoUnavailableMessage) }
        if case .failed = rb { return .error(message: geoUnavailableMessage) }
        guard case .known(let ca) = ra, case .known(let cb) = rb else {
            return .skip // at least one endpoint still loading
        }
        let d = Haversine.meters(between: ca, and: cb)
        if d >= 1000 {
            return .number(value: roundResult(d / 1000, decimalPlaces: max(decimalPlaces, 10)),
                           unit: "km")
        }
        return .number(value: roundResult(d, decimalPlaces: decimalPlaces), unit: "m")
    }
}

// MARK: - r85: DMS / degree lane

/// r85: the DMS/degree line lane. OWNERSHIP (deterministic, and safe
/// around the catalog's temperature glyphs: `C°`/`F°`/`K°` carry the
/// degree sign after a LETTER and are never owned here):
///   - the line ends with ` as DMS` / ` as decimal`;
///   - it carries a prime/double-prime component (a DMS run);
///   - a DIGIT (or its sign) sits directly before a degree sign —
///     the decimal-degree shape, including a trailing cardinal.
/// Owned lines:
///   - `<decimal> [°] as DMS` → `.dms` (156.742 → `156° 44′ 31.2″`),
///   - `<decimal> as decimal` / a DMS run (glyphs trail each number)
///     → `.number(v, "°")`,
///   - `<number>° [NSEW]` clean → `.number(v, "°")` (N/E → +, S/W → −),
///   - any other owned line → the number before the FIRST degree sign
///     as a `.number(v, "°")` (prose like `It's 5° today` answers `5°`
///     — a quiet degree value, never an error).
public enum DMSParse {
    public static func isOwned(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        let lower = t.lowercased()
        if lower.hasSuffix(" as dms") || lower.hasSuffix(" as decimal") { return true }
        if t.contains("\u{2032}") || t.contains("\u{2033}") { return true }
        guard t.contains("\u{00B0}") else { return false }
        return digitBeforeDegree(t)
    }

    public static func tryLine(_ line: String,
                               context: NumberFormatContext) -> LineResult? {
        guard isOwned(line) else { return nil }
        let t = line.trimmingCharacters(in: .whitespaces)
        let lower = t.lowercased()
        if lower.hasSuffix(" as dms") {
            let left = String(t.dropLast(7)).trimmingCharacters(in: .whitespaces)
            guard let v = decimalAngle(left, context: context) else {
                return .error(message: "Invalid angle")
            }
            guard let parts = DMSTools.fromDecimal(v) else {
                return .error(message: "Invalid angle")
            }
            return .dms(parts)
        }
        if lower.hasSuffix(" as decimal") {
            let left = String(t.dropLast(11)).trimmingCharacters(in: .whitespaces)
            guard let v = anyAngle(left, context: context) else {
                return .error(message: "Invalid angle")
            }
            return .number(value: v, unit: "°")
        }
        if let v = dmsRun(t, context: context) {
            return .number(value: v, unit: "°")
        }
        if let v = cleanDecimalDegree(t, context: context) {
            return .number(value: v, unit: "°")
        }
        // Prime/double-prime lines are STRICT: a malformed DMS run is a
        // visible error. Plain digit-degree lines are LENIENT: the
        // number before the first degree sign answers (prose like
        // `It's 5° today` → `5°`, never an error).
        if t.contains("\u{2032}") || t.contains("\u{2033}") {
            return .error(message: "Invalid angle")
        }
        if let v = firstNumberBeforeDegree(t, context: context) {
            return .number(value: v, unit: "°")
        }
        return .error(message: "Invalid angle")
    }

    // MARK: Components

    /// True when a digit or sign sits directly before some degree
    /// sign (the decimal-degree ownership test; `C°` never matches).
    static func digitBeforeDegree(_ s: String) -> Bool {
        let chars = Array(s)
        for (i, c) in chars.enumerated() where c == "\u{00B0}" {
            guard i > 0 else { continue }
            if chars[i - 1].isNumber || chars[i - 1] == "-" || chars[i - 1] == "+" {
                return true
            }
        }
        return false
    }

    /// `<number> [°] [NSEW]` — a single decimal angle.
    static func decimalAngle(_ s: String, context: NumberFormatContext) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        let upper = t.uppercased()
        var sign: Double = 1
        var vStr = t
        if upper.hasSuffix("\u{00B0}") {
            vStr = String(upper.dropLast())
        } else if upper.count >= 2, let last = upper.last, "NSEW".contains(last),
                  upper[upper.index(before: upper.endIndex)] == " " {
            vStr = String(upper.dropLast())
            sign = (last == "S" || last == "W") ? -1 : 1
        }
        let cleaned = vStr.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{00B0}", with: "")
        guard let v = DMSTools.decimalNumber(cleaned, context: context) else { return nil }
        return sign * v
    }

    /// A DMS run: `[sign] D [°] [M [′]] [S [″]]` with at least TWO
    /// components — the glyphs TRAIL each number (`156° 44′ 31.2″`),
    /// or are absent (`156 44 31`).
    static func dmsRun(_ s: String, context: NumberFormatContext) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        var idx = t.startIndex
        var sign: Double = 1
        if t.first == "-" { sign = -1; idx = t.index(after: idx) }
        else if t.first == "+" { idx = t.index(after: idx) }
        struct Comp { var value: Double; var glyph: Character? }
        var comps: [Comp] = []
        while idx < t.endIndex {
            while idx < t.endIndex, t[idx] == " " { idx = t.index(after: idx) }
            guard idx < t.endIndex else { break }
            let start = idx
            while idx < t.endIndex,
                  (t[idx].isNumber || t[idx] == "." || t[idx] == ",") {
                idx = t.index(after: idx)
            }
            guard idx > start else { return nil }
            let numText = String(t[start..<idx]).lowercased()
            guard let v = DMSTools.decimalNumber(numText, context: context) else { return nil }
            var glyph: Character? = nil
            if idx < t.endIndex {
                let c = t[idx]
                if c == "\u{00B0}" || c == "\u{2032}" || c == "\u{2033}" {
                    glyph = c
                    idx = t.index(after: idx)
                }
            }
            comps.append(Comp(value: v, glyph: glyph))
        }
        guard comps.count >= 2, comps.count <= 3 else { return nil }
        if let g = comps[0].glyph, g != "\u{00B0}" { return nil }
        if comps.count > 1, let g = comps[1].glyph, g != "\u{2032}" { return nil }
        if comps.count > 2, comps[2].glyph != "\u{2033}" { return nil }
        let d = comps[0].value
        let m = comps[1].value
        let sec = comps.count > 2 ? comps[2].value : 0
        return sign * (d + m / 60 + sec / 3600)
    }

    /// `<signed number>° [NSEW]` with nothing else.
    static func cleanDecimalDegree(_ s: String, context: NumberFormatContext) -> Double? {
        guard s.contains("\u{00B0}") else { return nil }
        let upper = s.uppercased()
        guard let di = upper.firstIndex(of: "\u{00B0}") else { return nil }
        let vPart = String(upper[upper.startIndex..<di]).trimmingCharacters(in: .whitespaces)
        let after = String(upper[upper.index(after: di)...]).trimmingCharacters(in: .whitespaces)
        var sign: Double = 1
        if !after.isEmpty {
            guard after.count == 1, let c = after.first, "NSEW".contains(c) else { return nil }
            sign = (c == "S" || c == "W") ? -1 : 1
        }
        guard !vPart.isEmpty else { return nil }
        guard let v = DMSTools.decimalNumber(vPart, context: context) else { return nil }
        if v < 0 { return v }
        return sign * v
    }

    /// The number DIRECTLY before the first degree sign.
    static func firstNumberBeforeDegree(_ s: String, context: NumberFormatContext) -> Double? {
        guard let di = s.firstIndex(of: "\u{00B0}") else { return nil }
        var i = s.index(before: di)
        while i > s.startIndex && s[i] == " " { i = s.index(before: i) }
        let end = i
        while i > s.startIndex, (s[i].isNumber || s[i] == "." || s[i] == ",") {
            i = s.index(before: i)
        }
        guard end > i else { return nil }
        let textStart = (i == s.startIndex) ? s.startIndex : s.index(after: i)
        let text = String(s[textStart..<di])
        return DMSTools.decimalNumber(text.lowercased(), context: context)
    }

    static func anyAngle(_ s: String, context: NumberFormatContext) -> Double? {
        if let v = dmsRun(s, context: context) { return v }
        return decimalAngle(s, context: context)
    }
}
