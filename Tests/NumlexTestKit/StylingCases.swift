import Foundation
import NumlexCore

// MARK: - r21: StylingPreferences store behavior
//
// Old/partial/full decode, defaults equality, round-trip and fallback
// for unknown font/color raw values. The store version is NOT bumped by
// the styling key: decoding is purely additive, so pre-r21 stores keep
// loading with styling defaults.

public let stylingCases: [EngineCase] = [
    EngineCase("styling-old-store-decodes-to-defaults") {
        // Exactly the pre-r21 payload shape: no `styling` key at all.
        let old = """
        {"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en",
         "sheetName": "Sheet", "lineNumbers": true, "fontColor": "white",
         "input": {"padOperators": true, "replaceAsterisk": true,
                   "replaceBacktick": false, "quickOperators": true,
                   "groupNumbers": true, "insertPreviousAnswer": true}}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        try expectEqual(s.styling, StylingPreferences.defaults, "old store gets styling defaults")
        try expectEqual(AppSettings.defaults.styling, StylingPreferences.defaults,
                        "defaults object equality")
    },
    EngineCase("styling-partial-payload-defaults-key-by-key") {
        // One field present, the rest must come from the defaults.
        let partial = """
        {"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en",
         "sheetName": "Sheet", "lineNumbers": true, "fontColor": "white",
         "styling": {"fontDesign": "rounded"}}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(partial.utf8))
        try expectEqual(s.styling.fontDesign, .rounded, "present field decodes")
        try expectEqual(s.styling.numbers, .cyan, "absent role falls back")
        try expectEqual(s.styling.operators, .standardText, "absent role falls back")
        try expectEqual(s.styling.variables, .green, "absent role falls back")
        try expectEqual(s.styling.units, .pinkPurple, "absent role falls back")
        try expectEqual(s.styling.specifiers, .standardText, "absent role falls back")
        try expectEqual(s.styling.headings, .standardText, "absent role falls back")
        try expectEqual(s.styling.comments, .blue, "absent role falls back")
        try expectEqual(s.styling.labels, .standardText, "absent role falls back")
    },
    EngineCase("styling-unknown-raw-values-fallback") {
        // Unknown font/color strings must never fail the whole store:
        // they fall back per field to the defaults.
        let weird = """
        {"decimalPlaces": 10, "fontSizeKey": "tf", "language": "en",
         "sheetName": "Sheet", "lineNumbers": true, "fontColor": "white",
         "styling": {"fontDesign": "comic-sans", "numbers": "neon",
                     "comments": "rainbow", "variables": "green"}}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(weird.utf8))
        try expectEqual(s.styling.fontDesign, .system, "unknown font falls back")
        try expectEqual(s.styling.numbers, .cyan, "unknown color falls back")
        try expectEqual(s.styling.comments, .blue, "unknown color falls back")
        try expectEqual(s.styling.variables, .green, "known color survives")
    },
    EngineCase("styling-roundtrip") {
        var s = AppSettings.defaults
        s.styling = StylingPreferences(fontDesign: .monospaced,
                                       numbers: .moneyPurple,
                                       operators: .cyan,
                                       variables: .standardText,
                                       units: .green,
                                       specifiers: .pinkPurple,
                                       headings: .blue,
                                       comments: .standardText,
                                       labels: .moneyPurple)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(back, s, "encode/decode round-trip is exact")
        try expectEqual(back.styling, s.styling, "styling survives round-trip")
    },
    EngineCase("styling-font-choices-are-finite-and-stable") {
        let raw = StylingFontDesign.allCases.map(\.rawValue)
        try expectEqual(raw, ["system", "rounded", "serif", "monospaced"],
                        "font design set is the finite native list")
        for design in StylingFontDesign.allCases {
            let data = try JSONEncoder().encode(design)
            let back = try JSONDecoder().decode(StylingFontDesign.self, from: data)
            try expectEqual(back, design, "design \(design.rawValue) round-trips")
        }
    },
    EngineCase("styling-color-choices-are-finite-and-stable") {
        let raw = RoleColorChoice.allCases.map(\.rawValue)
        try expectEqual(raw, ["standardText", "cyan", "green", "pinkPurple", "blue", "moneyPurple"],
                        "color set is the finite swatch list")
        for color in RoleColorChoice.allCases {
            let data = try JSONEncoder().encode(color)
            let back = try JSONDecoder().decode(RoleColorChoice.self, from: data)
            try expectEqual(back, color, "color \(color.rawValue) round-trips")
        }
    },
    EngineCase("styling-defaults-match-current-app") {
        let d = StylingPreferences.defaults
        // The exact current app: proportional system font, cyan numbers,
        // green variables, pink-purple units, blue `// ` comments; the
        // rest keep the fixed white base.
        try expectEqual(d.fontDesign, .system)
        try expectEqual(d.numbers, .cyan)
        try expectEqual(d.operators, .standardText)
        try expectEqual(d.variables, .green)
        try expectEqual(d.units, .pinkPurple)
        try expectEqual(d.specifiers, .standardText)
        try expectEqual(d.headings, .standardText)
        try expectEqual(d.comments, .blue)
        try expectEqual(d.labels, .standardText)
    },
]