import Foundation

// MARK: - r87: number presentation models (presentation-only)
//
// Global preferences are APP-GLOBAL (persisted with the store, never in
// `.nlx`). Per-line NOTATION overrides live in `AnswerDisplayPreference`
// (sheet metadata, exported). Line HIGHLIGHTS are sheet metadata as
// well. Every decode is key-by-key tolerant: missing/malformed/unknown
// values fall back per key to defaults — defaults reproduce the
// pre-r87 behavior byte-for-byte (automatic formatter, minus prefix,
// symbol-prefix currency with no space, fractionization off).

/// r87: how a plain numeric answer is formatted. Stable raw values; an
/// unknown raw string decodes as `.automatic` (the pre-r87 behavior).
public enum NumberNotation: String, CaseIterable, Codable, Equatable, Sendable {
    /// The pre-r87 automatic formatter (grouped integer / trimmed
    /// decimals, compact toggle, >=1e16 scientific fallback).
    case automatic
    /// Fixed precision with trailing-zero trimming.
    case decimal
    /// Normalized mantissa in [1, 10), signed exponent.
    case scientific
    /// Exponent a multiple of 3, mantissa in [1, 1000).
    case engineering
    /// Re-typeable ASCII mixed/proper fraction (falls back to decimal
    /// when no bounded approximation fits).
    case fraction
    /// A user pattern (`#,##0.00` …); falls back to `.automatic` when
    /// the stored pattern is invalid (never blank).
    case custom

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NumberNotation(rawValue: raw) ?? .automatic
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// r87: per-line NOTATION override stored in `AnswerDisplayPreference`.
/// `nil` (absent key) = Default: the line follows the global notation.
/// Deliberately distinct from the global enum: the per-line list has no
/// "automatic" (automatic IS the global behavior — selecting Automatic
/// explicitly records the global automatic choice, which is equivalent
/// to a missing override).
public enum AnswerNotationOverride: String, CaseIterable, Codable, Equatable, Sendable {
    case automatic, decimal, scientific, engineering, fraction, custom

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let known = AnswerNotationOverride(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "unknown notation override '\(raw)'"))
        }
        self = known
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    /// The GLOBAL notation this override selects (nil never occurs —
    /// absence of the key is the Default).
    public var notation: NumberNotation {
        switch self {
        case .automatic: return .automatic
        case .decimal: return .decimal
        case .scientific: return .scientific
        case .engineering: return .engineering
        case .fraction: return .fraction
        case .custom: return .custom
        }
    }
}

/// r87: negative-number presentation. Default `.minus` is the pre-r87
/// shape (`-1,234.5`).
public enum NegativeStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case minus, parentheses, trailingMinus

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NegativeStyle(rawValue: raw) ?? .minus
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// r87: currency symbol placement around the numeric part.
/// `.before` (default) is the pre-r87 byte-for-byte shape: known
/// symbols prefix with NO space (`$1,234.50`); unknown ISO codes fall
/// back to `<value> <CODE>` (value, space, code once — documented
/// deterministic rule, also the pre-r87 shape).
public enum CurrencyPlacement: String, CaseIterable, Codable, Equatable, Sendable {
    case before            // $1,234.50
    case beforeSpaced      // $ 1,234.50
    case after             // 1,234.50$
    case afterSpaced       // 1,234.50 $

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CurrencyPlacement(rawValue: raw) ?? .before
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// r87: the allowed fraction denominators for the fraction notation.
/// Finite presets only (bounded search space, deterministic output).
public enum FractionPreset: Int, CaseIterable, Codable, Equatable, Sendable {
    case e8 = 8, e16 = 16, e32 = 32, e64 = 64, e1000 = 1000

    /// Tolerant decode: a missing/malformed value falls back to `.e16`;
    /// a present value outside the preset set also falls back (the
    /// presets are the ONLY legal denominator bounds).
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = FractionPreset(rawValue: raw) ?? .e16
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// r87: the GLOBAL number presentation preferences (app-global, nested
/// additively in `AppSettings`). Every default reproduces the pre-r87
/// behavior: automatic notation (the existing formatter), no custom
/// pattern, fraction denominator 16 (irrelevant while fractionization
/// is off), minus prefix, symbol-before currency with no space.
public struct NumberPresentationPreferences: Codable, Equatable, Sendable {
    /// Default notation for answers without a per-line override.
    public var notation: NumberNotation
    /// The custom pattern (canonical ASCII skeleton, locale-neutral).
    /// Empty = custom mode unavailable (falls back to automatic).
    /// Persisted verbatim when invalid so the user can fix it; the
    /// formatter exposes the validation error and falls back.
    public var customPattern: String
    /// The maximum fraction denominator (fraction notation only).
    public var fractionPreset: FractionPreset
    /// Negative-number style.
    public var negativeStyle: NegativeStyle
    /// Currency symbol placement (known symbols only — unknown codes
    /// always keep the documented `<value> <CODE>` fallback).
    public var currencyPlacement: CurrencyPlacement

    public init(notation: NumberNotation = .automatic,
                customPattern: String = "",
                fractionPreset: FractionPreset = .e16,
                negativeStyle: NegativeStyle = .minus,
                currencyPlacement: CurrencyPlacement = .before) {
        self.notation = notation
        self.customPattern = customPattern
        self.fractionPreset = fractionPreset
        self.negativeStyle = negativeStyle
        self.currencyPlacement = currencyPlacement
    }

    public static let defaults = NumberPresentationPreferences()

    /// Key-by-key tolerant decode (a missing WHOLE block is the legacy
    /// signal: the caller keeps `.defaults`).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NumberPresentationPreferences.defaults
        notation = (try? c.decodeIfPresent(NumberNotation.self, forKey: .notation)) ?? d.notation
        // The stored pattern is decoded permissively (it stays
        // persisted verbatim for correction; the FORMATTER treats an
        // invalid/overlong pattern as invalid and falls back to the
        // automatic formatter — never blank, never a crash).
        customPattern = (try? c.decodeIfPresent(String.self, forKey: .customPattern)) ?? d.customPattern
        fractionPreset = (try? c.decodeIfPresent(FractionPreset.self, forKey: .fractionPreset)) ?? d.fractionPreset
        negativeStyle = (try? c.decodeIfPresent(NegativeStyle.self, forKey: .negativeStyle)) ?? d.negativeStyle
        currencyPlacement = (try? c.decodeIfPresent(CurrencyPlacement.self, forKey: .currencyPlacement)) ?? d.currencyPlacement
    }
}

// MARK: - r87: answer-column appearance (styling, per the task the
// "color" choice IS the column background; the answer glyph color is
// resolved centrally for contrast — see the app-side palette).

/// r87: horizontal placement of answer content in the 200pt column.
public enum AnswerColumnAlignment: String, CaseIterable, Codable, Equatable, Sendable {
    case leading, trailing

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AnswerColumnAlignment(rawValue: raw) ?? .leading
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// r87: the answer column's surface. `.neutral` (default) is the exact
/// pre-r87 panel; the other choices are finite adaptive sRGB pairs
/// resolved by the app-side palette (no competing glass).
public enum AnswerColumnSurface: String, CaseIterable, Codable, Equatable, Sendable {
    case neutral, sand, slate, sage, blush

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AnswerColumnSurface(rawValue: raw) ?? .neutral
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// r87: one highlight entry decoded TOLERANTLY: a malformed `color`
/// drops only the entry's color; a malformed `lineID` drops the whole
/// entry — the sheet never fails because of one bad record.
struct LineHighlightEntry: Decodable {
    let lineID: UUID
    let color: HighlightColor?

    private enum CodingKeys: String, CodingKey {
        case lineID, color
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lineID = try c.decode(UUID.self, forKey: .lineID)
        color = try? c.decodeIfPresent(HighlightColor.self, forKey: .color)
    }
}

// MARK: - r87: persistent per-line highlights (sheet metadata)

/// r87: the six finite highlight colors. Every case is a deterministic
/// adaptive sRGB PAIR resolved by the app-side palette (subtle fills —
/// syntax colors and selection stay above them).
public enum HighlightColor: String, CaseIterable, Codable, Equatable, Sendable {
    case yellow, orange, green, blue, purple, pink

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let known = HighlightColor(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "unknown highlight color '\(raw)'"))
        }
        self = known
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// r87: one persisted highlight, keyed by STABLE line UUID (never row
/// index) — the same identity contract as answer display overrides, so
/// inserts/deletes above a highlighted line keep the fill on it and
/// stale IDs are sanitized away on every mutation.
public struct LineHighlightPreference: Codable, Equatable, Identifiable, Sendable {
    public var lineID: UUID
    public var color: HighlightColor

    public var id: UUID { lineID }

    public init(lineID: UUID, color: HighlightColor) {
        self.lineID = lineID
        self.color = color
    }

    /// Keeps only entries whose line still exists (a malformed color
    /// makes its entry drop), drops duplicates (first wins) and
    /// returns the survivors in CURRENT line order.
    public static func sanitize(_ prefs: [LineHighlightPreference],
                                lineIDs: [UUID]) -> [LineHighlightPreference] {
        let order = Dictionary(uniqueKeysWithValues: lineIDs.enumerated().map { ($1, $0) })
        var seen = Set<UUID>()
        var kept: [LineHighlightPreference] = []
        for p in prefs {
            guard order[p.lineID] != nil, !seen.contains(p.lineID) else { continue }
            seen.insert(p.lineID)
            kept.append(p)
        }
        return kept.sorted { order[$0.lineID]! < order[$1.lineID]! }
    }

    /// Tolerant entry decode: a wrong-typed color (or any malformed
    /// entry) is dropped by the caller's `(try? ...)` — the sheet never
    /// fails because of one bad highlight record.
}
