import AppKit
import NumlexCore
import SwiftUI

enum ExportDialogMode: Equatable {
    case pdf
    case print

    var titleKey: String {
        self == .pdf ? "export.title.pdf" : "export.title.print"
    }
    var confirmKey: String {
        self == .pdf ? "export.confirmPDF" : "export.confirmPrint"
    }
}

/// The native options sheet for both PDF export and printing. It holds
/// only session state: the options never enter AppSettings, the store
/// or `.nlx`. The action is disabled while the line range is invalid or
/// the chosen range + filters leave nothing to print.
struct ExportDialogView: View {
    let mode: ExportDialogMode
    let context: ExportPresentationContext
    let language: AppLanguage
    @Binding var options: ExportOptions
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private enum RangeMode: String, CaseIterable {
        case all, range
    }

    @State private var rangeMode: RangeMode
    @State private var fromLine: Int
    @State private var toLine: Int

    init(mode: ExportDialogMode,
         context: ExportPresentationContext,
         language: AppLanguage,
         options: Binding<ExportOptions>,
         onCancel: @escaping () -> Void,
         onConfirm: @escaping () -> Void) {
        self.mode = mode
        self.context = context
        self.language = language
        self._options = options
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        switch options.wrappedValue.range {
        case .all:
            _rangeMode = State(initialValue: .all)
            _fromLine = State(initialValue: 1)
            _toLine = State(initialValue: max(context.lineCount, 1))
        case .lines(let from, let to):
            _rangeMode = State(initialValue: .range)
            _fromLine = State(initialValue: from)
            _toLine = State(initialValue: to)
        }
    }

    private func t(_ key: String) -> String {
        L10n.t(key, language: language)
    }

    private var rangeValid: Bool {
        ExportSnapshotBuilder.validate(range: options.range,
                                       lineCount: context.lineCount)
    }

    private var printableCount: Int {
        guard rangeValid else { return 0 }
        return ExportSnapshotBuilder.printableRowCount(context: context,
                                                       options: options)
    }

    private var canConfirm: Bool { rangeValid && printableCount > 0 }

    private var validationMessage: String? {
        if !rangeValid {
            return String(format: t("export.invalidRange"), context.lineCount)
        }
        if printableCount == 0 {
            return t("export.emptyRange")
        }
        return nil
    }

    private func syncRange() {
        options.range = rangeMode == .all
            ? .all
            : .lines(from: fromLine, to: toLine)
    }

    private var fromBinding: Binding<Int> {
        Binding(get: { fromLine }, set: { fromLine = $0; syncRange() })
    }
    private var toBinding: Binding<Int> {
        Binding(get: { toLine }, set: { toLine = $0; syncRange() })
    }

    private func clampFields() {
        let count = max(context.lineCount, 1)
        fromLine = min(max(fromLine, 1), count)
        toLine = min(max(toLine, 1), count)
        options = options.clamped(toLineCount: context.lineCount)
        syncRange()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t(mode.titleKey))
                .font(.headline)

            // Font family + face + size.
            VStack(alignment: .leading, spacing: 8) {
                Text(t("export.font"))
                    .font(.subheadline).foregroundStyle(.secondary)
                Picker(t("export.fontFamily"), selection: $options.fontFamily) {
                    Text("Notebook").tag(String?.none)
                    ForEach(ExportFontCatalog.shared.families, id: \.self) { family in
                        Text(family).tag(String?.some(family))
                    }
                }
                .accessibilityLabel(t("export.fontFamily"))
                Picker(t("export.fontFace"),
                       selection: Binding(
                           get: { options.fontFace },
                           set: { options.fontFace = $0 })) {
                    Text("Regular").tag(String?.none)
                    ForEach(ExportFontCatalog.shared.faces(for: options.fontFamily)) { face in
                        Text(face.label).tag(String?.some(face.name))
                    }
                }
                .disabled(options.fontFamily == nil)
                .accessibilityLabel(t("export.fontFace"))
                HStack {
                    Text(t("export.size"))
                    Slider(value: $options.fontPointSize, in: 8...36, step: 1)
                        .accessibilityLabel(t("export.size"))
                        .accessibilityValue("\(Int(options.fontPointSize)) pt")
                    Text("\(Int(options.fontPointSize)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }

            Divider()

            // What to include.
            VStack(alignment: .leading, spacing: 8) {
                Toggle(t("export.syntax"), isOn: $options.syntaxHighlighting)
                Toggle(t("export.lineNumbers"), isOn: $options.lineNumbers)
                Toggle(t("export.total"), isOn: $options.showTotal)
                Toggle(t("export.hideComments"), isOn: $options.hideComments)
                Toggle(t("export.hideHash"), isOn: $options.hideHashMarker)
            }

            Divider()

            // Line range.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(t("export.lines"))
                    Picker("", selection: $rangeMode) {
                        Text(t("export.linesAll")).tag(RangeMode.all)
                        Text(t("export.linesRange")).tag(RangeMode.range)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 180)
                    .onChange(of: rangeMode) { _, _ in
                        clampFields()
                    }
                }
                if rangeMode == .range {
                    HStack {
                        Text(t("export.from"))
                        TextField("", value: fromBinding, format: .number)
                            .frame(width: 60)
                            .accessibilityLabel(t("export.from"))
                        Text(t("export.to"))
                        TextField("", value: toBinding, format: .number)
                            .frame(width: 60)
                            .accessibilityLabel(t("export.to"))
                    }
                }
                if let validationMessage {
                    Text(validationMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button(t("export.cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(t(mode.confirmKey), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: clampFields)
        .onChange(of: options.fontFamily) { _, _ in
            // A new family invalidates the previous face; the resolver
            // falls back to the family's first face.
            options.fontFace = nil
        }
    }
}
