import SwiftUI
import NumlexCore

/// The Settings scene content. One restrained outer Liquid Glass surface
/// with native GroupBox sections; no in-content "Settings" heading (the
/// system titlebar already carries the single localized window title),
/// no fixed 420/480 nested widths, no glass card nested in a glass card.
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
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
                                ForEach([2,3,4,5,6,7,8,10], id: \.self) { v in
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
                            Text(L10n.t("fontsize", language: model.settings.language))
                                .font(Design.labelSmall).foregroundStyle(.secondary)
                            Picker("", selection: Binding(
                                get: { model.settings.fontSizeKey },
                                set: { model.settings.fontSizeKey = $0; model.persist() }
                            )) {
                                ForEach(fontSizeOptions, id: \.key) { opt in
                                    Text(opt.label).tag(opt.key)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
        .padding(20)
        .background(SettingsWindowConfigurator(title: L10n.t("settings", language: model.settings.language)))
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 760,
               minHeight: 600, idealHeight: 700, maxHeight: 860)
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

/// Configures the native Settings scene window exactly once per language:
/// the single localized title (replacing the default "Numlex Settings"),
/// resizability, and the designed content size. The title is re-asserted
/// only when it drifts (language change / scene re-render), never on every
/// update pass; the content size is set once in makeNSView.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            guard let window = view.window else { return }
            window.title = title
            window.styleMask.insert(.resizable)
            window.setContentSize(NSSize(width: 640, height: 700))
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            guard let window = nsView.window, window.title != title else { return }
            window.title = title
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
