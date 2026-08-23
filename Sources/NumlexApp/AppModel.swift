import Foundation
import NumlexCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let nlx = UTType(filenameExtension: "nlx") ?? .json
}

@Observable
final class AppModel {
    var sheets: [Sheet] = []
    var selectedIndex: Int = 0
    var settings: AppSettings = .defaults
    var rates: Rates = Rates()
    var isRatesLoaded = false

    init() {
        var migrated = false
        if let payload = Persistence.load() {
            // Legacy stores: canonicalize the mathematical lines of every
            // sheet once (visible `*` becomes `×` in the stored content),
            // then refresh automatic titles so they reflect the canonical
            // text. Manual titles are untouched by `retitled`.
            sheets = payload.sheets.map { sheet in
                let result = Sheet.canonicalized(sheet)
                if result.changed { migrated = true }
                return result.sheet
            }
            selectedIndex = min(payload.selectedIndex, max(sheets.count - 1, 0))
            settings = payload.settings
        }
        if sheets.isEmpty {
            sheets = [
                Sheet(title: "Demo", content: "# Demo\n12 + 30 × 2\n45.5 × 2\n10 km to meter\nprice = 1250\nprice × 1.2",
                      createdAt: Date(), modifiedAt: Date(), isTitleCustom: true),
                Sheet(title: "Sheet", content: "", createdAt: Date(), modifiedAt: Date())
            ]
            selectedIndex = 0
        }
        // Persist the migration exactly once, after the whole state is
        // initialized (calling persist mid-init would touch a half-built
        // model); unchanged stores are never rewritten.
        if migrated { persist() }
        // rates loaded on appear
        // Task { await loadRates() } moved to view onAppear
        _ = 0
    }

    var selectedSheet: Sheet? {
        guard sheets.indices.contains(selectedIndex) else { return nil }
        return sheets[selectedIndex]
    }

    func updateContent(_ content: String) {
        guard sheets.indices.contains(selectedIndex) else { return }
        var sheet = sheets[selectedIndex]
        sheet.content = content
        sheet.modifiedAt = Date()
        // Title follows the first calculation until the user renames it.
        sheets[selectedIndex] = Sheet.retitled(sheet, content: content)
        persist()
    }

    func newSheet() {
        let seed = "\(settings.sheetName) \(sheets.count + 1)"
        let sheet = Sheet(title: seed, content: "", createdAt: Date(), modifiedAt: Date())
        sheets.insert(sheet, at: 0)
        selectedIndex = 0
        persist()
    }

    func renameSheet(id: UUID, to newTitle: String) {
        guard let idx = sheets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Empty rename falls back to the automatic title.
            sheets[idx].isTitleCustom = false
            sheets[idx].title = Sheet.autoTitle(from: sheets[idx].content, fallback: sheets[idx].titleSeed)
        } else {
            sheets[idx].title = trimmed
            sheets[idx].isTitleCustom = true
        }
        persist()
    }

    func deleteSheet(at index: Int) {
        guard sheets.indices.contains(index) else { return }
        if sheets.count == 1 {
            sheets[0] = Sheet(title: "\(settings.sheetName) 1", content: "", createdAt: Date(), modifiedAt: Date())
            selectedIndex = 0
        } else {
            sheets.remove(at: index)
            if index < selectedIndex { selectedIndex -= 1 }
            else if index == selectedIndex { selectedIndex = min(selectedIndex, sheets.count - 1) }
        }
        persist()
    }

    func select(index: Int) {
        guard sheets.indices.contains(index) else { return }
        selectedIndex = index
        persist()
    }

    func exportCurrent() -> SheetExport? {
        guard let s = selectedSheet else { return nil }
        return SheetExport(title: s.title, content: s.content, isTitleCustom: s.isTitleCustom)
    }

    private func makeImportedSheet(_ obj: SheetExport) -> Sheet {
        // Files exported before the naming feature decode with a nil flag;
        // then meaningful names stay custom and generic ones stay automatic.
        let custom = obj.isTitleCustom ?? !Sheet.isGenericTitle(obj.title)
        // Imported math lines are canonicalized too; prose, comments,
        // titles and conversions come back byte-identical.
        let content = NotebookFormatting.canonicalDocument(obj.content)
        return Sheet(title: obj.title, content: content,
                     createdAt: Date(), modifiedAt: Date(), isTitleCustom: custom)
    }

    func importSheet(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONDecoder().decode(SheetExport.self, from: data) else { return }
        sheets.append(makeImportedSheet(obj))
        selectedIndex = sheets.count - 1
        persist()
    }

    func importSheet(data: Data) {
        guard let obj = try? JSONDecoder().decode(SheetExport.self, from: data) else { return }
        sheets.append(makeImportedSheet(obj))
        selectedIndex = sheets.count - 1
        persist()
    }

    func persist() {
        let payload = StorePayload(sheets: sheets, selectedIndex: selectedIndex, settings: settings)
        Persistence.save(payload)
    }

    @MainActor
    func loadRates() async {
        let r = await RatesService.shared.load()
        rates = r
        isRatesLoaded = true
    }

    func setRates(_ r: Rates) async {
        await RatesService.shared.set(r)
        rates = r
    }
}
