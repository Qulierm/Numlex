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

    EngineCase("appearance-fresh-system-legacy-light") {
        // r97: a FRESH install defaults to Auto (nothing persisted), while
        // the LEGACY missing/malformed key still decodes to Light so
        // existing stores keep their choice; the icon default is Dark.
        try expectEqual(AppSettings().appearance, .system, "fresh init default is Auto")
        try expectEqual(AppSettings.defaults.appearance, .system, "fresh defaults constant is Auto")
        try expectEqual(AppSettings().appIcon, .dark, "fresh icon default is Dark")
        try expectEqual(AppSettings.defaults.appIcon, .dark, "defaults icon constant is Dark")
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
        let keys = ["appearanceAuto", "appIcon", "appIconDark", "appIconLight"]
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

    EngineCase("icon-light-composer-source-geometry") {
        guard let darkJSON = appIconSource("Assets/AppIcon.icon/icon.json"),
              let lightJSON = appIconSource("Assets/AppIconLight.icon/icon.json")
        else { throw CaseFailure(message: "icon packages missing", location: "AppIconCases") }
        let dark = try JSONSerialization.jsonObject(with: Data(darkJSON.utf8)) as? [String: Any]
        let light = try JSONSerialization.jsonObject(with: Data(lightJSON.utf8)) as? [String: Any]
        guard let dark, let light,
              let dGroup = (dark["groups"] as? [[String: Any]])?.first,
              let lGroup = (light["groups"] as? [[String: Any]])?.first,
              let dLayer = (dGroup["layers"] as? [[String: Any]])?.first,
              let lLayer = (lGroup["layers"] as? [[String: Any]])?.first
        else { throw CaseFailure(message: "icon.json shape unexpected", location: "AppIconCases") }
        // Backgrounds differ; the foreground geometry must not.
        try expectEqual(dark["fill"] as? String, "system-dark", "Dark uses system-dark")
        try expectEqual(light["fill"] as? String, "system-light", "Light uses system-light")
        let dPos = dLayer["position"] as? [String: Any]
        let lPos = lLayer["position"] as? [String: Any]
        try expectEqual(dPos?["scale"] as? Double, lPos?["scale"] as? Double, "same scale")
        try expectEqual(dPos?["scale"] as? Double, 1.9, "scale is 1.9")
        let dTr = dPos?["translation-in-points"] as? [Double]
        let lTr = lPos?["translation-in-points"] as? [Double]
        try expectEqual(dTr, lTr, "same translation")
        try expectEqual(lLayer["name"] as? String, dLayer["name"] as? String, "same layer name")
        try expectEqual(lLayer["image-name"] as? String, dLayer["image-name"] as? String,
                        "same mask image name")
        try expectEqual(dGroup["shadow"] as? [String: Any] != nil,
                        lGroup["shadow"] as? [String: Any] != nil, "both carry a shadow")
        try expectEqual(dGroup["translucency"] as? [String: Any] != nil,
                        lGroup["translucency"] as? [String: Any] != nil,
                        "both carry translucency")
        let dFill = dLayer["fill"] as? [String: Any]
        let lFill = lLayer["fill"] as? [String: Any]
        try expectEqual(dFill?["orientation"] != nil, lFill?["orientation"] != nil,
                        "both carry a gradient orientation")
        let dGrad = dFill?["linear-gradient"] as? [String]
        let lGrad = lFill?["linear-gradient"] as? [String]
        try expect(dGrad != lGrad, "Light uses its own (dark) gradient")
        try expectEqual(lGrad?.first, "srgb:0.25114,0.25114,0.25114,1.00000",
                        "Light top stop is the reverse-derived value")
        try expectEqual(lGrad?.last, "srgb:0.00000,0.00000,0.00000,1.00000",
                        "Light bottom stop is the reverse-derived value")
        // The foreground MASK BYTES are shared (identical file hash).
        let maskPath = "Assets/AppIconLight.icon/Assets/Image 32.png"
        guard let data = try? Data(contentsOf: appIconRepoRoot().appendingPathComponent(maskPath)) else {
            throw CaseFailure(message: "Light mask missing", location: "AppIconCases")
        }
        try expectEqual(sha256Hex(data),
                        "b293279246cb9e37396b89878c5d631e6ff8c35a6e7fd95a2622b483d5c0080d",
                        "Light reuses the Dark foreground mask byte-exactly")
    },

    EngineCase("icon-dual-catalog-provenance") {
        // The committed catalog is the CI artifact and carries BOTH named
        // iconstacks with the full modern rendition ladder.
        guard let car = try? Data(contentsOf: appIconRepoRoot()
            .appendingPathComponent("Assets/AppIcon.compiled/Assets.car")) else {
            throw CaseFailure(message: "compiled Assets.car missing", location: "AppIconCases")
        }
        try expectEqual(sha256Hex(car),
                        "be00c077a667c61da549c125efdde6e3d8448bb6bcf7b0f593777d6c6737ed1d",
                        "catalog hash is the verified CI artifact")
        try expectEqual(car.count, 3_407_048, "catalog size matches the artifact")
        guard let inventory = appIconSource("Assets/AppIcon.compiled/Assets.car.assetutil-info.txt"),
              let start = inventory.firstIndex(of: "["),
              let entries = try JSONSerialization.jsonObject(
                with: Data(inventory[start...].utf8)) as? [[String: Any]]
        else { throw CaseFailure(message: "inventory missing/unparsable", location: "AppIconCases") }
        for name in ["AppIcon", "AppIconLight"] {
            let stacks = entries.filter {
                ($0["AssetType"] as? String) == "IconImageStack" && ($0["Name"] as? String) == name
            }
            try expect(stacks.count >= 1, "\(name) IconImageStack present")
            let px = Set(entries.compactMap { e -> Int? in
                guard (e["AssetType"] as? String) == "Icon Image",
                      (e["Name"] as? String) == name else { return nil }
                return e["PixelWidth"] as? Int
            })
            for need in [32, 64, 128, 256, 512, 1024] {
                try expect(px.contains(need), "\(name) rendition \(need)")
            }
        }
        guard let metaJSON = appIconSource("Assets/AppIcon.compiled/icon-build-metadata.json"),
              let meta = try JSONSerialization.jsonObject(with: Data(metaJSON.utf8)) as? [String: Any]
        else { throw CaseFailure(message: "metadata missing", location: "AppIconCases") }
        try expectEqual(meta["app-icon"] as? String, "AppIcon", "primary name")
        try expectEqual(meta["alternate-app-icon"] as? String, "AppIconLight", "alternate name")
        try expectEqual(meta["assets-car-sha256"] as? String, sha256Hex(car), "metadata hash agrees")
        try expectEqual(meta["alternate-source-icon-json-sha256"] as? String,
                        "d6e6fb4d915e26080a53e3be0593c12aab147d21ace68167b4b0d72830a205e5",
                        "alternate source hash recorded")
        try expect((meta["iconstacks"] as? [String])?.contains("AppIconLight") == true,
                   "metadata records both iconstacks")
        guard let plist = appIconSource("Assets/AppIcon.compiled/Assets.car-partial.plist") else {
            throw CaseFailure(message: "partial plist missing", location: "AppIconCases")
        }
        try expect(plist.contains("<string>AppIcon</string>"),
                   "partial plist keeps the primary icon name")
    },

    EngineCase("icon-dual-compile-pipeline-wiring") {
        guard let compiler = appIconSource("Scripts/compile-modern-app-icon.sh") else {
            throw CaseFailure(message: "compiler missing", location: "AppIconCases")
        }
        try expect(compiler.contains("--alternate-app-icon"), "compiler passes the alternate")
        try expect(compiler.contains("AppIconLight.icon"), "compiler knows the Light package")
        try expect(compiler.contains("IconImageStack"), "compiler requires real iconstacks")
        try expect(compiler.contains("rendition"), "compiler checks the rendition ladder")
        try expect(compiler.contains("alternate-source-icon-json-sha256"),
                   "compiler records the alternate source hash")
        guard let workflow = appIconSource(".github/workflows/build-modern-app-icon.yml") else {
            throw CaseFailure(message: "workflow missing", location: "AppIconCases")
        }
        try expect(workflow.contains("Assets/AppIconLight.icon/**"),
                   "workflow triggers on the Light source")
        try expect(workflow.contains("validate-icon-sources.sh"),
                   "workflow runs the source calibration")
        try expect(workflow.contains("ci/light-modern-app-icon"),
                   "workflow supports the focused CI branch")
        guard let validator = appIconSource("Scripts/validate-icon-sources.sh") else {
            throw CaseFailure(message: "validator missing", location: "AppIconCases")
        }
        try expect(validator.contains("compare-icon-renders"), "validator uses the comparator")
        try expect(FileManager.default.fileExists(atPath: appIconRepoRoot()
            .appendingPathComponent("Scripts/compare-icon-renders.swift").path),
                   "CoreGraphics comparator is tracked")
        // build-app.sh must refuse a catalog without the alternate stack.
        guard let build = appIconSource("Scripts/build-app.sh") else {
            throw CaseFailure(message: "build-app.sh missing", location: "AppIconCases")
        }
        try expect(build.contains("AppIconLight") && build.contains("IconImageStack"),
                   "build-app.sh asserts the dual catalog")
    },

    EngineCase("icon-controller-source-invariants") {
        guard let icon = appIconSource("Sources/NumlexApp/AppIconController.swift") else {
            throw CaseFailure(message: "AppIconController missing", location: "AppIconCases")
        }
        try expect(icon.contains("app.applicationIconImage = nil"),
                   "dark resets through AppKit's null-resettable contract")
        // The packaged Light path is the NAMED modern asset first; the ICNS
        // is only a development/failure fallback, normalized in memory.
        try expect(icon.contains("NSImage(named: NSImage.Name(alternateCatalogIconName))"),
                   "Light prefers the named AppIconLight catalog asset")
        try expect(icon.contains("static let alternateCatalogIconName = \"AppIconLight\""),
                   "the alternate catalog name is AppIconLight")
        try expect(icon.contains("lightIconImage(normalizedTo: bundleIconSide)"),
                   "the controller normalizes the Light icon to the bundle size")
        try expect(icon.contains("static func normalized(_ image: NSImage, to side: CGFloat) -> NSImage"),
                   "an in-memory normalization helper exists")
        try expect(!withoutComments(icon).contains("NSWorkspace"),
                   "no Finder icon machinery in the resolution path")
        try expect(icon.contains("static func lightFallbackIcon() -> NSImage?"),
                   "the ICNS stays available as the development fallback")
        try expect(icon.contains("guard let image = AppIconResources.lightIconImage(normalizedTo: bundleIconSide)"),
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

    EngineCase("icon-dark-restore-lifecycle-source") {
        guard let model = appIconSource("Sources/NumlexApp/AppModel.swift") else {
            throw CaseFailure(message: "AppModel missing", location: "AppIconCases")
        }
        guard let icon = appIconSource("Sources/NumlexApp/AppIconController.swift") else {
            throw CaseFailure(message: "AppIconController missing", location: "AppIconCases")
        }
        guard let root = appIconSource("Sources/NumlexApp/NumlexApp.swift") else {
            throw CaseFailure(message: "NumlexApp.swift missing", location: "AppIconCases")
        }
        // THE regression: the model must never apply an icon while it is
        // being constructed. The App struct builds AppModel() before
        // applicationDidFinishLaunching, so an init apply installed the
        // persisted LIGHT icon before the delegate captured, the capture
        // then recorded Light as "the bundle default", and the Dark
        // restore reinstalled it forever.
        let modelCode = withoutComments(model)
        try expectEqual(modelCode.components(separatedBy: "AppIconController").count - 1, 1,
                        "the model touches AppIconController exactly once")
        if let setter = modelCode.range(of: "func setAppIcon(_ choice: AppIconChoice)"),
           let use = modelCode.range(of: "AppIconController"),
           let initStart = modelCode.range(of: "init(") {
            try expect(use.lowerBound > setter.lowerBound,
                       "the model's only icon call is the user-change path")
            try expect(!(initStart.lowerBound..<setter.lowerBound).contains(use.lowerBound),
                       "AppModel.init must not apply an application icon")
        }
        try expect(modelCode.contains("AppAppearanceController.apply(appearance)"),
                   "the appearance re-application stays in the model")
        try expect(model.contains("func setAppIcon(_ choice: AppIconChoice)"),
                   "the user-change path survives")
        // Both iconstacks are separately named and separately resolved.
        try expect(icon.contains("static let primaryCatalogIconName = \"AppIcon\""),
                   "the primary catalog name is AppIcon")
        try expect(icon.contains("static func darkCatalogIcon() -> NSImage?"),
                   "a named Dark resolver exists")
        try expect(icon.contains("NSImage(named: NSImage.Name(primaryCatalogIconName))"),
                   "Dark resolves through the named primary asset")
        try expect(icon.contains("static func lightCatalogIcon() -> NSImage?"),
                   "the Light resolver stays")
        try expect(icon.contains("static let alternateCatalogIconName = \"AppIconLight\""),
                   "the alternate catalog name is AppIconLight")
        // The launch capture prefers the NAMED primary asset, and only
        // then whatever AppKit itself resolved from the bundle — never a
        // previously applied alternate.
        try expect(icon.contains("launchIcon = AppIconResources.darkCatalogIcon() ?? app.applicationIconImage"),
                   "capture prefers the named primary AppIcon")
        // The Dark restore is deterministic and ordered: named primary
        // asset, then the captured primary, then the null reset LAST.
        guard let restore = icon.range(of: "private static func restorePrimaryBundleIcon") else {
            throw CaseFailure(message: "restorePrimaryBundleIcon missing", location: "AppIconCases")
        }
        let body = String(icon[restore.lowerBound...].prefix(1_200))
        guard let named = body.range(of: "AppIconResources.darkCatalogIcon()"),
              let captured = body.range(of: "app.applicationIconImage = launchIcon"),
              let nullReset = body.range(of: "app.applicationIconImage = nil") else {
            throw CaseFailure(message: "Dark restore is missing a fallback stage",
                              location: "AppIconCases")
        }
        try expect(named.lowerBound < captured.lowerBound
                   && captured.lowerBound < nullReset.lowerBound,
                   "Dark restore order: named AppIcon, captured primary, null reset last")
        // The delegate owns the launch lifecycle: capture, then apply.
        let rootCode = withoutComments(root)
        guard let capture = rootCode.range(of: "AppIconController.captureLaunchIcon()"),
              let apply = rootCode.range(of: "AppIconController.apply(AppIconController.persistedChoice())") else {
            throw CaseFailure(message: "delegate icon lifecycle missing", location: "AppIconCases")
        }
        try expect(capture.lowerBound < apply.lowerBound,
                   "the delegate captures the true primary before applying the choice")
    },

    EngineCase("appearance-fresh-vs-legacy-source") {
        guard let ctl = appIconSource("Sources/NumlexApp/AppAppearanceController.swift") else {
            throw CaseFailure(message: "AppAppearanceController missing", location: "AppIconCases")
        }
        // r97: a FRESH install (no readable store) starts in Auto…
        try expect(ctl.contains("Persistence.load()?.settings.appearance ?? .system"),
                   "the no-store launch falls back to Auto")
        // …while the LEGACY missing-key decode stays Light in the model.
        guard let settings = appIconSource("Sources/NumlexCore/Models/Settings.swift") else {
            throw CaseFailure(message: "Settings.swift missing", location: "AppIconCases")
        }
        try expect(settings.contains("forKey: .appearance)) ?? .light"),
                   "a missing/malformed appearance key still decodes Light")
        try expect(settings.contains("appearance: AppAppearance = .system"),
                   "the fresh AppSettings default is Auto")
        try expect(settings.contains("appIcon: AppIconChoice = .dark"),
                   "the fresh AppSettings icon default is Dark")
        // Persistence exactness for the three explicit choices.
        for a in AppAppearance.allCases {
            var s = AppSettings()
            s.appearance = a
            let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
            try expectEqual(back.appearance, a, "explicit \(a.rawValue) roundtrips exactly")
        }
        for icon in AppIconChoice.allCases {
            var s = AppSettings()
            s.appIcon = icon
            let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
            try expectEqual(back.appIcon, icon, "explicit icon \(icon.rawValue) roundtrips exactly")
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
