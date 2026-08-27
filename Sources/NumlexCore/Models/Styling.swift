import Foundation

/// r21: user-chosen font design for notebook text. Finite native system
/// designs only — every entry maps 1:1 to an `NSFont` system design AND
/// a SwiftUI `Font.Design`, so the editor (TextKit), the answer column
/// and the settings preview always render the same face with the same
/// metrics (line-height and baseline math run on the real font).
/// Persistent raw values are stable strings; decoding an unknown value
/// falls back to `.system` instead of failing the whole store.
public enum StylingFontDesign: String, CaseIterable, Sendable, Equatable, Codable {
    case system
    case rounded
    case serif
    case monospaced

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let known = StylingFontDesign(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "unknown font design '\(raw)'"))
        }
        self = known
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// r21: one finite color choice for a notebook role. Every case is a
/// deterministic sRGB swatch (see the app-side palette resolver, which
/// owns the exact channel values); `standardText` is the editor's fixed
/// white base. The money-marker, answer-token and caret colors are NOT
/// part of this set — they stay fixed by design. Unknown raw values fall
/// back to `.standardText`.
public enum RoleColorChoice: String, CaseIterable, Sendable, Equatable, Codable {
    case standardText
    case cyan
    case green
    case pinkPurple
    case blue
    case moneyPurple

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let known = RoleColorChoice(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "unknown role color '\(raw)'"))
        }
        self = known
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// r21: the notebook styling section of the settings store.
///
/// Key-by-key optional decode: an old store without the `styling` key,
/// a partial styling payload (one field changed), or a payload with an
/// unknown font/color value each fall back per field to the defaults —
/// never fail, never migrate content (StorePayload.version stays 2).
///
/// Defaults reproduce the current app EXACTLY: system proportional
/// regular font; cyan numbers, green variables, pink-purple units,
/// blue `// ` comments; operators, specifiers, heading bodies and prose
/// labels in the fixed white base text.
public struct StylingPreferences: Codable, Equatable, Sendable {
    public var fontDesign: StylingFontDesign
    public var numbers: RoleColorChoice
    public var operators: RoleColorChoice
    public var variables: RoleColorChoice
    public var units: RoleColorChoice
    public var specifiers: RoleColorChoice
    public var headings: RoleColorChoice
    public var comments: RoleColorChoice
    public var labels: RoleColorChoice

    public init(fontDesign: StylingFontDesign = .system,
                numbers: RoleColorChoice = .cyan,
                operators: RoleColorChoice = .standardText,
                variables: RoleColorChoice = .green,
                units: RoleColorChoice = .pinkPurple,
                specifiers: RoleColorChoice = .standardText,
                headings: RoleColorChoice = .standardText,
                comments: RoleColorChoice = .blue,
                labels: RoleColorChoice = .standardText) {
        self.fontDesign = fontDesign
        self.numbers = numbers
        self.operators = operators
        self.variables = variables
        self.units = units
        self.specifiers = specifiers
        self.headings = headings
        self.comments = comments
        self.labels = labels
    }

    public static let defaults = StylingPreferences()

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StylingPreferences.defaults
        // try? decodeIfPresent: a present-but-invalid value (unknown raw
        // string, wrong type) behaves exactly like a missing key and
        // falls back to the field default instead of failing the store.
        fontDesign = (try? c.decodeIfPresent(StylingFontDesign.self, forKey: .fontDesign)) ?? d.fontDesign
        numbers = (try? c.decodeIfPresent(RoleColorChoice.self, forKey: .numbers)) ?? d.numbers
        operators = (try? c.decodeIfPresent(RoleColorChoice.self, forKey: .operators)) ?? d.operators
        variables = (try? c.decodeIfPresent(RoleColorChoice.self, forKey: .variables)) ?? d.variables
        units = (try? c.decodeIfPresent(RoleColorChoice.self, forKey: .units)) ?? d.units
        specifiers = (try? c.decodeIfPresent(RoleColorChoice.self, forKey: .specifiers)) ?? d.specifiers
        headings = (try? c.decodeIfPresent(RoleColorChoice.self, forKey: .headings)) ?? d.headings
        comments = (try? c.decodeIfPresent(RoleColorChoice.self, forKey: .comments)) ?? d.comments
        labels = (try? c.decodeIfPresent(RoleColorChoice.self, forKey: .labels)) ?? d.labels
    }
}