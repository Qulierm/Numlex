import Foundation

/// r73: the user's regional number CONVENTIONS. The numeric locale is
/// deliberately independent of the UI language: `AppSettings.language`
/// only localizes chrome text; number input/display separators resolve
/// from ONE shared `NumberFormatContext` (below), built from this
/// preset plus a (test-injectable) `Locale` for the system preset.
///
/// Presets:
/// - `system`: the actual `Locale.current` numeric conventions
///   (`decimalSeparator`, `groupingSeparator`) — including NBSP/NNBSP
///   or Indian-style grouping where the platform provides it. The
///   displayed region name is the localized OS region; the app never
///   pretends the system locale is a fixed preset.
/// - `northAmerica`: `1,234.56` — decimal `.` grouping `,`
///   argument separator `,`.
/// - `westernEurope`: `1.234,56` — decimal `,` grouping `.`
///   argument separator `;` (`max(1,5; 2,5)`).
/// - `easternEurope`: `1 234,56` — decimal `,` grouping U+00A0
///   (non-breaking space; a plain typed space is accepted as grouping
///   input) — argument separator `;`.
public enum NumberRegionPreset: String, Codable, CaseIterable, Sendable {
    case system, northAmerica, westernEurope, easternEurope

    /// Fixed numeric locale per fixed preset (the `system` preset uses
    /// the caller-supplied locale, never one of these).
    public var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .northAmerica: return "en_US"
        case .westernEurope: return "de_DE"
        case .easternEurope: return "ru_RU"
        }
    }

    /// The human-readable picker title: fixed presets name their
    /// convention; the system preset shows the OS region's localized
    /// name (falling back to "System Region" when the OS exposes none).
    public func displayName(in locale: Locale) -> String {
        switch self {
        case .system:
            // The OS region's localized name. The raw "NSRegion" key
            // (NSLocale's region code key) avoids the soft-deprecated
            // Swift `Locale.regionCode` accessor.
            let code = (locale as NSLocale)
                .object(forKey: NSLocale.Key(rawValue: "NSRegion")) as? String
            if let code, !code.isEmpty {
                return locale.localizedString(forRegionCode: code)
                    ?? "System Region"
            }
            return "System Region"
        case .northAmerica: return "North America"
        case .westernEurope: return "Western Europe"
        case .easternEurope: return "Eastern Europe"
        }
    }
}

/// r73: per-key-tolerant decode of the regional preferences block.
/// A missing WHOLE block is the legacy-store signal (the caller keeps
/// the pre-r73 US behavior — see `NumberFormatContext.legacy`); a
/// block that IS present decodes key-by-key with per-key fallbacks:
/// an unknown `region` raw value falls back to `.system`, each missing
/// boolean falls back to the new-store default (paste conversion OFF,
/// grouping ON, compact OFF — "preserve current scale by default").
public struct RegionalNumberPreferences: Codable, Equatable, Sendable {
    public var region: NumberRegionPreset
    /// Convert confidently-foreign numeric spans when pasting from
    /// outside (OFF by default: paste stays byte-identical otherwise).
    public var convertForeignOnPaste: Bool
    /// Show (and type) thousands separators in integer parts.
    public var showThousandsSeparator: Bool
    /// Compact presentation of large scalars (100000 → 100k).
    /// Presentation-only: stored values, tokens and totals keep full
    /// precision; money and unit results are never compacted.
    public var useCompactNotation: Bool

    public init(region: NumberRegionPreset,
                convertForeignOnPaste: Bool,
                showThousandsSeparator: Bool,
                useCompactNotation: Bool) {
        self.region = region
        self.convertForeignOnPaste = convertForeignOnPaste
        self.showThousandsSeparator = showThousandsSeparator
        self.useCompactNotation = useCompactNotation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = (try? c.decodeIfPresent(String.self, forKey: .region)) ?? nil
        region = raw.flatMap { NumberRegionPreset(rawValue: $0) } ?? .system
        convertForeignOnPaste = try c.decodeIfPresent(Bool.self, forKey: .convertForeignOnPaste)
            ?? RegionalNumberPreferences.newDefaults.convertForeignOnPaste
        showThousandsSeparator = try c.decodeIfPresent(Bool.self, forKey: .showThousandsSeparator)
            ?? RegionalNumberPreferences.newDefaults.showThousandsSeparator
        useCompactNotation = try c.decodeIfPresent(Bool.self, forKey: .useCompactNotation)
            ?? RegionalNumberPreferences.newDefaults.useCompactNotation
    }
}

extension NumberFormatContext {
    /// The same context with compact notation off — the clipboard and
    /// per-answer copy always carry the full-precision value even when
    /// the display row compacts it (`100k` shows, `100,000` copies).
    var withoutCompactNotation: NumberFormatContext {
        guard compactNotation else { return self }
        return NumberFormatContext(
            locale: locale,
            decimalSeparator: decimalSeparator,
            groupingSeparator: groupingSeparator,
            inputGroupingSeparators: inputGroupingSeparators,
            argumentSeparator: argumentSeparator,
            displayGrouping: displayGrouping,
            compactNotation: false,
            convertForeignOnPaste: convertForeignOnPaste,
            legacy: legacy
        )
    }
}

extension RegionalNumberPreferences {
    /// Defaults for BRAND-NEW stores (and the one-time upgrade of a
    /// legacy store the moment a regional control is first written):
    /// system region, paste conversion OFF, grouping ON (the legacy
    /// display already grouped), compact OFF (the legacy display never
    /// compacted — existing answer scales are preserved).
    public static let newDefaults = RegionalNumberPreferences(
        region: .system,
        convertForeignOnPaste: false,
        showThousandsSeparator: true,
        useCompactNotation: false
    )
}

/// r73: THE immutable, value-passed number-format context threaded
/// through parsing, highlighting, input autoformat, display and
/// clipboard. Callers that take no context get the exact pre-r73
/// behavior (`legacy`): decimal `.`, grouping `,` in both display and
/// input (input additionally gated by the existing
/// `input.groupNumbers` setting), function argument separator `,` —
/// no locale-driven state anywhere.
public struct NumberFormatContext: Equatable, Sendable {
    /// Numeric locale (system conventions for `.system`; the fixed
    /// preset locale otherwise). Never drives UI language.
    public let locale: Locale
    /// `.`, `,` — the decimal separator in typed/pasted input.
    public let decimalSeparator: String
    /// The grouping separator used when `displayGrouping` is ON:
    /// `,` (NA/legacy), `.` (Western Europe), U+00A0 (Eastern Europe),
    /// or the system locale's own separator (possibly empty/NNBSP).
    public let groupingSeparator: String
    /// Extra grouping separators ACCEPTED in input on top of
    /// `groupingSeparator` (Eastern Europe also accepts a plain typed
    /// space between groups).
    public let inputGroupingSeparators: [String]
    /// Function-call argument separator: `,` in decimal-point modes,
    /// `;` in decimal-comma modes (`max(1,5; 2,5)`).
    public let argumentSeparator: String
    /// Whether display (and fresh input) insert thousands separators.
    public let displayGrouping: Bool
    /// Compact notation presentation for large scalars (display/copy
    /// only).
    public let compactNotation: Bool
    /// Convert foreign numeric spans on external paste.
    public let convertForeignOnPaste: Bool
    /// True for the pre-r73 legacy store behavior (the display grouped
    /// unconditionally; input grouping follows `input.groupNumbers`).
    public let legacy: Bool

    public init(locale: Locale,
                decimalSeparator: String,
                groupingSeparator: String,
                inputGroupingSeparators: [String] = [],
                argumentSeparator: String,
                displayGrouping: Bool,
                compactNotation: Bool,
                convertForeignOnPaste: Bool,
                legacy: Bool = false) {
        self.locale = locale
        self.decimalSeparator = decimalSeparator
        self.groupingSeparator = groupingSeparator
        self.inputGroupingSeparators = inputGroupingSeparators
        self.argumentSeparator = argumentSeparator
        self.displayGrouping = displayGrouping
        self.compactNotation = compactNotation
        self.convertForeignOnPaste = convertForeignOnPaste
        self.legacy = legacy
    }

    public var decimalComma: Bool { decimalSeparator == "," }

    /// The exact pre-r73 behavior (en_US conventions): decimal `.`
    /// grouping `,` (display always grouped; input grouped per the
    /// existing `input.groupNumbers` preference), argument `,`.
    public static let legacy = NumberFormatContext(
        locale: Locale(identifier: "en_US"),
        decimalSeparator: ".",
        groupingSeparator: ",",
        argumentSeparator: ",",
        displayGrouping: true,
        compactNotation: false,
        convertForeignOnPaste: false,
        legacy: true
    )

    /// Resolves the app's ONE active context: `nil` preferences are
    /// legacy stores (pre-r73 US behavior, unchanged on launch);
    /// present preferences resolve through their preset — the
    /// `system` preset uses `locale` (inject `Locale(identifier:)`
    /// for deterministic tests), fixed presets use their own locale.
    public static func resolve(_ prefs: RegionalNumberPreferences?,
                               locale: Locale = .current) -> NumberFormatContext {
        guard let prefs else { return .legacy }
        switch prefs.region {
        case .system:
            let l = locale
            let dec = (l.decimalSeparator?.isEmpty == false ? l.decimalSeparator! : ".")
            let grp = l.groupingSeparator ?? ""
            return NumberFormatContext(
                locale: l,
                decimalSeparator: dec,
                groupingSeparator: grp.isEmpty ? "," : grp,
                inputGroupingSeparators: grp.isEmpty ? [] : [grp],
                argumentSeparator: dec == "," ? ";" : ",",
                displayGrouping: prefs.showThousandsSeparator,
                compactNotation: prefs.useCompactNotation,
                convertForeignOnPaste: prefs.convertForeignOnPaste
            )
        case .northAmerica:
            return NumberFormatContext(
                locale: Locale(identifier: "en_US"),
                decimalSeparator: ".",
                groupingSeparator: ",",
                argumentSeparator: ",",
                displayGrouping: prefs.showThousandsSeparator,
                compactNotation: prefs.useCompactNotation,
                convertForeignOnPaste: prefs.convertForeignOnPaste
            )
        case .westernEurope:
            return NumberFormatContext(
                locale: Locale(identifier: "de_DE"),
                decimalSeparator: ",",
                groupingSeparator: ".",
                argumentSeparator: ";",
                displayGrouping: prefs.showThousandsSeparator,
                compactNotation: prefs.useCompactNotation,
                convertForeignOnPaste: prefs.convertForeignOnPaste
            )
        case .easternEurope:
            let nbsp = "\u{00A0}"
            return NumberFormatContext(
                locale: Locale(identifier: "ru_RU"),
                decimalSeparator: ",",
                groupingSeparator: nbsp,
                inputGroupingSeparators: [nbsp, " "],
                argumentSeparator: ";",
                displayGrouping: prefs.showThousandsSeparator,
                compactNotation: prefs.useCompactNotation,
                convertForeignOnPaste: prefs.convertForeignOnPaste
            )
        }
    }
}
