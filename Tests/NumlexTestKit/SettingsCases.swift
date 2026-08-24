import Foundation
import NumlexCore

/// Focused cases for the font-size scale: every settings key maps to the
/// raised size, the default key and fallback resolve to 20, and the line
/// height always derives from the effective font size so TextKit metrics
/// and the answer column stay 1:1 at every level.
public let settingsCases: [EngineCase] = [
    EngineCase("settings-font-size-every-key") {
        let expected: [String: Double] = [
            "ttt": 18, "tt": 19, "tf": 20, "tff": 21, "ts": 22,
            "tss": 24, "te": 26, "tn": 28, "tth": 30,
        ]
        for (key, size) in expected {
            var s = AppSettings.defaults
            s.fontSizeKey = key
            try expectEqual(s.fontSize, size, "key \(key)")
        }
        // The visible settings labels must advertise exactly these sizes.
        for opt in fontSizeOptions {
            try expectEqual(fontSizeOptions.first(where: { $0.key == opt.key })?.label,
                            String(Int(expected[opt.key]!)), "label for \(opt.key)")
        }
    },
    EngineCase("settings-font-size-default-and-fallback") {
        try expectEqual(AppSettings.defaults.fontSizeKey, "tf", "default key")
        try expectEqual(AppSettings.defaults.fontSize, 20, "default size")
        var s = AppSettings.defaults
        s.fontSizeKey = "not-a-key"
        try expectEqual(s.fontSize, 20, "unknown key falls back to default size")
    },
    EngineCase("settings-line-height-derives-from-font") {
        for opt in fontSizeOptions {
            var s = AppSettings.defaults
            s.fontSizeKey = opt.key
            let expected = (s.fontSize * 1.6).rounded()
            try expectEqual(s.lineHeight, expected, "lineHeight for \(opt.key)")
        }
        try expectEqual(AppSettings.defaults.lineHeight, 32.0, "default tf = 20pt -> 32")
        // Every step of the scale keeps the 1.6 ratio rounded — the same
        // value TextKit and the answer column must use.
        let sizes = fontSizeOptions.map {
            AppSettings(fontSizeKey: $0.key).fontSize
        }
        try expect(sizes == sizes.sorted(), "scale stays monotonic")
    },
]
