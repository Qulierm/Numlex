import Foundation
import NumlexCore

/// r90: the redesigned Settings window — native split navigation with a
/// category sidebar and ONE focused detail page per destination.
///
/// The app target is not importable from the test kit, so the layout,
/// ownership and identity contracts are pinned at the source, exactly
/// like the other app-layer invariants.
public let settingsNavigationCases: [EngineCase] = [

    EngineCase("settings-nav-reference-tiles") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        // r95: the reference composition — the CURRENT page title
        // centered ABOVE a compact, centered row of icon-over-label
        // tiles. No left sidebar, no split view, no full-width tab bar,
        // no divider, no icon-only squares.
        try expect(!text.contains("NavigationSplitView("), "no split navigation")
        try expect(!text.contains("List(selection: $destination)"), "no left sidebar list")
        try expect(!text.contains(".listStyle(.sidebar)"), "no sidebar list style")
        try expect(!text.contains("sidebarIdealWidth"), "no sidebar width constant")
        try expect(!text.contains("SettingsSidebarIdentity"), "no sidebar identity footer")
        try expect(!text.contains(".pickerStyle(.segmented)") || text.contains("appearance"),
                   "the destination row is not a segmented control")
        // Header order: centered title FIRST, then the tile row.
        let header = text[text.range(of: "private var topNavigation: some View {")!.lowerBound...]
        let titleIdx = header.range(of: "Text(L10n.t(destination.titleKey, language: language))")!.lowerBound
        let rowIdx = header.range(of: "ForEach(SettingsDestination.allCases) { item in")!.lowerBound
        try expect(titleIdx < rowIdx, "the centered page title precedes the tile row")
        try expect(header[titleIdx...].hasPrefix("Text(L10n.t(destination.titleKey, language: language))"),
                   "the header title is the full page title key")
        try expect(text.contains(".font(.system(size: 14, weight: .semibold))"),
                   "the header title is the compact 14 pt semibold style")
        // Each tile: icon OVER a visible concise label, one fixed slot.
        try expect(text.contains("VStack(spacing: 3)"), "icon over label inside the tile")
        try expect(text.contains("Image(systemName: item.symbol)"), "the SF Symbol is the tile icon")
        try expect(text.contains("Text(label)"), "the tile shows a VISIBLE localized label")
        try expect(text.contains(".font(.system(size: 11.5, weight: .medium))"),
                   "the tile label is the compact 11.5 pt style")
        try expect(text.contains("let label = L10n.t(item.navigationLabelKey, language: language)"),
                   "the visible label is the concise navigation key")
        try expect(text.contains("height: SettingsGeometry.navigationTileHeight"),
                   "one shared tile height")
        try expect(text.contains("width: SettingsGeometry.navigationTileWidth"),
                   "one shared tile width")
        try expect(text.contains("static let navigationTileWidth: CGFloat = 66"),
                   "the tile slot is 66 pt wide")
        try expect(text.contains("static let navigationTileHeight: CGFloat = 50"),
                   "the tile slot is 50 pt high")
        try expect(text.contains("HStack(spacing: 2)"), "a compact centered tile row")
        try expect(text.contains(".frame(maxWidth: .infinity, alignment: .center)"),
                   "the cluster is centered")
        // Reference selection language: NEUTRAL tile + ACCENT content.
        try expect(text.contains(".foregroundStyle(selected ? Color.accentColor : Color.secondary)"),
                   "the selected icon AND label are accent-colored")
        try expect(text.contains("Color.primary.opacity(0.09)"), "the selected tile is a neutral fill")
        try expect(!settingsNavWithoutComments(text).contains(".fill(Color.accentColor)"),
                   "never a solid accent tile")
        try expect(!settingsNavWithoutComments(text).contains("Color.white"),
                   "never a white selected icon")
        // No bar chrome.
        try expect(!text.contains(".overlay(alignment: .bottom) { Divider() }"),
                   "no full-width divider under the header")
        // Accessibility + keyboard.
        try expect(text.contains("let fullTitle = L10n.t(item.titleKey, language: language)"),
                   "tooltip/accessibility use the FULL page title")
        try expect(text.contains(".help(fullTitle)"), "a localized tooltip on every tile")
        try expect(text.contains(".accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)"),
                   "exactly one tile is announced as selected")
        try expect(text.contains(".accessibilityElement(children: .ignore)"),
                   "the tile is one accessibility element")
        try expect(text.contains(".accessibilityLabel(fullTitle)"), "the tile is named by its full title")
        try expect(text.contains(".onKeyPress(.leftArrow)") && text.contains(".onKeyPress(.rightArrow)"),
                   "arrow keys move the selection")
        try expect(text.contains("private func moveSelection("), "one selection mover")
        try expect(text.contains("@FocusState private var focusedItem"), "the cluster tracks focus")
        try expect(text.contains(".focusEffectDisabled()"), "the platform focus rectangle is suppressed")
        try expect(text.contains("focusedItem != nil && selected"),
                   "the focus cue stays on the selected tile only")
        try expect(text.contains(".onHover") && text.contains("hoveredItem"),
                   "hover is tracked without changing the frame")
        // Session-local selection, default General.
        try expect(text.contains("@State private var destination: SettingsDestination = .general"),
                   "session-local selection defaulting to General")
        try expect(!text.contains("settings.settingsDestination"), "no persisted destination key")
        // Not custom titlebar chrome; one detail builder.
        let code = settingsNavWithoutComments(text)
        try expect(!code.contains("NSTitlebarAccessoryViewController"), "no fake titlebar tabs")
        try expect(!code.contains("trafficLight"), "no fake traffic lights")
        try expect(text.contains("@ViewBuilder\n    private var detail: some View"),
                   "one detail builder")
        let switches = text.components(separatedBy: "case .general: GeneralSettingsPage").count
        try expectEqual(switches, 2, "general is the first detail branch")
    },

    EngineCase("settings-nav-six-destinations-in-order") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        // The horizontal bar exposes exactly SIX destinations, in this
        // order, with About last.
        let order = ["general", "editing", "numbers", "constantsUnits", "styling", "about"]
        var last = -1
        for name in order {
            guard let r = text.range(of: "case \(name)\n") else {
                throw CaseFailure(message: "missing destination case \(name)",
                                  location: "SettingsNav")
            }
            let idx = text.distance(from: text.startIndex, to: r.lowerBound)
            try expect(idx > last, "\(name) appears in navigation order")
            last = idx
        }
        try expect(!text.contains("case appearance"), "no appearance destination")
        try expect(!text.contains("case updates"), "no updates destination")
        try expect(!text.contains("UpdatesSettingsPage"), "no updates page")
        try expect(text.contains("case .about: AboutSettingsPage(model: model)"),
                   "About is the last detail branch")
        try expectEqual(text.components(separatedBy: "enum SettingsDestination").count - 1, 1,
                        "one destination enum")
        try expect(text.contains("String, CaseIterable, Hashable, Identifiable"),
                   "stable Hashable/CaseIterable destinations")
        try expect(text.contains("@State private var destination: SettingsDestination = .general"),
                   "session-local state defaulting to General")
        try expect(!text.contains("settings.settingsDestination"),
                   "no persisted destination key")
    },

    EngineCase("settings-nav-symbols-and-labels") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        for symbol in ["gearshape", "pencil.tip",
                       "number", "function", "paintbrush",
                       "info.circle"] {
            try expect(text.contains("return \"\(symbol)\""),
                       "sidebar uses the SF Symbol \(symbol)")
        }
        // The merged General page still owns the appearance/icon art.
        try expect(text.contains("symbol: \"circle.lefthalf.filled\""),
                   "the appearance row keeps its SF Symbol inside General")
        try expect(text.contains("Image(systemName: item.symbol)"),
                   "navigation items are icon-only SF Symbols")
        try expect(text.contains("item.titleKey"), "the full page title names each item")
        try expect(!text.contains("Image(\"icon"), "no raster navigation art")
        // The full page-title keys are the single naming source (the
        // icon-only bar derives them from the destination raw values).
        try expect(text.contains("var titleKey: String { \"settings.\\(rawValue)\" }"),
                   "every destination derives its full title key")
        // The page titles come from the destination raw values — no
        // separate abbreviated navigation label exists any more.
        try expect(text.contains("settings.aboutShort"),
                   "About keeps a concise VISIBLE tile label")
        try expectEqual(L10n.t("settings.about", language: .ru), "О программе",
                        "the Russian page title is the full name")
        // Icon-only navigation: the FULL page title is the tooltip and
        // the accessibility label, so no abbreviated navigation label
        // exists any more.
        try expectEqual(L10n.t("settings.about", language: .it), "Informazioni",
                        "Italian About title")
        try expectEqual(L10n.t("settings.about", language: .ru), "О программе",
                        "Russian About label")
        try expect(L10n.t("settings.updates", language: .it) == "Aggiornamenti",
                   "the Italian updates group heading is retained")
    },

    EngineCase("settings-detail-shared-scaffold") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        try expect(text.contains("private struct SettingsDetailPage<Content: View>: View"),
                   "one shared detail scaffold")
        try expect(text.contains("Text(L10n.t(destination.titleKey, language: language))"),
                   "page title comes from the destination")
        // r92: no page subtitle at all — the destination model no longer
        // exposes one and the scaffold renders only the title.
        try expect(!text.contains("subtitleKey"), "the destination model has no subtitle key")
        try expect(!text.contains("destination.subtitleKey"), "no subtitle is rendered")
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
        for dest in ["general", "about", "editing",
                     "constantsUnits", "numbers", "styling"] {
            let needle = "SettingsDetailPage(destination: .\(dest), language: language)"
            try expect(text.contains(needle), "\(dest) uses the shared scaffold")
        }
        // Exactly SIX scaffolds — the merged Appearance page is gone.
        try expectEqual(text.components(separatedBy: "SettingsDetailPage(destination: .").count - 1, 6,
                        "six destinations use the shared scaffold")
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
        let general = page("GeneralSettingsPage", until: "AboutSettingsPage")
        let about = page("AboutSettingsPage", until: "EditingSettingsPage")
        let numbers = page("NumbersSettingsPage", until: "StylingSettingsPage")
        // The merged page really is one page: no Appearance struct is left.
        try expect(page("AppearanceSettingsPage", until: "AboutSettingsPage").isEmpty,
                   "no AppearanceSettingsPage remains after the r91 merge")

        // General: language, the Auto/Light/Dark appearance, the icon
        // chooser AND the three notebook switches — the r91 merge, each
        // control exactly once.
        for key in ["language", "linenumber", "hideSidebarBtn", "showTotalBar"] {
            try expect(general.contains("L10n.t(\"\(key)\"") || general.contains("L10n.t(\"\(key)\","),
                       "General owns \(key)")
        }
        try expect(general.contains("model.setAppearance($0)"), "appearance write path")
        try expect(general.contains("L10n.t(appearanceKey(a)"), "localized theme labels")
        try expect(general.contains("AppAppearance.uiOrder"), "Auto/Light/Dark order kept")
        try expect(general.contains("model.setAppIcon($0)"), "icon write path")
        try expect(general.contains("AppIconPicker("), "icon chooser lives in General")
        // r92 caption contract: the obvious icon caption is GONE (the
        // group heading and the tile names carry it), while the
        // consequence captions stay.
        try expect(!general.contains("appIconCap"), "the icon caption is removed")
        try expect(!general.contains("linenumberCap"), "the line-number caption is removed")
        // Exactly once each — the merge must not duplicate a control.
        let generalCode = settingsNavWithoutComments(general)
        try expectEqual(generalCode.components(separatedBy: "model.setAppearance($0)").count - 1, 1,
                        "one appearance write path in General")
        try expectEqual(generalCode.components(separatedBy: "model.setAppIcon($0)").count - 1, 1,
                        "one icon write path in General")
        try expectEqual(generalCode.components(separatedBy: "AppIconPicker(").count - 1, 1,
                        "one icon chooser in General")
        try expectEqual(generalCode.components(separatedBy: "AppAppearance.uiOrder").count - 1, 1,
                        "one appearance picker in General")
        for forbidden in ["updates.checkNow", "currencyRates"] {
            try expect(!generalCode.contains(forbidden), "General must not own \(forbidden)")
        }
        // About owns the app identity AND the Sparkle controls.
        try expect(about.contains("updates.checkNow"), "About owns Check Now")
        try expect(!settingsNavWithoutComments(about).contains("setAppearance("),
                   "About has no appearance control")
        try expect(about.contains("model.updates"), "About uses the controller")
        try expect(about.contains("CFBundleShortVersionString"),
                   "About reads the version at runtime")
        try expect(!about.contains("\"4.8.1\""), "About hardcodes no release version")
        try expect(about.contains("AppIconResources.previewImage(for: model.settings.appIcon)"),
                   "About shows the CURRENT app icon")
        // Exactly one Check-for-Updates affordance (no duplicated title
        // and button on the same page).
        try expectEqual(settingsNavWithoutComments(about)
            .components(separatedBy: "updates.checkNow").count - 1, 1,
            "one Check for Updates string in About")
        // r92: the Number-format card is compact — the Region row is a
        // single line, a hairline separates it from the sample grid, and
        // the removed region caption leaves no key behind.
        try expect(!numbers.contains("numbers.regionCap"), "the region caption is removed")
        try expect(numbers.contains("Divider()\n                sampleGrid"),
                   "a hairline separates the Region row from the examples")
        // Numbers owns the rate attribution (single occurrence in the file).
        try expect(numbers.contains("currencyRates"), "Numbers owns the rate attribution")
        try expectEqual(text.components(separatedBy: "L10n.t(\"currencyRates\"").count - 1, 1,
                        "the rate attribution appears exactly once")
        // Sparkle's preference stays outside AppSettings.
        try expect(!text.contains("settings.automaticallyChecksForUpdates"),
                   "Sparkle preference is not mirrored into AppSettings")
    },

    EngineCase("settings-no-sidebar-footer") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        // r93: there is no sidebar at all, so there is no bottom
        // identity either — the app icon and version live ONLY on the
        // About page and the categories live in the horizontal top bar.
        try expect(!text.contains("SettingsSidebarIdentity"),
                   "no bottom sidebar identity view")
        // The General page still has the MAIN-window "hide sidebar
        // button" preference — that is unrelated to Settings navigation.
        try expect(!text.contains("sidebarIdealWidth")
                   && !text.contains("columnVisibility: .constant(.all)"),
                   "no Settings sidebar column remains")
        try expect(text.contains("CFBundleShortVersionString"),
                   "the version is read from the bundle at runtime")
        try expect(!text.contains("\"4.8.1\""), "no hardcoded release version in layout")
        try expect(!text.contains("SettingsSidebarIdentity("), "the footer is not instantiated")
    },

    EngineCase("settings-navigation-localization-complete") {
        let keys = ["settings.updates",
                    "settings.constantsUnits",
                    "settings.about", "about.app",
                    // The merged General page's own labels.
                    "general.interface", "general.notebook", "appearance", "appIcon"]
        for lang in AppLanguage.allCases {
            for key in keys {
                let value = L10n.t(key, language: lang)
                try expect(value != key, "\(lang.rawValue) missing \(key)")
                try expect(!value.isEmpty, "\(lang.rawValue) empty \(key)")
            }
        }
        // Every non-English label must differ from English (natural
        // translations, never an English fallback). German keeps the
        // established loanword "Updates", so it is excluded there.
        // French shares the English spelling of "Application", so only
        // the other languages are required to differ for that key.
        for lang in [AppLanguage.ru, .de, .it, .zh] {
            for key in ["settings.about", "about.app",
                        "general.notebook"] {
                try expect(L10n.t(key, language: lang) != L10n.t(key, language: .en),
                           "\(lang.rawValue) localizes \(key)")
            }
        }
        // The retired page subtitles and navigation-only labels leave NO
        // dead localization key.
        for lang in AppLanguage.allCases {
            for key in ["settings.general.subtitle", "settings.editing.subtitle",
                        "settings.numbers.subtitle", "settings.updates.subtitle",
                        "settings.navigationLabel"] {
                try expectEqual(L10n.t(key, language: lang), key,
                                "no dead subtitle key \(key)")
            }
            // The removed obvious captions leave no key either.
            for key in ["appIconCap", "numbers.regionCap", "linenumberCap",
                        "styling.column.alignmentCap"] {
                try expectEqual(L10n.t(key, language: lang), key,
                                "no dead caption key \(key)")
            }
        }
        // The Spanish-contaminated Italian settings block stays repaired.
        try expectEqual(L10n.t("settings.about", language: .ru), "О программе",
                        "Russian About page title")
        try expectEqual(L10n.t("settings.updates", language: .it), "Aggiornamenti",
                        "Italian Updates label")
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
        // r94: the page consumes the AVAILABLE width — no fixed content
        // column and no centered frame.
        try expect(!text.contains("detailWidth"), "no fixed detail width remains")
        try expect(text.contains("static let pageHorizontalPadding: CGFloat = 19"),
                   "one page-padding constant")
        try expect(text.contains(".padding(.horizontal, SettingsGeometry.pageHorizontalPadding)"),
                   "the page uses the shared horizontal padding")
        try expect(text.contains(".frame(maxWidth: .infinity, alignment: .topLeading)"),
                   "the page fills the available width")
        try expect(!text.contains("sidebarIdealWidth"), "no sidebar width constant remains")
        try expect(!text.contains("navigationSplitViewColumnWidth"),
                   "no split-view column width remains")
        // r91 geometry: narrower sidebar, SAME right detail width.
        for pin in ["minWidth: CGFloat = 520", "idealWidth: CGFloat = 560",
                    "maxWidth: CGFloat = 640",
                    "minHeight: CGFloat = 500", "idealHeight: CGFloat = 540",
                    "maxHeight: CGFloat = 640",
                    "pageHorizontalPadding: CGFloat = 19"] {
            try expect(text.contains(pin), "r91 geometry keeps \(pin)")
        }
        // The invariant that matters to the user now: the page reaches
        // the window edges with only the shared page padding.
        try expectEqual(560 - 2 * 19, 522,
                        "the ideal page/card width is 522 pt")
        let main = settingsNavSource("Sources/NumlexApp/Views/ContentView.swift")
        try expect(!main.contains("SettingsGeometry"),
                   "the main window never reads the settings geometry")
    },

    EngineCase("settings-compact-chrome") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        // r92: there is no split container, so there is no sidebar-toggle
        // item to remove at all; the EMPTY window toolbar is hidden
        // through public AppKit and the native title is reasserted.
        try expect(!text.contains("NavigationSplitView("), "no split toggle source")
        try expect(text.contains("window.toolbar"), "the window toolbar is addressed")
        try expect(text.contains("toolbar.isVisible = false"),
                   "the empty window toolbar is hidden")
        try expect(text.contains("window.titleVisibility = .visible"),
                   "the native window title stays visible")
        try expect(!settingsNavWithoutComments(text).contains(".toolbarVisibility("),
                   "the declarative form is NOT used (it removed the whole titlebar)")
        try expect(text.contains("private struct SettingsWindowConfigurator"),
                   "the configurator owns the chrome")
        // Chrome invariants: never nil the toolbar, never a fake/framed
        // titlebar, never draw content under the titlebar.
        let code = settingsNavWithoutComments(text)
        try expect(!code.contains("window.toolbar = nil"), "never nils the toolbar")
        try expect(!code.contains("ignoresSafeArea"), "no ignoresSafeArea")
        try expect(!code.contains("NSVisualEffectView"), "no fake titlebar material")
        try expect(!code.contains("trafficLight"), "no fake traffic lights")
        try expect(!code.contains("NSTitlebarAccessoryViewController"),
                   "no titlebar accessory")
        // The MAIN window keeps its sidebar affordances.
        let app = settingsNavSource("Sources/NumlexApp/NumlexApp.swift")
        try expect(app.contains("SidebarCommands()"), "the main window keeps SidebarCommands")
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
        try expect(localization.contains("\"settings.about\""), "the About label key is present")
        try expect(!localization.contains("\"settings.appearance\"\n"),
                   "the retired appearance label key is gone")
        try expect(!localization.contains("\"settings.general.subtitle\""),
                   "the retired page subtitles are gone")
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
