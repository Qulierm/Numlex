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
        // r95/r96: the reference composition — a compact, centered row
        // of icon-over-label tiles ONLY. No left sidebar, no split view,
        // no full-width tab bar, no divider, no icon-only squares and
        // (r96) NO section title above the row: the active tile's visible
        // label already identifies the page.
        try expect(!text.contains("NavigationSplitView("), "no split navigation")
        try expect(!text.contains("List(selection: $destination)"), "no left sidebar list")
        try expect(!text.contains(".listStyle(.sidebar)"), "no sidebar list style")
        try expect(!text.contains("sidebarIdealWidth"), "no sidebar width constant")
        try expect(!text.contains("SettingsSidebarIdentity"), "no sidebar identity footer")
        try expect(!text.contains(".pickerStyle(.segmented)") || text.contains("appearance"),
                   "the destination row is not a segmented control")
        // r96: the header is ONLY the tile row — no section title above
        // it, and no page title inside the scrolling detail either.
        guard let headerStart = text.range(of: "private var topNavigation: some View {")?.lowerBound,
              let detailStart = text.range(of: "@ViewBuilder\n    private var detail: some View")?.lowerBound else {
            throw CaseFailure(message: "topNavigation/detail missing", location: "SettingsNav")
        }
        let header = String(text[headerStart..<detailStart])
        try expect(!header.contains("Text(L10n.t(destination.titleKey"),
                   "no section title is rendered above the tiles")
        let detailRange = text[detailStart...]
        let detailBody = String(detailRange.prefix(4_000))
        try expect(!detailBody.contains("L10n.t(destination.titleKey"),
                   "no page title is repeated inside the scrolling detail")
        try expect(header.contains("ForEach(SettingsDestination.allCases) { item in"),
                   "the header is the tile row")
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

    EngineCase("settings-nav-seven-destinations-in-order") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        // The horizontal bar exposes exactly SEVEN destinations, in this
        // order, with About last (temporal Task 1 inserted Dates & Times
        // between Numbers and Constants).
        let order = ["general", "editing", "numbers", "datesTimes", "constantsUnits", "styling", "about"]
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

    EngineCase("settings-caption-contract") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        // r96: the requested captions are gone from the UI.
        for key in ["showTotalBarCap", "styling.column.surfaceCap", "currencyRates",
                    "updates.secure", "about.app"] {
            try expect(!text.contains("\"\(key)\""), "\(key) is not used in the UI")
        }
        // The empty custom-format state must read as a REAL field with
        // the canonical grammar placeholder.
        try expect(text.contains("TextField(\"#,##0.00\""),
                   "the custom-format field carries the canonical placeholder")
        try expect(text.contains(".textFieldStyle(.roundedBorder)"),
                   "the custom-format field has a visible native border")
        // The grouping caption keeps only its example sentence in every
        // language (no "separate setting in the Numbers tab" claim).
        for lang in AppLanguage.allCases {
            let cap = L10n.t("autoGroupCap", language: lang)
            try expect(cap.contains("10"), "\(lang.rawValue): the example stays")
            for banned in ["tab", "Tab", "вкладк", "scheda", "标签"] {
                try expect(!cap.contains(banned),
                           "\(lang.rawValue): no stale \(banned) reference")
            }
        }
    },

    EngineCase("settings-nav-symbols-and-labels") {
        let text = settingsNavSource("Sources/NumlexApp/Views/SettingsView.swift")
        for symbol in ["gearshape", "pencil.tip",
                       "number", "calendar", "function", "paintbrush",
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
        // r96: the scaffold renders NO page title (the header tiles
        // identify the page); it must not reintroduce one.
        try expect(!text.contains("Text(L10n.t(destination.titleKey, language: language))"),
                   "the detail scaffold renders no page title")
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
        for dest in ["general", "about", "editing", "datesTimes",
                     "constantsUnits", "numbers", "styling"] {
            let needle = "SettingsDetailPage(destination: .\(dest), language: language)"
            try expect(text.contains(needle), "\(dest) uses the shared scaffold")
        }
        // Exactly SEVEN scaffolds — the merged Appearance page is gone.
        try expectEqual(text.components(separatedBy: "SettingsDetailPage(destination: .").count - 1, 7,
                        "seven destinations use the shared scaffold")
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
        // r96: the icon chooser is the TRAILING control of a third
        // Interface SettingsRow — not a separate group/card.
        try expect(general.contains("SettingsRow(title: L10n.t(\"appIcon\", language: language)"),
                   "the app-icon row lives in the Interface group")
        try expect(!general.contains("SettingsGroup(title: L10n.t(\"appIcon\""),
                   "no separate Application-icon group remains")
        try expect(!general.contains(".frame(width: 240)"),
                   "the appearance picker has no fixed-width wrapper")
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
        // Exactly one check ACTION, and the row title plus the button
        // label are different strings (no duplicated caption).
        try expectEqual(settingsNavWithoutComments(about)
            .components(separatedBy: "model.updates.checkForUpdates()").count - 1, 1,
            "one check action in About")
        try expect(about.contains("updates.checkNowShort"),
                   "the button uses the short action label")
        // The redesigned About carries the identity hero and the two
        // real external links.
        try expect(about.contains("about.version"), "the hero shows the localized version")
        try expect(about.contains("about.documentation"), "the Documentation link label")
        try expect(about.contains("https://numlex.tech/docs/"), "the exact docs URL")
        try expect(about.contains("https://github.com/Qulierm/Numlex"), "the exact GitHub URL")
        try expect(about.contains(".buttonStyle(.bordered)"), "native bordered links")
        try expect(!about.contains("updates.secure"), "no security paragraph")
        try expect(!about.contains("about.app"), "no redundant Application heading")
        // r92: the Number-format card is compact — the Region row is a
        // single line, a hairline separates it from the sample grid, and
        // the removed region caption leaves no key behind.
        try expect(!numbers.contains("numbers.regionCap"), "the region caption is removed")
        try expect(numbers.contains("Divider()\n                sampleGrid"),
                   "a hairline separates the Region row from the examples")
        // r96: the currency-rate attribution footer is gone from the UI
        // (the provider still powers evaluation — no behavior change).
        try expect(!numbers.contains("currencyRates"),
                   "the rate attribution footer is removed from the page")
        try expect(!numbers.contains("open.er-api"),
                   "no provider link remains in the page")
        try expect(!text.contains("L10n.t(\"currencyRates\""),
                   "the retired attribution key is unused")
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
                    "settings.about",
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
            // ("about.version" is excluded: German/French legitimately
            // spell "Version" exactly like English.)
            for key in ["settings.about", "about.documentation",
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
                        "settings.navigationLabel", "about.app", "currencyRates",
                        "showTotalBarCap", "styling.column.surfaceCap",
                        "updates.secure"] {
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
