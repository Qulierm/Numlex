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

/// r89: the eight USER-CONFIGURABLE notebook syntax roles, in the same
/// order the settings lists them. Each role maps to exactly one preset
/// field on `StylingPreferences` (via `presetKeyPath`) and one custom
/// slot on `CustomSyntaxColors` (via `customKeyPath`), so model, palette
/// and UI share ONE role enumeration instead of eight parallel switches.
/// Fixed roles (money marker, hash marker, caret, answer tokens,
/// highlight fills) are deliberately absent.
public enum SyntaxColorRole: String, CaseIterable, Sendable, Equatable, Codable {
    case numbers
    case operators
    case variables
    case units
    case specifiers
    case headings
    case comments
    case labels

    /// The preset-choice field this role owns on `StylingPreferences`.
    public var presetKeyPath: WritableKeyPath<StylingPreferences, RoleColorChoice> {
        switch self {
        case .numbers: \.numbers
        case .operators: \.operators
        case .variables: \.variables
        case .units: \.units
        case .specifiers: \.specifiers
        case .headings: \.headings
        case .comments: \.comments
        case .labels: \.labels
        }
    }

    /// The custom-color slot this role owns on `CustomSyntaxColors`.
    public var customKeyPath: WritableKeyPath<CustomSyntaxColors, SyntaxSRGBColor?> {
        switch self {
        case .numbers: \.numbers
        case .operators: \.operators
        case .variables: \.variables
        case .units: \.units
        case .specifiers: \.specifiers
        case .headings: \.headings
        case .comments: \.comments
        case .labels: \.labels
        }
    }

    /// The settings label key ("styling.role.<raw>").
    public var labelKey: String { "styling.role.\(rawValue)" }
}

/// r89: the canonical, deterministic opaque sRGB value persisted for a
/// custom syntax color: three strict UInt8 channels, no alpha, no color
/// space tag, no platform color object. Encoding is a stable triple of
/// integers; decoding fails on wrong type, non-finite or out-of-range
/// components so a malformed value can only drop its own slot.
public struct SyntaxSRGBColor: Codable, Equatable, Hashable, Sendable {
    public let r: UInt8
    public let g: UInt8
    public let b: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Strict finite double components in 0...1; finite in-range values
    /// are clamped and rounded to UInt8, non-finite input yields `nil`
    /// (the caller drops the value for that role only).
    public init?(_ red: Double, _ green: Double, _ blue: Double) {
        guard red.isFinite, green.isFinite, blue.isFinite else { return nil }
        func q(_ v: Double) -> UInt8 {
            UInt8((min(max(v, 0), 1) * 255).rounded())
        }
        self.init(r: q(red), g: q(green), b: q(blue))
    }
}

/// r89: the optional per-role custom color overrides. Every field is
/// independently optional and independently tolerant: a missing whole
/// block decodes to `nil` on the owner, a present block with missing or
/// malformed entries keeps only the valid roles, and unknown keys are
/// ignored. `nil`/absent means "use the preset" for that role.
public struct CustomSyntaxColors: Codable, Equatable, Sendable {
    public var numbers: SyntaxSRGBColor?
    public var operators: SyntaxSRGBColor?
    public var variables: SyntaxSRGBColor?
    public var units: SyntaxSRGBColor?
    public var specifiers: SyntaxSRGBColor?
    public var headings: SyntaxSRGBColor?
    public var comments: SyntaxSRGBColor?
    public var labels: SyntaxSRGBColor?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        numbers = (try? c.decodeIfPresent(SyntaxSRGBColor.self, forKey: .numbers))
        operators = (try? c.decodeIfPresent(SyntaxSRGBColor.self, forKey: .operators))
        variables = (try? c.decodeIfPresent(SyntaxSRGBColor.self, forKey: .variables))
        units = (try? c.decodeIfPresent(SyntaxSRGBColor.self, forKey: .units))
        specifiers = (try? c.decodeIfPresent(SyntaxSRGBColor.self, forKey: .specifiers))
        headings = (try? c.decodeIfPresent(SyntaxSRGBColor.self, forKey: .headings))
        comments = (try? c.decodeIfPresent(SyntaxSRGBColor.self, forKey: .comments))
        labels = (try? c.decodeIfPresent(SyntaxSRGBColor.self, forKey: .labels))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(numbers, forKey: .numbers)
        try c.encodeIfPresent(operators, forKey: .operators)
        try c.encodeIfPresent(variables, forKey: .variables)
        try c.encodeIfPresent(units, forKey: .units)
        try c.encodeIfPresent(specifiers, forKey: .specifiers)
        try c.encodeIfPresent(headings, forKey: .headings)
        try c.encodeIfPresent(comments, forKey: .comments)
        try c.encodeIfPresent(labels, forKey: .labels)
    }

    public subscript(role: SyntaxColorRole) -> SyntaxSRGBColor? {
        get { self[keyPath: role.customKeyPath] }
        set { self[keyPath: role.customKeyPath] = newValue }
    }

    public mutating func clear(_ role: SyntaxColorRole) {
        self[role] = nil
    }

    public var isEmpty: Bool {
        Self.allRoles.allSatisfy { self[$0] == nil }
    }

    static let allRoles = SyntaxColorRole.allCases

    private enum CodingKeys: String, CodingKey {
        case numbers, operators, variables, units, specifiers
        case headings, comments, labels
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
    /// r87: horizontal placement of the answer content in the 200pt
    /// column. Default `.leading` = the pre-r87 layout.
    public var answerColumnAlignment: AnswerColumnAlignment
    /// r87: the answer column surface. Default `.neutral` = the exact
    /// pre-r87 panel background; the other choices are adaptive sRGB
    /// pairs resolved by the app-side palette (the answer glyph color
    /// stays the centrally resolved accessible base for every surface).
    public var answerColumnSurface: AnswerColumnSurface
    /// r89: optional per-role custom syntax colors. `nil` (the default,
    /// and the decoded value for missing/malformed blocks) means every
    /// role renders its preset; a present block overrides only the roles
    /// whose slot holds a value.
    public var customSyntaxColors: CustomSyntaxColors?

    public init(fontDesign: StylingFontDesign = .system,
                numbers: RoleColorChoice = .cyan,
                operators: RoleColorChoice = .standardText,
                variables: RoleColorChoice = .green,
                units: RoleColorChoice = .pinkPurple,
                specifiers: RoleColorChoice = .standardText,
                headings: RoleColorChoice = .standardText,
                comments: RoleColorChoice = .blue,
                labels: RoleColorChoice = .standardText,
                answerColumnAlignment: AnswerColumnAlignment = .leading,
                answerColumnSurface: AnswerColumnSurface = .neutral,
                customSyntaxColors: CustomSyntaxColors? = nil) {
        self.fontDesign = fontDesign
        self.numbers = numbers
        self.operators = operators
        self.variables = variables
        self.units = units
        self.specifiers = specifiers
        self.headings = headings
        self.comments = comments
        self.labels = labels
        self.answerColumnAlignment = answerColumnAlignment
        self.answerColumnSurface = answerColumnSurface
        self.customSyntaxColors = customSyntaxColors
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
        answerColumnAlignment = (try? c.decodeIfPresent(AnswerColumnAlignment.self, forKey: .answerColumnAlignment)) ?? d.answerColumnAlignment
        answerColumnSurface = (try? c.decodeIfPresent(AnswerColumnSurface.self, forKey: .answerColumnSurface)) ?? d.answerColumnSurface
        // r89: the whole custom block is optional and tolerant — a wrong
        // type drops the block (nil), malformed individual entries are
        // already dropped field-by-field inside CustomSyntaxColors.
        customSyntaxColors = try? c.decodeIfPresent(CustomSyntaxColors.self, forKey: .customSyntaxColors)
    }
}

// MARK: - r89: custom syntax color APIs (pure, model-side)

extension StylingPreferences {
    /// The exact preset choice currently set for one role.
    public func presetChoice(for role: SyntaxColorRole) -> RoleColorChoice {
        self[keyPath: role.presetKeyPath]
    }

    /// The custom override for one role, when one exists.
    public func customColor(for role: SyntaxColorRole) -> SyntaxSRGBColor? {
        customSyntaxColors?[role]
    }

    /// Sets (or clears, for `nil`) one role's custom override without
    /// touching its preset or any other field.
    public mutating func setCustomColor(_ color: SyntaxSRGBColor?,
                                        for role: SyntaxColorRole) {
        if let color {
            var table = customSyntaxColors ?? CustomSyntaxColors()
            table[role] = color
            if table.isEmpty { customSyntaxColors = nil }
            else { customSyntaxColors = table }
        } else {
            customSyntaxColors?[role] = nil
            if customSyntaxColors?.isEmpty == true { customSyntaxColors = nil }
        }
    }

    /// Chooses a preset for one role and CLEARS its custom override —
    /// the preset becomes the effective color again.
    public mutating func choosePreset(_ choice: RoleColorChoice,
                                      for role: SyntaxColorRole) {
        self[keyPath: role.presetKeyPath] = choice
        setCustomColor(nil, for: role)
    }

    /// Restores one role to its exact `StylingPreferences.defaults` preset
    /// and clears its custom override.
    public mutating func resetRoleColors(_ role: SyntaxColorRole) {
        let d = Self.defaults
        self[keyPath: role.presetKeyPath] = d[keyPath: role.presetKeyPath]
        setCustomColor(nil, for: role)
    }

    /// Restores the eight role preset fields to `StylingPreferences`
    /// `.defaults` and drops every custom override. Preserves
    /// `fontDesign`, the answer-column settings and every other field —
    /// colors only.
    public mutating func resetAllSyntaxColors() {
        let d = Self.defaults
        for role in SyntaxColorRole.allCases {
            self[keyPath: role.presetKeyPath] = d[keyPath: role.presetKeyPath]
        }
        customSyntaxColors = nil
    }

    /// True when one role differs from the factory defaults (preset or
    /// a custom override is present).
    public func isSyntaxColorNonDefault(_ role: SyntaxColorRole) -> Bool {
        let d = Self.defaults
        return self[keyPath: role.presetKeyPath] != d[keyPath: role.presetKeyPath]
            || customColor(for: role) != nil
    }

    /// Drives the Reset-Syntax-Colors enabled state.
    public var hasNonDefaultSyntaxColors: Bool {
        SyntaxColorRole.allCases.contains { isSyntaxColorNonDefault($0) }
    }
}