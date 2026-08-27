import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case en, ru, de, fr, it, zh
}


/// The six configurable input behaviors (r19). Nested inside
/// `AppSettings`; every key is optional on decode, so stores written by
/// older versions (missing the whole `input` object) fall back to the
/// defaults instead of failing.
public struct InputPreferences: Codable, Equatable, Sendable {
    /// Pad binary operators with one space on each side (`1+1` becomes `1 + 1`).
    public var padOperators: Bool
    /// Replace ASCII `*` with `×` in input formatting.
    public var replaceAsterisk: Bool
    /// Replace a backtick with `+` in math/natural numeric context.
    public var replaceBacktick: Bool
    /// Map completed digit-bounded p/m/x/d to + / - / × / ÷ operators.
    public var quickOperators: Bool
    /// Group typed integer parts with thousand separators.
    public var groupNumbers: Bool
    /// Insert the last answerable line as a token when an operator is
    /// typed on a new line.
    public var insertPreviousAnswer: Bool

    public init(padOperators: Bool, replaceAsterisk: Bool, replaceBacktick: Bool,
                quickOperators: Bool, groupNumbers: Bool, insertPreviousAnswer: Bool) {
        self.padOperators = padOperators
        self.replaceAsterisk = replaceAsterisk
        self.replaceBacktick = replaceBacktick
        self.quickOperators = quickOperators
        self.groupNumbers = groupNumbers
        self.insertPreviousAnswer = insertPreviousAnswer
    }

    /// Every key is optional on decode: a partially written `input`
    /// object (or an old store missing the whole object) falls back
    /// key-by-key to the r19 defaults instead of failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        padOperators = try c.decodeIfPresent(Bool.self, forKey: .padOperators) ?? InputPreferences.defaults.padOperators
        replaceAsterisk = try c.decodeIfPresent(Bool.self, forKey: .replaceAsterisk) ?? InputPreferences.defaults.replaceAsterisk
        replaceBacktick = try c.decodeIfPresent(Bool.self, forKey: .replaceBacktick) ?? InputPreferences.defaults.replaceBacktick
        quickOperators = try c.decodeIfPresent(Bool.self, forKey: .quickOperators) ?? InputPreferences.defaults.quickOperators
        groupNumbers = try c.decodeIfPresent(Bool.self, forKey: .groupNumbers) ?? InputPreferences.defaults.groupNumbers
        insertPreviousAnswer = try c.decodeIfPresent(Bool.self, forKey: .insertPreviousAnswer) ?? InputPreferences.defaults.insertPreviousAnswer
    }
}

extension InputPreferences {
    /// The r19 defaults for new stores and the settings screen.
    public static let defaults = InputPreferences(
        padOperators: true,
        replaceAsterisk: true,
        replaceBacktick: false,
        quickOperators: true,
        groupNumbers: true,
        insertPreviousAnswer: true
    )

    /// The exact pre-r19 behavior: the hardcoded canonicalization with no
    /// QuickOperators and no grouping. Used for the one-time v1 store
    /// migration so old sheets get exactly what the legacy app did.
    public static let legacy = InputPreferences(
        padOperators: true,
        replaceAsterisk: true,
        replaceBacktick: false,
        quickOperators: false,
        groupNumbers: false,
        insertPreviousAnswer: true
    )
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var decimalPlaces: Int // 2..10
    public var fontSizeKey: String // ttt..tth maps to sizes
    public var language: AppLanguage
    public var sheetName: String
    public var lineNumbers: Bool
    public var fontColor: String // legacy
    public var input: InputPreferences
    /// r21: notebook styling (font design + role colors). The fontSizeKey
    /// above stays the single size source; this section owns its UI.
    public var styling: StylingPreferences

    public static let defaults = AppSettings(
        decimalPlaces: 10,
        fontSizeKey: "tf",
        language: .en,
        sheetName: "Sheet",
        lineNumbers: true,
        fontColor: "white"
    )

    public init(decimalPlaces: Int = 10, fontSizeKey: String = "tf", language: AppLanguage = .en, sheetName: String = "Sheet", lineNumbers: Bool = true, fontColor: String = "white", input: InputPreferences = .defaults, styling: StylingPreferences = .defaults) {
        self.decimalPlaces = decimalPlaces
        self.fontSizeKey = fontSizeKey
        self.language = language
        self.sheetName = sheetName
        self.lineNumbers = lineNumbers
        self.fontColor = fontColor
        self.input = input
        self.styling = styling
    }

    /// Backward-compatible decode: the pre-r19 store has no `input` key
    /// at all and must fall back to the defaults, not fail; the r21
    /// `styling` key is optional the same way. StorePayload.version is
    /// intentionally NOT bumped — decoding is purely additive.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decimalPlaces = try c.decode(Int.self, forKey: .decimalPlaces)
        fontSizeKey = try c.decode(String.self, forKey: .fontSizeKey)
        language = try c.decode(AppLanguage.self, forKey: .language)
        sheetName = try c.decode(String.self, forKey: .sheetName)
        lineNumbers = try c.decode(Bool.self, forKey: .lineNumbers)
        fontColor = try c.decode(String.self, forKey: .fontColor)
        input = try c.decodeIfPresent(InputPreferences.self, forKey: .input) ?? .defaults
        styling = (try? c.decodeIfPresent(StylingPreferences.self, forKey: .styling)) ?? .defaults
    }

    public var fontSize: Double {
        // Every level is exactly 1 pt above the previous scale so that
        // persisted keys keep their relative size and both the editor
        // body and the answer column grow together.
        switch fontSizeKey {
        case "ttt": return 18
        case "tt": return 19
        case "tf": return 20
        case "tff": return 21
        case "ts": return 22
        case "tss": return 24
        case "te": return 26
        case "tn": return 28
        case "tth": return 30
        default: return 20
        }
    }
    /// Derives the line height from the EFFECTIVE font size so TextKit
    /// metrics and the answer column stay 1:1 at every settings level.
    public var lineHeight: Double { (fontSize * 1.6).rounded() }
}

public let fontSizeOptions: [(key: String, label: String)] = [
    ("ttt", "18"), ("tt", "19"), ("tf", "20"), ("tff", "21"), ("ts", "22"), ("tss", "24"), ("te", "26"), ("tn", "28"), ("tth", "30")
]
