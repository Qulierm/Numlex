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
            // r19 store migration: v1 stores get the EXACT pre-r19
            // canonicalization once (marker positions remapped through
            // the real transformation map); v2+ stores are loaded
            // byte-identical — a setting toggle or relaunch never
            // rewrites typed content again.
            settings = payload.settings
            let storeVersion = payload.version
            sheets = payload.sheets.map { sheet in
                var s = sheet
                if storeVersion < StorePayload.currentVersion {
                    let (content, map) = InputFormatting.formatDocument(
                        s.content, prefs: .legacy)
                    if content != s.content {
                        s.references = Self.remapReferences(s.references, content: content, map: map)
                        s.content = content
                        s = Sheet.retitled(s, content: content)
                        migrated = true
                    }
                }
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
        // Title follows the first calculation until the user renames it
        // (r33: a first calculation may USE a global constant).
        sheets[selectedIndex] = Sheet.retitled(sheet, content: content,
                                               constants: settings.customConstants)
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
        sheets[selectedIndex] = Sheet.retitled(sheet, content: newContent,
                                               constants: settings.customConstants)
        persist()
        focusSheetID = sheet.id
        focusCaret = location + 1
    }

    /// The "insert previous answer" input helper (r19): when the user
    /// types an operator on a fresh line, the nearest earlier
    /// answerable line becomes a live token followed by the operator.
    /// The plan is computed PURE (PreviousAnswerPlan) and applied in one
    /// atomic mutation; returns whether the keystroke was consumed.
    @discardableResult
    func insertPreviousAnswer(key: Character, at caret: Int) -> Bool {
        guard settings.input.insertPreviousAnswer else { return false }
        guard let sheet = selectedSheet else { return false }
        // The sheet's CURRENT sidecar must take part in eligibility:
        // an active token chain (`token + 1`) is answerable, a broken
        // token line never is.
        // r33: eligibility evaluates with the global constants, so a
        // constant-driven line is a valid previous answer.
        guard let plan = PreviousAnswerPlan.plan(
            content: sheet.content, lineIDs: sheet.lineIDs, caret: caret,
            op: key, rates: rates, decimalPlaces: settings.decimalPlaces,
            references: sheet.references,
            constants: settings.customConstants
        ) else { return false }
        // Honor the operator settings in the inserted text, and apply
        // the pure insertion: marker + separator + operator lands at
        // the caret, every pre-existing reference at/after the caret
        // shifts by the insertion's UTF-16 length (line IDs untouched),
        // and the fresh reference is appended before sanitizing.
        let op = (key == "*" && settings.input.replaceAsterisk) ? "×" : String(key)
        let sep = settings.input.padOperators ? " " : ""
        let applied = PreviousAnswerPlan.apply(
            plan: plan, content: sheet.content, lineIDs: sheet.lineIDs,
            references: sheet.references, operatorText: op, separator: sep)
        var s = sheet
        s.content = applied.content
        s.lineIDs = applied.lineIDs
        s.references = applied.references
        s.modifiedAt = Date()
        sheets[selectedIndex] = Sheet.retitled(s, content: s.content,
                                               constants: settings.customConstants)
        persist()
        focusSheetID = s.id
        focusCaret = applied.caret
        return true
    }

    /// Marker remap through an EXACT transformation map (the v1 store
    /// migration): a marker landing on anything but U+FFFC is dropped.
    static func remapReferences(_ refs: [AnswerReference], content: String, map: [Int]) -> [AnswerReference] {
        let ns = content as NSString
        return refs.compactMap { r in
            guard map.count >= 1 else { return nil }
            let p = map[min(max(r.location, 0), map.count - 1)]
            guard p >= 0, p < ns.length, ns.character(at: p) == answerTokenMarkerUTF16 else { return nil }
            return r.withLocation(p)
        }
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
            // Empty rename falls back to the automatic title (r33: with
            // the global constants in scope).
            sheets[idx].isTitleCustom = false
            sheets[idx].title = Sheet.autoTitle(
                from: sheets[idx].content, fallback: sheets[idx].titleSeed,
                constants: settings.customConstants)
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

    // MARK: Global constants (r33)

    /// Appends a fresh default row (`constant`, `constant 2`, … with
    /// expression `0`) when under the 100-row limit; returns the new
    /// row's ID so the view can focus its name field.
    @discardableResult
    func addConstant(after rowID: UUID? = nil) -> UUID? {
        guard settings.customConstants.count < ConstantResolver.maxRows else {
            return nil
        }
        let taken = Set(settings.customConstants.map { canonicalNameKey($0.name) })
        var n = 2
        var name = "constant"
        while taken.contains(canonicalNameKey(name)) {
            name = "constant \(n)"
            n += 1
        }
        let row = UserConstant(name: name, expression: "0")
        if let rowID, let i = settings.customConstants.firstIndex(where: { $0.id == rowID }) {
            settings.customConstants.insert(row, at: i + 1)
        } else {
            settings.customConstants.append(row)
        }
        persist()
        return row.id
    }

    /// Live edit of one row by STABLE ID (never a fragile index): the
    /// name/expression are capped by the resolver's grammar limits and
    /// the change persists immediately — every sheet re-evaluates from
    /// the observable settings mutation.
    func updateConstant(id: UUID, name: String, expression: String) {
        guard let i = settings.customConstants.firstIndex(where: { $0.id == id }) else {
            return
        }
        settings.customConstants[i].name =
            String(name.prefix(ConstantResolver.maxNameLength))
        settings.customConstants[i].expression =
            String(expression.prefix(ConstantResolver.maxExpressionLength))
        persist()
    }

    /// Immediate delete by stable ID; dependent sheets re-evaluate on
    /// the same tick (the name becomes unreserved at once).
    func deleteConstant(id: UUID) {
        guard settings.customConstants.contains(where: { $0.id == id }) else { return }
        settings.customConstants.removeAll { $0.id == id }
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
        // Imported lines go through the SAME preference-aware input
        // pass as typing (r19): the user's own operator/grouping
        // settings apply, prose/comments/titles/conversions untouched.
        let (content, map) = InputFormatting.formatDocument(
            obj.content, prefs: settings.input)
        // The pass may re-space token lines: replay its EXACT UTF-16
        // map so imported references keep pointing at real markers.
        var refs = obj.references ?? []
        if !refs.isEmpty {
            let m: [Int] = content == obj.content
                ? Array(0...((obj.content as NSString).length))
                : map
            let ns = content as NSString
            refs = refs.compactMap { r in
                let p = m[min(max(r.location, 0), m.count - 1)]
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
        let payload = StorePayload(sheets: sheets, selectedIndex: selectedIndex,
                                  settings: settings,
                                  version: StorePayload.currentVersion)
        Persistence.save(payload)
    }

    /// Loads (and, when stale, refreshes) the currency table through
    /// the single-flight refresher; the MainActor publish happens here.
    /// A failed refresh keeps the stale cached table — the app never
    /// shows an error state for rates, it just uses the last good one.
    @MainActor
    func loadRates() async {
        let r = await RateRefresher.shared.refresh()
        rates = r
        isRatesLoaded = true
    }

    /// Manual/test hook: install a table without any network.
    func setRates(_ r: Rates) async {
        await RateRefresher.shared.set(r)
        rates = r
    }
}
