import AppKit
import SwiftUI
import NumlexCore

/// r34/r75 — the ONE settings-window geometry source (points). Width
/// range plus CONTENT height range (NSWindow content size — the
/// titlebar is extra, and the configurator applies these through
/// contentMinSize / contentMaxSize, never frame minSize/maxSize). The
/// window opens at 560x460 (r75 compact single column: 520...640
/// content width, 460...540 content height); r75 narrowed the range
/// because every tab is now ONE readable column and the old 690...820
/// two-column range left the window needlessly wide.
private enum SettingsGeometry {
    static let minWidth: CGFloat = 520
    static let idealWidth: CGFloat = 560
    static let maxWidth: CGFloat = 640
    static let minHeight: CGFloat = 460
    static let idealHeight: CGFloat = 460
    static let maxHeight: CGFloat = 540
}

/// The Settings scene content (r21, r33, r34, r74): one native macOS
/// `TabView` with exactly four tabs — General (all non-style settings,
/// six input helpers, language/line numbers, rate attribution),
/// Numbers (r73 region + the three independent toggles, one live
/// example block), Constants (the GLOBAL user-defined constants, one
/// scrollable row table) and Styling (font size/family plus one finite
/// color picker per notebook role, with a full-width live preview).
/// r74: every tab is ONE single readable column on the shared
/// SettingsPage scaffold (label left, native control right,
/// description under the label text); the only remaining glass
/// surface is the Constants row table. No in-content "Settings"
/// heading (the system titlebar carries the single localized window
/// title), no nested cards, no fake tabs. Geometry comes from
/// SettingsGeometry (560x460 content initial; 520...640 x 460...540).
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsTab(model: model)
                .tabItem {
                    Label(L10n.t("settings.general", language: model.settings.language),
                          systemImage: "gear")
                }
            ConstantsSettingsTab(model: model)
                .tabItem {
                    Label(L10n.t("settings.constants", language: model.settings.language),
                          systemImage: "function")
                }
            StylingSettingsTab(model: model)
                .tabItem {
                    Label(L10n.t("settings.styling", language: model.settings.language),
                          systemImage: "paintbrush")
                }
            NumbersSettingsTab(model: model)
                .tabItem {
                    Label(L10n.t("settings.numbers", language: model.settings.language),
                          systemImage: "globe")
                }
        }
        .frame(minWidth: SettingsGeometry.minWidth,
               idealWidth: SettingsGeometry.idealWidth,
               maxWidth: SettingsGeometry.maxWidth,
               minHeight: SettingsGeometry.minHeight,
               idealHeight: SettingsGeometry.idealHeight,
               maxHeight: SettingsGeometry.maxHeight)
        // Window chrome the scene APIs cannot express: resizability and
        // the designed CONTENT size range (the SwiftUI frame above
        // drives the content bounds; the configurator mirrors them on
        // the NSWindow from the SAME SettingsGeometry source). The
        // title stays the native tab title
        // (General/Constants/Styling — the System Settings convention);
        // the configurator never fights it.
        .background(SettingsWindowConfigurator())
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    @Bindable var model: AppModel

    private var language: AppLanguage { model.settings.language }

    /// One persisted boolean binding (every control writes through
    /// model.persist(), exactly like the previous rows).
    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0; model.persist() }
        )
    }

    /// The native checkbox control shared by every General row.
    private func checkbox(_ isOn: Binding<Bool>) -> some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.checkbox)
    }

    var body: some View {
        // r74: ONE single readable column on the shared page scaffold —
        // label left, native control right, description under the label
        // text. No two-column split, no per-card glass. (The Sheet
        // title control was removed from the UI in r23; AppSettings.
        // sheetName stays in the model for decoding and new-sheet
        // naming.)
        let language = self.language
        return SettingsPage {
            // Interface + display rows.
            SettingsGroup {
                SettingsRow(title: L10n.t("language", language: language)) {
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
                SettingsRow(title: L10n.t("round", language: language)) {
                    // r75: compact native MENU picker — the old 9-segment
                    // control (fixed 232 pt) clipped its last segment at
                    // narrow widths; the menu keeps the SAME 2...10 range
                    // and binding and shows every choice as a full
                    // unclipped list.
                    Picker("", selection: Binding(
                        get: { model.settings.decimalPlaces },
                        set: { model.settings.decimalPlaces = $0; model.persist() }
                    )) {
                        ForEach(2...10, id: \.self) { v in
                            Text("\(v)").tag(v)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                SettingsRow(title: L10n.t("appearance", language: language)) {
                    // The ONE write path (model.setAppearance: one
                    // settings write, one persist, one process-wide
                    // NSApp.appearance application) — a direct settings
                    // write would skip the live switch.
                    Picker("", selection: Binding(
                        get: { model.settings.appearance },
                        set: { model.setAppearance($0) }
                    )) {
                        ForEach(AppAppearance.allCases, id: \.self) { a in
                            Text(L10n.t(
                                a == .light ? "appearanceLight" : "appearanceDark",
                                language: language)).tag(a)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 128)
                }
                SettingsRow(title: L10n.t("linenumber", language: language)) {
                    checkbox(boolBinding(\AppSettings.lineNumbers))
                }
                SettingsRow(
                    title: L10n.t("hideSidebarBtn", language: language),
                    detail: L10n.t("hideSidebarBtnCap", language: language)
                ) {
                    checkbox(boolBinding(\AppSettings.hideSidebarButtonWhenCollapsed))
                }
            }

            SettingsGroup(title: L10n.t("operators", language: language)) {
                SettingsRow(
                    title: L10n.t("opPad", language: language),
                    detail: L10n.t("opPadCap", language: language)
                ) {
                    checkbox(boolBinding(\AppSettings.input.padOperators))
                }
                SettingsRow(
                    title: L10n.t("opStar", language: language),
                    detail: L10n.t("opStarCap", language: language)
                ) {
                    checkbox(boolBinding(\AppSettings.input.replaceAsterisk))
                }
                SettingsRow(
                    title: L10n.t("opBacktick", language: language),
                    detail: L10n.t("opBacktickCap", language: language)
                ) {
                    checkbox(boolBinding(\AppSettings.input.replaceBacktick))
                }
                SettingsRow(
                    title: L10n.t("opQuick", language: language),
                    detail: L10n.t("opQuickCap", language: language)
                ) {
                    checkbox(boolBinding(\AppSettings.input.quickOperators))
                }
            }

            SettingsGroup(title: L10n.t("autoInsert", language: language)) {
                SettingsRow(
                    title: L10n.t("autoGroup", language: language),
                    detail: L10n.t("autoGroupCap", language: language)
                ) {
                    checkbox(boolBinding(\AppSettings.input.groupNumbers))
                }
                SettingsRow(
                    title: L10n.t("autoPrev", language: language),
                    detail: L10n.t("autoPrevCap", language: language)
                ) {
                    checkbox(boolBinding(\AppSettings.input.insertPreviousAnswer))
                }
            }

            // Currency rate attribution (the bundled fiat catalog is
            // converted with the open provider table fetched at
            // launch — no API key required).
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t("currencyRates", language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Link("open.er-api.com",
                     destination: URL(string: "https://open.er-api.com")!)
                    .font(.system(size: 12))
            }
        }
    }
}

// MARK: - Shared components (r23 glass card, r74 page layout)

/// One glass surface: 10 pt content padding, leading alignment, regular
/// liquid glass in a 14 pt continuous-corner rounded rect. A section
/// shows exactly ONE card; titles live outside it (no nested cards, no
/// fake titlebar).
private struct SettingsCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

extension View {
    fileprivate func settingsCard() -> some View {
        modifier(SettingsCardModifier())
    }
}

/// r74 shared page layout: ONE single readable column inside a
/// top-aligned ScrollView with 20 pt page insets. Every tab uses this
/// scaffold, so all four share the same layout rules; a tab that
/// overflows the minimum window height scrolls instead of enlarging
/// the window.
private struct SettingsPage<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

/// One group of rows under an optional 13 pt semibold heading
/// (heading-less groups are allowed for compact tabs).
private struct SettingsGroup<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            content
        }
    }
}

/// One r74 settings row: 13 pt label on the left with its optional
/// 11 pt secondary description underneath, aligned to the LABEL text
/// (never to the control glyph), and the native control trailing.
private struct SettingsRow<Control: View>: View {
    let title: String
    let detail: String?
    let control: Control

    init(title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
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
    }
}


// MARK: - Constants tab (r33)

/// The r33 Constants tab: a concise localized intro, ONE glass card
/// holding a vertically scrollable row table (Name, Value, per-row
/// status, borderless destructive trash) and a bottom toolbar with the
/// Add Constant button and the count/limit. Every row binds by STABLE
/// UUID through the focused AppModel methods; each committed change
/// persists and re-evaluates every sheet live. `.nlx` exports never
/// embed constants — that is stated in the intro, never in the rows.
private struct ConstantsSettingsTab: View {
    @Bindable var model: AppModel
    /// Focus target for the fresh row's name field (Add and
    /// Enter-in-Value land here for immediate overwrite).
    @FocusState private var focusedName: UUID?

    private var language: AppLanguage { model.settings.language }

    /// One deterministic resolution for the whole tab: the stable status
    /// per row ID (the shared pure resolver, never per-row state).
    private var resolution: [UUID: ConstantResolver.ResolvedRow] {
        Dictionary(uniqueKeysWithValues:
            ConstantResolver.resolve(model.settings.customConstants)
                .rows.map { ($0.id, $0) })
    }

    var body: some View {
        // r75: the SAME shared 20 pt page scaffold as every other tab
        // (previously this tab used its own 16 pt padding, drifting the
        // margins); the card + footer now sit exactly on the page
        // insets and the page scrolls when the window is short.
        SettingsPage {
            Text(L10n.t("constants.intro", language: language))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // The single card: column captions + the scrollable rows.
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
            .settingsCard()

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
        case .scalar(let v):
            return formatDisplayValue(v, decimalPlaces: model.settings.decimalPlaces,
                                      context: model.numberContext)
        case .money(let v, let code):
            return formatMoney(v, code: code, context: model.numberContext)
        }
    }
}

// MARK: - Numbers tab (r73 content, r74 layout)

/// The r73 Numbers tab on the shared r74 single column: the region
/// group (picker, caption, ONE live example block) and the three
/// independent toggle rows. The old duplicated Example card is gone —
/// the samples are rendered through the app's ONE number context, the
/// same values the notebook itself shows. Changing the region never
/// reinterprets silently: the owner evaluates the selected sheet under
/// both contexts first and only opens the confirmation dialog when an
/// answer actually changes.
private struct NumbersSettingsTab: View {
    @Bindable var model: AppModel

    private var language: AppLanguage { model.settings.language }
    private var systemLocale: Locale { Locale.current }

    /// Live samples rendered through the active context: the shared
    /// display of 1234.567 at the Settings decimals, the compact
    /// preview of 100000 (compact forced on for the preview), and the
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

    /// The ONE live example block (the duplicate Example card was
    /// removed in r74): caption + value pairs through the active
    /// context.
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
        return SettingsPage {
            SettingsGroup(title: L10n.t("numbers.region", language: language)) {
                SettingsRow(
                    title: L10n.t("numbers.regionLabel", language: language),
                    detail: L10n.t("numbers.regionCap", language: language)
                ) {
                    regionPicker
                }
                sampleGrid
            }
            SettingsGroup(title: L10n.t("autoInsert", language: language)) {
                SettingsRow(
                    title: L10n.t("numbers.convertPaste", language: language),
                    detail: L10n.t("numbers.convertPasteCap", language: language)
                ) {
                    Toggle("", isOn: regionalBinding(\.convertForeignOnPaste))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
                SettingsRow(
                    title: L10n.t("numbers.grouping", language: language),
                    detail: L10n.t("numbers.groupingCap", language: language)
                ) {
                    Toggle("", isOn: regionalBinding(\.showThousandsSeparator))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
                SettingsRow(
                    title: L10n.t("numbers.compact", language: language),
                    detail: L10n.t("numbers.compactCap", language: language)
                ) {
                    Toggle("", isOn: regionalBinding(\.useCompactNotation))
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
            }
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

// MARK: - Styling tab

/// The r21 Styling tab on the shared r74 single column: font size,
/// font design and one finite color choice per notebook role as
/// aligned label/control rows (every picker shows a real sRGB swatch
/// plus the localized name). Below, the live preview — ONE clearly
/// labelled area sharing the page width. It resolves colors/fonts
/// through the SAME palette resolver as the real editor (no duplicated
/// RGB values anywhere) and keeps the REAL notebook font size
/// (including 30 pt, never shrunk); the page scrolls instead of the
/// window enlarging.
private struct StylingSettingsTab: View {
    @Bindable var model: AppModel

    private var language: AppLanguage { model.settings.language }

    private var styling: StylingPreferences { model.settings.styling }

    private func setRole(_ keyPath: WritableKeyPath<StylingPreferences, RoleColorChoice>,
                         to value: RoleColorChoice) {
        model.settings.styling[keyPath: keyPath] = value
        model.persist()
    }

    var body: some View {
        // r74: controls in ONE readable column (label left, native
        // control right); the live preview is a single full-width area
        // below, never a fixed narrow second column.
        let language = self.language
        return SettingsPage {
            SettingsGroup {
                controlRow(L10n.t("styling.fontsize", language: language)) {
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

                controlRow(L10n.t("styling.font", language: language)) {
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

                Divider().padding(.vertical, 4)

                roleRow("styling.role.numbers", keyPath: \.numbers)
                roleRow("styling.role.operators", keyPath: \.operators)
                roleRow("styling.role.variables", keyPath: \.variables)
                roleRow("styling.role.units", keyPath: \.units)
                roleRow("styling.role.specifiers", keyPath: \.specifiers)
                roleRow("styling.role.headings", keyPath: \.headings)
                roleRow("styling.role.comments", keyPath: \.comments)
                roleRow("styling.role.labels", keyPath: \.labels)
            }

            SettingsGroup(title: L10n.t("styling.preview", language: language)) {
                StylingPreview(
                    fontSize: model.settings.fontSize,
                    lineHeight: model.settings.lineHeight,
                    styling: styling
                )
            }
        }
    }

    private var fontSizeLabel: String {
        fontSizeOptions.first(where: { $0.key == model.settings.fontSizeKey })?.label
            ?? String(Int(model.settings.fontSize))
    }

    /// One aligned label + trailing popup row (r74 row rhythm).
    private func controlRow(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 13))
            Spacer(minLength: 12)
            control()
        }
    }

    /// One role row: localized role label on the left, a menu with a
    /// real sRGB swatch + localized color name on the right.
    private func roleRow(_ labelKey: String,
                         keyPath: WritableKeyPath<StylingPreferences, RoleColorChoice>) -> some View {
        HStack(spacing: 16) {
            Text(L10n.t(labelKey, language: language))
                .font(.system(size: 13))
            Spacer(minLength: 12)
            Menu {
                ForEach(RoleColorChoice.allCases, id: \.self) { choice in
                    Button {
                        setRole(keyPath, to: choice)
                    } label: {
                        HStack(spacing: 7) {
                            swatch(choice)
                            Text(L10n.t("styling.color.\(choice.rawValue)",
                                        language: language))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    swatch(styling[keyPath: keyPath])
                    Text(L10n.t("styling.color.\(styling[keyPath: keyPath].rawValue)",
                                language: language))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                // r75: trailing-aligned with a cap — a long localized
                // color name truncates instead of overflowing the page.
                .frame(maxWidth: 180, alignment: .trailing)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    /// Deterministic sRGB swatch circle: same resolver the editor and
    /// preview use, so the picker always shows the true rendered color.
    private func swatch(_ choice: RoleColorChoice) -> some View {
        Circle()
            .fill(Color(nsColor: NotebookPalette.color(for: choice)))
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
/// resolver as the editor. The only illustration-only content is the
/// `0.5 as fraction` row (the engine has no fraction feature — the
/// screenshot shows the intended look, so the preview demonstrates it
/// with explicit role overrides; all other lines are genuine engine
/// banding).
private struct StylingPreview: View {
    let fontSize: Double
    let lineHeight: Double
    let styling: StylingPreferences

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
    /// regular on the selected
    /// size/design; `// ` comments semibold in the comments color; hash
    /// headings heavy (gray marker, headings-color body); every
    /// classified span via the palette resolver.
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
                                                   decimalPlaces: 10)
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
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

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
        let view = NSView()
        Task { @MainActor in
            guard let window = view.window else { return }
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
            // SwiftUI re-asserts its own style mask during scene
            // reconfiguration and drops the resizable bit; hold it. The
            // same first-open moment is where an AppKit frame restore
            // (stale, from an older wider build) lands AFTER makeNSView,
            // so the one-time out-of-range snap lives here, not only in
            // makeNSView/updateNSView.
            context.coordinator.observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        guard let window = view.window else { return }
                        if !window.styleMask.contains(.resizable) {
                            window.styleMask.insert(.resizable)
                        }
                        self?.snapIfOutOfRange(window)
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
