import AppKit
import SwiftUI
import NumlexCore

/// r34/r75/r90/r91 — the ONE settings-window geometry source (points).
/// Width/height ranges are CONTENT sizes (NSWindow content size — the
/// titlebar is extra, and the configurator applies these through
/// contentMinSize / contentMaxSize, never frame minSize/maxSize).
///
/// r90: the settings window is a native split navigation — a category
/// sidebar plus ONE focused detail page — so the content is compact
/// (min 640x500, ideal 680x540, max 760x640) rather than a giant clone
/// of the reference. Measured on macOS 26: the split view clamps the
/// width at the declared minimum, while its own sidebar chrome asks
/// for the IDEAL height (540 pt) as the practical floor — the declared
/// 500 pt minimum is a lower bound the window never reaches in
/// practice.
///
/// r91: the sidebar is narrower (140/146/150 pt) while the RIGHT detail
/// column keeps its exact width: the total shrinks by the same delta as
/// the sidebar, so the ideal detail stays 680 - 146 = 534 pt, the same
/// figure the 700 - 166 window gave before. Height is untouched.
private enum SettingsGeometry {
    static let minWidth: CGFloat = 520
    static let idealWidth: CGFloat = 560
    static let maxWidth: CGFloat = 640
    static let minHeight: CGFloat = 500
    static let idealHeight: CGFloat = 540
    static let maxHeight: CGFloat = 640

    /// r94/r95: one navigation tile — an equal, near-square slot that
    /// fits the longest localized visible label ("Bearbeiten",
    /// "Konstanten", "Сведения") at the 11 pt label size.
    static let navigationTileWidth: CGFloat = 66
    static let navigationTileHeight: CGFloat = 50

    /// r94: the page padding. The page consumes the AVAILABLE window
    /// width — there is no fixed content column and no centered frame,
    /// so the cards reach the window edges with only this inset instead
    /// of leaving ~95 pt empty fields on both sides.
    static let pageHorizontalPadding: CGFloat = 19
}

/// r90/r91: the SIX settings destinations, in sidebar order. Session-
/// local navigation state only — never persisted into AppSettings/.nlx.
/// r91 merged the former Appearance page into General (its language,
/// appearance and icon controls sit together in one place now).
enum SettingsDestination: String, CaseIterable, Hashable, Identifiable {
    case general
    case editing
    case numbers
    case datesTimes
    case constantsUnits
    case styling
    case about

    var id: String { rawValue }

    /// The FULL localized page title key: the centered header title,
    /// the tooltip and the accessibility label.
    var titleKey: String { "settings.\(rawValue)" }

    /// The CONCISE localized label shown UNDER the tile icon. It equals
    /// the page title wherever that already fits the tile; Dates,
    /// Constants, Styling and About carry dedicated short keys because
    /// the full titles ("Dates & Times", Russian "Оформление", Italian
    /// "Informazioni") are too wide for a compact tile.
    var navigationLabelKey: String {
        switch self {
        case .datesTimes: return "settings.datesTimesShort"
        case .constantsUnits: return "settings.constantsUnitsShort"
        case .styling: return "settings.stylingShort"
        case .about: return "settings.aboutShort"
        default: return titleKey
        }
    }

    /// SF Symbols only — restrained, hierarchical, never branded art.
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .editing: return "pencil.tip"
        case .numbers: return "number"
        case .datesTimes: return "calendar"
        case .constantsUnits: return "function"
        case .styling: return "paintbrush"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    /// Session-local navigation state (never persisted into the store).
    @State private var destination: SettingsDestination = .general
    /// Keyboard focus inside the icon cluster (per-button focus, the
    /// arrow keys move the selection; never persisted).
    @FocusState private var focusedItem: SettingsDestination?
    /// Hover highlight (a wash only — never a frame change).
    @State private var hoveredItem: SettingsDestination?

    private var language: AppLanguage { model.settings.language }

    var body: some View {
        // r93: HORIZONTAL TOP NAVIGATION. The Settings categories are a
        // compact bar directly below the native titlebar and the
        // selected page fills everything below it — there is no left
        // sidebar (and no split-view container, so nothing can be
        // collapsed and no sidebar-toggle exists). The navigation stays
        // fixed while the detail page scrolls vertically.
        VStack(spacing: 0) {
            topNavigation
            Divider()
            detail
        }
        .frame(minWidth: SettingsGeometry.minWidth,
               idealWidth: SettingsGeometry.idealWidth,
               maxWidth: SettingsGeometry.maxWidth,
               minHeight: SettingsGeometry.minHeight,
               idealHeight: SettingsGeometry.idealHeight,
               maxHeight: SettingsGeometry.maxHeight)
        // The Settings scene must not grow the (empty) window toolbar:
        // the compact native titlebar is all the chrome this window
        // needs. The declarative `.toolbarVisibility(.hidden, for:
        // .windowToolbar)` was prototyped and rejected: on this Settings
        // scene it removes the WHOLE titlebar (no traffic lights, no
        // window title, no drag region). The configurator therefore
        // hides the empty NSToolbar through public AppKit and reasserts
        // the visible window title — native chrome intact.
        // Window chrome the scene APIs cannot express: resizability and
        // the designed CONTENT size range (the SwiftUI frame above
        // drives the content bounds; the configurator mirrors them on
        // the NSWindow from the SAME SettingsGeometry source).
        .background(SettingsWindowConfigurator())
    }

    /// The header: ONLY the centered, compact row of icon-over-label
    /// tiles. The active tile's visible label (plus its tooltip and
    /// accessibility name) identifies the page, so no separate section
    /// title is shown above it and none is repeated in the scrolling
    /// detail. There is no full-width tab bar, divider or bar material.
    private var topNavigation: some View {
        HStack(spacing: 2) {
            ForEach(SettingsDestination.allCases) { item in
                topNavigationItem(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 9)
        .padding(.bottom, 9)
    }

    /// One tile: the SF Symbol above its visible concise localized
    /// label, in an EQUAL fixed slot so the row never reflows or
    /// rescales. The selected tile carries a calm neutral rounded
    /// rectangle (never a solid accent fill) while its icon AND label
    /// turn accent-colored; unselected tiles stay transparent with
    /// muted content, and hover is a weaker neutral wash.
    private func topNavigationItem(_ item: SettingsDestination) -> some View {
        let label = L10n.t(item.navigationLabelKey, language: language)
        let fullTitle = L10n.t(item.titleKey, language: language)
        let selected = destination == item
        let hovered = hoveredItem == item
        return Button {
            destination = item
        } label: {
            VStack(spacing: 3) {
                Image(systemName: item.symbol)
                    .font(.system(size: 21, weight: .regular))
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(width: SettingsGeometry.navigationTileWidth,
                   height: SettingsGeometry.navigationTileHeight)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.09)
                      : (hovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(selected ? Color.primary.opacity(0.12)
                              : Color.clear,
                              lineWidth: 0.8)
                .allowsHitTesting(false)
        )
        .overlay(
            // The focus cue stays TILE-local: an accent stroke on the
            // selected tile only (never a full-bar rectangle, never a
            // solid blue tile).
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focusedItem != nil && selected
                              ? Color.accentColor : Color.clear,
                              lineWidth: 2)
                .allowsHitTesting(false)
        )
        .onHover { inside in
            if inside { hoveredItem = item }
            else if hoveredItem == item { hoveredItem = nil }
        }
        .help(fullTitle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullTitle)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .focused($focusedItem, equals: item)
        .focusable()
        // The platform's own focus rectangle is suppressed: the cue
        // above is tile-local and follows the SELECTION.
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { moveSelection(-1); return .handled }
        .onKeyPress(.rightArrow) { moveSelection(1); return .handled }
    }

    /// Arrow-key navigation across the fixed category order (wrapping).
    private func moveSelection(_ delta: Int) {
        let all = SettingsDestination.allCases
        guard let index = all.firstIndex(of: destination) else { return }
        let next = (index + delta + all.count) % all.count
        destination = all[next]
        focusedItem = all[next]
    }

    @ViewBuilder
    private var detail: some View {
        switch destination {
        case .general: GeneralSettingsPage(model: model)
        case .editing: EditingSettingsPage(model: model)
        case .numbers: NumbersSettingsPage(model: model)
        case .datesTimes: DatesTimesSettingsPage(model: model)
        case .constantsUnits: ConstantsUnitsSettingsPage(model: model)
        case .styling: StylingSettingsPage(model: model)
        case .about: AboutSettingsPage(model: model)
        }
    }
}

// MARK: - Shared components (r74 page layout, r76 groups and switches)

/// r90: the shared detail-page scaffold — one top-aligned scroll view
/// with the category title, a concise subtitle and then the content
/// cards. Every destination uses it, so the whole Settings window
/// shares one hierarchy; a page that overflows the window scrolls
/// instead of resizing it, and each page starts at its own top.
private struct SettingsDetailPage<Content: View>: View {
    let destination: SettingsDestination
    let language: AppLanguage
    let content: Content

    init(destination: SettingsDestination, language: AppLanguage,
         @ViewBuilder content: () -> Content) {
        self.destination = destination
        self.language = language
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // r95: the page title lives in the fixed header ABOVE the
                // navigation tiles (centered), so the scroll content
                // starts directly with the first group heading.
                content
            }
            .padding(.horizontal, SettingsGeometry.pageHorizontalPadding)
            .padding(.top, 11)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// The one restrained card surface: a low-tint rounded rectangle, theme
/// aware, never per-row glass and never a competing material.
private struct SettingsCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color.primary.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

/// r76: one logical GROUP of rows. An optional 13 pt semibold heading
/// sits ABOVE a restrained, theme-aware rounded surface (5 % primary
/// tint — light and dark aware, never per-row glassEffect and never
/// one card per toggle). Groups are the section boundaries that keep
/// each tab from reading as a mishmash of loose rows.
private struct SettingsGroup<Content: View>: View {
    let title: String?
    let surface: Bool
    let content: Content

    init(title: String? = nil, surface: Bool = true,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.surface = surface
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            if surface {
                // ONE card per logical group with the related rows
                // stacked inside and a hairline between them — the
                // reference density, never one card per toggle.
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsCardBackground())
            } else {
                content
            }
        }
    }
}

/// r76: one settings row — 13 pt label on the left with its optional
/// 11 pt secondary description underneath (wrapped, never clipped),
/// aligned to the LABEL text, and the native control trailing. The
/// row is vertically centered so a wrapped description keeps the
/// control (switch/menus) visually balanced against the label block.
private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    let symbol: String?
    let divider: Bool
    let control: Control

    init(title: String, detail: String? = nil, symbol: String? = nil,
         divider: Bool = false,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.divider = divider
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if divider {
                Divider().padding(.leading, symbol == nil ? 0 : 32)
            }
            row
        }
    }

    private var row: some View {
        HStack(alignment: .center, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .center)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 11)
    }
}

/// r76: the ONE native switch used by every boolean preference.
/// `labelsHidden` removes the visible label (the row already shows
/// the title on the left) while the explicit accessibilityLabel keeps
/// the switch fully named for VoiceOver/focus — the row title is the
/// switch's label, never an anonymous toggle.
private struct SettingsSwitch: View {
    let title: String
    @Binding var isOn: Bool

    init(title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel(title)
    }
}

/// r88: the ONE shared empty state used by the Constants and Units
/// pages when there are no rows: one SF Symbol, a localized title +
/// caption and the prominent native Add action. Vertically compact
/// and balanced — no table shell, no headers, no detached footer.
private struct SettingsEmptyState: View {
    let systemImage: String
    let title: String
    let caption: String
    let actionTitle: String
    let onAction: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
            Button(action: onAction) {
                Label(actionTitle, systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - General page (r91: language, appearance, icon + notebook behaviour)

/// r91: the single "how Numlex presents itself" page. It owns the
/// interface language, the Auto/Light/Dark appearance, the application
/// icon and the notebook behaviour switches — the controls that used to
/// be split across General and Appearance, now with exactly one home
/// each and no duplicated page.
private struct GeneralSettingsPage: View {
    @Bindable var model: AppModel

    private var language: AppLanguage { model.settings.language }

    /// One persisted boolean binding (every control writes through
    /// model.persist(), exactly like before).
    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0; model.persist() }
        )
    }

    /// Preset selection seeds name/rate through the ONE model API.
    private var taxPresetBinding: Binding<String> {
        Binding(
            get: { model.settings.tax.preset },
            set: { model.selectTaxPreset($0) }
        )
    }

    private var taxNameBinding: Binding<String> {
        Binding(
            get: { model.settings.tax.name },
            set: { model.updateTaxName($0) }
        )
    }

    /// The rate field: empty = unconfigured (nil); a valid finite
    /// 0...<100 value persists; invalid text leaves the stored value
    /// untouched (the field snaps back on the next render).
    private var taxRateBinding: Binding<String> {
        Binding(
            get: {
                guard let rate = model.settings.tax.ratePercent else { return "" }
                return formatDisplayValue(rate, decimalPlaces: 4,
                                          context: model.numberContext)
            },
            set: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "%", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { model.updateTaxRate(nil); return }
                var numeric = trimmed
                if model.numberContext.decimalComma {
                    if !model.numberContext.groupingSeparator.isEmpty {
                        numeric = numeric.replacingOccurrences(
                            of: model.numberContext.groupingSeparator, with: "")
                    }
                    numeric = numeric.replacingOccurrences(of: ",", with: ".")
                } else {
                    numeric = numeric.replacingOccurrences(of: ",", with: "")
                }
                guard let value = Double(numeric) else { return }
                model.updateTaxRate(value)
            }
        )
    }

    var body: some View {
        let language = self.language
        return SettingsDetailPage(destination: .general, language: language) {
            SettingsGroup(title: L10n.t("general.interface", language: language)) {
                SettingsRow(title: L10n.t("language", language: language),
                            symbol: "globe") {
                    Picker("", selection: Binding(
                        get: { model.settings.language },
                        set: { model.settings.language = $0; model.persist() }
                    )) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.rawValue.uppercased()).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                // The appearance picker keeps the one write path
                // (model.setAppearance).
                SettingsRow(title: L10n.t("appearance", language: language),
                            symbol: "circle.lefthalf.filled",
                            divider: true) {
                    Picker("", selection: Binding(
                        get: { model.settings.appearance },
                        set: { model.setAppearance($0) }
                    )) {
                        ForEach(AppAppearance.uiOrder, id: \.self) { a in
                            Text(L10n.t(appearanceKey(a), language: language)).tag(a)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    // r96: NO fixed width wrapper — the segmented chrome
                    // sizes to its segments, so its visible right edge
                    // lands on the same trailing edge as the Language
                    // menu instead of floating inside transparent space.
                    .fixedSize()
                }
                // The app-icon chooser lives in the SAME Interface group
                // as the other presentation controls, trailing-aligned
                // like every other row control (the icon write path
                // stays model.setAppIcon).
                SettingsRow(title: L10n.t("appIcon", language: language),
                            symbol: "app",
                            divider: true) {
                    AppIconPicker(
                        selection: model.settings.appIcon,
                        language: language,
                        onSelect: { model.setAppIcon($0) }
                    )
                }
            }

            SettingsGroup(title: L10n.t("tax.group", language: language)) {
                SettingsRow(
                    title: L10n.t("tax.preset", language: language),
                    detail: L10n.t("tax.presetCap", language: language),
                    symbol: "globe.badge.chevron.backward"
                ) {
                    Picker("", selection: taxPresetBinding) {
                        Text(L10n.t("tax.preset.custom", language: language)).tag("")
                        ForEach(TaxPresets.all, id: \.region) { preset in
                            // A manual-entry preset (US) has NO automatic
                            // rate and renders without a percentage.
                            Text(preset.ratePercent.map {
                                "\(preset.region) — \(preset.name) \(formatDisplayValue($0, decimalPlaces: 4, context: model.numberContext))%"
                            } ?? "\(preset.region) — \(preset.name)")
                                .tag(preset.region)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel(L10n.t("tax.preset", language: language))
                }
                SettingsRow(
                    title: L10n.t("tax.name", language: language),
                    detail: L10n.t("tax.nameCap", language: language),
                    symbol: "tag",
                    divider: true
                ) {
                    TextField("", text: taxNameBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13))
                        .frame(width: 150)
                        .accessibilityLabel(L10n.t("tax.name", language: language))
                }
                SettingsRow(
                    title: L10n.t("tax.rate", language: language),
                    detail: L10n.t("tax.rateCap", language: language),
                    symbol: "percent",
                    divider: true
                ) {
                    HStack(spacing: 5) {
                        TextField("", text: taxRateBinding)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13))
                            .frame(width: 70)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel(L10n.t("tax.rate", language: language))
                        Text("%")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsGroup(title: L10n.t("general.notebook", language: language)) {
                SettingsRow(
                    title: L10n.t("linenumber", language: language),
                    symbol: "list.number"
                ) {
                    SettingsSwitch(title: L10n.t("linenumber", language: language),
                                   isOn: boolBinding(\AppSettings.lineNumbers))
                }
                SettingsRow(
                    title: L10n.t("hideSidebarBtn", language: language),
                    detail: L10n.t("hideSidebarBtnCap", language: language),
                    symbol: "sidebar.left",
                    divider: true,
                ) {
                    SettingsSwitch(title: L10n.t("hideSidebarBtn", language: language),
                                   isOn: boolBinding(\AppSettings.hideSidebarButtonWhenCollapsed))
                }
                SettingsRow(
                    title: L10n.t("showTotalBar", language: language),
                    symbol: "sum",
                    divider: true,
                ) {
                    SettingsSwitch(title: L10n.t("showTotalBar", language: language),
                                   isOn: boolBinding(\AppSettings.showTotalBar))
                }
            }
        }
    }
}

// MARK: - Updates page (Sparkle 2.9.6, its own focused home)

/// r90: the secure-update controls get their own destination. The
/// automatic-check preference stays Sparkle's OWN UserDefaults value
/// (never copied into AppSettings/.nlx); unavailable packaged metadata
/// keeps the plain explanation instead of a crash.
/// r92: About — the app's identity and its update controls in ONE
/// calm page. The identity (current preview icon, name, bundle version)
/// used to live in a bottom sidebar footer; it has exactly one home
/// here now, so the sidebar is just the category list. The Sparkle
/// controls stay exactly as before (their preference is Sparkle-owned,
/// never in AppSettings/.nlx), with no duplicated title/button pair.
@MainActor
private struct AboutSettingsPage: View {
    @Bindable var model: AppModel

    private var language: AppLanguage { model.settings.language }

    /// The bundle version, read at runtime — a development fallback
    /// only, never a hardcoded release fact.
    static var bundleVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "dev"
    }

    /// The identity hero: the CURRENT app icon (which follows the chosen
    /// Dark/Light icon live), the app name and the localized runtime
    /// version — one centered block, no redundant section heading.
    private var identityHero: some View {
        VStack(spacing: 8) {
            if let image = AppIconResources.previewImage(for: model.settings.appIcon) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 64, height: 64)
            }
            Text("Numlex")
                .font(.system(size: 17, weight: .semibold))
            Text(String(format: L10n.t("about.version", language: language),
                        Self.bundleVersion))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Numlex \(String(format: L10n.t("about.version", language: language), Self.bundleVersion))"))
    }

    /// The two real external links. Native bordered buttons, localized
    /// visible labels, full accessibility labels, SF Symbols only (no
    /// bundled brand art) and no networking on page load.
    private var links: some View {
        HStack(spacing: 10) {
            Link(destination: URL(string: "https://numlex.tech/docs/")!) {
                Label(L10n.t("about.documentation", language: language),
                      systemImage: "book.closed")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text(L10n.t("about.documentation", language: language)))

            Link(destination: URL(string: "https://github.com/Qulierm/Numlex")!) {
                Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("GitHub"))
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    var body: some View {
        let language = self.language
        return SettingsDetailPage(destination: .about, language: language) {
            // One surface card carrying the identity hero and the links.
            SettingsGroup(title: nil) {
                identityHero
                Divider()
                links
            }

            // Updates stay a compact, aligned group: ONE check action and
            // ONE automatic-check toggle (no generic security prose).
            SettingsGroup(title: L10n.t("settings.updates", language: language)) {
                if model.updates.isAvailable {
                    SettingsRow(title: L10n.t("updates.checkNow", language: language),
                                symbol: "arrow.triangle.2.circlepath") {
                        Button(L10n.t("updates.checkNowShort", language: language)) {
                            model.updates.checkForUpdates()
                        }
                        .disabled(!model.updates.canCheckForUpdates)
                    }
                    SettingsRow(title: L10n.t("updates.auto", language: language),
                                symbol: "clock.arrow.circlepath",
                                divider: true) {
                        SettingsSwitch(
                            title: L10n.t("updates.auto", language: language),
                            isOn: Binding(
                                get: { model.updates.automaticallyChecksForUpdates },
                                set: { model.updates.setAutomaticallyChecksForUpdates($0) }
                            )
                        )
                    }
                } else {
                    Text(L10n.t("updates.unavailable", language: language))
                        .font(.system(size: 12))
                    Text(L10n.t(model.updates.unavailableReason?.l10nKey
                                ?? "updates.unavailable",
                                language: language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            }
        }
    }
}

// MARK: - Editing tab (r76: operator helpers + automatic input insertions)

/// r76: the Editing tab owns EVERYTHING that rewrites what the user
/// TYPES — the operator helpers and the automatic input insertions.
/// It is deliberately separate from Numbers: input grouping
/// (this tab) shapes the text as it is typed; answer grouping and
/// rounding (Numbers tab) shape what the app DISPLAYS.
private struct EditingSettingsPage: View {
    @Bindable var model: AppModel

    private var language: AppLanguage { model.settings.language }

    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0; model.persist() }
        )
    }
    private func inputBinding(_ keyPath: WritableKeyPath<InputPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings.input[keyPath: keyPath] },
            set: {
                var input = model.settings.input
                input[keyPath: keyPath] = $0
                model.settings.input = input
                model.persist()
            }
        )
    }

    var body: some View {
        let language = self.language
        return SettingsDetailPage(destination: .editing, language: language) {
            SettingsGroup(title: L10n.t("operators", language: language)) {
                SettingsRow(
                    title: L10n.t("opPad", language: language),
                    detail: L10n.t("opPadCap", language: language)
                ) {
                    SettingsSwitch(title: L10n.t("opPad", language: language),
                                   isOn: inputBinding(\.padOperators))
                }
                SettingsRow(
                    title: L10n.t("opStar", language: language),
                    detail: L10n.t("opStarCap", language: language),
                    divider: true,
                ) {
                    SettingsSwitch(title: L10n.t("opStar", language: language),
                                   isOn: inputBinding(\.replaceAsterisk))
                }
                SettingsRow(
                    title: L10n.t("opBacktick", language: language),
                    detail: L10n.t("opBacktickCap", language: language),
                    divider: true,
                ) {
                    SettingsSwitch(title: L10n.t("opBacktick", language: language),
                                   isOn: inputBinding(\.replaceBacktick))
                }
                SettingsRow(
                    title: L10n.t("opQuick", language: language),
                    detail: L10n.t("opQuickCap", language: language),
                    divider: true,
                ) {
                    SettingsSwitch(title: L10n.t("opQuick", language: language),
                                   isOn: inputBinding(\.quickOperators))
                }
            }

            SettingsGroup(title: L10n.t("autoInsert", language: language)) {
                SettingsRow(
                    title: L10n.t("autoGroup", language: language),
                    detail: L10n.t("autoGroupCap", language: language)
                ) {
                    SettingsSwitch(title: L10n.t("autoGroup", language: language),
                                   isOn: inputBinding(\.groupNumbers))
                }
                SettingsRow(
                    title: L10n.t("autoPrev", language: language),
                    detail: L10n.t("autoPrevCap", language: language),
                    divider: true,
                ) {
                    SettingsSwitch(title: L10n.t("autoPrev", language: language),
                                   isOn: inputBinding(\.insertPreviousAnswer))
                }
            }
        }
    }
}

// MARK: - Constants tab (r33, r75 shared page, r76 restrained surface)

/// The r33 Constants tab: a concise localized intro, ONE restrained
/// surface holding a vertically scrollable row table (Name, Value,
/// per-row status, borderless destructive trash) and a bottom toolbar
/// with the Add Constant button and the count/limit. Every row binds
/// by STABLE UUID through the focused AppModel methods; each committed
/// change persists and re-evaluates every sheet live. `.nlx` exports
/// never embed constants — that is stated in the intro, never in the
/// rows.
private struct ConstantsUnitsSettingsPage: View {
    @Bindable var model: AppModel
    /// Focus target for the fresh row's name field (Add and
    /// Enter-in-Value land here for immediate overwrite).
    @FocusState private var focusedName: UUID?
    /// r84: the page's section — the Constants table or the custom
    /// Units table (same scaffold, same row grammar).
    @State private var section = 0

    private var language: AppLanguage { model.settings.language }

    /// One deterministic resolution for the whole tab: the stable status
    /// per row ID (the shared pure resolver, never per-row state).
    private var resolution: [UUID: ConstantResolver.ResolvedRow] {
        Dictionary(uniqueKeysWithValues:
            ConstantResolver.resolve(model.settings.customConstants)
                .rows.map { ($0.id, $0) })
    }

    /// r84: the custom-unit resolution for the Units section (the same
    /// pure resolver the evaluation passes use).
    private var unitResolution: [UUID: UnitResolver.ResolvedRow] {
        Dictionary(uniqueKeysWithValues:
            UnitResolver.resolve(model.settings.customUnits,
                                 constants: model.settings.customConstants)
                .rows.map { ($0.id, $0) })
    }

    var body: some View {
        // r75: the SAME shared 20 pt page scaffold as every other tab;
        // r76: the table surface matches the restrained group surface
        // (no per-card glass in Settings at all).
        SettingsDetailPage(destination: .constantsUnits, language: language) {
            // r84: the page sections (Constants | Units) — the switch
            // sits flush with the page insets like the tab content.
            Picker("", selection: $section) {
                Text(L10n.t("units.tab.constants", language: language)).tag(0)
                Text(L10n.t("units.tab.units", language: language)).tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if section == 0 {
                constantsContent
            } else {
                unitsContent
            }
        }
    }

    // MARK: Constants section (r88: empty state + table)

    /// r88: when there are NO custom constants the page shows ONE
    /// restrained native empty state — an SF Symbol, a localized title
    /// and caption, and the prominent Add Constant action. No column
    /// headers, no divider, no blank table shell, no detached footer.
    /// The first Add creates a real row (and focuses it) and switches
    /// the page to the populated layout; deleting the last row returns
    /// to the empty state.
    @ViewBuilder
    private var constantsContent: some View {
        if model.settings.customConstants.isEmpty {
            SettingsEmptyState(
                systemImage: "function",
                title: L10n.t("constants.emptyTitle", language: language),
                caption: L10n.t("constants.emptyCap", language: language),
                actionTitle: L10n.t("constants.add", language: language),
                onAction: {
                    if let id = model.addConstant() { focusedName = id }
                })
        } else {
            Group {
                Text(L10n.t("constants.intro", language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // The single surface: column captions + the scrollable rows.
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(L10n.t("constants.name", language: language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 132, alignment: .leading)
                        Text(L10n.t("constants.value", language: language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach($model.settings.customConstants) { $row in
                                constantRow($row)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                // Bottom toolbar: Add Constant + count/limit — flush with
                // the page insets (the r75 footer no longer drifts +4 pt).
                HStack(spacing: 10) {
                    Button {
                        if let id = model.addConstant() { focusedName = id }
                    } label: {
                        Label(L10n.t("constants.add", language: language),
                              systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.settings.customConstants.count >= ConstantResolver.maxRows)
                    Spacer()
                    Text("\(model.settings.customConstants.count) / \(ConstantResolver.maxRows)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Units section (r84 table, r88 empty state)

    /// r88: the SAME restrained empty state as Constants — one SF
    /// Symbol, a localized title + caption, the prominent Add Unit
    /// action. No header/divider/blank table shell when there are no
    /// rows; the first Add creates a real focused row and the page
    /// switches to the populated layout.
    @ViewBuilder
    private var unitsContent: some View {
        if model.settings.customUnits.isEmpty {
            SettingsEmptyState(
                systemImage: "ruler",
                title: L10n.t("units.emptyTitle", language: language),
                caption: L10n.t("units.emptyCap", language: language),
                actionTitle: L10n.t("units.add", language: language),
                onAction: {
                    if let id = model.addUnitRow() { focusedName = id }
                })
        } else {
            Group {
                Text(L10n.t("units.intro", language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(L10n.t("units.name", language: language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 132, alignment: .leading)
                        Text(L10n.t("units.definition", language: language))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach($model.settings.customUnits) { $row in
                                unitRow($row)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )

                HStack(spacing: 10) {
                    Button {
                        if let id = model.addUnitRow() { focusedName = id }
                    } label: {
                        Label(L10n.t("units.add", language: language),
                              systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.settings.customUnits.count >= UnitResolver.maxRows)
                    Spacer()
                    Text("\(model.settings.customUnits.count) / \(UnitResolver.maxRows)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// One custom-unit row: Name + Definition fields (the definition
    /// is either `<number> <unit…>` or the literal `new unit`), the
    /// per-row status (a resolved preview for active rows), and the
    /// borderless destructive trash. Enter in Definition adds the next
    /// row when under the limit.
    @ViewBuilder
    private func unitRow(_ row: Binding<UserUnitDefinition>) -> some View {
        HStack(spacing: 8) {
            TextField(L10n.t("units.name", language: language),
                      text: row.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .frame(width: 132)
                .focused($focusedName, equals: row.id)
            TextField(L10n.t("units.definition", language: language),
                      text: row.definition)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit {
                    if model.settings.customUnits.count < UnitResolver.maxRows {
                        if let id = model.addUnitRow(after: row.id) {
                            focusedName = id
                        }
                    }
                }
            if let resolved = unitResolution[row.id] {
                unitStatusView(resolved)
            }
            Button {
                model.deleteUnitRow(id: row.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("units.delete", language: language))
            .accessibilityLabel(L10n.t("units.delete", language: language))
        }
    }

    /// The per-row unit status: a green check plus the RESOLVED preview
    /// for active rows (a linear multiple shows its value in the base
    /// unit of its family; a new dimension shows the `new unit`
    /// marker), a red warning plus the localized reason otherwise.
    @ViewBuilder
    private func unitStatusView(_ resolved: UnitResolver.ResolvedRow) -> some View {
        HStack(spacing: 5) {
            switch resolved.status {
            case .active:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                if let expr = resolved.resolved {
                    Text(unitPreview(expr))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            case .empty:
                EmptyView()
            case .incomplete, .invalidName, .duplicate, .builtInCollision,
                 .constantCollision, .invalidDefinition, .unknownDependency,
                 .cycle, .nonFinite, .exceedsLimit:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text(unitStatusText(resolved.status))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 0)
    }

    private func unitStatusText(_ s: CustomUnitStatus) -> String {
        switch s {
        case .active, .empty: return ""
        case .incomplete: return L10n.t("units.statusIncomplete", language: language)
        case .invalidName: return L10n.t("units.statusInvalidName", language: language)
        case .duplicate: return L10n.t("units.statusDuplicate", language: language)
        case .builtInCollision: return L10n.t("units.statusBuiltIn", language: language)
        case .constantCollision: return L10n.t("units.statusConstant", language: language)
        case .invalidDefinition: return L10n.t("units.statusInvalidDefinition", language: language)
        case .unknownDependency: return L10n.t("units.statusUnknown", language: language)
        case .cycle: return L10n.t("units.statusCycle", language: language)
        case .nonFinite: return L10n.t("units.statusNonFinite", language: language)
        case .exceedsLimit: return L10n.t("units.statusLimit", language: language)
        }
    }

    /// The resolved preview: a new-dimension unit shows the `new unit`
    /// marker; a linear multiple shows `= <value> <base unit>` (the
    /// base label is the catalog unit of the same family+vector with
    /// the smallest scale, so `furlong` previews `= 201.17 m`).
    private func unitPreview(_ expr: UnitExpr) -> String {
        if expr.customAxis != nil {
            return L10n.t("units.newUnit", language: language)
        }
        let base = UnitCatalog.all
            .filter { $0.vector == expr.vector && $0.family == expr.family }
            .min { $0.linearFactor ?? .greatestFiniteMagnitude
                    < $1.linearFactor ?? .greatestFiniteMagnitude }
        let label = base?.label ?? ""
        let value = formatDisplayValue(expr.toBase,
                                       decimalPlaces: model.settings.decimalPlaces,
                                       context: model.numberContext)
        return "= " + value + (label.isEmpty ? "" : " " + label)
    }

    /// One row: Name + Value fields (capped by the model on commit),
    /// the per-row status, and the borderless destructive trash.
    /// Enter in Value adds the next row when under the limit — a plain
    /// field edit never creates rows.
    @ViewBuilder
    private func constantRow(_ row: Binding<UserConstant>) -> some View {
        HStack(spacing: 8) {
            TextField(L10n.t("constants.name", language: language),
                      text: row.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .frame(width: 132)
                .focused($focusedName, equals: row.id)
            TextField(L10n.t("constants.value", language: language),
                      text: row.expression)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .onSubmit {
                    if model.settings.customConstants.count < ConstantResolver.maxRows {
                        if let id = model.addConstant(after: row.id) {
                            focusedName = id
                        }
                    }
                }
            if let resolved = resolution[row.id] {
                statusView(resolved)
            }
            Button {
                model.deleteConstant(id: row.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("constants.delete", language: language))
            .accessibilityLabel(L10n.t("constants.delete", language: language))
        }
    }

    /// The per-row status: a green check plus the RESOLVED preview for
    /// valid rows (scalar display honors the Settings decimal
    /// preference; money through the shared `formatMoney`), a red
    /// warning plus the localized reason otherwise. The source
    /// expression itself is never rewritten.
    @ViewBuilder
    private func statusView(_ resolved: ConstantResolver.ResolvedRow) -> some View {
        HStack(spacing: 5) {
            switch resolved.status {
            case .valid(let qty):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text(preview(qty))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .empty:
                EmptyView()
            case .incomplete, .invalidName, .duplicate, .reserved,
                 .invalidExpression, .invalidDependency, .cycle, .exceedsLimit:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text(statusText(resolved.status))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 0)
    }

    private func statusText(_ s: ConstantResolver.RowStatus) -> String {
        switch s {
        case .empty, .valid: return ""
        case .incomplete: return L10n.t("constants.incomplete", language: language)
        case .invalidName: return L10n.t("constants.invalidName", language: language)
        case .duplicate: return L10n.t("constants.duplicate", language: language)
        case .reserved: return L10n.t("constants.reserved", language: language)
        case .invalidExpression: return L10n.t("constants.invalidExpression", language: language)
        case .invalidDependency: return L10n.t("constants.invalidDependency", language: language)
        case .cycle: return L10n.t("constants.cycle", language: language)
        case .exceedsLimit: return L10n.t("constants.exceedsLimit", language: language)
        }
    }

    /// The resolved preview: scalars respect the Settings decimal
    /// preference for DISPLAY only; money uses the shared presentation.
    private func preview(_ qty: TypedQty) -> String {
        switch qty {
        case .scalar(let v, let kind, let fraction):
            // r83: a constant holding a semantic kind previews with its
            // kinded string (`t = 10% + 20%` previews `30%`).
            if kind != .plain {
                return AnswerDisplay.formatKinded(v, unit: nil, kind: kind, fraction: fraction,
                                                  decimalPlaces: model.settings.decimalPlaces,
                                                  context: model.numberContext)
            }
            return formatDisplayValue(v, decimalPlaces: model.settings.decimalPlaces,
                                      context: model.numberContext)
        case .money(let v, let code):
            return formatMoney(v, code: code, context: model.numberContext)
        case .integer(let v, let r):
            // r85: an exact integer constant previews its base text.
            if r == 10 { return IntLiteral.formatDecimal(v, context: model.numberContext) }
            return IntLiteral.format(v, radix: r)
        case .bool(let b):
            // r82: a boolean constant expression previews as its word.
            return b ? "true" : "false"
        case .quantity(let q):
            // r84: a unit-bearing quantity previews as value + unit label.
            let base = formatDisplayValue(q.value, decimalPlaces: model.settings.decimalPlaces,
                                          context: model.numberContext)
            return q.display.label.isEmpty ? base : base + " " + q.display.label
        }
    }
}

// MARK: - Dates & Times tab (temporal Task 1)

/// The seventh Settings destination: the app-global temporal preferences.
/// Task 1 owns the custom-timezone editor; the work-calendar rows
/// (holiday region, hours per workday) live below it and are added by
/// the work-calendar task through the SAME persisted block. Nothing on
/// this page is sheet metadata: the values never enter `.nlx`, and every
/// edit persists ONCE through the model's mutation API so the observable
/// settings write live-reevaluates the sheets without touching any
/// editor identity, caret or selection.
private struct DatesTimesSettingsPage: View {
    @Bindable var model: AppModel
    @FocusState private var focusedZone: UUID?

    private var language: AppLanguage { model.settings.language }

    private var zones: [CustomTimeZone] { model.settings.temporal.customTimeZones }
    private var states: [CustomTimeZoneState] { CustomTimeZoneEditor.states(zones) }

    var body: some View {
        let language = self.language
        return SettingsDetailPage(destination: .datesTimes, language: language) {
            SettingsGroup(title: L10n.t("datesTimes.work", language: language)) {
                SettingsRow(
                    title: L10n.t("holidayRegion.label", language: language),
                    detail: L10n.t("holidayRegion.cap", language: language)
                ) {
                    Picker("", selection: holidayRegionBinding) {
                        Text(L10n.t("holidayRegion.automatic", language: language))
                            .tag(TemporalPreferences.automaticHolidayRegion)
                        ForEach(holidayRegions, id: \.self) { code in
                            Text(regionLabel(code, language: language)).tag(code)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel(L10n.t("holidayRegion.label", language: language))
                }
                SettingsRow(
                    title: L10n.t("hoursPerWorkday.label", language: language),
                    detail: L10n.t("hoursPerWorkday.cap", language: language),
                    divider: true
                ) {
                    HStack(spacing: 8) {
                        Text(formatDisplayValue(model.settings.temporal.hoursPerWorkday,
                                                decimalPlaces: 2,
                                                context: model.numberContext))
                            .font(.system(size: 13))
                            .frame(minWidth: 28, alignment: .trailing)
                        Stepper("",
                                value: hoursPerWorkdayBinding,
                                in: 1...24,
                                step: 0.5)
                            .labelsHidden()
                            .accessibilityLabel(L10n.t("hoursPerWorkday.label",
                                                       language: language))
                    }
                }
            }
            SettingsGroup(title: L10n.t("timezones.group", language: language)) {
                if zones.isEmpty {
                    SettingsEmptyState(
                        systemImage: "globe",
                        title: L10n.t("timezones.emptyTitle", language: language),
                        caption: L10n.t("timezones.emptyCap", language: language),
                        actionTitle: L10n.t("timezones.add", language: language),
                        onAction: {
                            if let id = model.addCustomTimeZone() { focusedZone = id }
                        })
                } else {
                    Text(L10n.t("timezones.intro", language: language))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text(L10n.t("timezones.name", language: language))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 132, alignment: .leading)
                            Text(L10n.t("timezones.identifier", language: language))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                        Divider()

                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(zones) { zone in
                                    timezoneRow(zone)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )

                    HStack(spacing: 10) {
                        Button {
                            if let id = model.addCustomTimeZone() { focusedZone = id }
                        } label: {
                            Label(L10n.t("timezones.add", language: language),
                                  systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .disabled(zones.count >= TemporalPreferences.maxCustomTimeZones)
                        Spacer()
                        Text("\(zones.count) / \(TemporalPreferences.maxCustomTimeZones)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The bundled holiday regions (sorted ISO codes) plus Automatic.
    private var holidayRegions: [String] {
        HolidayCatalog.shared?.countries ?? []
    }

    private func regionLabel(_ code: String, language: AppLanguage) -> String {
        let localized = Locale(identifier: "en_US").localizedString(forRegionCode: code) ?? code
        return "\(code) — \(localized)"
    }

    /// The holiday-region write path: one settings write, one persist.
    private var holidayRegionBinding: Binding<String> {
        Binding(
            get: { model.settings.temporal.holidayRegion },
            set: { model.settings.temporal.holidayRegion =
                    $0.isEmpty ? TemporalPreferences.automaticHolidayRegion : $0
                   model.persist() }
        )
    }

    /// Hours per workday: clamped to the 1...24 contract on every write.
    private var hoursPerWorkdayBinding: Binding<Double> {
        Binding(
            get: { model.settings.temporal.hoursPerWorkday },
            set: { model.settings.temporal.hoursPerWorkday =
                    TemporalPreferences.clampedHours($0)
                   model.persist() }
        )
    }

    /// One custom-timezone row: the alias, the IANA identifier, the live
    /// validation status and the borderless destructive trash. Enter in
    /// the identifier adds the next row when under the cap (the same
    /// focus handoff the constants/units tables use); every keystroke
    /// persists once through the mutation API so the lane sees it live.
    @ViewBuilder
    private func timezoneRow(_ zone: CustomTimeZone) -> some View {
        let language = self.language
        let state = CustomTimeZoneEditor.state(name: zone.name,
                                               identifier: zone.identifier,
                                               zones: zones, excluding: zone.id)
        HStack(spacing: 8) {
            TextField(L10n.t("timezones.name", language: language),
                      text: nameBinding(zone))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .frame(width: 132)
                .focused($focusedZone, equals: zone.id)
                .accessibilityLabel(L10n.t("timezones.name", language: language))
            TextField(L10n.t("timezones.identifier", language: language),
                      text: identifierBinding(zone))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .accessibilityLabel(L10n.t("timezones.identifier", language: language))
                .onSubmit {
                    if zones.count < TemporalPreferences.maxCustomTimeZones {
                        if let id = model.addCustomTimeZone(after: zone.id) {
                            focusedZone = id
                        }
                    }
                }
            timezoneStatusView(state)
            Button {
                model.deleteCustomTimeZone(id: zone.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(L10n.t("timezones.delete", language: language))
            .accessibilityLabel(L10n.t("timezones.delete", language: language))
        }
    }

    /// The live status: a green check plus the resolved zone for active
    /// rows, a red warning plus the localized reason otherwise; a fresh
    /// both-empty row stays quiet like the other editors.
    @ViewBuilder
    private func timezoneStatusView(_ state: CustomTimeZoneState) -> some View {
        let language = self.language
        HStack(spacing: 5) {
            switch state {
            case .active:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text(L10n.t("timezones.status.active", language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            case .empty:
                EmptyView()
            case .incomplete, .invalidName, .duplicate, .builtInCollision, .unknownZone:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Text(timezoneStatusText(state))
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(timezoneStatusText(state))
    }

    private func timezoneStatusText(_ state: CustomTimeZoneState) -> String {
        let language = self.language
        switch state {
        case .active: return L10n.t("timezones.status.active", language: language)
        case .empty: return ""
        case .incomplete: return L10n.t("timezones.status.incomplete", language: language)
        case .invalidName: return L10n.t("timezones.status.invalidName", language: language)
        case .duplicate: return L10n.t("timezones.status.duplicate", language: language)
        case .builtInCollision: return L10n.t("timezones.status.builtInCollision", language: language)
        case .unknownZone: return L10n.t("timezones.status.unknownZone", language: language)
        }
    }

    /// The name field writes through the ONE mutation API (bounded +
    /// persisted once per edit).
    private func nameBinding(_ zone: CustomTimeZone) -> Binding<String> {
        Binding(
            get: {
                model.settings.temporal.customTimeZones
                    .first(where: { $0.id == zone.id })?.name ?? zone.name
            },
            set: { model.updateCustomTimeZone(id: zone.id, name: $0,
                                              identifier: zone.identifier) }
        )
    }

    private func identifierBinding(_ zone: CustomTimeZone) -> Binding<String> {
        Binding(
            get: {
                model.settings.temporal.customTimeZones
                    .first(where: { $0.id == zone.id })?.identifier ?? zone.identifier
            },
            set: { model.updateCustomTimeZone(id: zone.id, name: zone.name,
                                              identifier: $0) }
        )
    }
}

// MARK: - Numbers tab (r73 content, r76 three logical groups)

/// The r73 Numbers tab re-organized in r76 into three logical groups
/// on the shared r74/r75 single column:
///   1. Number format — the region picker, ONE live example block
///      (caption + function-argument separator) through the app's ONE
///      number context,
///   2. Answer display — rounding (the compact menu picker that moved
///      here from General in r76, its ONLY home), thousands-separator
///      display and compact notation,
///   3. Pasting — the opt-in foreign-number conversion with its
///      example.
/// Changing the region never reinterprets silently: the owner
/// evaluates the selected sheet under both contexts first and only
/// opens the confirmation dialog when an answer actually changes.
private struct NumbersSettingsPage: View {
    @Bindable var model: AppModel

    private var language: AppLanguage { model.settings.language }
    private var systemLocale: Locale { Locale.current }

    /// Live samples rendered through the active context: the shared
    /// display of 1234.567 at the Settings decimals, the compact
    /// preview of 100000 (compact forced on for the preview — it
    /// illustrates what the compact toggle will do, while every value
    /// in the notebook keeps full precision), and the
    /// function-argument shape this mode types (decimal-comma modes
    /// use `;` between arguments).
    private var sampleValue: String {
        formatDisplayValue(1234.567, decimalPlaces: model.settings.decimalPlaces,
                           context: model.numberContext)
    }
    private var sampleCompact: String {
        let forced = NumberFormatContext(
            locale: model.numberContext.locale,
            decimalSeparator: model.numberContext.decimalSeparator,
            groupingSeparator: model.numberContext.groupingSeparator,
            inputGroupingSeparators: model.numberContext.inputGroupingSeparators,
            argumentSeparator: model.numberContext.argumentSeparator,
            displayGrouping: model.numberContext.displayGrouping,
            compactNotation: true,
            convertForeignOnPaste: model.numberContext.convertForeignOnPaste
        )
        return formatDisplayValue(100000, decimalPlaces: model.settings.decimalPlaces,
                                  context: forced)
    }
    private var sampleFunction: String {
        model.numberContext.decimalComma ? "max(1,5; 2,5)" : "max(1.5, 2.5)"
    }

    /// r87: a Binding into the GLOBAL presentation preferences.
    private func presentationBinding<T>(
        _ kp: WritableKeyPath<NumberPresentationPreferences, T>
    ) -> Binding<T> {
        Binding(
            get: { model.settings.presentation[keyPath: kp] },
            set: { v in
                model.settings.presentation[keyPath: kp] = v
                model.persist()
            }
        )
    }

    /// r87: the live "default answer format" preview — 1234.567
    /// through the current global notation (custom renders through
    /// the validated pattern, invalid/empty pattern shows a dash).
    private var formatPreview: String {
        let prefs = model.settings.presentation
        switch prefs.notation {
        case .custom:
            guard let pattern = NumberPattern.tryValidated(prefs.customPattern)
            else { return "—" }
            return NumberPresentation.renderPattern(
                pattern, value: 1234.567,
                negativeStyle: prefs.negativeStyle,
                context: model.numberContext)
        default:
            return NumberPresentation.format(
                1234.567, category: .plain,
                notation: prefs.notation,
                precision: model.settings.decimalPlaces,
                prefs: prefs, context: model.numberContext)
        }
    }

    /// r87: the custom-pattern row's caption — the grammar caption,
    /// replaced by the validation message when the stored pattern is
    /// invalid (the formatter then falls back to automatic).
    private var customPatternDetail: String {
        let language = self.language
        guard !model.settings.presentation.customPattern.isEmpty,
              NumberPattern.tryValidated(model.settings.presentation.customPattern) == nil
        else {
            return L10n.t("customPattern.cap", language: language)
        }
        return L10n.t("customPattern.invalid", language: language)
    }

    private func regionalBinding(_ kp: WritableKeyPath<RegionalNumberPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings.regional.map { $0[keyPath: kp] }
                    ?? RegionalNumberPreferences.newDefaults[keyPath: kp] },
            set: { v in
                var p = model.settings.regional ?? .newDefaults
                p[keyPath: kp] = v
                model.settings.regional = p
                model.persist()
            }
        )
    }

    private var regionPicker: some View {
        let language = self.language
        let regionSelection = Binding(
            get: { model.settings.regional?.region ?? .system },
            set: { model.requestRegionChange($0) }
        )
        return Picker(L10n.t("numbers.regionLabel", language: language),
                      selection: regionSelection) {
            ForEach(NumberRegionPreset.allCases, id: \.self) { p in
                // The system preset displays the OS region's localized
                // name (the app never pretends it is a fixed preset).
                Text(p.displayName(in: systemLocale))
                    .tag(p)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        // r75: no fixedSize — the label may be a long localized
        // "System Region (...)" name; cap + truncate only as a
        // last resort so the row never overflows the page inset.
        .frame(maxWidth: 240, alignment: .trailing)
        .lineLimit(1)
    }

    /// The ONE live example block: caption + value pairs through the
    /// active context (the same values the notebook itself shows).
    private var sampleGrid: some View {
        let language = self.language
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text(L10n.t("numbers.sample", language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(sampleValue)
                    .font(.system(size: 13))
            }
            GridRow {
                Text(L10n.t("numbers.compact", language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(sampleCompact)
                    .font(.system(size: 13))
            }
            GridRow {
                Text(L10n.t("numbers.syntax", language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(sampleFunction)
                    .font(.system(size: 13))
            }
        }
        .padding(.leading, 4)
    }

    var body: some View {
        let confirmBinding = Binding(
            get: { model.pendingRegionChange != nil },
            set: { if !$0 { model.cancelRegionChange() } }
        )
        let language = self.language
        return SettingsDetailPage(destination: .numbers, language: language) {
            // 1. NUMBER FORMAT — what shape numbers have everywhere.
            SettingsGroup(title: L10n.t("numbers.region", language: language)) {
                // r92: one-line Region row (its long caption was removed)
                // with the live examples directly below, separated by the
                // same hairline the grouped rows use.
                SettingsRow(title: L10n.t("numbers.regionLabel", language: language)) {
                    regionPicker
                }
                Divider()
                sampleGrid
                    .padding(.vertical, 9)
            }

            // 2. ANSWER DISPLAY — how RESULTS are rounded and grouped
            // (independent of the region and of input grouping).
            SettingsGroup(title: L10n.t("numbers.answer", language: language)) {
                SettingsRow(
                    title: L10n.t("rounding", language: language),
                    detail: L10n.t("roundingCap", language: language)
                ) {
                    // r88: global rounding is a native AppKit-backed
                    // ticked slider (the SAME shared primitive as the
                    // per-answer menu slider): blue native track/thumb,
                    // 9 ticks below the track for the 2...10 contract
                    // range, a compact live `N dp` label. The callback
                    // fires only when the snapped integer changes, so
                    // persisting happens exactly once per stop. This is
                    // rounding's ONE home (moved out of General in r76).
                    DiscreteTickSlider(
                        minValue: 2,
                        maxValue: 10,
                        value: model.settings.decimalPlaces,
                        liveLabel: AnswerDisplay.sliderLabel(
                            model.settings.decimalPlaces),
                        a11yLabel: L10n.t("decimalPlaces", language: language),
                        a11yValueFor: { v in
                            AnswerDisplay.sliderAccessibilityValue(
                                v, language: language)
                        },
                        onChange: { v in
                            model.settings.decimalPlaces = v
                            model.persist()
                        }
                    )
                    .frame(width: 236, height: 32)
                }
                SettingsRow(
                    title: L10n.t("numbers.grouping", language: language),
                    detail: L10n.t("numbers.groupingCap", language: language),
                    divider: true,
                ) {
                    SettingsSwitch(title: L10n.t("numbers.grouping", language: language),
                                   isOn: regionalBinding(\.showThousandsSeparator))
                }
                SettingsRow(
                    title: L10n.t("numbers.compact", language: language),
                    detail: L10n.t("numbers.compactCap", language: language),
                    divider: true,
                ) {
                    SettingsSwitch(title: L10n.t("numbers.compact", language: language),
                                   isOn: regionalBinding(\.useCompactNotation))
                }
            }

            // 3. DEFAULT ANSWER FORMAT (r87) — the global notation,
            // negative style, currency placement, the fraction
            // denominator and the custom pattern with its live
            // preview. Every default reproduces the pre-r87 shapes.
            SettingsGroup(title: L10n.t("numbers.format", language: language)) {
                SettingsRow(
                    title: L10n.t("notation.label", language: language),
                    detail: L10n.t("numbers.formatCap", language: language)
                ) {
                    // r87: native menu picker over the six notations
                    // (the same key family as the per-line Number
                    // Format menu — format<Notation>).
                    Picker("", selection: presentationBinding(\.notation)) {
                        ForEach(NumberNotation.allCases, id: \.self) { n in
                            Text(L10n.t("format" + n.rawValue.capitalized,
                                        language: language)).tag(n)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                if model.settings.presentation.notation == .fraction {
                    SettingsRow(
                        title: L10n.t("fraction.label", language: language),
                        detail: L10n.t("fraction.cap", language: language),
                        divider: true,
                    ) {
                        Picker("",
                               selection: presentationBinding(\.fractionPreset)) {
                            ForEach(FractionPreset.allCases, id: \.self) { fp in
                                Text("\(fp.rawValue)").tag(fp)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                SettingsRow(
                    title: L10n.t("negative.label", language: language),
                    detail: L10n.t("negative.cap", language: language),
                    divider: true,
                ) {
                    Picker("",
                           selection: presentationBinding(\.negativeStyle)) {
                        ForEach(NegativeStyle.allCases, id: \.self) { n in
                            Text(L10n.t(n.l10nKey,
                                        language: language)).tag(n)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(
                    title: L10n.t("currency.label", language: language),
                    detail: L10n.t("currency.cap", language: language),
                    divider: true,
                ) {
                    Picker("",
                           selection: presentationBinding(\.currencyPlacement)) {
                        ForEach(CurrencyPlacement.allCases, id: \.self) { cp in
                            Text(L10n.t(cp.l10nKey,
                                        language: language)).tag(cp)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(
                    title: L10n.t("customPattern.label", language: language),
                    detail: customPatternDetail,
                    divider: true,
                ) {
                    TextField("#,##0.00",
                              text: presentationBinding(\.customPattern))
                        // r96: a REAL, always-visible native field: the
                        // empty state must read as a text field before
                        // it is focused, and the canonical grammar
                        // sample is its placeholder (the pattern itself
                        // is locale-neutral, so it is not translated).
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(Text(L10n.t("customPattern.label", language: language)))
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: 180, alignment: .trailing)
                }
                // r87: the live preview — the SAME 1234.567 sample as
                // the region group, rendered by the current global
                // notation (custom through the validated pattern).
                SettingsRow(
                    title: L10n.t("customPattern.preview", language: language),
                    detail: nil,
                    divider: true,
                ) {
                    Text(formatPreview)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }

            // 4. PASTING — the opt-in conversion of foreign numbers.
            SettingsGroup(title: L10n.t("numbers.pasting", language: language)) {
                SettingsRow(
                    title: L10n.t("numbers.convertPaste", language: language),
                    detail: L10n.t("numbers.convertPasteCap", language: language)
                ) {
                    SettingsSwitch(title: L10n.t("numbers.convertPaste", language: language),
                                   isOn: regionalBinding(\.convertForeignOnPaste))
                }
            }

            // r90: the currency-rate attribution lives here — the most
            // relevant home for it (it describes the numbers the answer
            // column shows). ONE understated footer line, no duplicate.

        }
        .alert(
            L10n.t("numbers.confirmTitle", language: language),
            isPresented: confirmBinding
        ) {
            Button(L10n.t("numbers.apply", language: language)) {
                model.confirmRegionChange()
            }
            Button(L10n.t("numbers.cancel", language: language), role: .cancel) {
                model.cancelRegionChange()
            }
        } message: {
            if let pending = model.pendingRegionChange {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("numbers.confirmBody", language: language))
                    ForEach(pending.examples, id: \.self) { ex in
                        Text(ex).font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }
}

// MARK: - Styling tab (r76: typography / syntax colors / preview)

/// The r21 Styling tab re-organized in r76 into three groups:
/// Typography (font size + font design), Syntax colors (one finite
/// color choice per notebook role, each picker showing a real sRGB
/// swatch plus the localized name) and Preview (ONE clearly labelled
/// full-width area that shares the page width). It resolves
/// colors/fonts through the SAME palette resolver as the real editor
/// (no duplicated RGB values anywhere) and keeps the REAL notebook
/// font size (including 30 pt, never shrunk); the page scrolls
/// instead of the window enlarging.
private struct StylingSettingsPage: View {
    @Bindable var model: AppModel

    private var language: AppLanguage { model.settings.language }

    private var styling: StylingPreferences { model.settings.styling }

    /// r89: presets clear the role's custom override — the preset
    /// becomes effective again.
    private func choosePreset(_ choice: RoleColorChoice, for role: SyntaxColorRole) {
        model.settings.styling.choosePreset(choice, for: role)
        model.persist()
    }

    /// r89: the per-role Default action: exact factory preset + no
    /// custom override.
    private func resetRole(_ role: SyntaxColorRole) {
        model.settings.styling.resetRoleColors(role)
        model.persist()
    }

    /// r89: colors only — font design/size and the answer column
    /// settings are preserved.
    private func resetAllSyntaxColors() {
        model.settings.styling.resetAllSyntaxColors()
        model.persist()
    }

    var body: some View {
        let language = self.language
        return SettingsDetailPage(destination: .styling, language: language) {
            // 1. TYPOGRAPHY.
            SettingsGroup(title: L10n.t("styling.typography", language: language)) {
                SettingsRow(title: L10n.t("styling.fontsize", language: language)) {
                    Menu {
                        ForEach(fontSizeOptions, id: \.key) { opt in
                            Button {
                                model.settings.fontSizeKey = opt.key
                                model.persist()
                            } label: {
                                Text("\(opt.label) pt")
                            }
                        }
                    } label: {
                        Text("\(fontSizeLabel) pt")
                            .font(.system(size: 13, weight: .medium))
                            .frame(minWidth: 56, alignment: .trailing)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                SettingsRow(title: L10n.t("styling.font", language: language)) {
                    Menu {
                        ForEach(StylingFontDesign.allCases, id: \.self) { design in
                            Button {
                                model.settings.styling.fontDesign = design
                                model.persist()
                            } label: {
                                Text(L10n.t("styling.font.\(design.rawValue)",
                                            language: language))
                            }
                        }
                    } label: {
                        Text(L10n.t("styling.font.\(styling.fontDesign.rawValue)",
                                    language: language))
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            // r75: capped so a long localized font-design
                            // name can never push the row past the inset.
                            .frame(maxWidth: 160, alignment: .trailing)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            // 2. ANSWER COLUMN (r87) — the 200pt column's surface and
            // where answers sit inside it.
            SettingsGroup(title: L10n.t("styling.column", language: language)) {
                SettingsRow(
                    title: L10n.t("styling.column.alignment", language: language)
                ) {
                    Picker("", selection: Binding(
                        get: { model.settings.styling.answerColumnAlignment },
                        set: { model.settings.styling.answerColumnAlignment = $0
                                model.persist() }
                    )) {
                        ForEach(AnswerColumnAlignment.allCases, id: \.self) { a in
                            Text(L10n.t("alignment.\(a.rawValue)",
                                        language: language)).tag(a)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(
                    title: L10n.t("styling.column.surface", language: language),
                    divider: true,
                ) {
                    Picker("", selection: Binding(
                        get: { model.settings.styling.answerColumnSurface },
                        set: { model.settings.styling.answerColumnSurface = $0
                                model.persist() }
                    )) {
                        ForEach(AnswerColumnSurface.allCases, id: \.self) { sf in
                            Text(L10n.t("surface.\(sf.rawValue)",
                                        language: language)).tag(sf)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            // 3. SYNTAX COLORS — one finite preset choice plus an
            // arbitrary custom sRGB per role (r89), plus the
            // colors-only Reset Syntax Colors action.
            SettingsGroup(title: L10n.t("styling.colors", language: language)) {
                ForEach(SyntaxColorRole.allCases, id: \.self) { role in
                    syntaxRoleRow(role)
                }
                // r89: visible Reset-Syntax-Colors action, enabled only
                // while any role differs from the factory defaults.
                HStack {
                    Spacer()
                    Button(L10n.t("styling.colors.resetAll", language: language)) {
                        resetAllSyntaxColors()
                    }
                    .disabled(!styling.hasNonDefaultSyntaxColors)
                    .help(L10n.t("styling.colors.resetAllCap", language: language))
                    .accessibilityLabel(L10n.t("styling.colors.resetAll", language: language))
                }
            }

            // 4. PREVIEW — the live, full-width, real-font-size sample.
            SettingsGroup(title: L10n.t("styling.preview", language: language),
                          surface: false) {
                StylingPreview(
                    fontSize: model.settings.fontSize,
                    lineHeight: model.settings.lineHeight,
                    styling: styling,
                    unitContext: model.unitContext
                )
            }
        }
    }

    private var fontSizeLabel: String {
        fontSizeOptions.first(where: { $0.key == model.settings.fontSizeKey })?.label
            ?? String(Int(model.settings.fontSize))
    }

    // MARK: - r89: syntax color rows (preset menu + ColorPicker + reset)

    /// One compact role row (fits the 520pt minimum page): localized
    /// role label, the preset menu whose label is the EFFECTIVE swatch
    /// plus the preset name or “Custom”, the native ColorPicker well
    /// (arbitrary opaque sRGB) and — only while non-default — the
    /// per-role Default action.
    private func syntaxRoleRow(_ role: SyntaxColorRole) -> some View {
        HStack(spacing: 10) {
            Text(L10n.t(role.labelKey, language: language))
                .font(.system(size: 13))
            Spacer(minLength: 10)
            syntaxPresetMenu(role)
            syntaxColorWell(role)
            if styling.isSyntaxColorNonDefault(role) {
                Button {
                    resetRole(role)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.borderless)
                .help(L10n.t("styling.colors.default", language: language))
                .accessibilityLabel(L10n.t("styling.colors.resetRole", language: language))
            }
        }
        .frame(minHeight: 24)
    }

    /// The preset menu: the label shows the exact effective swatch and
    /// either the preset name or “Custom” while an override is active;
    /// choosing ANY preset clears the role's custom color.
    private func syntaxPresetMenu(_ role: SyntaxColorRole) -> some View {
        let isCustom = styling.customColor(for: role) != nil
        let presetName = L10n.t(
            "styling.color.\(styling.presetChoice(for: role).rawValue)",
            language: language)
        return Menu {
            ForEach(RoleColorChoice.allCases, id: \.self) { choice in
                Button {
                    choosePreset(choice, for: role)
                } label: {
                    HStack(spacing: 7) {
                        roleSwatch(choice)
                        Text(L10n.t("styling.color.\(choice.rawValue)",
                                    language: language))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                effectiveRoleSwatch(role)
                Text(isCustom
                     ? L10n.t("styling.colors.custom", language: language)
                     : presetName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    // r89: long German/French/Russian names truncate
                    // instead of clipping the row horizontally.
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            .frame(maxWidth: 160, alignment: .trailing)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// The native color well: editing converts the pick to the
    /// canonical opaque sRGB triple and marks the role Custom. The get
    /// side returns the quantized round-trip, so re-applying the same
    /// value is a no-op (disk writes happen only on actual RGB
    /// changes), and the well always displays the exact effective color.
    private func syntaxColorWell(_ role: SyntaxColorRole) -> some View {
        ColorPicker("", selection: Binding(
            get: {
                if let custom = styling.customColor(for: role) {
                    return custom.color
                }
                let preset = NotebookPalette.color(
                    for: styling.presetChoice(for: role))
                return Color(nsColor: preset)
            },
            set: { new in
                guard let quantized = SyntaxSRGBColor(new) else { return }
                // Dedupe identical quantized values: a ColorPicker drag
                // emits continuously; only actual RGB changes write.
                guard quantized != styling.customColor(for: role) else { return }
                model.settings.styling.setCustomColor(quantized, for: role)
                model.persist()
            }
        ), supportsOpacity: false)
            .labelsHidden()
            .help(L10n.t("styling.colors.pick", language: language))
            .accessibilityLabel(L10n.t(role.labelKey, language: language))
    }

    /// Exact preset swatch circle (no custom override).
    private func roleSwatch(_ choice: RoleColorChoice) -> some View {
        Circle()
            .fill(Color(nsColor: NotebookPalette.color(for: choice)))
            .frame(width: 10, height: 10)
            .overlay(
                Circle().strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            )
    }

    /// The role's EFFECTIVE swatch — custom sRGB when set, otherwise
    /// the preset — the same value the editor and preview render.
    private func effectiveRoleSwatch(_ role: SyntaxColorRole) -> some View {
        Circle()
            .fill(Color(nsColor: NotebookPalette.color(
                for: styling.presetChoice(for: role),
                custom: styling.customColor(for: role))))
            .frame(width: 10, height: 10)
            .overlay(
                Circle().strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            )
    }
}

// MARK: - Live preview

/// The notebook preview: a white editor area (the app's real editor
/// background) next to the calm gray answer strip, with the same row
/// rhythm as the app (fixed line height derived from the selected size).
/// Every line is painted by the REAL classifier + the SAME palette
/// resolver as the editor. The `0.5 as fraction` row uses explicit
/// role overrides to show the fraction glyph treatment (the engine
/// resolves fractions natively since r83; the overrides only paint
/// the fraction roles the demo row wants to demonstrate); all other
/// lines are genuine engine banding.
private struct StylingPreview: View {
    let fontSize: Double
    let lineHeight: Double
    let styling: StylingPreferences
    /// r84: the app's unit context — the preview classifier resolves
    /// custom unit names exactly as the editor does.
    let unitContext: UnitContext

    /// One demo row: editor text, the answer the app would show (nil =
    /// no answer row), and optional illustrative role overrides per
    /// UTF-16 range (only the fraction line).
    private struct DemoRow {
        let text: String
        let answer: String?
        let overrides: [(NSRange, SyntaxRole)]
        init(_ text: String, _ answer: String?, _ overrides: [(NSRange, SyntaxRole)] = []) {
            self.text = text
            self.answer = answer
            self.overrides = overrides
        }
    }

    private var rows: [DemoRow] {
        [
            DemoRow("123 + 456", "579"),
            DemoRow("variable = 30 minutes", "30 min"),
            // Illustration only: explicit roles for the fraction line the
            // engine does not evaluate (number, specifier, unit).
            DemoRow("0.5 as fraction", "½", [
                (NSRange(location: 0, length: 3), .number),
                (NSRange(location: 4, length: 2), .specifier),
                (NSRange(location: 7, length: 8), .conversion),
            ]),
            DemoRow("# Totals", nil),
            DemoRow("// weekly summary", nil),
            DemoRow("Total:", nil),
            DemoRow("some plain prose", nil),
        ]
    }

    private var palette: NotebookPalette { NotebookPalette(styling: styling) }
    private var rowHeight: CGFloat { CGFloat(lineHeight) }

    var body: some View {
        HStack(spacing: 0) {
            // Editor side.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(previewAttributed(row.text))
                        .frame(height: rowHeight, alignment: .leading)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            // r36: the ONE centralized editor surface token — the
            // preview editor side matches the real NSTextView exactly.
            .background(Color(nsColor: Design.editorBackground))

            // Answer strip.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Group {
                        if let answer = row.answer {
                            Text(answer)
                                .font(palette.swiftUIFont(fontSize))
                                .foregroundStyle(Color(nsColor: Design.baseText))
                                .lineLimit(1)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: rowHeight, alignment: .leading)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            // Hugs the widest answer at the REAL preview font size (the
            // semantic font never shrinks); the editor side above takes
            // the remaining width via layoutPriority.
            .fixedSize()
            .background(Color(nsColor: Design.answerPanelBackground))
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 1)
        )
    }

    /// Paints one preview line through the real classifier (plus the
    /// row's illustrative overrides): the dark base (Design.baseText)
    /// regular on the selected size/design; `// ` comments semibold in
    /// the comments color; hash headings heavy (gray marker,
    /// headings-color body); every classified span via the palette
    /// resolver.
    private func previewAttributed(_ line: String) -> AttributedString {
        let font = palette.editorFont(size: fontSize)
        let ns = NSMutableAttributedString(string: line)
        let full = NSRange(location: 0, length: (line as NSString).length)
        ns.addAttribute(.font, value: font, range: full)
        ns.addAttribute(.foregroundColor, value: Design.baseText, range: full)

        if line.hasPrefix("#") {
            let marker = NSRange(location: 0, length: 1)
            ns.addAttribute(.font,
                            value: palette.editorFont(size: fontSize, weight: .heavy),
                            range: marker)
            ns.addAttribute(.foregroundColor, value: Design.headingMarkerColor, range: marker)
            if full.length > 1 {
                let body = NSRange(location: 1, length: full.length - 1)
                ns.addAttribute(.font,
                                value: palette.editorFont(size: fontSize, weight: .heavy),
                                range: body)
                ns.addAttribute(.foregroundColor, value: palette.headings, range: body)
            }
        } else if line.hasPrefix("// ") {
            ns.addAttribute(.font,
                            value: palette.editorFont(size: fontSize, weight: .semibold),
                            range: full)
            ns.addAttribute(.foregroundColor, value: palette.comments, range: full)
        } else {
            // Overrides (illustration rows) win; everything else is the
            // real classifier output for exactly this line text.
            if let demo = rows.first(where: { $0.text == line }), !demo.overrides.isEmpty {
                for (range, role) in demo.overrides {
                    guard let color = palette.color(forRole: role),
                          range.location >= 0, NSMaxRange(range) <= full.length else { continue }
                    ns.addAttribute(.foregroundColor, value: color, range: range)
                }
            } else {
                let spans = SyntaxClassifier.spans(for: line,
                                                   rates: Rates(base: "", rates: [:]),
                                                   decimalPlaces: 10,
                                                   unitContext: unitContext)
                for span in spans.flatMap({ $0 }) {
                    guard let color = palette.color(forRole: span.role),
                          span.range.location >= 0,
                          NSMaxRange(span.range) <= full.length else { continue }
                    ns.addAttribute(.foregroundColor, value: color, range: span.range)
                }
            }
        }
        return AttributedString(ns)
    }
}

// MARK: - Settings window configurator

/// Configures the native Settings scene window (r34, r75): resizability
/// and the designed CONTENT size range from the single SettingsGeometry
/// source (520x460 ... 640x540) — applied through `contentMinSize`/
/// `contentMaxSize` (the titlebar is excluded, unlike the old frame-based
/// minSize/maxSize mix). The initial open is deterministic: content
/// 560x460. The title is owned by the native tab view (the active tab's
/// localized name), matching the System Settings convention — exactly
/// one settings window, exactly one title, no duplicates.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    @MainActor
    final class Coordinator {
        var observers: [NSObjectProtocol] = []
        private var observedWindows: Set<ObjectIdentifier> = []

        /// r92: observes ONE window (idempotent per window) so the
        /// compact chrome is reasserted whenever the window becomes key
        /// — the empty window toolbar must not reappear and the window
        /// must keep its resizable bit and designed content range after
        /// a scene reconfiguration. The reassertion hops to the next
        /// main-actor turn so no window state is mutated inside the
        /// notification that announced the change.
        func observe(_ window: NSWindow) {
            let id = ObjectIdentifier(window)
            guard !observedWindows.contains(id) else { return }
            observedWindows.insert(id)
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { _ in
                MainActor.assumeIsolated {
                    SettingsWindowConfigurator.configure(window)
                }
            })
        }
    }

    /// A view that reports when it lands in its window. `makeNSView`
    /// alone can run BEFORE the NSWindow exists (SwiftUI builds the
    /// view tree first), which used to leave the window without the
    /// resizable style bit and without the designed content bounds —
    /// `viewDidMoveToWindow` is the earliest guaranteed moment.
    @MainActor
    final class ProbeView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow?(window) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Applies the designed chrome to a window: resizable + the CONTENT
    /// size range from the ONE geometry source, then the one-time
    /// out-of-range snap.
    @MainActor
    static func configure(_ window: NSWindow) {
        if !window.styleMask.contains(.resizable) {
            window.styleMask.insert(.resizable)
        }
        window.contentMinSize = NSSize(width: SettingsGeometry.minWidth,
                                       height: SettingsGeometry.minHeight)
        window.contentMaxSize = NSSize(width: SettingsGeometry.maxWidth,
                                       height: SettingsGeometry.maxHeight)
        hideEmptyToolbar(window)
    }

    /// r92: the Settings window has no toolbar items, so its toolbar is
    /// hidden entirely. Hiding the (empty) NSToolbar collapses the
    /// reserved toolbar band, which is what both put the sidebar list
    /// and the page heading back under the compact native titlebar and
    /// REMOVED the large blank zone the split navigation used to
    /// reserve. Public AppKit only: the toolbar object is kept (never
    /// nil, no fake titlebar, no traffic-light surgery), merely made
    /// invisible — and reasserted because a scene reconfiguration can
    /// bring the empty band back.
    @MainActor
    static func hideEmptyToolbar(_ window: NSWindow) {
        if let toolbar = window.toolbar, toolbar.isVisible {
            toolbar.isVisible = false
        }
        // Hiding the toolbar collapses the reserved band but macOS also
        // drops the centered window title with it; the native title is
        // part of the chrome this window keeps, so it is reasserted.
        if window.titleVisibility != .visible {
            window.titleVisibility = .visible
        }
    }

    /// Content range from the ONE geometry source (never frame sizes).
    private var contentMin: NSSize {
        NSSize(width: SettingsGeometry.minWidth, height: SettingsGeometry.minHeight)
    }
    private var contentMax: NSSize {
        NSSize(width: SettingsGeometry.maxWidth, height: SettingsGeometry.maxHeight)
    }

    /// r75: snap an OUT-OF-RANGE content size (a stale persisted frame
    /// from an older, wider build) back to the designed initial size —
    /// exactly once on the window's first `didBecomeKey`. A user resize
    /// inside the designed range is never touched (the check only fires
    /// on out-of-range sizes, and contentMin/Max keep it that way).
    private func snapIfOutOfRange(_ window: NSWindow) {
        let size = window.contentRect(forFrameRect: window.frame).size
        let outOfRange = size.width < SettingsGeometry.minWidth - 0.5
            || size.width > SettingsGeometry.maxWidth + 0.5
            || size.height < SettingsGeometry.minHeight - 0.5
            || size.height > SettingsGeometry.maxHeight + 0.5
        if outOfRange {
            window.setContentSize(NSSize(width: SettingsGeometry.idealWidth,
                                         height: SettingsGeometry.idealHeight))
        }
    }

    func makeNSView(context: Context) -> NSView {
        let view = ProbeView()
        let coordinator = context.coordinator
        view.onWindow = { window in
            MainActor.assumeIsolated {
                Self.configure(window)
                coordinator.observe(window)
            }
        }
        Task { @MainActor in
            guard let window = view.window else { return }
            Self.configure(window)
            window.styleMask.insert(.resizable)
            // Content (not frame) bounds: 520x460 ... 640x540, mirroring
            // the root SwiftUI frame exactly (same SettingsGeometry
            // source) — no titlebar arithmetic.
            window.contentMinSize = contentMin
            window.contentMaxSize = contentMax
            // Deterministic first open: content 560x460 — even when a
            // frame persisted from an older (wider/taller) build would
            // reopen the window oversized, setContentSize snaps it back
            // exactly ONCE (the snap only ever fires on out-of-range
            // sizes; a user resize inside the range is never touched).
            window.setContentSize(NSSize(width: SettingsGeometry.idealWidth,
                                         height: SettingsGeometry.idealHeight))
            // The empty window toolbar is hidden again here (the
            // observers re-check after later reconfigurations).
            // SwiftUI re-asserts its own style mask during scene
            // reconfiguration and drops the resizable bit; hold it. The
            // same first-open moment is where an AppKit frame restore
            // (stale, from an older wider build) lands AFTER makeNSView,
            // so the one-time out-of-range snap lives here, not only in
            // makeNSView/updateNSView.
            context.coordinator.observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
                ) { _ in
                    Task { @MainActor in
                        guard let window = view.window else { return }
                        if !window.styleMask.contains(.resizable) {
                            window.styleMask.insert(.resizable)
                        }
                        snapIfOutOfRange(window)
                        Self.hideEmptyToolbar(window)
                    }
                }
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            guard let window = nsView.window else { return }
            if !window.styleMask.contains(.resizable) {
                window.styleMask.insert(.resizable)
            }
            // Re-assert the content bounds (scene reconfiguration can
            // reset them). Idempotent — never resizes a legal window.
            window.contentMinSize = contentMin
            window.contentMaxSize = contentMax
            // Only when something (a stale persisted frame from an older
            // build, an external resize) pushed the window OUT of the
            // designed range: snap back to the designed initial size.
            // A user resize inside the range is never touched.
            snapIfOutOfRange(window)
            // A scene update can bring the empty toolbar band back; the
            // window hides it again (r92).
            Self.configure(window)
        }
    }

    func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        for obs in coordinator.observers {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

// For Settings scene (separate window)
struct NativeSettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        SettingsView(model: model)
    }
}

/// The localized label key for one appearance choice.
@MainActor
private func appearanceKey(_ a: AppAppearance) -> String {
    switch a {
    case .system: return "appearanceAuto"
    case .light: return "appearanceLight"
    case .dark: return "appearanceDark"
    }
}

/// The two-tile application-icon selector: native buttons with the exact
/// supplied preview PNGs (never generated from a display string), a
/// localized label under each tile and one accent checkmark on the
/// selected tile. Plain button style keeps focus/keyboard behavior and
/// accessibility (each tile is a real selectable control); the row width
/// never changes on selection, so the Settings window cannot reflow.
private struct AppIconPicker: View {
    let selection: AppIconChoice
    let language: AppLanguage
    let onSelect: (AppIconChoice) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AppIconChoice.uiOrder, id: \.self) { choice in
                tile(choice)
            }
        }
    }

    @ViewBuilder
    private func tile(_ choice: AppIconChoice) -> some View {
        let selected = selection == choice
        let label = L10n.t(choice == .dark ? "appIconDark" : "appIconLight",
                           language: language)
        Button {
            onSelect(choice)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image = AppIconResources.previewImage(for: choice) {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 56, height: 56)
                        } else {
                            // Missing development preview: a neutral
                            // placeholder — never a crash, never a
                            // silently different asset.
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 56, height: 56)
                                .overlay(Image(systemName: "app.dashed")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.25),
                                          lineWidth: selected ? 2 : 1)
                    )
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentColor, Color(nsColor: .windowBackgroundColor))
                            .offset(x: 5, y: -5)
                    }
                }
                Text(label)
                    .font(Design.labelSmall)
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityValue(selected ? "selected" : "not selected")
        .help(label)
    }
}
