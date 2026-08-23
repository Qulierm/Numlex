import SwiftUI
import NumlexCore
import UniformTypeIdentifiers

struct ContentView: View {
    var model: AppModel
    @State private var topLine = 0
    @State private var lineTops: [CGFloat] = []
    @State private var showImport = false
    @State private var showExport = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            // Editor and answer column share one column (and therefore one
            // top inset), which keeps their rows aligned 1:1.
            HStack(spacing: 0) {
                GeometryReader { geo in
                    let settings = model.settings
                    let sheet = model.selectedSheet
                    let binding = Binding<String>(
                        get: { sheet?.content ?? "" },
                        set: { model.updateContent($0) }
                    )
                    NotebookEditor(
                        text: binding,
                        placeholder: L10n.t("enter", language: settings.language),
                        fontSize: settings.fontSize,
                        lineHeight: settings.lineHeight,
                        lineNumbers: settings.lineNumbers,
                        onScroll: { line in topLine = line },
                        onLayout: { tops in lineTops = tops }
                    )
                    .id(sheet?.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .textBackgroundColor))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                let settings = model.settings
                let rows: [LineResult] = {
                    var vars: [String: Double] = [:]
                    // evaluateSheet accumulates variables across lines sequentially.
                    let content = model.selectedSheet?.content ?? ""
                    return evaluateSheet(content, variables: &vars, rates: model.rates, decimalPlaces: settings.decimalPlaces)
                }()
                AnswerColumnView(
                    rows: rows,
                    lineHeight: settings.lineHeight,
                    fontSize: settings.fontSize,
                    decimalPlaces: settings.decimalPlaces,
                    sumLabel: L10n.t("sumOfResults", language: settings.language),
                    topLine: topLine,
                    lineTops: lineTops
                )
            }
            .toolbar(removing: .title)
        }
        .frame(minWidth: 820, minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: .newSheet)) { _ in model.newSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .importSheet)) { _ in showImport = true }
        .onReceive(NotificationCenter.default.publisher(for: .exportSheet)) { _ in showExport = true }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.nlx, .json], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                model.importSheet(from: url)
            }
        }
        .fileExporter(isPresented: $showExport, document: NLXDocument(model: model), contentType: .nlx, defaultFilename: "\(model.selectedSheet?.title ?? "Sheet").nlx") { result in
            if case .failure(let err) = result { print("export failed \(err)") }
        }
        .onAppear {
            Task { @MainActor in await model.loadRates() }
            if let window = NSApp.keyWindow {
                window.setContentSize(NSSize(width: 1050, height: 680))
                window.minSize = NSSize(width: 820, height: 560)
                window.center()
            }
        }
    }
}

struct NLXDocument: FileDocument {
    var export: SheetExport
    static var readableContentTypes: [UTType] { [.nlx, .json] }
    init(model: AppModel) {
        if let s = model.sheets.indices.contains(model.selectedIndex) ? model.sheets[model.selectedIndex] : nil {
            export = SheetExport(title: s.title, content: s.content)
        } else {
            export = SheetExport(title: "Sheet", content: "")
        }
    }
    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let obj = try? JSONDecoder().decode(SheetExport.self, from: data) {
            export = obj
        } else {
            export = SheetExport(title: "Sheet", content: "")
        }
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(export)
        return FileWrapper(regularFileWithContents: data)
    }
}
