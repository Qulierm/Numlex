import SwiftUI
import NumlexCore

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var model: AppModel

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Text(L10n.t("settings", language: model.settings.language))
                    .font(.title3.weight(.semibold))

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

                Spacer()
            }
            .padding(20)
            .frame(width: 420)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(20)
    }
}

// For Settings scene (separate window)
struct NativeSettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        SettingsView(model: model)
            .frame(width: 480, height: 520)
    }
}
