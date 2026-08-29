import Foundation
import NumlexCore

/// r38: the persisted Light/Dark appearance preference — raw-value
/// stability, additive/backward-compatible decoding (missing key,
/// invalid raw, wrong type all fall back to `.light` without failing
/// the store) and full roundtrip. The NSApp.appearance projection and
/// the palette resolver are app-layer UI state (not exercised here).
public let r38Cases: [EngineCase] = [
    EngineCase("r38-appearance-raw-order-stability") {
        try expectEqual(AppAppearance.allCases, [.light, .dark],
                        "exactly two cases, light before dark")
        try expectEqual(AppAppearance.allCases.map(\.rawValue), ["light", "dark"],
                        "raw values are the stable wire values")
        try expectEqual(AppAppearance(rawValue: "light")!, .light)
        try expectEqual(AppAppearance(rawValue: "dark")!, .dark)
        try expect(AppAppearance(rawValue: "LIGHT") == nil,
                   "raw values are case-sensitive wire values")
        // Codable roundtrip of the bare enum in both directions.
        for a in AppAppearance.allCases {
            let data = try JSONEncoder().encode(a)
            try expectEqual(try JSONDecoder().decode(AppAppearance.self, from: data), a)
        }
    },
    EngineCase("r38-appearance-settings-default-light") {
        try expectEqual(AppSettings().appearance, .light,
                        "the plain initializer defaults to light")
        try expectEqual(AppSettings.defaults.appearance, .light,
                        "the shared defaults constant is light")
    },
    EngineCase("r38-appearance-legacy-missing-key") {
        // A pre-r38 store: the settings object exists but carries no
        // `appearance` key at all — it decodes light, never fails.
        let json = """
        {"decimalPlaces":7,"fontSizeKey":"ts","language":"ru","sheetName":"S",
         "lineNumbers":false,"fontColor":"white"}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        try expectEqual(s.appearance, .light, "missing key decodes to light")
        try expectEqual(s.decimalPlaces, 7, "sibling keys are untouched")
        try expectEqual(s.language, .ru)
    },
    EngineCase("r38-appearance-invalid-key-fallback") {
        // Invalid raw value: unknown but well-formed string -> light.
        let bad = """
        {"decimalPlaces":10,"fontSizeKey":"tf","language":"en","sheetName":"Sheet",
         "lineNumbers":true,"fontColor":"white","appearance":"neon"}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(bad.utf8))
        try expectEqual(s.appearance, .light, "invalid raw falls back to light")
        // Wrong JSON type (number): still light, store never fails.
        let wrongType = """
        {"decimalPlaces":10,"fontSizeKey":"tf","language":"en","sheetName":"Sheet",
         "lineNumbers":true,"fontColor":"white","appearance":7}
        """
        let s2 = try JSONDecoder().decode(AppSettings.self, from: Data(wrongType.utf8))
        try expectEqual(s2.appearance, .light, "wrong type falls back to light")
        try expectEqual(s2.decimalPlaces, 10, "the rest of the store decodes")
    },
    EngineCase("r38-appearance-dark-full-roundtrip") {
        var s = AppSettings()
        s.decimalPlaces = 4
        s.fontSizeKey = "tth"
        s.language = .de
        s.sheetName = "Kurse"
        s.lineNumbers = false
        s.appearance = .dark
        let data = try JSONEncoder().encode(s)
        let s2 = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(s2, s, "dark settings survive a full roundtrip")
        try expectEqual(s2.appearance, .dark)
        try expectEqual(s2.decimalPlaces, 4)
        try expectEqual(s2.fontSizeKey, "tth")
        try expectEqual(s2.language, .de)
        try expectEqual(s2.sheetName, "Kurse")
        try expectEqual(s2.lineNumbers, false)
        // And light roundtrips identically.
        s.appearance = .light
        let s3 = try JSONDecoder().decode(
            AppSettings.self, from: JSONEncoder().encode(s))
        try expectEqual(s3.appearance, .light)
        try expectEqual(s3, s)
    }
]
