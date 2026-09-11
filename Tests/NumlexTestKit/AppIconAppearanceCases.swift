import AppKit
import CryptoKit
import Foundation
import NumlexCore

/// The alternate app icon (Dark default / Light alternate) and the third
/// Auto appearance theme: persisted-value contracts, tolerant legacy
/// decoding, vendored-asset integrity (exact hashes, dimensions and
/// pixel correspondence) and the source-level wiring that keeps exactly
/// ONE writer for `NSApp.applicationIconImage` and for
/// `NSApp.appearance`.
public let appIconAppearanceCases: [EngineCase] = [

    // MARK: - Icon choice (persisted contract)

    EngineCase("icon-choice-raw-order-default-roundtrip") {
        try expectEqual(AppIconChoice.allCases, [.dark, .light],
                        "exactly two cases, dark before light")
        try expectEqual(AppIconChoice.allCases.map(\.rawValue), ["dark", "light"],
                        "raw values are the stable lowercase wire values")
        try expectEqual(AppIconChoice.uiOrder, [.dark, .light], "picker order")
        try expectEqual(AppSettings().appIcon, .dark, "default is the bundle primary")
        for c in AppIconChoice.allCases {
            let data = try JSONEncoder().encode(c)
            try expectEqual(try JSONDecoder().decode(AppIconChoice.self, from: data), c,
                            "bare enum roundtrip \(c.rawValue)")
        }
        try expectEqual(AppIconChoice.resolve(nil), .dark, "missing -> dark")
        try expectEqual(AppIconChoice.resolve("neon"), .dark, "unknown -> dark")
        try expectEqual(AppIconChoice.resolve(""), .dark, "empty -> dark")
        try expectEqual(AppIconChoice.resolve("light"), .light, "light parses")
        try expectEqual(AppIconChoice.resolve("LIGHT"), .light, "case-tolerant")
    },

    EngineCase("icon-choice-settings-legacy-fallbacks") {
        // A pre-icon store: no `appIcon` key at all.
        let legacy = """
        {"decimalPlaces":7,"fontSizeKey":"ts","language":"ru","sheetName":"S",
         "lineNumbers":false,"fontColor":"white"}
        """
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        try expectEqual(s.appIcon, .dark, "missing key -> dark")
        try expectEqual(s.decimalPlaces, 7, "sibling keys intact")
        try expectEqual(s.appearance, .light, "appearance fallback unchanged")
        // Unknown raw value (well-formed string).
        let unknown = """
        {"decimalPlaces":10,"fontSizeKey":"tf","language":"en","sheetName":"Sheet",
         "lineNumbers":true,"fontColor":"white","appIcon":"neon"}
        """
        try expectEqual(try JSONDecoder().decode(AppSettings.self, from: Data(unknown.utf8)).appIcon,
                        .dark, "unknown raw -> dark")
        // Wrong JSON type (number) must not fail the store.
        let wrongType = """
        {"decimalPlaces":10,"fontSizeKey":"tf","language":"en","sheetName":"Sheet",
         "lineNumbers":true,"fontColor":"white","appIcon":7}
        """
        let s2 = try JSONDecoder().decode(AppSettings.self, from: Data(wrongType.utf8))
        try expectEqual(s2.appIcon, .dark, "wrong type -> dark")
        try expectEqual(s2.decimalPlaces, 10, "the rest of the store decodes")
    },

    EngineCase("icon-choice-settings-roundtrip-and-siblings") {
        var s = AppSettings.defaults
        s.appIcon = .light
        s.appearance = .dark
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        try expectEqual(back.appIcon, .light, "icon roundtrips")
        try expectEqual(back.appearance, .dark, "sibling appearance intact")
        try expectEqual(back, s, "full settings equality after roundtrip")
        // The new key is additive: StorePayload.version is unchanged and
        // the .nlx (sheet export) carries no app-global settings.
        try expectEqual(StorePayload.currentVersion, 2, "store version unchanged")
        let sheet = Sheet(title: "S", content: "1 + 1")
        let nlx = try JSONEncoder().encode(sheet)
        try expect(String(decoding: nlx, as: UTF8.self).contains("appIcon") == false,
                   ".nlx export never carries app-global settings")
    },

    // MARK: - Appearance (third Auto case)

    EngineCase("appearance-system-raw-order-and-projection") {
        try expectEqual(AppAppearance.allCases, [.system, .light, .dark],
                        "declaration order: system, light, dark")
        try expectEqual(AppAppearance.uiOrder, [.system, .light, .dark], "picker order")
        try expectEqual(AppAppearance.allCases.map(\.rawValue), ["system", "light", "dark"],
                        "stable wire values (light/dark unchanged)")
        for a in AppAppearance.allCases {
            let data = try JSONEncoder().encode(a)
            try expectEqual(try JSONDecoder().decode(AppAppearance.self, from: data), a,
                            "roundtrip \(a.rawValue)")
        }
        // The root override is OPTIONAL: nil for Auto (follow macOS),
        // never a two-way ternary that maps Auto to dark.
        try expectEqual(AppAppearance.system.colorSchemeIsDarkOverride, nil, "Auto -> nil")
        try expectEqual(AppAppearance.light.colorSchemeIsDarkOverride, false, "Light -> false")
        try expectEqual(AppAppearance.dark.colorSchemeIsDarkOverride, true, "Dark -> true")
        // Effective resolution: Auto follows the process, pinned ignores it.
        for systemDark in [false, true] {
            try expectEqual(AppAppearance.system.effectiveIsDark(processIsDark: systemDark),
                            systemDark, "Auto follows the system")
            try expectEqual(AppAppearance.light.effectiveIsDark(processIsDark: systemDark),
                            false, "Light pinned")
            try expectEqual(AppAppearance.dark.effectiveIsDark(processIsDark: systemDark),
                            true, "Dark pinned")
        }
    },

    EngineCase("appearance-legacy-defaults-still-light") {
        // `AppSettings()` and the shared defaults keep Light — the new
        // Auto case is user-selectable, never a silent new default.
        try expectEqual(AppSettings().appearance, .light, "init default stays light")
        try expectEqual(AppSettings.defaults.appearance, .light, "defaults constant stays light")
        let missing = """
        {"decimalPlaces":10,"fontSizeKey":"tf","language":"en","sheetName":"Sheet",
         "lineNumbers":true,"fontColor":"white"}
        """
        try expectEqual(try JSONDecoder().decode(AppSettings.self, from: Data(missing.utf8)).appearance,
                        .light, "missing key -> light")
        let invalid = """
        {"decimalPlaces":10,"fontSizeKey":"tf","language":"en","sheetName":"Sheet",
         "lineNumbers":true,"fontColor":"white","appearance":"neon"}
        """
        try expectEqual(try JSONDecoder().decode(AppSettings.self, from: Data(invalid.utf8)).appearance,
                        .light, "invalid raw -> light")
        // All three roundtrip through the full settings object.
        for a in AppAppearance.allCases {
            var s = AppSettings.defaults
            s.appearance = a
            s.appIcon = (a == .dark) ? .light : .dark
            let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
            try expectEqual(back.appearance, a, "appearance roundtrip \(a.rawValue)")
            try expectEqual(back.appIcon, s.appIcon, "icon sibling intact \(a.rawValue)")
        }
    },

    // MARK: - Localization

    EngineCase("appearance-icon-localization-all-six") {
        let keys = ["appearanceAuto", "appIcon", "appIconCap", "appIconDark", "appIconLight"]
        for lang in AppLanguage.allCases {
            for key in keys {
                let v = L10n.t(key, language: lang)
                try expect(v != key, "\(lang.rawValue) missing \(key)")
                try expect(!v.isEmpty, "\(lang.rawValue) empty \(key)")
            }
        }
        try expectEqual(L10n.t("appearanceAuto", language: .en), "Auto", "English Auto")
        try expectEqual(L10n.t("appearanceAuto", language: .ru), "Авто", "Russian Auto")
        try expectEqual(L10n.t("appearanceAuto", language: .zh), "自动", "Chinese Auto")
    },

    // MARK: - Vendored assets

    EngineCase("icon-assets-hashes-and-dimensions") {
        let root = appIconRepoRoot()
        func url(_ rel: String) -> URL { root.appendingPathComponent(rel).standardizedFileURL }
        let expected: [(String, Int, String)] = [
            ("Sources/NumlexApp/Resources/AppIconLight.icns", 582_175,
             "d6d3c7108b437f4f0e51ad7a8989ad5b59a3e01e1a2e7044a2ac027c54c83e40"),
            ("Sources/NumlexApp/Resources/AppIconDarkPreview.png", 498_113,
             "f2b66202656f9d04372010d251a54668d1a9d153648bb4940465c43e85902932"),
            ("Sources/NumlexApp/Resources/AppIconLightPreview.png", 449_640,
             "4367adca2ded31ca07fe7cfcd7f1be4cab3b1e3a1fe927dc4d1a5855d505cf2e"),
        ]
        for (rel, size, sha) in expected {
            guard let data = try? Data(contentsOf: url(rel)) else {
                throw CaseFailure(message: "missing \(rel)", location: "AppIconCases")
            }
            try expectEqual(data.count, size, "\(rel) size")
            try expectEqual(sha256Hex(data), sha, "\(rel) sha256")
        }
        // Both previews are 512x512 16-bit RGBA PNGs (the supplied tiles).
        for rel in ["Sources/NumlexApp/Resources/AppIconDarkPreview.png",
                    "Sources/NumlexApp/Resources/AppIconLightPreview.png"] {
            let data = try Data(contentsOf: url(rel))
            try expectEqual(String(decoding: data.prefix(8), as: UTF8.self).isEmpty, false,
                            "png signature read")
            let w = pngUInt32(data, at: 16), h = pngUInt32(data, at: 20)
            try expectEqual(w, 512, "\(rel) width")
            try expectEqual(h, 512, "\(rel) height")
            try expectEqual(data[24], 16, "\(rel) bit depth 16")
            try expectEqual(data[25], 6, "\(rel) RGBA color type")
        }
        // The Light preview is the Light ICNS's 512 rendition (same
        // artwork; the container re-encode differs in a few bytes). The
        // Dark preview is the current bundle icon's exact 512 rendition
        // and is byte-identical.
        guard let icns = try? Data(contentsOf: url("Sources/NumlexApp/Resources/AppIconLight.icns")),
              let embedded = icnsPayload(ofType: "ic09", in: icns) else {
            throw CaseFailure(message: "Light ICNS ic09 rendition missing", location: "AppIconCases")
        }
        guard let preview = try? Data(contentsOf: url("Sources/NumlexApp/Resources/AppIconLightPreview.png")),
              let a = bitmap(preview), let b = bitmap(embedded) else {
            throw CaseFailure(message: "Light preview/rendition not decodable", location: "AppIconCases")
        }
        // The Light preview and the ICNS ic09 rendition are the same
        // 512x512 artwork: the container re-encode leaves at most a
        // handful of channel bytes different (measured: 39 of 1,048,576,
        // max delta 144 on the alpha/edge pixels). Assert the rendition
        // identity with that explicit, bounded tolerance rather than
        // claiming byte equality the encoder never promised.
        var differing = 0
        let n = min(a.pixels.count, b.pixels.count)
        for i in 0..<n where a.pixels[i] != b.pixels[i] { differing += 1 }
        try expect(differing <= 64,
                   "Light preview matches the ICNS ic09 rendition (differing bytes: \(differing))")
        try expectEqual(a.width, 512, "ic09 width")
        try expectEqual(a.height, 512, "ic09 height")
        // The CURRENT Dark primary bundle icon is untouched.
        guard let darkIcns = try? Data(contentsOf: url("Sources/NumlexApp/Resources/AppIcon.icns")) else {
            throw CaseFailure(message: "AppIcon.icns missing", location: "AppIconCases")
        }
        guard let darkEmbedded = icnsPayload(ofType: "ic09", in: darkIcns),
              let darkPreview = try? Data(contentsOf: url("Sources/NumlexApp/Resources/AppIconDarkPreview.png")) else {
            throw CaseFailure(message: "Dark ic09/preview missing", location: "AppIconCases")
        }
        try expect(darkEmbedded == darkPreview, "Dark preview is the exact ic09 bytes")
    },

    EngineCase("icon-assets-packaging-wiring") {
        guard let pkg = appIconSource("Package.swift") else {
            throw CaseFailure(message: "Package.swift missing", location: "AppIconCases")
        }
        for res in ["AppIconLight.icns", "AppIconDarkPreview.png", "AppIconLightPreview.png"] {
            try expect(pkg.contains(".copy(\"Resources/\(res)\")"),
                       "Package.swift copies \(res)")
        }
        guard let build = appIconSource("Scripts/build-app.sh") else {
            throw CaseFailure(message: "build-app.sh missing", location: "AppIconCases")
        }
        for sha in ["d6d3c7108b437f4f0e51ad7a8989ad5b59a3e01e1a2e7044a2ac027c54c83e40",
                    "f2b66202656f9d04372010d251a54668d1a9d153648bb4940465c43e85902932",
                    "4367adca2ded31ca07fe7cfcd7f1be4cab3b1e3a1fe927dc4d1a5855d505cf2e"] {
            try expect(build.contains(sha), "build-app.sh pins \(sha.prefix(12))…")
        }
        try expect(build.contains("exit 1"), "build-app.sh fails closed")
        try expect(build.contains("Resources/AppIconLight.icns"), "packages the Light ICNS")
        try expect(build.contains("AppIconLightPreview.png"), "packages the Light preview")
        try expect(build.contains("AppIconDarkPreview.png"), "packages the Dark preview")
        // The Dark primary stays the modern Assets.car + ICNS pair.
        try expect(build.contains("Assets.car"), "Assets.car still packaged")
        try expect(build.contains("Resources/AppIcon.icns"), "AppIcon.icns still packaged")
    },

    // MARK: - Source invariants (one writer per AppKit property)

    EngineCase("icon-controller-source-invariants") {
        guard let icon = appIconSource("Sources/NumlexApp/AppIconController.swift") else {
            throw CaseFailure(message: "AppIconController missing", location: "AppIconCases")
        }
        try expect(icon.contains("app.applicationIconImage = nil"),
                   "dark resets through AppKit's null-resettable contract")
        try expect(icon.contains("AppIconResources.lightIconImage()"),
                   "light uses the packaged alternate ICNS")
        try expect(icon.contains("guard let image = AppIconResources.lightIconImage() else { return false }"),
                   "a missing Light resource fails safe (no generic icon)")
        try expect(icon.contains("captureLaunchIcon"),
                   "the bundle-resolved launch icon is captured for the fallback")
        try expect(!withoutComments(icon).contains("NSWorkspace"),
                   "no Finder/NSWorkspace icon writes")
        // Exactly ONE writer of applicationIconImage in the whole app.
        let writers = appIconAppSources()
            .map { (name: $0.name, text: withoutComments($0.text)) }
            .filter { $0.text.contains(".applicationIconImage = ") }
        for w in writers {
            try expect(w.name == "AppIconController.swift",
                       "applicationIconImage written only in the controller (found \(w.name))")
        }
        try expect(writers.count == 1, "exactly one writer file")
        // No alternate-icon plist keys or NSWorkspace calls anywhere.
        for src in appIconAppSources() {
            let code = withoutComments(src.text)
            // NSWorkspace itself is legitimate elsewhere (for example
            // `accessibilityDisplayShouldReduceMotion`); the ICON API is not.
            try expect(!code.contains("NSWorkspace.shared.setIcon")
                       && !code.contains("NSWorkspace.shared.icon(forFile:")
                       && !code.contains("setIcon("),
                       "\(src.name) must not write a Finder icon")
            try expect(!code.contains("CFBundleAlternateIcons"),
                       "\(src.name) must not use alternate-icon plists")
        }
    },

    EngineCase("appearance-controller-source-invariants") {
        guard let ctl = appIconSource("Sources/NumlexApp/AppAppearanceController.swift") else {
            throw CaseFailure(message: "AppAppearanceController missing", location: "AppIconCases")
        }
        try expect(ctl.contains("case .system: app.appearance = nil"),
                   "Auto assigns nil (follow macOS)")
        try expect(ctl.contains("case .light: app.appearance = aqua"), "Light pins Aqua")
        try expect(ctl.contains("case .dark: app.appearance = darkAqua"), "Dark pins DarkAqua")
        for src in appIconAppSources() where src.name != "AppAppearanceController.swift" {
            let code = withoutComments(src.text)
            try expect(!code.contains("NSApp.appearance =") && !code.contains("app.appearance ="),
                       "\(src.name) must not write NSApp.appearance")
        }
        guard let root = appIconSource("Sources/NumlexApp/NumlexApp.swift") else {
            throw CaseFailure(message: "NumlexApp.swift missing", location: "AppIconCases")
        }
        try expect(root.contains("colorSchemeIsDarkOverride"),
                   "the root maps the OPTIONAL override")
        try expect(!root.contains("appearance == .light ? .light : .dark"),
                   "no two-way ternary that would map Auto to dark")
        try expect(root.contains("AppIconController.captureLaunchIcon()"),
                   "the launch icon is captured before the choice is applied")
        try expect(root.contains("AppIconController.apply(AppIconController.persistedChoice())"),
                   "the persisted icon applies before the first visible UI")
        let captureIdx = root.range(of: "AppIconController.captureLaunchIcon()")?.lowerBound
        let applyIdx = root.range(of: "AppIconController.apply(AppIconController.persistedChoice())")?.lowerBound
        if let c = captureIdx, let a = applyIdx {
            try expect(root.distance(from: c, to: a) > 0,
                       "capture happens before the first apply")
        }
        guard let model = appIconSource("Sources/NumlexApp/AppModel.swift") else {
            throw CaseFailure(message: "AppModel.swift missing", location: "AppIconCases")
        }
        try expect(model.contains("func setAppIcon(_ choice: AppIconChoice)"),
                   "the model owns the one icon write path")
        try expect(model.contains("settings.appIcon = choice") && model.contains("persist()"),
                   "setAppIcon mutates then persists before applying")
    },

    EngineCase("settings-picker-source-invariants") {
        guard let view = appIconSource("Sources/NumlexApp/Views/SettingsView.swift") else {
            throw CaseFailure(message: "SettingsView missing", location: "AppIconCases")
        }
        try expect(view.contains("AppAppearance.uiOrder"), "three-choice appearance picker")
        try expect(view.contains("AppIconChoice.uiOrder"), "two-tile icon picker")
        try expect(view.contains("model.setAppIcon($0)"), "the picker goes through the model path")
        try expect(view.contains("model.setAppearance($0)"), "appearance goes through the model path")
        try expect(view.contains("AppIconResources.previewImage(for: choice)"),
                   "previews come from the shared loader")
        try expect(view.contains("accessibilityValue"), "tiles expose accessibility state")
        try expect(view.contains(".pickerStyle(.segmented)"), "native segmented appearance picker")
        // Preview tiles are not synthesized from display strings.
        try expect(!view.contains("NSImage(systemSymbolName: \"app\""),
                   "no synthesized icon art")
    },

    EngineCase("textkit-effective-appearance-wiring") {
        guard let editor = appIconSource("Sources/NumlexApp/Editor/NotebookEditor.swift") else {
            throw CaseFailure(message: "NotebookEditor missing", location: "AppIconCases")
        }
        try expect(editor.contains("var effectiveDark: Bool"),
                   "the editor takes the EFFECTIVE scheme")
        try expect(editor.contains("effectiveDark != self.effectiveDark"),
                   "an effective-scheme change triggers the repaint")
        try expect(editor.contains("refreshAppearance()"), "the existing color-only path is used")
        // refreshAppearance must stay color-only: no content/selection writes.
        guard let refresh = editor.range(of: "private func refreshAppearance() {") else {
            throw CaseFailure(message: "refreshAppearance missing", location: "AppIconCases")
        }
        let tail = String(editor[refresh.lowerBound...].prefix(700))
        for forbidden in ["textStorage.setAttributedString", "selectedRange =",
                          "string =", "scroll(", "scrollTo", "lineHeight ="] {
            try expect(!tail.contains(forbidden),
                       "refreshAppearance must not touch \(forbidden)")
        }
        guard let content = appIconSource("Sources/NumlexApp/Views/ContentView.swift") else {
            throw CaseFailure(message: "ContentView missing", location: "AppIconCases")
        }
        try expect(content.contains("@Environment(\\.colorScheme)"),
                   "ContentView reads the effective scheme from the environment")
        try expect(content.contains("effectiveDark: colorScheme == .dark"),
                   "and passes it to the editor")
    }
]

// MARK: - helpers

private func appIconRepoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // NumlexTestKit
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // repo root
}

private func appIconSource(_ rel: String) -> String? {
    let url = appIconRepoRoot().appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}

/// Every Swift source of the app target (for one-writer invariants).
private func appIconAppSources() -> [(name: String, text: String)] {
    let fm = FileManager.default
    let dir = appIconRepoRoot().appendingPathComponent("Sources/NumlexApp")
    guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
    var out: [(String, String)] = []
    for case let url as URL in e where url.pathExtension == "swift" {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            out.append((url.lastPathComponent, text))
        }
    }
    return out.sorted { $0.0 < $1.0 }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func pngUInt32(_ data: Data, at offset: Int) -> Int {
    guard data.count >= offset + 4 else { return -1 }
    return (Int(data[offset]) << 24) | (Int(data[offset + 1]) << 16)
        | (Int(data[offset + 2]) << 8) | Int(data[offset + 3])
}

/// The payload bytes of one ICNS entry (`ic09` = the 512×512 rendition).
private func icnsPayload(ofType type: String, in data: Data) -> Data? {
    guard data.count > 8 else { return nil }
    let total = (Int(data[4]) << 24) | (Int(data[5]) << 16) | (Int(data[6]) << 8) | Int(data[7])
    var off = 8
    while off + 8 <= min(total, data.count) {
        let t = String(bytes: data[off..<off + 4], encoding: .ascii) ?? ""
        let length = (Int(data[off + 4]) << 24) | (Int(data[off + 5]) << 16)
            | (Int(data[off + 6]) << 8) | Int(data[off + 7])
        guard length > 8, off + length <= data.count else { return nil }
        if t == type { return data.subdata(in: (off + 8)..<(off + length)) }
        off += length
    }
    return nil
}

/// Decoded 8-bit RGBA pixels of an image (CoreGraphics normalisation:
/// both sides are drawn into the same RGBA8 space, so 16-bit source
/// depths and different PNG encoders cannot produce false mismatches).
private func bitmap(_ data: Data) -> (width: Int, height: Int, pixels: Data)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let w = image.width, h = image.height
    var out = Data(count: w * h * 4)
    let ok = out.withUnsafeMutableBytes { raw -> Bool in
        guard let base = raw.baseAddress,
              let ctx = CGContext(data: base, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
    }
    return ok ? (w, h, out) : nil
}

/// A Swift source with `//` and `/* */` comments removed, so source
/// invariants test CODE, not prose that legitimately names a forbidden
/// API while documenting its absence.
private func withoutComments(_ text: String) -> String {
    var out = ""
    var i = text.startIndex
    var inLine = false, inBlock = false
    var prev: Character = " "
    while i < text.endIndex {
        let c = text[i]
        let next = text.index(after: i)
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if prev == "*" && c == "/" { inBlock = false; out.removeLast() }
        } else if prev == "/" && c == "/" {
            inLine = true; out.removeLast()
        } else if prev == "/" && c == "*" {
            inBlock = true; out.removeLast()
        } else {
            out.append(c)
        }
        prev = c
        i = next
    }
    return out
}
