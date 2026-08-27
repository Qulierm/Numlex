import AppKit
import SwiftUI
import NumlexCore

/// The Settings scene content (r21): one native macOS `TabView` with
/// exactly two tabs — General (all non-style settings, six input
/// helpers, language/line numbers, sheet title, rate attribution) and
/// Styling (font size/family plus one finite color picker per notebook
/// role, with a live preview). One restrained outer Liquid Glass surface
/// per tab with native GroupBox sections; no in-content "Settings"
/// heading (the system titlebar carries the single localized window
/// title), no nested cards, no fake tabs.
struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsTab(model: model)
                .tabItem {
                    Label(L10n.t("settings.general", language: model.settings.language),
                          systemImage: "gear")
                }
            StylingSettingsTab(model: model)
                .tabItem {
                    Label(L10n.t("settings.styling", language: model.settings.language),
                          systemImage: "paintbrush")
                }
        }
        .frame(minWidth: 690, idealWidth: 720, maxWidth: 820,
               minHeight: 510, idealHeight: 540, maxHeight: 640)
        // Window chrome the scene APIs cannot express: resizability and
        // the designed min/content sizes. The title stays the native tab
        // title (General/Styling — the System Settings convention); the
        // configurator never fights it.
        .background(SettingsWindowConfigurator())
    }
}

// MARK: - General tab

private struct GeneralSettingsTab: View {
    @Bindable var model: AppModel

    private var language: AppLanguage { model.settings.language }

    /// One persisted boolean binding (every control writes through
    /// model.persist(), exactly like the previous GroupBox rows).
    private func boolBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { model.settings[keyPath: keyPath] = $0; model.persist() }
        )
    }

    var body: some View {
        // r23 compact: NO scroll view — a fixed two-column layout that
        // shows every control at once in the 720x540 window (and at the
        // 690x510 minimum). Left: rounding + operators. Right:
        // automatic insertions, line numbers + language, currency
        // attribution. Every surface is exactly one glass card; section
        // titles sit outside their cards. (The Sheet title control was
        // removed from the UI in r23; AppSettings.sheetName stays in the
        // model for decoding and new-sheet naming.)
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                // Rounding numbers: 12 pt label + segmented 2...10.
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.t("round", language: language))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { model.settings.decimalPlaces },
                        set: { model.settings.decimalPlaces = $0; model.persist() }
                    )) {
                        ForEach(2...10, id: \.self) { v in
                            Text("\(v)").tag(v)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .settingsCard()

                // Operators: external title + one card with the four
                // input helpers and their example captions.
                SettingsSection(title: L10n.t("operators", language: language)) {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingToggle(
                            title: L10n.t("opPad", language: language),
                            description: L10n.t("opPadCap", language: language),
                            isOn: boolBinding(\AppSettings.input.padOperators)
                        )
                        SettingToggle(
                            title: L10n.t("opStar", language: language),
                            description: L10n.t("opStarCap", language: language),
                            isOn: boolBinding(\AppSettings.input.replaceAsterisk)
                        )
                        SettingToggle(
                            title: L10n.t("opBacktick", language: language),
                            description: L10n.t("opBacktickCap", language: language),
                            isOn: boolBinding(\AppSettings.input.replaceBacktick)
                        )
                        SettingToggle(
                            title: L10n.t("opQuick", language: language),
                            description: L10n.t("opQuickCap", language: language),
                            isOn: boolBinding(\AppSettings.input.quickOperators)
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 14) {
                // Automatic insertions: external title + one card.
                SettingsSection(title: L10n.t("autoInsert", language: language)) {
                    VStack(alignment: .leading, spacing: 10) {
                        SettingToggle(
                            title: L10n.t("autoGroup", language: language),
                            description: L10n.t("autoGroupCap", language: language),
                            isOn: boolBinding(\AppSettings.input.groupNumbers)
                        )
                        SettingToggle(
                            title: L10n.t("autoPrev", language: language),
                            description: L10n.t("autoPrevCap", language: language),
                            isOn: boolBinding(\AppSettings.input.insertPreviousAnswer)
                        )
                    }
                }

                // Line numbers + interface language: one card.
                VStack(alignment: .leading, spacing: 10) {
                    SettingToggle(
                        title: L10n.t("linenumber", language: language),
                        description: nil,
                        isOn: boolBinding(\AppSettings.lineNumbers)
                    )
                    HStack(spacing: 8) {
                        Text(L10n.t("language", language: language))
                            .font(.system(size: 12, weight: .medium))
                        Spacer(minLength: 8)
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
                        .frame(width: 84)
                    }
                }
                .settingsCard()

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
                .settingsCard()
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Card components (r23)

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

/// An external section title above its single card: 13 pt semibold
/// with 8 pt leading padding and 6 pt spacing to the content.
private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 8)
            content
                .settingsCard()
        }
    }
}

/// One checkbox row: top-aligned checkbox, 12 pt medium title and an
/// optional 10 pt secondary description (2 pt spacing).
private struct SettingToggle: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.checkbox)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if let description {
                    Text(description)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Styling tab

/// The r21 Styling tab: a screenshot-like two-column layout. Left column
/// — aligned rows for font size (the single existing size key), font
/// family (finite native system designs) and one finite color choice per
/// notebook role; every picker shows a real sRGB swatch plus the
/// localized name. Right column — a live preview of the notebook that
/// resolves colors/fonts through the SAME palette resolver as the real
/// editor (no duplicated RGB values anywhere).
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
        // r23 compact: NO scroll view — the font size/family rows and all
        // eight role rows are a fixed compact column (8 pt rhythm, 14 pt
        // padding, 11 pt labels) that fits the 720x540 window at once.
        // The live preview keeps the REAL notebook font size (including
        // 30 pt) and its answer strip hugs its content, so the preview
        // fits by width-sharing instead of shrinking its semantic font.
        HStack(spacing: 0) {
            // Left column: aligned control rows.
            VStack(alignment: .leading, spacing: 8) {
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
                                .font(.system(size: 11, weight: .medium))
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
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .frame(minWidth: 90, alignment: .trailing)
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

                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(width: 272)

            Divider()

            // Right column: live preview.
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("styling.preview", language: language))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                StylingPreview(
                    fontSize: model.settings.fontSize,
                    lineHeight: model.settings.lineHeight,
                    styling: styling
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var fontSizeLabel: String {
        fontSizeOptions.first(where: { $0.key == model.settings.fontSizeKey })?.label
            ?? String(Int(model.settings.fontSize))
    }

    /// One aligned label + trailing popup row.
    private func controlRow(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
            Spacer(minLength: 6)
            control()
        }
    }

    /// One role row: localized role label on the left, a menu with a
    /// real sRGB swatch + localized color name on the right.
    private func roleRow(_ labelKey: String,
                         keyPath: WritableKeyPath<StylingPreferences, RoleColorChoice>) -> some View {
        HStack(spacing: 8) {
            Text(L10n.t(labelKey, language: language))
                .font(.system(size: 11))
                .foregroundStyle(.primary)
            Spacer(minLength: 6)
            Menu {
                ForEach(RoleColorChoice.allCases, id: \.self) { choice in
                    Button {
                        setRole(keyPath, to: choice)
                    } label: {
                        HStack(spacing: 7) {
                            swatch(choice)
                            Text(L10n.t("styling.color.\(choice.rawValue)", language: language))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    swatch(styling[keyPath: keyPath])
                    Text(L10n.t("styling.color.\(styling[keyPath: keyPath].rawValue)",
                                language: language))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .frame(minWidth: 112, alignment: .trailing)
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

/// The notebook preview: a dark editor area (the app's real editor
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
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .background(Color(nsColor: .textBackgroundColor))

            // Answer strip.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Group {
                        if let answer = row.answer {
                            Text(answer)
                                .font(palette.swiftUIFont(fontSize))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        } else {
                            Color.clear
                        }
                    }
                    .frame(height: rowHeight, alignment: .leading)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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
    /// row's illustrative overrides): base white regular on the selected
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

/// Configures the native Settings scene window: resizability and the
/// designed content size/minimum (the swiftUI frame drives the max). The
/// title is owned by the native tab view (the active tab's localized
/// name), matching the System Settings convention — exactly one settings
/// window, exactly one title, no duplicates.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    @MainActor
    final class Coordinator {
        var observers: [NSObjectProtocol] = []
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            // The root .frame on the TabView gives the hosting view the
            // designed size range (690x510 ... 820x640); the NSWindow
            // min/max mirror it so the window opens at 720x540.
            window.minSize = NSSize(width: 690, height: 518)
            window.maxSize = NSSize(width: 820, height: 648)
            window.setContentSize(NSSize(width: 720, height: 540))
            // SwiftUI re-asserts its own style mask during scene
            // reconfiguration and drops the resizable bit; hold it.
            context.coordinator.observers.append(
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
                ) { _ in
                    Task { @MainActor in
                        if let window = view.window, !window.styleMask.contains(.resizable) {
                            window.styleMask.insert(.resizable)
                        }
                    }
                }
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            if let window = nsView.window, !window.styleMask.contains(.resizable) {
                window.styleMask.insert(.resizable)
            }
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