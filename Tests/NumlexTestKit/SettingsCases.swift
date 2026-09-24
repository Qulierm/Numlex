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

    // MARK: window frame + sidebar visibility (additive persistence)

    EngineCase("settings-window-frame-legacy-store-is-unchanged") {
        // A store written by ANY earlier build has neither key. It must
        // decode to today's behavior byte-for-byte: no saved frame (the
        // app centers 800x600) and the sidebar expanded. The payload
        // version stays 2 and nothing is migrated.
        let encoder = JSONEncoder()
        let full = try encoder.encode(AppSettings.defaults)
        guard var obj = try JSONSerialization.jsonObject(with: full) as? [String: Any] else {
            throw CaseFailure(message: "settings must encode to an object", location: "SettingsCases")
        }
        obj.removeValue(forKey: "windowFrame")
        obj.removeValue(forKey: "sidebarVisible")
        let legacy = try JSONSerialization.data(withJSONObject: obj)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacy)
        try expect(decoded.windowFrame == nil, "no key -> no saved frame (centered default)")
        try expectEqual(decoded.sidebarVisible, true, "no key -> the expanded sidebar")
        try expectEqual(decoded, AppSettings.defaults, "a keyless store equals the defaults")
        try expectEqual(StorePayload.currentVersion, 2, "the payload version is NOT bumped")
    },

    EngineCase("settings-window-frame-round-trips") {
        let settings = AppSettings(windowFrame: SavedWindowFrame(x: -120, y: 40, width: 900, height: 700),
                                   sidebarVisible: false)
        let data = try JSONEncoder().encode(settings)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        try expectEqual(back.windowFrame,
                        SavedWindowFrame(x: -120, y: 40, width: 900, height: 700),
                        "the saved frame survives the round trip")
        try expectEqual(back.sidebarVisible, false, "a hidden sidebar survives the round trip")
        try expectEqual(back, settings, "the whole payload round-trips")
        // The frame is encoded as four plain numbers.
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let frame = obj["windowFrame"] as? [String: Any] else {
            throw CaseFailure(message: "windowFrame must encode as an object", location: "SettingsCases")
        }
        try expectEqual(frame["x"] as? Double, -120, "x is a plain Double")
        try expectEqual(frame["width"] as? Double, 900, "width is a plain Double")
    },

    EngineCase("settings-window-frame-malformed-decode-is-nil") {
        let encoder = JSONEncoder()
        let full = try encoder.encode(AppSettings.defaults)
        func decode(_ windowFrame: Any) throws -> AppSettings {
            guard var obj = try JSONSerialization.jsonObject(with: full) as? [String: Any] else {
                throw CaseFailure(message: "settings must encode to an object", location: "SettingsCases")
            }
            obj["windowFrame"] = windowFrame
            let data = try JSONSerialization.data(withJSONObject: obj)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        }
        // Wrong type entirely: the store still decodes.
        let wrongType = try decode("not a frame")
        try expect(wrongType.windowFrame == nil, "a wrong JSON type falls back to nil")
        let wrongShape = try decode([1, 2, 3])
        try expect(wrongShape.windowFrame == nil, "a wrong shape falls back to nil")
        // A well-formed object with an unusable size.
        for bad: [String: Double] in [
            ["x": 100, "y": 100, "width": 0, "height": 600],
            ["x": 100, "y": 100, "width": 800, "height": 0],
            ["x": 100, "y": 100, "width": -10, "height": 600],
            ["x": 100, "y": 100, "width": 800, "height": -10],
        ] {
            let decoded = try decode(bad)
            try expect(decoded.windowFrame == nil,
                       "a zero/negative size decodes to nil: \(bad)")
        }
        // Non-finite numbers cannot be expressed in JSON, so they are
        // covered by the pure `hasUsableSize` rule; a MISSING component
        // must not fail the store either.
        let partial = try decode(["x": 100.0, "y": 100.0])
        try expect(partial.windowFrame == nil, "a partial object falls back to nil")
        // And the rest of the settings is never lost.
        let survivor = try decode("not a frame")
        try expectEqual(survivor.decimalPlaces, AppSettings.defaults.decimalPlaces,
                        "the rest of the store survives a malformed frame")
        try expectEqual(survivor.sidebarVisible, true, "the sidebar default still applies")
    },

    EngineCase("settings-sidebar-visible-malformed-falls-back") {
        let encoder = JSONEncoder()
        let full = try encoder.encode(AppSettings.defaults)
        func decode(_ value: Any) throws -> AppSettings {
            guard var obj = try JSONSerialization.jsonObject(with: full) as? [String: Any] else {
                throw CaseFailure(message: "settings must encode to an object", location: "SettingsCases")
            }
            obj["sidebarVisible"] = value
            let data = try JSONSerialization.data(withJSONObject: obj)
            return try JSONDecoder().decode(AppSettings.self, from: data)
        }
        let wrongType = try decode("yes")
        try expectEqual(wrongType.sidebarVisible, true,
                        "a wrong JSON type falls back to the expanded sidebar")
        let number = try decode(1)
        try expectEqual(number.sidebarVisible, true,
                        "a number falls back to the expanded sidebar")
        let off = try decode(false)
        try expectEqual(off.sidebarVisible, false, "a real false is preserved")
        let on = try decode(true)
        try expectEqual(on.sidebarVisible, true, "a real true is preserved")
    },
]
