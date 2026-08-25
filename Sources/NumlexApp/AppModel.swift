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
                var s = Sheet.canonicalized(sheet).sheet
                // Defensive: a corrupted payload must never carry dead
                // references or a stale line-ID table.
                s.references = Sheet.sanitizeReferences(s.references, in: s.content)
                if s.lineIDs.count != s.logicalLineCount {
                    s.lineIDs = (0..<s.logicalLineCount).map { _ in UUID() }
                }
                if s.lineIDs.count != s.logicalLineCount || !s.references.isEmpty { migrated = true }
                return s
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

    /// User edit of the selected sheet. The announced edit (range +
    /// replacement, nil when unknown) drives the pure line-identity
    /// reconciliation: logical line IDs and token marker positions are
    /// carried over exactly, the canonical format pass included.
    func updateContent(_ content: String, edit: NotebookEdit?) {
        guard sheets.indices.contains(selectedIndex) else { return }
        var sheet = sheets[selectedIndex]
        let reconciled = LineIdentity.reconcile(
            oldContent: sheet.content,
            oldLineIDs: sheet.lineIDs,
            oldReferences: sheet.references,
            newContent: content,
            edit: edit
        )
        sheet.content = content
        sheet.lineIDs = reconciled.lineIDs
        sheet.references = reconciled.references
        sheet.modifiedAt = Date()
        // Title follows the first calculation until the user renames it.
        sheets[selectedIndex] = Sheet.retitled(sheet, content: content)
        persist()
    }

    /// Registers references born from an internal paste; the editor has
    /// already derived each marker's final UTF-16 location.
    func addReferences(_ refs: [AnswerReference]) {
        guard sheets.indices.contains(selectedIndex) else { return }
        var sheet = sheets[selectedIndex]
        var all = sheet.references
        all.append(contentsOf: refs)
        sheet.references = Sheet.sanitizeReferences(all, in: sheet.content)
        sheets[selectedIndex] = sheet
        persist()
    }

    /// Double-click on a successful answer: append ONE token on its own
    /// new final logical line — occupying an existing trailing blank
    /// line when present, otherwise adding a newline first. The token
    /// references the source line by STABLE ID; `labelLine` remembers
    /// the 1-based line number for the inactive `Line N` label. The caret
    /// lands right after the token.
    func insertToken(sourceLineIndex: Int) {
        guard sheets.indices.contains(selectedIndex) else { return }
        var sheet = sheets[selectedIndex]
        guard sheet.lineIDs.indices.contains(sourceLineIndex) else { return }
        let content = sheet.content
        var newContent: String
        var lineIDs = sheet.lineIDs
        if content.isEmpty || content.hasSuffix("\n") {
            // The final logical line is blank: it becomes the token line.
            newContent = content + String(answerTokenMarker)
        } else {
            newContent = content + "\n" + String(answerTokenMarker)
            lineIDs.append(UUID())
        }
        let location = (newContent as NSString).length - 1
        var refs = sheet.references
        refs.append(AnswerReference(
            sourceLineID: sheet.lineIDs[sourceLineIndex],
            labelLine: sourceLineIndex + 1,
            location: location
        ))
        sheet.content = newContent
        sheet.lineIDs = lineIDs
        sheet.references = Sheet.sanitizeReferences(refs, in: newContent)
        sheet.modifiedAt = Date()
        sheets[selectedIndex] = Sheet.retitled(sheet, content: newContent)
        persist()
        focusSheetID = sheet.id
        focusCaret = location + 1
    }

    /// One-shot keyboard-focus request for a freshly created sheet.
    /// Transient on purpose: it is never part of the persisted payload,
    /// so relaunches and imports can never steal focus.
    var focusSheetID: Sheet.ID?
    /// UTF-16 caret position for the pending focus request (nil = 0);
    /// token insertion lands the caret right after the fresh marker.
    var focusCaret: Int?

    func newSheet() {
        let seed = "\(settings.sheetName) \(sheets.count + 1)"
        let sheet = Sheet(title: seed, content: "", createdAt: Date(), modifiedAt: Date())
        sheets.insert(sheet, at: 0)
        selectedIndex = 0
        focusSheetID = sheet.id
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

    /// Pure selection math lives in `sheetDeletionPlan` (NumlexCore, unit
    /// tested): before-selection keeps the same sheet selected,
    /// selected-deletion picks the next (previous at the end), and the
    /// sole sheet is replaced in place with a fresh empty one.
    func deleteSheet(at index: Int) {
        guard let plan = sheetDeletionPlan(count: sheets.count,
                                           deleteIndex: index,
                                           selectedIndex: selectedIndex) else { return }
        if plan.replacesSoleSheet {
            sheets[0] = Sheet(title: "\(settings.sheetName) 1", content: "",
                              createdAt: Date(), modifiedAt: Date())
            selectedIndex = 0
        } else {
            sheets.remove(at: index)
            selectedIndex = plan.selectedIndexAfter
        }
        persist()
    }

    /// App-menu “Delete Sheet”: the same deletion (and therefore the same
    /// animation) as the sidebar context menu, applied to the selection.
    func deleteSelected() {
        deleteSheet(at: selectedIndex)
    }

    func select(index: Int) {
        guard sheets.indices.contains(index) else { return }
        selectedIndex = index
        persist()
    }

    func exportCurrent() -> SheetExport? {
        guard let s = selectedSheet else { return nil }
        return SheetExport(title: s.title, content: s.content,
                           isTitleCustom: s.isTitleCustom,
                           lineIDs: s.lineIDs, references: s.references)
    }

    private func makeImportedSheet(_ obj: SheetExport) -> Sheet {
        // Files exported before the naming feature decode with a nil flag;
        // then meaningful names stay custom and generic ones stay automatic.
        let custom = obj.isTitleCustom ?? !Sheet.isGenericTitle(obj.title)
        // Imported math lines are canonicalized too; prose, comments,
        // titles and conversions come back byte-identical.
        let content = NotebookFormatting.canonicalDocument(obj.content)
        // The format pass may re-space token lines: replay its UTF-16
        // map so imported references keep pointing at real markers.
        var refs = obj.references ?? []
        if !refs.isEmpty {
            let map: [Int]
            if content != obj.content {
                map = NotebookFormatting.mapDocument(from: obj.content, to: content)
            } else {
                map = Array(0...((obj.content as NSString).length))
            }
            let ns = content as NSString
            refs = refs.compactMap { r in
                let p = map[min(max(r.location, 0), map.count - 1)]
                guard p >= 0, p < ns.length, ns.character(at: p) == answerTokenMarkerUTF16 else { return nil }
                return r.withLocation(p)
            }
        }
        var lineIDs = obj.lineIDs ?? []
        if lineIDs.count != content.components(separatedBy: "\n").count {
            lineIDs = content.components(separatedBy: "\n").map { _ in UUID() }
        }
        return Sheet(title: obj.title, content: content,
                     createdAt: Date(), modifiedAt: Date(), isTitleCustom: custom,
                     lineIDs: lineIDs, references: refs)
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
