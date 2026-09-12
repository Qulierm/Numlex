import Foundation
import AppKit
import NumlexCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let nlx = UTType(filenameExtension: "nlx") ?? .json
}

@Observable
final class AppModel {
    var sheets: [Sheet] = []
    var selectedIndex: Int = 0 {
        // r77: a sheet switch re-seeds the answer appearance state so
        // the new sheet's rows never replay insertion animations.
        didSet { noteAnswerActivity() }
    }
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

    /// The app's ONE updater integration (Sparkle 2.9.6), created on first
    /// main-actor access. Disabled gracefully when the packaged metadata is
    /// unavailable (for example `swift run Numlex`), so development runs
    /// never crash. Sparkle's own automatic-check preference lives in
    /// Sparkle's UserDefaults — intentionally NOT part of `AppSettings` or
    /// `.nlx`.
    @ObservationIgnored private var updaterStorage: UpdateController?

    @MainActor
    var updates: UpdateController {
        if let updaterStorage { return updaterStorage }
        let controller = UpdateController()
        updaterStorage = controller
        return controller
    }

    // MARK: - r73: the ONE app-wide number context

    /// The OS locale identifier, re-read when the OS locale changes so
    /// the `system` preset (and every locale-derived separator) follows
    /// the user's OS without an app restart.
    private var localeID = Locale.current.identifier

    /// THE single resolved number context the whole app uses: parsing,
    /// highlighting, input autoformat, answer display and clipboard all
    /// read this ONE value, so display and parsing can never drift.
    /// `settings.regional == nil` (a pre-r73 store the user never
    /// touched in the Numbers tab) resolves to the exact pre-r73 US
    /// behavior.
    var numberContext: NumberFormatContext {
        NumberFormatContext.resolve(settings.regional,
                                    locale: Locale(identifier: localeID))
    }

    /// r84: the app's ONE unit context: the built-in `UnitCatalog`
    /// plus the ACTIVE custom units from the global settings (the
    /// resolver runs per pass; `.builtIns` when nothing is active, so
    /// pre-r84 behavior is byte-for-byte preserved).
    var unitContext: UnitContext {
        UnitResolver.resolve(settings.customUnits,
                             constants: settings.customConstants).context
    }

    /// Package 2: the ONE immutable financial context for this pass —
    /// the app-global tax configuration plus the bundled offline
    /// catalogs. Derived from the observable settings, never global
    /// mutable state.
    var financialContext: FinancialContext {
        FinancialContext.app(tax: settings.tax)
    }

    /// The Numbers tab's pending region change, awaiting the
    /// reinterpretation confirmation: `nil` means no dialog is up. The
    /// examples are the first changed lines (source -> old -> new) of
    /// the selected sheet.
    struct PendingRegionChange: Equatable {
        let preset: NumberRegionPreset
        let examples: [String]
    }
    var pendingRegionChange: PendingRegionChange?

    /// Requests a region preset change. The region never reinterprets
    /// silently: the selected sheet is evaluated under the old and the
    /// new context, and any answer whose value changed opens the
    /// confirmation dialog with before/after examples. A no-difference
    /// change (or an empty sheet) applies immediately. Legacy stores
    /// are promoted to `RegionalNumberPreferences.newDefaults` with the
    /// requested preset on the first write — the defaults reproduce
    /// the legacy scale (grouping on, compact off, paste off).
    func requestRegionChange(_ preset: NumberRegionPreset) {
        guard settings.regional?.region != preset else { return }
        let old = numberContext
        var prefs = settings.regional ?? RegionalNumberPreferences.newDefaults
        prefs.region = preset
        let new = NumberFormatContext.resolve(prefs,
                                              locale: Locale(identifier: localeID))
        guard old != new else {
            settings.regional = prefs
            persist()
            return
        }
        var examples: [String] = []
        if let sheet = selectedSheet,
           !sheet.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var oldVars = [String: Double]()
            var newVars = [String: Double]()
            let rowsOld = evaluateSheet(sheet.content, variables: &oldVars,
                                        rates: rates,
                                        decimalPlaces: max(settings.decimalPlaces, 10),
                                        constants: settings.customConstants,
                                        context: old,
                                        unitContext: unitContext,
                                        preferences: settings.temporal,
                                        financial: financialContext)
            let rowsNew = evaluateSheet(sheet.content, variables: &newVars,
                                        rates: rates,
                                        decimalPlaces: max(settings.decimalPlaces, 10),
                                        constants: settings.customConstants,
                                        context: new,
                                        unitContext: unitContext,
                                        preferences: settings.temporal,
                                        financial: financialContext)
            let lines = sheet.content.components(separatedBy: "\n")
            for row in rowsOld where rowsNew.indices.contains(row.sourceLineIndex) {
                let other = rowsNew[row.sourceLineIndex]
                guard row.result != other.result else { continue }
                let src = lines.indices.contains(row.sourceLineIndex)
                    ? lines[row.sourceLineIndex].trimmingCharacters(in: .whitespaces)
                    : ""
                if src.isEmpty { continue }
                let a = AnswerDisplay.text(for: row.result,
                                           decimalPlaces: settings.decimalPlaces,
                                           context: old) ?? "—"
                let b = AnswerDisplay.text(for: other.result,
                                           decimalPlaces: settings.decimalPlaces,
                                           context: new) ?? "—"
                examples.append("\(src): \(a) → \(b)")
                if examples.count == 5 { break }
            }
        }
        if examples.isEmpty {
            settings.regional = prefs
            persist()
        } else {
            pendingRegionChange = PendingRegionChange(preset: preset, examples: examples)
        }
    }

    /// The confirmation dialog's Apply: the user accepted that the
    /// sheet's answers reinterpret.
    func confirmRegionChange() {
        guard let pending = pendingRegionChange else { return }
        var prefs = settings.regional ?? RegionalNumberPreferences.newDefaults
        prefs.region = pending.preset
        settings.regional = prefs
        pendingRegionChange = nil
        persist()
    }

    /// The confirmation dialog's Cancel: nothing changes — the sheet
    /// keeps its old region and its prior interpretations.
    func cancelRegionChange() {
        pendingRegionChange = nil
    }

    // MARK: - r77: answer appearance motion (UI-only, never persisted)

    /// Pure appearance-pass state for NEW answer rows (stable line
    /// UUIDs, never positions). Seeded with the selected sheet's line
    /// IDs on load/relaunch/sheet switch so those rows never replay an
    /// insertion animation; only genuinely new lines (typed lines,
    /// re-created lines after a deletion) fade in once. UI state only
    /// — it is never part of the store.
    var answerAppearance = AnswerAppearance()
    /// The sheet whose line IDs the appearance state is seeded for.
    private(set) var answerSheetID: Sheet.ID?
    /// Line ID → current fade-in opacity (0...1). Empty = every row at
    /// full opacity (the tick bumps this ~60/s only while a pass runs,
    /// so the view re-renders only for the ~180 ms appearance burst).
    private(set) var answerOpacities: [UUID: Double] = [:]
    /// One-shot chained tick for the answer pass (1/60 s, common run-
    /// loop mode); self-terminating, like the editor's token pass. A
    /// mid-flight switch to Reduce Motion is honoured on the next tick
    /// (≤ one frame) by polling `Motion.reduceMotion` there — no
    /// notification dependency.
    private var answerAnimTimer: Timer?
    private var answerAnimRunning = false

    /// Called after every change that can change the selected sheet's
    /// line population (user edits, deletions, token insertions, sheet
    /// switches, store load). Only the SHEET-SWITCH / load case is
    /// handled here: the sheet's line IDs are seeded `pending` so the
    /// first observation adopts their real result phases silently (no
    /// replay of already-visible answers). Per-line result transitions
    /// are reported by the view through `noteAnswerResultActivity` —
    /// line-ID bookkeeping alone cannot see a result appearing on an
    /// existing line (the r77b root cause of "no visible motion").
    /// r77c: main-thread diagnostics log (call sites all run on the
    /// main thread; inert unless launched with --trace).
    private func dlog(_ s: String) {
        MainActor.assumeIsolated {
            Diagnostics.shared?.log(s)
        }
    }

    func noteAnswerActivity() {
        let sheetID = selectedSheet?.id
        if sheetID != answerSheetID {
            answerSheetID = sheetID
            answerAppearance.seed(ids: selectedSheet?.lineIDs ?? [])
            stopAnswerTick()
            answerOpacities = [:]
            // r77c: sheet-switch / load seed point (no replay).
            dlog(String(
                "noteAnswerActivity sheet=\(sheetID?.uuidString.prefix(4) ?? "nil") "
                + "lines=\(selectedSheet?.lineIDs.count ?? 0) (seed)"))
        }
    }

    /// r77b: the answer view reports, after every re-evaluation, one
    /// entry per source line (stable UUID + displayed answer key, nil
    /// for quiet lines). A line that goes quiet → real answer starts
    /// ONE fade-in pass (visible 180–220 ms fade of the answer row);
    /// a changed result on an answering line is crossfade-only in the
    /// view; seeded (pending) lines adopt silently. The tick runs only
    /// while a pass is in flight.
    func noteAnswerResultActivity(_ entries: [AnswerMotionEntry]) {
        let fresh = answerAppearance.observe(
            entries: entries,
            now: ProcessInfo.processInfo.systemUptime,
            reduceMotion: Motion.reduceMotion
        )
        let animating = answerAppearance.isAnimating
        // r77c: compact observation record — what changed and what it
        // did (pass started / nothing), one line per observation.
        let freshDesc = fresh.map { $0.uuidString.prefix(4) }.joined(separator: ",")
        let entriesDesc = entries.prefix(10).map {
            let k = $0.key.map { String($0.prefix(6)) } ?? "q"
            return $0.id.uuidString.prefix(4) + ":" + k
        }.joined(separator: " ")
        dlog("noteAnswerResult n=\(entries.count) fresh=[\(freshDesc)] anim=\(animating) \(entriesDesc)")
        if animating {
            startAnswerTick()
            // r77b: evidence burst (inert unless --motion-evidence is
            // passed; the call sites run on the main thread).
            MainActor.assumeIsolated {
                MotionEvidence.shared?.noteBurst()
            }
        } else if !answerOpacities.isEmpty {
            // Only clear when something was in flight — an empty map
            // assignment would needlessly re-render on every edit.
            answerOpacities = [:]
        }
    }

    private func startAnswerTick() {
        guard !answerAnimRunning else { return }
        answerAnimRunning = true
        scheduleAnswerTick()
    }

    private func scheduleAnswerTick() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: false) { [weak self] _ in
            self?.answerTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        answerAnimTimer = timer
    }

    private func answerTick() {
        // r77: Reduce Motion flipped on mid-pass: settle instantly
        // (within this one frame) — final opacity, chain stopped.
        if Motion.reduceMotion {
            answerAppearance.cancelAll()
            stopAnswerTick()
            answerOpacities = [:]
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        var opacities: [UUID: Double] = [:]
        for id in selectedSheet?.lineIDs ?? [] {
            if let p = answerAppearance.progress(for: id, now: now) {
                opacities[id] = p
            }
        }
        answerAppearance.expire(now: now)
        answerOpacities = opacities
        // r77b: instrumented evidence (inert unless launched with
        // --motion-evidence <dir>): 60 Hz per-tick opacity samples.
        MainActor.assumeIsolated {
            MotionEvidence.shared?.sample(opacities: opacities, now: now)
        }
        // r77c: 60 Hz opacity record while a pass is in flight.
        let opacDesc = opacities
            .map { "\($0.key.uuidString.prefix(4))=\($0.value)" }
            .joined(separator: " ")
        dlog("tick opac=\(opacDesc)")
        if answerAppearance.isAnimating {
            scheduleAnswerTick()
        } else {
            stopAnswerTick()
            answerOpacities = [:]
        }
    }

    private func stopAnswerTick() {
        answerAnimTimer?.invalidate()
        answerAnimTimer = nil
        answerAnimRunning = false
    }

    deinit {
        stopAnswerTick()
    }

    init() {
        // r73: follow OS locale changes live — the `system` preset's
        // separators re-resolve on the next observation tick without a
        // restart (the identifier bump re-renders every body that
        // reads `numberContext`).
        NotificationCenter.default.addObserver(
            forName: (NSLocale.currentLocaleDidChangeNotification as Notification.Name),
            object: nil, queue: .main
        ) { [weak self] _ in
            let id = Locale.current.identifier
            if let self, self.localeID != id {
                self.localeID = id
            }
        }
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
        //
        // r91: the APPEARANCE only. The application icon is NOT touched
        // here: the App struct can build this model BEFORE
        // applicationDidFinishLaunching, so an apply() from init could
        // install the persisted alternate icon before the delegate
        // captured the bundle default — the delegate then recorded that
        // alternate as the launch icon, and the Dark restore reinstalled
        // it forever (the Light-locked bug). The delegate owns the icon
        // lifecycle: capture the true primary default, then apply.
        let appearance = settings.appearance
        MainActor.assumeIsolated {
            AppAppearanceController.apply(appearance)
        }
        // r77: seed the answer appearance state with the loaded sheet's
        // lines — initial load never plays insertion animations.
        noteAnswerActivity()
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
        noteAnswerActivity()
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

    /// r87: per-line NOTATION override on the selected sheet by source
    /// line index. `notation == nil` = Default (clears the notation
    /// override; the precision override is kept — use
    /// `resetAnswerFormatting` to clear both). The model revalidates
    /// sheet + line ID at call time, so a stale open menu cannot
    /// retarget.
    func setAnswerNotation(at index: Int, notation: AnswerNotationOverride?) {
        guard sheets.indices.contains(selectedIndex) else { return }
        var s = sheets[selectedIndex]
        guard s.lineIDs.indices.contains(index) else { return }
        let id = s.lineIDs[index]
        if let n = notation {
            if let i = s.answerDisplay.firstIndex(where: { $0.lineID == id }) {
                s.answerDisplay[i].notation = n
            } else {
                s.answerDisplay.append(AnswerDisplayPreference(
                    lineID: id, decimalPlaces: settings.decimalPlaces, notation: n))
            }
        } else {
            if let i = s.answerDisplay.firstIndex(where: { $0.lineID == id }) {
                s.answerDisplay[i].notation = nil
                if s.answerDisplay[i].decimalPlaces == settings.decimalPlaces {
                    // Pure default entry: drop it entirely.
                    s.answerDisplay.remove(at: i)
                }
            }
        }
        s.dropStaleAnswerDisplay()
        s.modifiedAt = Date()
        sheets[selectedIndex] = s
        persist()
    }

    /// r87: removes BOTH the notation and the precision overrides of
    /// one line so it resumes live global sync.
    func resetAnswerFormatting(at index: Int) {
        guard sheets.indices.contains(selectedIndex) else { return }
        var s = sheets[selectedIndex]
        guard s.lineIDs.indices.contains(index) else { return }
        let id = s.lineIDs[index]
        s.answerDisplay.removeAll { $0.lineID == id }
        s.dropStaleAnswerDisplay()
        s.modifiedAt = Date()
        sheets[selectedIndex] = s
        persist()
    }

    /// r87: the persistent line highlight for the lines `lineIDs`
    /// references. `color == nil` = None (removes the highlight).
    /// Sheet-ID guarded and bounds-validated: stale/missing sheets are
    /// no-ops; only LIVE line IDs are stored (sanitized). This touches
    /// sheet metadata only — never content, line IDs, references,
    /// caret, focus or scroll.
    func setLineHighlight(sheetID: Sheet.ID?, lineIDs: [UUID], color: HighlightColor?) {
        guard let sheetID, let si = sheets.firstIndex(where: { $0.id == sheetID }) else { return }
        var s = sheets[si]
        let live = Set(s.lineIDs)
        let targets = Set(lineIDs.filter { live.contains($0) })
        if targets.isEmpty { return }
        if let c = color {
            for id in targets {
                if let i = s.highlights.firstIndex(where: { $0.lineID == id }) {
                    s.highlights[i].color = c
                } else {
                    s.highlights.append(LineHighlightPreference(lineID: id, color: c))
                }
            }
        } else {
            s.highlights.removeAll { targets.contains($0.lineID) }
        }
        s.highlights = LineHighlightPreference.sanitize(s.highlights, lineIDs: s.lineIDs)
        s.modifiedAt = Date()
        sheets[si] = s
        persist()
    }

    /// r87: deletes ONE logical source line of the selected sheet by
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
        noteAnswerActivity()
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
        // r77c: trace the whole insertion decision (the double-click
        // chain's final step).
        let beforeFFFC = selectedSheet.map { $0.content.components(separatedBy: "\u{FFFC}").count - 1 } ?? 0
        let sheetID = selectedSheet.map { $0.id.uuidString.prefix(4) }
        var planOK = false
        if let sheetID {
            // The plan is computed inside the guard chain below; log
            // the outcome there too.
            _ = sheetID
        }
        guard let selection else {
            dlog("insertToken ABORT no-selection sheet=\(sheetID ?? "nil") line=\(sourceLineIndex)")
            return
        }
        guard sheets.indices.contains(selectedIndex) else {
            dlog("insertToken ABORT bad-selectedIndex sheet=\(sheetID ?? "nil")")
            return
        }
        let sheet = sheets[selectedIndex]
        guard let plan = AnswerTokenInsertion.plan(
            content: sheet.content,
            lineIDs: sheet.lineIDs,
            references: sheet.references,
            sourceLineIndex: sourceLineIndex,
            selection: selection
        ) else {
            dlog("insertToken ABORT plan-nil sheet=\(sheetID ?? "nil") line=\(sourceLineIndex) sel=\(selection) nlines=\(sheet.lineIDs.count)")
            return
        }
        planOK = true
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
        let afterFFFC = sheets[selectedIndex].content.components(separatedBy: "\u{FFFC}").count - 1
        dlog(String(
            "insertToken OK plan=\(planOK) sheet=\(sheetID ?? "nil") line=\(sourceLineIndex) "
            + "sel=\(selection.location)+\(selection.length) fffc \(beforeFFFC)→\(afterFFFC) caret=\(plan.caret)"))
        noteAnswerActivity()
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
            constants: settings.customConstants,
            weather: weatherContext, geo: geoContext
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
        noteAnswerActivity()
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
        // r77c: the new sheet's full lifecycle marker (id, index,
        // focus request) for the double-click-after-New-Sheet trace.
        dlog(String(
            "newSheet DONE id=\(sheet.id.uuidString.prefix(4)) idx=\(idx) title=\(sheet.title)"))
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

    /// r84: appends (or inserts after a row) a fresh custom-unit row
    /// with the next generated name and an EMPTY definition (the row
    /// stays inert until both fields are filled). Returns the row ID
    /// for focus handoff; nil at the limit.
    func addUnitRow(after rowID: UUID? = nil) -> UUID? {
        guard settings.customUnits.count < UnitResolver.maxRows else {
            return nil
        }
        let taken = Set(settings.customUnits.map {
            UnitResolver.normName($0.name)
        })
        let row = UserUnitDefinition(
            name: UnitResolver.generatedUnitName(taken: taken),
            definition: "")
        if let rowID, let i = settings.customUnits.firstIndex(where: { $0.id == rowID }) {
            settings.customUnits.insert(row, at: i + 1)
        } else {
            settings.customUnits.append(row)
        }
        persist()
        return row.id
    }

    /// r84: removes one custom-unit row and persists.
    func deleteUnitRow(id: UUID) {
        guard settings.customUnits.contains(where: { $0.id == id }) else { return }
        settings.customUnits.removeAll { $0.id == id }
        persist()
    }

    // MARK: Tax configuration (Package 2)

    /// Preset selection seeds the tax name and rate once (US seeds the
    /// name only — it has no automatic national rate). Manual edits
    /// afterwards stay user-owned. One settings write, one persist; no
    /// sheet/editor state is touched.
    func selectTaxPreset(_ region: String) {
        if let preset = TaxPresets.preset(for: region) {
            settings.tax.preset = preset.region
            settings.tax.name = TaxPreferences.sanitizedName(preset.name)
            // A manual preset carries NO automatic rate (US); selecting
            // it leaves the rate unset until the user enters one.
            settings.tax.ratePercent = TaxPreferences.sanitizedRate(preset.ratePercent)
        } else {
            settings.tax.preset = ""
        }
        persist()
    }

    func updateTaxName(_ name: String) {
        let sanitized = TaxPreferences.sanitizedName(name)
        guard sanitized != settings.tax.name else { return }
        settings.tax.name = sanitized
        persist()
    }

    /// nil clears the rate (the lane then fails with the actionable
    /// message); values outside the finite 0...<100 domain are ignored.
    func updateTaxRate(_ ratePercent: Double?) {
        if let ratePercent {
            guard let sanitized = TaxPreferences.sanitizedRate(ratePercent) else { return }
            guard settings.tax.ratePercent != sanitized else { return }
            settings.tax.ratePercent = sanitized
        } else {
            guard settings.tax.ratePercent != nil else { return }
            settings.tax.ratePercent = nil
        }
        persist()
    }

    // MARK: Custom timezones (temporal Task 1)

    /// THE one custom-timezone mutation family: add / update / delete.
    /// Every call persists ONCE and only touches `settings.temporal` —
    /// sheets, content, line IDs, references, the editor identity and
    /// the caret are never touched, and the observable settings write is
    /// what live-reevaluates every sheet through the TimezoneLane.
    /// Appends (or inserts after a row) a fresh custom-timezone row when
    /// under the 100-row cap; returns the new row's ID so the view can
    /// focus its name field.
    @discardableResult
    func addCustomTimeZone(after rowID: UUID? = nil) -> UUID? {
        let zones = settings.temporal.customTimeZones
        guard zones.count < TemporalPreferences.maxCustomTimeZones else { return nil }
        let taken = Set(zones.map { CustomTimeZoneEditor.canonicalName($0.name) })
        let row = CustomTimeZone(
            name: CustomTimeZoneEditor.generatedName(taken: taken),
            identifier: "")
        if let rowID, let i = zones.firstIndex(where: { $0.id == rowID }) {
            settings.temporal.customTimeZones.insert(row, at: i + 1)
        } else {
            settings.temporal.customTimeZones.append(row)
        }
        persist()
        return row.id
    }

    /// Live edit of one custom-timezone row by STABLE ID (never an
    /// index): both fields are bounded, invalid rows are still persisted
    /// (so the user can fix them) but the lane consumes only active rows.
    func updateCustomTimeZone(id: UUID, name: String, identifier: String) {
        guard let i = settings.temporal.customTimeZones.firstIndex(where: { $0.id == id }) else {
            return
        }
        settings.temporal.customTimeZones[i].name =
            String(name.prefix(CustomTimeZoneEditor.maxNameLength))
        settings.temporal.customTimeZones[i].identifier =
            String(identifier.prefix(CustomTimeZoneEditor.maxIdentifierLength))
        persist()
    }

    /// Immediate delete by stable ID; dependent sheets re-evaluate on the
    /// same tick through the observable settings mutation.
    func deleteCustomTimeZone(id: UUID) {
        guard settings.temporal.customTimeZones.contains(where: { $0.id == id }) else { return }
        settings.temporal.customTimeZones.removeAll { $0.id == id }
        persist()
    }

    func exportCurrent() -> SheetExport? {
        guard let s = selectedSheet else { return nil }
        return SheetExport(title: s.title, content: s.content,
                           isTitleCustom: s.isTitleCustom,
                           lineIDs: s.lineIDs, references: s.references,
                           answerDisplay: s.answerDisplay,
                           highlights: s.highlights)
    }

    private func makeImportedSheet(_ obj: SheetExport) -> Sheet {
        // Files exported before the naming feature decode with a nil flag;
        // then meaningful names stay custom and generic ones stay automatic.
        let custom = obj.isTitleCustom ?? !Sheet.isGenericTitle(obj.title)
        // Imported lines go through the SAME preference-aware input
        // pass as typing (r19): the user's own operator/grouping
        // settings apply, prose/comments/titles/conversions untouched.
        let (content, map) = InputFormatting.formatDocument(
            obj.content, prefs: settings.input, context: numberContext)
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
        // r87: imported highlights follow the same contract.
        let highlights = LineHighlightPreference.sanitize(obj.highlights ?? [], lineIDs: lineIDs)
        return Sheet(title: obj.title, content: content,
                     createdAt: Date(), modifiedAt: Date(), isTitleCustom: custom,
                     lineIDs: lineIDs, references: refs, answerDisplay: display,
                     highlights: highlights)
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

    /// THE one icon-change path: mutate the observable setting, persist
    /// the store, then apply the choice process-wide through the one
    /// controller. A missing/corrupt Light resource fails safe — the
    /// persisted value still roundtrips, and the process keeps its
    /// current icon instead of showing a generic placeholder.
    func setAppIcon(_ choice: AppIconChoice) {
        guard choice != settings.appIcon else { return }
        settings.appIcon = choice
        persist()
        MainActor.assumeIsolated {
            _ = AppIconController.apply(choice)
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

    // MARK: - Weather (r55)

    /// Last-good weather snapshots by canonical query, published for
    /// the current sheet. Never persisted in the store payload — the
    /// durable cache is the separate `weather.json` owned by
    /// `WeatherRefresher.shared`.
    var weatherSnapshots: [String: WeatherSnapshot] = [:]
    // r85: the published GEOGRAPHY state, keyed by BARE place key.
    // The persistent cache is the separate `locations.json` owned by
    // `GeoStore` (geocode-only: place coordinates, nothing else).
    var geoSnapshots: [String: GeoSnapshot] = [:]
    /// Place queries with no cache yet (render quiet, never a spinner).
    var geoPending: Set<String> = []
    /// Places with a terminal failure AND no cached snapshot (render
    /// the localized `Location unavailable` status).
    var geoFailed: Set<String> = []

    /// r85: the pure evaluation context for the current render.
    var geoContext: GeoContext {
        GeoContext(snapshots: geoSnapshots,
                   pendingKeys: geoPending,
                   failedKeys: geoFailed)
    }
    /// Requested queries with no cache yet (render quiet, never a
    /// spinner or an error).
    var weatherPending: Set<String> = []
    /// Queries with a terminal failure AND no cached snapshot (render
    /// the localized `Weather unavailable` status).
    var weatherFailed: Set<String> = []

    /// The pure evaluation context for the current render: snapshots
    /// plus failure marks. ContentView reads this ONCE per body pass
    /// and feeds the same context to both resolveSheet calls, so the
    /// editor and the answers can never disagree.
    var weatherContext: WeatherContext {
        WeatherContext(snapshots: weatherSnapshots,
                       pendingKeys: weatherPending,
                       failedKeys: weatherFailed)
    }

    /// Refreshes weather for the given sheet content (r55): publishes
    /// last-good cache immediately, marks only uncached queries
    /// pending, debounces rapid typing, then refreshes stale/missing
    /// queries in the background and publishes ready/unavailable on
    /// the MainActor. All state is keyed by canonical query — never by
    /// line — so rapid typing, sheet switches, query removal,
    /// duplicate lines, late responses and cancellation can never
    /// redirect a result to another query or rewrite source (source is
    /// never written here at all). Switching back to a fresh cached
    /// query performs no network. Not coupled to rates loading.
    @MainActor
    func refreshWeather(content: String, sheetID: UUID) async {
        let queries = WeatherQuery.scanQueries(in: content)
        let keys = Set(queries.map(\.key))
        // Prune published state for removed queries; a returning query
        // repopulates from the global cache without network.
        for k in weatherSnapshots.keys where !keys.contains(k) {
            weatherSnapshots.removeValue(forKey: k)
        }
        weatherPending = weatherPending.intersection(keys)
        weatherFailed = weatherFailed.intersection(keys)
        guard !queries.isEmpty else { return }
        guard selectedSheet?.id == sheetID else { return }
        for q in queries {
            if let s = await WeatherRefresher.shared.cachedSnapshot(for: q) {
                guard selectedSheet?.id == sheetID else { return }
                weatherSnapshots[q.key] = s
                weatherPending.remove(q.key)
                weatherFailed.remove(q.key)
            } else if weatherSnapshots[q.key] == nil {
                weatherPending.insert(q.key)
            }
        }
        // Debounce: each keystroke changes the .task(id:) signature
        // and cancels this run before any fetch starts, so partial
        // input never triggers a geocode.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, selectedSheet?.id == sheetID else { return }
        await withTaskGroup(of: (String, WeatherSnapshot?).self) { group in
            for q in queries {
                let stale = await WeatherRefresher.shared.isStale(q.key)
                if !stale, weatherSnapshots[q.key] != nil { continue }
                group.addTask { [query = q] in
                    let s = await WeatherRefresher.shared.refresh(query)
                    return (query.key, s)
                }
            }
            for await (key, snap) in group {
                guard !Task.isCancelled, self.selectedSheet?.id == sheetID else { continue }
                self.weatherPending.remove(key)
                if let s = snap {
                    self.weatherSnapshots[key] = s
                    self.weatherFailed.remove(key)
                } else if self.weatherSnapshots[key] == nil {
                    // Terminal failure with no cache: visible status
                    // until the query/signature changes. A failed
                    // refresh WITH a stale snapshot keeps showing the
                    // stale value (last-good wins over failure).
                    self.weatherFailed.insert(key)
                }
            }
        }
    }

    // MARK: - Geography (r85)

    /// r85: refreshes place coordinates for the given sheet content —
    /// the mirror of `refreshWeather`, geocoding ONLY. Place keys are
    /// the BARE canonical keys (the query kinds strip their prefix).
    @MainActor
    func refreshGeo(content: String, sheetID: UUID) async {
        let queries = GeoQueryParse.scanQueries(in: content)
        var placeKeys: [String: String] = [:] // bare key -> display place
        for q in queries {
            switch q.kind {
            case .location, .latitude, .longitude:
                let bare = String(q.key.dropFirst(4))
                if let d = q.placeDisplay { placeKeys[bare] = d }
            case .distance(let a, let b):
                for e in [a, b] {
                    if case .place(let k, let d) = e { placeKeys[k] = d }
                }
            }
        }
        let keys = Set(placeKeys.keys)
        for k in geoSnapshots.keys where !keys.contains(k) {
            geoSnapshots.removeValue(forKey: k)
        }
        geoPending = geoPending.intersection(keys)
        geoFailed = geoFailed.intersection(keys)
        guard !keys.isEmpty else { return }
        guard selectedSheet?.id == sheetID else { return }
        for (k, d) in placeKeys {
            if let s = await GeoRefresher.shared.cachedSnapshot(forPlaceKey: k) {
                guard selectedSheet?.id == sheetID else { return }
                geoSnapshots[k] = s
                geoPending.remove(k)
                geoFailed.remove(k)
            } else if geoSnapshots[k] == nil {
                geoPending.insert(k)
            }
        }
        // Debounce: each keystroke cancels this run before any fetch.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, selectedSheet?.id == sheetID else { return }
        await withTaskGroup(of: (String, GeoSnapshot?).self) { group in
            for (k, d) in placeKeys {
                let stale = await GeoRefresher.shared.isStale(k)
                if !stale, geoSnapshots[k] != nil { continue }
                group.addTask { [key = k, display = d] in
                    let s = await GeoRefresher.shared.refresh(displayPlace: display, placeKey: key)
                    return (key, s)
                }
            }
            for await (key, snap) in group {
                guard !Task.isCancelled, self.selectedSheet?.id == sheetID else { continue }
                self.geoPending.remove(key)
                if let s = snap {
                    self.geoSnapshots[key] = s
                    self.geoFailed.remove(key)
                } else if self.geoSnapshots[key] == nil {
                    self.geoFailed.insert(key)
                }
            }
        }
    }

}
