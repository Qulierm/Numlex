import Foundation
import NumlexCore

/// r90: the redesigned Settings window — native split navigation with a
/// category sidebar and ONE focused detail page per destination.
///
/// The app target is not importable from the test kit, so the layout,
/// ownership and identity contracts are pinned at the source, exactly
/// like the other app-layer invariants.
public let settingsNavigationCases: [EngineCase] = [

    EngineCase("settings-nav-split-not-tabs") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        try expect(text.contains("NavigationSplitView"), "native split navigation")
        try expect(text.contains("List(selection: $destination)"), "one selectable sidebar list")
        try expect(!text.contains("TabView"), "no root TabView")
        try expect(!text.contains(".tabItem"), "no tabItem strip")
        try expect(!text.contains("NSTabView"), "no AppKit tab view")
        try expect(text.contains(".listStyle(.sidebar)"), "native sidebar list style")
        try expect(text.contains(".toolbar(removing: .sidebarToggle)"),
                   "no competing sidebar toggle in the window toolbar")
        // Exactly one detail destination is rendered at a time.
        try expect(text.contains("@ViewBuilder\n    private var detail: some View"),
                   "one detail builder")
        let switches = text.components(separatedBy: "case .general: GeneralSettingsPage").count
        try expectEqual(switches, 2, "general is the first detail branch")
    },

    EngineCase("settings-nav-seven-destinations-in-order") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        let order = ["general", "appearance", "editing", "numbers",
                     "constantsUnits", "styling", "updates"]
        var last = -1
        for name in order {
            guard let r = text.range(of: "case \(name)\n") else {
                throw CaseFailure(message: "missing destination case \(name)",
                                  location: "SettingsNav")
            }
            let idx = text.distance(from: text.startIndex, to: r.lowerBound)
            try expect(idx > last, "\(name) appears in sidebar order")
            last = idx
        }
        try expectEqual(text.components(separatedBy: "enum SettingsDestination").count - 1, 1,
                        "one destination enum")
        try expect(text.contains("String, CaseIterable, Hashable, Identifiable"),
                   "stable Hashable/CaseIterable destinations")
        try expect(text.contains("@State private var destination: SettingsDestination = .general"),
                   "session-local state defaulting to General")
        // Navigation state must never reach the persisted settings.
        try expect(!text.contains("settings.settingsDestination"),
                   "no persisted destination key")
    },

    EngineCase("settings-nav-symbols-and-labels") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        for symbol in ["gearshape", "circle.lefthalf.filled", "pencil.tip",
                       "number", "function", "paintbrush",
                       "arrow.triangle.2.circlepath"] {
            try expect(text.contains("return \"\(symbol)\""),
                       "sidebar uses the SF Symbol \(symbol)")
        }
        try expect(text.contains("Label(L10n.t(item.labelKey, language: language)"),
                   "rows use localized labels")
        try expect(text.contains(".lineLimit(1)"), "labels stay on one line")
        try expect(!text.contains("Image(\"icon"), "no raster sidebar art")
        // Retained destination labels come from the existing keys.
        for key in ["settings.general", "settings.editing", "settings.numbers",
                    "settings.styling"] {
            try expect(text.contains("\"\(key)\""), "reuses \(key)")
        }
        for key in ["settings.appearance", "settings.updates",
                    "settings.constantsUnitsShort"] {
            try expect(text.contains("\"\(key)\""), "adds \(key)")
        }
    },

    EngineCase("settings-detail-shared-scaffold") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        try expect(text.contains("private struct SettingsDetailPage<Content: View>: View"),
                   "one shared detail scaffold")
        try expect(text.contains("Text(L10n.t(destination.titleKey, language: language))"),
                   "page title comes from the destination")
        try expect(text.contains("Text(L10n.t(destination.subtitleKey, language: language))"),
                   "page subtitle comes from the destination")
        try expect(text.contains("ScrollView"), "detail pages scroll")
        try expect(text.contains("private struct SettingsCardBackground: View"),
                   "one restrained card surface")
        // Prose may NAME the forbidden API while documenting its
        // absence; the check reads code with comments stripped.
        try expect(!settingsNavWithoutComments(text).contains(".glassEffect("),
                   "no Liquid Glass inside Settings rows")
        try expect(!settingsNavWithoutComments(text).contains("NSVisualEffectView"),
                   "no fake material sidebar cards")
        try expect(!settingsNavWithoutComments(text).contains("trafficLight"),
                   "no fake traffic lights")
        try expect(!text.contains("NSTitlebarAccessoryViewController"),
                   "no duplicate fake titlebar")
        // Every page routes through the scaffold exactly once.
        for dest in ["general", "appearance", "updates", "editing",
                     "constantsUnits", "numbers", "styling"] {
            let needle = "SettingsDetailPage(destination: .\(dest), language: language)"
            try expect(text.contains(needle), "\(dest) uses the shared scaffold")
        }
    },

    EngineCase("settings-ownership-no-duplicates") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        // Extract the page bodies so ownership is checked per page.
        func page(_ name: String, until: String) -> String {
            guard let a = text.range(of: "private struct \(name): View {") else { return "" }
            guard let b = text.range(of: "private struct \(until)") else {
                return String(text[a.lowerBound...])
            }
            return String(text[a.lowerBound..<b.lowerBound])
        }
        let general = page("GeneralSettingsPage", until: "AppearanceSettingsPage")
        let appearance = page("AppearanceSettingsPage", until: "UpdatesSettingsPage")
        let updates = page("UpdatesSettingsPage", until: "EditingSettingsPage")
        let numbers = page("NumbersSettingsPage", until: "StylingSettingsPage")

        // General: language + the three notebook switches, nothing else.
        for key in ["language", "linenumber", "hideSidebarBtn", "showTotalBar"] {
            try expect(general.contains("L10n.t(\"\(key)\"") || general.contains("L10n.t(\"\(key)\","),
                       "General owns \(key)")
        }
        let generalCode = settingsNavWithoutComments(general)
        for forbidden in ["model.setAppearance(", "model.setAppIcon(",
                          "updates.checkNow", "currencyRates"] {
            try expect(!generalCode.contains(forbidden), "General must not own \(forbidden)")
        }
        // Appearance: the theme picker and the icon chooser, one write path each.
        try expect(appearance.contains("model.setAppearance($0)"), "appearance write path")
        try expect(appearance.contains("L10n.t(appearanceKey(a)"), "localized theme labels")
        try expect(appearance.contains("model.setAppIcon($0)"), "icon write path")
        try expect(appearance.contains("AppIconPicker("), "icon chooser lives here")
        try expect(appearance.contains("AppAppearance.uiOrder"), "Auto/Light/Dark order kept")
        try expect(appearance.contains("appIconCap"), "Dock/App Switcher scope caption kept")
        try expect(appearance.contains("RoundedRectangle") == false,
                   "the icon chooser is the shared card, not its own art")
        // Updates owns Sparkle only.
        try expect(updates.contains("updates.checkNow"), "Updates owns Check Now")
        try expect(!settingsNavWithoutComments(updates).contains("setAppearance("),
                   "Updates has no appearance control")
        try expect(updates.contains("model.updates"), "Updates uses the controller")
        try expect(!updates.contains("settings.appearance"), "Updates has no theme control")
        // Numbers owns the rate attribution (single occurrence in the file).
        try expect(numbers.contains("currencyRates"), "Numbers owns the rate attribution")
        try expectEqual(text.components(separatedBy: "L10n.t(\"currencyRates\"").count - 1, 1,
                        "the rate attribution appears exactly once")
        // Sparkle's preference stays outside AppSettings.
        try expect(!text.contains("settings.automaticallyChecksForUpdates"),
                   "Sparkle preference is not mirrored into AppSettings")
    },

    EngineCase("settings-sidebar-identity-dynamic") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        try expect(text.contains("private struct SettingsSidebarIdentity: View"),
                   "one bottom identity view")
        try expect(text.contains("AppIconResources.previewImage(for: iconChoice)"),
                   "identity reuses the packaged preview (no new raster)")
        try expect(text.contains("CFBundleShortVersionString"),
                   "version is read from the bundle at runtime")
        try expect(!text.contains("\"4.8.1\""), "no hardcoded release version in layout")
        try expect(text.contains("Divider()"), "identity is separated by a subtle rule")
        try expect(text.contains(".accessibilityElement(children: .combine)"),
                   "identity is one accessibility element")
        try expect(text.contains("frame(width: 36, height: 36)"),
                   "identity icon is a restrained 36 pt")
    },

    EngineCase("settings-navigation-localization-complete") {
        let keys = ["settings.sidebarTitle", "settings.appearance", "settings.updates",
                    "settings.constantsUnits", "settings.constantsUnitsShort",
                    "settings.general.subtitle", "settings.appearance.subtitle",
                    "settings.editing.subtitle", "settings.numbers.subtitle",
                    "settings.constantsUnits.subtitle", "settings.styling.subtitle",
                    "settings.updates.subtitle"]
        for lang in AppLanguage.allCases {
            for key in keys {
                let value = L10n.t(key, language: lang)
                try expect(value != key, "\(lang.rawValue) missing \(key)")
                try expect(!value.isEmpty, "\(lang.rawValue) empty \(key)")
            }
        }
        // The German/French/Russian/Chinese labels must differ from English
        // (natural translations, never an English fallback).
        for lang in [AppLanguage.ru, .de, .fr, .zh] {
            try expect(L10n.t("settings.appearance", language: lang)
                       != L10n.t("settings.appearance", language: .en),
                       "\(lang.rawValue) localizes Appearance")
            try expect(L10n.t("settings.sidebarTitle", language: lang)
                       != L10n.t("settings.sidebarTitle", language: .en),
                       "\(lang.rawValue) localizes the sidebar title")
        }
        // German keeps the established loanword "Updates" on purpose.
        try expectEqual(L10n.t("settings.updates", language: .de), "Updates",
                        "German uses the established loanword")
    },

    EngineCase("settings-window-geometry-single-authority") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        try expect(text.contains("private enum SettingsGeometry"), "one geometry authority")
        try expectEqual(text.components(separatedBy: "private enum SettingsGeometry").count - 1, 1,
                        "exactly one geometry declaration")
        // The configurator uses CONTENT sizes from the same source.
        try expect(text.contains("window.contentMinSize = contentMin"), "content min size")
        try expect(text.contains("window.contentMaxSize = contentMax"), "content max size")
        try expect(text.contains("snapIfOutOfRange"), "stale frames snap once")
        // The split column widths come from the same constants.
        try expect(text.contains("min: SettingsGeometry.sidebarMinWidth"),
                   "sidebar width from the shared source")
        try expect(text.contains("ideal: SettingsGeometry.sidebarIdealWidth"), "sidebar ideal")
        try expect(text.contains("max: SettingsGeometry.sidebarMaxWidth"), "sidebar max")
        let main = settingsNavSource("Sources/NumlexApp/Views/ContentView.swift")
        try expect(!main.contains("SettingsGeometry"),
                   "the main window never reads the settings geometry")
    },

    EngineCase("settings-runtime-contracts-unchanged") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        // The appearance/icon write paths, the constants/units state, the
        // styling preview and the Sparkle isolation survive the redesign.
        try expect(text.contains("model.setAppearance($0)"), "one appearance write path")
        try expect(text.contains("model.setAppIcon($0)"), "one icon write path")
        try expect(text.contains("ConstantsUnitsSettingsPage"), "constants/units page kept")
        try expect(text.contains("StylingPreview"), "styling preview kept")
        try expect(text.contains("model.confirmRegionChange()"), "region confirmation kept")
        try expect(text.contains("presentationBinding"), "presentation bindings kept")
        let localization = settingsNavSource("Sources/NumlexCore/Localization.swift")
        try expect(localization.contains("\"settings.appearance\""), "label key present")
        // The icon assets/provenance are untouched by this redesign.
        let car = try? Data(contentsOf: settingsNavRepoRoot()
            .appendingPathComponent("Assets/AppIcon.compiled/Assets.car"))
        try expect(car != nil, "dual-icon catalog still committed")
    }
]

// MARK: - helpers

private func settingsNavRepoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// A Swift source with comments removed, so layout invariants test CODE
/// rather than prose that documents an absent API.
private func settingsNavWithoutComments(_ text: String) -> String {
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

private func settingsNavSource(_ rel: String) -> String {
    let url = settingsNavRepoRoot().appendingPathComponent(rel).standardizedFileURL
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        return ""
    }
    return text
}
