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
    /// r39: one-level sidebar folders (array order = sidebar order).
    /// Membership lives on Sheet.folderID (nil = General). App-local
    /// only: never part of `.nlx` exports.
    var folders: [SheetFolder] = []
    /// r40: the sidebar's ONE active folder filter (presentation-only,
    /// never persisted). During normal UI it is always `.general` or
    /// `.folder(validID)`; the upper sheet list shows exactly the
    /// sheets of this tab. It initializes from the restored selection,
    /// follows sheet selection, is set by tab clicks and New Sheet /
    /// Import destinations, and repairs to `.general` when its folder
    /// goes away. `.none` is only a compatibility fallback.
    var activeGroup: SidebarGroup = .general

    /// The folder ID the active tab filters on (nil = General).
    var activeGroupID: UUID? { SheetOrganization.folderID(of: activeGroup) }

    /// The tab a sheet membership belongs to: its folder while it still
    /// exists, General for unfiled or orphaned membership — the filter
    /// always points at a real, visible tab.
    func activeGroup(for folderID: UUID?) -> SidebarGroup {
        if let id = folderID, folders.contains(where: { $0.id == id }) {
            return .folder(id)
        }
        return .general
    }
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
                // r51: rounding overrides survive only for live lines.
                s.dropStaleAnswerDisplay()
                if s.lineIDs.count != s.logicalLineCount || !s.references.isEmpty { migrated = true }
                return s
            }
            // r39: additive — pre-r39 payloads carry no folders key
            // (it decodes []). Corrupt relationships (orphaned
            // memberships, duplicate folder UUIDs) are repaired ONCE
            // here, on the way into the model: members are unfiled to
            // General, content and order untouched; a repair persists
            // exactly
            // once through the existing one-shot flag.
            let (repairedFolders, repairedSheets) = SheetOrganization.sanitize(
                folders: payload.folders, sheets: sheets)
            if repairedFolders != payload.folders || repairedSheets != sheets {
                migrated = true
            }
            folders = repairedFolders
            sheets = repairedSheets
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
        // r40: derive the initial active tab from the restored
        // selection (General for nil/orphan). Pure presentation state —
        // no store rewrite for an unchanged store.
        activeGroup = activeGroup(for: selectedSheet?.folderID)
        // r38: re-apply the persisted appearance through the one
        // controller. The AppDelegate already applied the same value
        // (the guard makes this a no-op when it did); NSApp exists by
        // the time the scene builds this model, so the first visible
        // frame always matches the persisted choice (this init runs on
        // the main actor — the App struct creates the model there).
        let appearance = settings.appearance
        MainActor.assumeIsolated {
            AppAppearanceController.apply(appearance)
        }
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

    /// r51: per-answer rounding override on the SELECTED sheet by
    /// source line index. `places == nil` clears back to Default.
    /// Presentation-only: persists immediately but touches nothing else
    /// — no content/lineID/reference/folder/caret/scroll change, only
    /// the answer column repaints.
    func setAnswerRounding(at index: Int, places: Int?) {
        guard sheets.indices.contains(selectedIndex) else { return }
        var s = sheets[selectedIndex]
        guard s.lineIDs.indices.contains(index) else { return }
        let id = s.lineIDs[index]
        if let p = places {
            let clamped = AnswerDisplay.clamped(p)
            if let i = s.answerDisplay.firstIndex(where: { $0.lineID == id }) {
                s.answerDisplay[i].decimalPlaces = clamped
            } else {
                s.answerDisplay.append(AnswerDisplayPreference(lineID: id, decimalPlaces: clamped))
            }
        } else {
            s.answerDisplay.removeAll { $0.lineID == id }
        }
        s.dropStaleAnswerDisplay()
        s.modifiedAt = Date()
        sheets[selectedIndex] = s
        persist()
    }

    /// r51: deletes ONE logical source line of the selected sheet by
    /// 0-based line index (the answer context menu's Delete Line). The
    /// exact UTF-16 plan removes the line plus its newline, the shared
    /// `LineIdentity.reconcile` remaps IDs/markers, stale rounding
    /// overrides drop, and tokens on the deleted line break naturally.
    /// Sole-line deletion leaves a valid empty sheet. Focus lands at
    /// the deletion start, clamped to the final content.
    func deleteSourceLine(at index: Int) {
        guard sheets.indices.contains(selectedIndex) else { return }
        let sheet = sheets[selectedIndex]
        guard let plan = AnswerDisplay.deleteLinePlan(content: sheet.content,
                                                      lineIndex: index) else { return }
        updateContent(plan.content, edit: plan.edit)
        var s = sheets[selectedIndex]
        s.dropStaleAnswerDisplay()
        sheets[selectedIndex] = s
        persist()
        focusSheetID = s.id
        focusCaret = min(plan.caret, (s.content as NSString).length)
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

    /// Double-click on a successful answer: insert ONE token at the
    /// editor's CURRENT caret/selection — exactly like typing at the
    /// caret. A collapsed caret inserts the marker in place; a non-empty
    /// selection is replaced by the single marker; NO newline is ever
    /// added. The token references the clicked source line by STABLE ID;
    /// `labelLine` remembers the 1-based line number for the inactive
    /// `Line N` label. The caret lands right after the token.
    ///
    /// `selection` is the live NSTextView selection (UTF-16) snapshotted
    /// from the current editor bridge. `nil` (no live editor) or an
    /// invalid/stale range is a deterministic no-op: nothing is
    /// persisted, retitled, focused, or animated.
    func insertToken(sourceLineIndex: Int, selection: NSRange?) {
        guard let selection else { return }
        guard sheets.indices.contains(selectedIndex) else { return }
        let sheet = sheets[selectedIndex]
        guard let plan = AnswerTokenInsertion.plan(
            content: sheet.content,
            lineIDs: sheet.lineIDs,
            references: sheet.references,
            sourceLineIndex: sourceLineIndex,
            selection: selection
        ) else { return }
        var s = sheet
        s.content = plan.content
        s.lineIDs = plan.lineIDs
        s.references = plan.references
        s.modifiedAt = Date()
        sheets[selectedIndex] = Sheet.retitled(s, content: plan.content,
                                               constants: settings.customConstants)
        persist()
        focusSheetID = s.id
        focusCaret = plan.caret
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

    /// Creates a fresh sheet at the TOP of its tab. The destination is
    /// the EXPLICIT group (the folder context menu passes its folder)
    /// or, by default, the ACTIVE sidebar tab — the top New Sheet
    /// button and Cmd-N always create where the user is looking, never
    /// in some stale selected sheet's old group. A destination folder
    /// that no longer exists unfiles the new sheet to General; the
    /// created sheet becomes selected and focused and the active tab
    /// stays the destination.
    func newSheet(in group: SidebarGroup = .none) {
        let dest: UUID?
        switch group {
        case .none: dest = activeGroupID
        case .general: dest = nil
        case .folder(let id): dest = folders.contains { $0.id == id } ? id : nil
        }
        let seed = "\(settings.sheetName) \(sheets.count + 1)"
        let sheet = Sheet(title: seed, content: "", createdAt: Date(), modifiedAt: Date(),
                          folderID: dest)
        let idx = SheetOrganization.insertionIndex(forGroup: dest, in: sheets)
        sheets.insert(sheet, at: idx)
        selectedIndex = idx
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
            // r39: the replacement keeps the deleted sheet's group,
            // so deleting the sole sheet of a folder leaves a fresh
            // empty sheet inside that same folder.
            let folder = sheets[0].folderID
            sheets[0] = Sheet(title: "\(settings.sheetName) 1", content: "",
                              createdAt: Date(), modifiedAt: Date(), folderID: folder)
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
        // r40: selecting a visible sheet keeps/sets the matching active
        // tab — it never clears the filter.
        activeGroup = activeGroup(for: sheets[index].folderID)
        selectedIndex = index
        persist()
    }

    // MARK: Sidebar folders (r39, tab-filtered in r40)

    /// The sheets of one tab (nil == General) in GLOBAL order: the
    /// stable (global index, sheet) pairs the upper list renders, so
    /// selection and deletion keep their global-index semantics.
    func sheets(in groupID: UUID?) -> [(index: Int, sheet: Sheet)] {
        Array(sheets.enumerated()).compactMap { idx, sheet in
            sheet.folderID == groupID ? (idx, sheet) : nil
        }
    }

    /// Creates a folder with the generated localized unique name, inserts
    /// it AFTER the reference tab (General => first custom folder; a
    /// custom folder => immediately after it; a stale reference =>
    /// appended), makes the new tab active and returns its id (the view
    /// opens its inline rename).
    @discardableResult
    func createFolder(after reference: SidebarGroup = .general) -> UUID {
        let title = SheetOrganization.generatedFolderName(
            existing: folders.map(\.title), language: settings.language)
        let folder = SheetFolder(id: UUID(), title: title)
        let idx = SheetOrganization.folderInsertionIndex(
            afterID: SheetOrganization.folderID(of: reference), in: folders)
        folders.insert(folder, at: idx)
        activeGroup = .folder(folder.id)
        persist()
        return folder.id
    }

    /// Renames a folder by stable ID: whitespace is trimmed and an empty
    /// result keeps the current title (a folder has no automatic title
    /// to fall back to). Manual title duplicates are allowed.
    func renameFolder(id: UUID, to newTitle: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != folders[i].title else { return }
        folders[i].title = trimmed
        persist()
    }

    /// Moves one sheet by stable ID into a folder (nil = General). The
    /// global array order, the selection index/ID and all content are
    /// untouched — the sheet just re-groups in the sidebar.
    func moveSheet(id: UUID, to groupID: UUID?) {
        guard SheetOrganization.moveSheet(&sheets, id: id, to: groupID) else { return }
        persist()
    }

    /// Deletes a folder by id and safely unfiles its members to General:
    /// no sheet is ever deleted, and the selected sheet/editor stay put.
    /// Deleting the ACTIVE tab switches the filter to General.
    func deleteFolder(id: UUID) {
        guard SheetOrganization.removeFolder(&folders, id: id, sheets: &sheets) else { return }
        if case .folder(let active) = activeGroup, active == id { activeGroup = .general }
        persist()
    }

    /// Switches the active folder filter WITHOUT touching the editor:
    /// selected sheet, index, caret, scroll and content all stay exactly
    /// where they are — only the upper list re-filters.
    func activate(group: SidebarGroup) {
        activeGroup = group
    }

    /// Repairs the active filter when its folder is gone (e.g. after an
    /// external store repair): an invalid folder always falls back to
    /// General.
    func repairActiveGroup() {
        if case .folder(let id) = activeGroup, !folders.contains(where: { $0.id == id }) {
            activeGroup = .general
        }
    }

    // MARK: Global constants (r33)

    /// Appends a fresh default row (a grammar-valid generated name —
    /// `constant`, `constant_2`, … — with expression `0`) when under
    /// the 100-row limit; returns the new row's ID so the view can
    /// focus its name field.
    @discardableResult
    func addConstant(after rowID: UUID? = nil) -> UUID? {
        guard settings.customConstants.count < ConstantResolver.maxRows else {
            return nil
        }
        let taken = Set(settings.customConstants.map { canonicalNameKey($0.name) })
        let row = UserConstant(
            name: ConstantResolver.generatedConstantName(taken: taken),
            expression: "0")
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
                           lineIDs: s.lineIDs, references: s.references,
                           answerDisplay: s.answerDisplay)
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
        // r51: imported display preferences survive only for live lines.
        let display = AnswerDisplay.sanitize(obj.answerDisplay ?? [], lineIDs: lineIDs)
        return Sheet(title: obj.title, content: content,
                     createdAt: Date(), modifiedAt: Date(), isTitleCustom: custom,
                     lineIDs: lineIDs, references: refs, answerDisplay: display)
    }

    func importSheet(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        importSheet(data: data)
    }

    func importSheet(data: Data) {
        guard let obj = try? JSONDecoder().decode(SheetExport.self, from: data) else { return }
        let sheet = makeImportedSheet(obj)
        sheets.append(sheet)
        selectedIndex = sheets.count - 1
        // r40: imports always land in General and the imported sheet
        // becomes selected — follow it to the General tab.
        activeGroup = activeGroup(for: sheet.folderID)
        persist()
    }

    func persist() {
        let payload = StorePayload(sheets: sheets, selectedIndex: selectedIndex,
                                  settings: settings,
                                  version: StorePayload.currentVersion,
                                  folders: folders)
        Persistence.save(payload)
    }

    /// r38: THE one appearance-change path: one settings write, one
    /// persist, one process-wide application. The SwiftUI scene roots
    /// and the editor pick the change up from the observable settings
    /// mutation; the controller handles the NSApp projection.
    func setAppearance(_ appearance: AppAppearance) {
        guard appearance != settings.appearance else { return }
        settings.appearance = appearance
        persist()
        // Called from the SwiftUI settings binding — main actor.
        MainActor.assumeIsolated {
            AppAppearanceController.apply(appearance)
        }
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
