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
                          systemImage: "gearshape")
                }
            StylingSettingsTab(model: model)
                .tabItem {
                    Label(L10n.t("settings.styling", language: model.settings.language),
                          systemImage: "paintbrush")
                }
        }
        .frame(minWidth: 880, idealWidth: 920, maxWidth: 1000,
               minHeight: 620, idealHeight: 700, maxHeight: 800)
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

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.t("round", language: model.settings.language))
                                .font(Design.labelSmall).foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { model.settings.decimalPlaces },
                                set: { model.settings.decimalPlaces = $0; model.persist() }
                            )) {
                                ForEach([2, 3, 4, 5, 6, 7, 8, 10], id: \.self) { v in
                                    Text("\(v)").tag(v)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // r19: the six configurable input helpers.
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            inputRow("opPad", captionKey: "opPadCap", value: Binding(
                                get: { model.settings.input.padOperators },
                                set: { model.settings.input.padOperators = $0; model.persist() }
                            ))
                            inputRow("opStar", captionKey: "opStarCap", value: Binding(
                                get: { model.settings.input.replaceAsterisk },
                                set: { model.settings.input.replaceAsterisk = $0; model.persist() }
                            ))
                            inputRow("opBacktick", captionKey: "opBacktickCap", value: Binding(
                                get: { model.settings.input.replaceBacktick },
                                set: { model.settings.input.replaceBacktick = $0; model.persist() }
                            ))
                            inputRow("opQuick", captionKey: "opQuickCap", value: Binding(
                                get: { model.settings.input.quickOperators },
                                set: { model.settings.input.quickOperators = $0; model.persist() }
                            ))
                        }
                    } label: {
                        Text(L10n.t("operators", language: model.settings.language))
                            .font(.system(size: 13, weight: .semibold))
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            inputRow("autoGroup", captionKey: "autoGroupCap", value: Binding(
                                get: { model.settings.input.groupNumbers },
                                set: { model.settings.input.groupNumbers = $0; model.persist() }
                            ))
                            inputRow("autoPrev", captionKey: "autoPrevCap", value: Binding(
                                get: { model.settings.input.insertPreviousAnswer },
                                set: { model.settings.input.insertPreviousAnswer = $0; model.persist() }
                            ))
                        }
                    } label: {
                        Text(L10n.t("autoInsert", language: model.settings.language))
                            .font(.system(size: 13, weight: .semibold))
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.t("sheetname", language: model.settings.language))
                                .font(Design.labelSmall).foregroundStyle(.secondary)
                            TextField("Sheet", text: Binding(
                                get: { model.settings.sheetName },
                                set: { model.settings.sheetName = $0; model.persist() }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(L10n.t("linenumber", language: model.settings.language), isOn: Binding(
                                get: { model.settings.lineNumbers },
                                set: { model.settings.lineNumbers = $0; model.persist() }
                            ))
                            Picker(L10n.t("language", language: model.settings.language), selection: Binding(
                                get: { model.settings.language },
                                set: { model.settings.language = $0; model.persist() }
                            )) {
                                ForEach(AppLanguage.allCases, id: \.self) { lang in
                                    Text(lang.rawValue.uppercased()).tag(lang)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    // Currency rate attribution: the bundled fiat catalog is
                    // converted with the open provider table fetched at
                    // launch (no API key required).
                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Currency rates")
                                .font(Design.labelSmall).foregroundStyle(.secondary)
                            Link("open.er-api.com",
                                 destination: URL(string: "https://open.er-api.com")!)
                                .font(.callout)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(24)
                // The general column keeps the old comfortable reading
                // width inside the wider tab window instead of stretching
                // full-bleed; nothing clips at any window size.
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
        }
        .padding(20)
    }

    /// One checkbox row with a muted example caption under the label
    /// (the r19 input-helper sections).
    private func inputRow(_ labelKey: String, captionKey: String, value: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(L10n.t(labelKey, language: model.settings.language), isOn: value)
            Text(L10n.t(captionKey, language: model.settings.language))
                .font(Design.labelSmall)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)
        }
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
        HStack(spacing: 0) {
            // Left column: aligned control rows.
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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
                                .frame(minWidth: 74, alignment: .trailing)
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
                                .frame(minWidth: 120, alignment: .trailing)
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
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .frame(width: 360)

            Divider()

            // Right column: live preview.
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.t("styling.preview", language: language))
                    .font(Design.labelSmall)
                    .foregroundStyle(.secondary)
                StylingPreview(
                    fontSize: model.settings.fontSize,
                    lineHeight: model.settings.lineHeight,
                    styling: styling
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var fontSizeLabel: String {
        fontSizeOptions.first(where: { $0.key == model.settings.fontSizeKey })?.label
            ?? String(Int(model.settings.fontSize))
    }

    /// One aligned label + trailing popup row.
    private func controlRow(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            control()
        }
    }

    /// One role row: localized role label on the left, a menu with a
    /// real sRGB swatch + localized color name on the right.
    private func roleRow(_ labelKey: String,
                         keyPath: WritableKeyPath<StylingPreferences, RoleColorChoice>) -> some View {
        HStack(spacing: 12) {
            Text(L10n.t(labelKey, language: language))
                .font(.system(size: 13))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
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
                HStack(spacing: 7) {
                    swatch(styling[keyPath: keyPath])
                    Text(L10n.t("styling.color.\(styling[keyPath: keyPath].rawValue)",
                                language: language))
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(minWidth: 150, alignment: .trailing)
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
            .frame(width: 11, height: 11)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            .frame(width: 170, alignment: .leading)
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
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            guard let window = view.window else { return }
            window.styleMask.insert(.resizable)
            window.minSize = NSSize(width: 884, height: 626)
            window.setContentSize(NSSize(width: 920, height: 700))
        }
        return view
    }

    /// SwiftUI re-asserts its own style mask during scene reconfiguration
    /// and drops the resizable bit; re-insert it on every update pass so
    /// the user can always resize the window between the content min and
    /// max sizes.
    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            if let window = nsView.window, !window.styleMask.contains(.resizable) {
                window.styleMask.insert(.resizable)
            }
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