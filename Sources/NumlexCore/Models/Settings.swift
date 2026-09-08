import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case en, ru, de, fr, it, zh
}

/// r38: the app-wide native appearance. Persisted in the store (the
/// single source of truth — no separate UserDefaults key). Raw values
/// are stable (`light`, `dark`); legacy stores without the key decode
/// to `.light` (the r36 permanent-light behavior), so existing stores
/// keep behaving exactly as before.
public enum AppAppearance: String, Codable, CaseIterable, Sendable, Equatable {
    case light, dark
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
    /// r60: hide the native sidebar toolbar button while the sidebar
    /// is collapsed (reopen via Control-Command-S). Default OFF.
    public var hideSidebarButtonWhenCollapsed: Bool
    /// r80: show the sheet's bottom Total panel under the answer
    /// column. Default ON (the pre-r80 layout). OFF removes only that
    /// panel and its reserved space — inline total lines keep
    /// evaluating and rendering as before.
    public var showTotalBar: Bool
    public var fontColor: String // legacy
    public var input: InputPreferences
    /// r21: notebook styling (font design + role colors). The fontSizeKey
    /// above stays the single size source; this section owns its UI.
    public var styling: StylingPreferences
    /// r33: GLOBAL user-defined constants, available live in every
    /// sheet (never embedded in `.nlx` exports). Source expressions
    /// only — no computed snapshots.
    public var customConstants: [UserConstant]
    /// r38: the app-wide Light/Dark appearance (persisted; the
    /// authoritative source for the one NSApp.appearance application).
    public var appearance: AppAppearance
    /// r73: the regional number settings. `nil` means the store has
    /// no `regional` key at all — the PRE-r73 legacy store — and the
    /// app keeps the pre-r73 US behavior (decimal `.`, grouping `,`,
    /// display always grouped) byte-for-byte. A present block resolves
    /// through `NumberFormatContext.resolve`; writing the regional
    /// tab on a legacy store promotes it to `RegionalNumberPreferences`
    /// (its defaults reproduce the legacy scale: system region is the
    /// OS locale, grouping on, compact off, paste conversion off).
    public var regional: RegionalNumberPreferences?
    /// r84: the GLOBAL custom units (name + definition source rows),
    /// available live in every sheet, app-global (never embedded in
    /// `.nlx` exports). Bounded to `UnitResolver.maxRows` (100) by the
    /// UI and classified per pass by `UnitResolver`.
    public var customUnits: [UserUnitDefinition]

    public static let defaults = AppSettings(
        decimalPlaces: 10,
        fontSizeKey: "tf",
        language: .en,
        sheetName: "Sheet",
        lineNumbers: true,
        hideSidebarButtonWhenCollapsed: false,
        showTotalBar: true,
        fontColor: "white",
        customUnits: []
)

    public init(decimalPlaces: Int = 10, fontSizeKey: String = "tf", language: AppLanguage = .en, sheetName: String = "Sheet", lineNumbers: Bool = true, hideSidebarButtonWhenCollapsed: Bool = false, showTotalBar: Bool = true, fontColor: String = "white", input: InputPreferences = .defaults, styling: StylingPreferences = .defaults, customConstants: [UserConstant] = [], appearance: AppAppearance = .light, regional: RegionalNumberPreferences? = nil, customUnits: [UserUnitDefinition] = []) {
        self.decimalPlaces = decimalPlaces
        self.fontSizeKey = fontSizeKey
        self.language = language
        self.sheetName = sheetName
        self.lineNumbers = lineNumbers
        self.hideSidebarButtonWhenCollapsed = hideSidebarButtonWhenCollapsed
        self.showTotalBar = showTotalBar
        self.fontColor = fontColor
        self.input = input
        self.styling = styling
        self.customConstants = customConstants
        self.appearance = appearance
        self.regional = regional
        self.customUnits = customUnits
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
        // r60: additive — pre-r60 stores carry no key and fall back
        // to false (StorePayload.version is NOT bumped).
        hideSidebarButtonWhenCollapsed = (try? c.decodeIfPresent(Bool.self, forKey: .hideSidebarButtonWhenCollapsed)) ?? false
        // r80: additive and failure-proof — a missing key (legacy
        // store) or a malformed value falls back to true, the
        // pre-r80 layout (StorePayload.version is NOT bumped).
        showTotalBar = (try? c.decodeIfPresent(Bool.self, forKey: .showTotalBar)) ?? true
        fontColor = try c.decode(String.self, forKey: .fontColor)
        input = try c.decodeIfPresent(InputPreferences.self, forKey: .input) ?? .defaults
        styling = (try? c.decodeIfPresent(StylingPreferences.self, forKey: .styling)) ?? .defaults
        // r33: additive — pre-r33 stores carry no `customConstants` key
        // at all and fall back to the empty list (StorePayload.version
        // is NOT bumped).
        customConstants = (try? c.decodeIfPresent([UserConstant].self, forKey: .customConstants)) ?? []
        // r38: additive, key-by-key and failure-proof — a missing key
        // (legacy store), an invalid raw value or a wrong JSON type all
        // fall back to `.light` instead of failing the whole store
        // (StorePayload.version is NOT bumped; nothing is migrated).
        appearance = (try? c.decodeIfPresent(AppAppearance.self, forKey: .appearance)) ?? .light
        // r73: additive — pre-r73 stores carry no `regional` key at
        // all: `nil` is the legacy signal (pre-r73 US behavior). A
        // present block decodes per-key tolerantly (see
        // RegionalNumberPreferences).
        regional = (try? c.decodeIfPresent(RegionalNumberPreferences.self, forKey: .regional))
        // r84: additive — pre-r84 stores carry no `customUnits` key
        // and fall back to the empty list (StorePayload.version is NOT
        // bumped; nothing is migrated).
        customUnits = (try? c.decodeIfPresent([UserUnitDefinition].self, forKey: .customUnits)) ?? []
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
