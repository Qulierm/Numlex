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
        if let payload = Persistence.load() {
            sheets = payload.sheets
            selectedIndex = min(payload.selectedIndex, max(sheets.count - 1, 0))
            settings = payload.settings
        }
        if sheets.isEmpty {
            sheets = [
                Sheet(title: "Demo", content: "# Demo\n12 + 30 * 2\n45.5 * 2\n10 km to meter\nprice = 1250\nprice * 1.2", createdAt: Date(), modifiedAt: Date()),
                Sheet(title: "Sheet", content: "", createdAt: Date(), modifiedAt: Date())
            ]
            selectedIndex = 0
        }
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
        sheets[selectedIndex].content = content
        sheets[selectedIndex].modifiedAt = Date()
        persist()
    }

    func newSheet() {
        let title = "\(settings.sheetName) \(sheets.count + 1)"
        let sheet = Sheet(title: title, content: "", createdAt: Date(), modifiedAt: Date())
        sheets.insert(sheet, at: 0)
        selectedIndex = 0
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
        return SheetExport(title: s.title, content: s.content)
    }

    func importSheet(from url: URL) {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONDecoder().decode(SheetExport.self, from: data) else { return }
        // also support legacy with createdAt?
        let sheet = Sheet(title: obj.title, content: obj.content, createdAt: Date(), modifiedAt: Date())
        sheets.append(sheet)
        selectedIndex = sheets.count - 1
        persist()
    }

    func importSheet(data: Data) {
        guard let obj = try? JSONDecoder().decode(SheetExport.self, from: data) else { return }
        let sheet = Sheet(title: obj.title, content: obj.content, createdAt: Date(), modifiedAt: Date())
        sheets.append(sheet)
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
