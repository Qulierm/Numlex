import SwiftUI
import NumlexCore
import UniformTypeIdentifiers

/// Sheets sidebar (liquid-glass redesign, r40 folder tabs): a padded
/// leading VStack with the full-width New Sheet action, the ONE filtered
/// sheet list (the sheets of the active tab) and the pinned bottom
/// folder tab strip. Every row uses the system liquid glass materials —
/// the selected sheet and the active tab show the regular interactive
/// pill, a hovered drop target a stronger tint — so the sidebar stays
/// calm in inactive windows and both appearances.
///
/// r40: folders are NOT an expandable hierarchy. They are tab-like
/// filters pinned to the sidebar bottom: selecting General or a custom
/// tab changes ONLY the upper sheet list (never the editor). Creation
/// happens through the hover `+` on any tab row (no standalone New
/// Folder button). The bottom Settings gear row has been GONE since
/// r39 — Settings is reachable through the system Settings… menu item
/// and ⌘, only.
///
/// r41: geometry and hover parity. The active/drop tab glass uses the
/// EXACT `sidebarButtonShape` (rounded-10 continuous) of the sidebar
/// action controls — no drifting radius literal. A short tab list is
/// NOT inside any ScrollView (no scroll state, wheel passes through);
/// only beyond the visible cap does a bounded ScrollView appear. The
/// hover `+` is driven by per-surface hover tracking with a short
/// cancellable exit, so crossing label→plus→plus on macOS 26 can never
/// produce a visible-off frame or a disabled control.
///
/// Sheet import/export live in the File menu (NumlexApp commands); the
/// sidebar carries no file-action row. The background is the native
/// window background; there is no fake titlebar, traffic-light row or
/// sidebar toggle.
struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var renamingID: UUID?
    /// The folder tab currently in inline rename (a folder created via
    /// the hover `+` opens straight into it).
    @State private var renamingFolderID: UUID?
    /// The tab a sheet drag currently targets (glass swap only — no
    /// geometry change). SidebarGroup-based so General (nil id) can
    /// never match an idle nil by accident.
    @State private var dropTargetGroup: SidebarGroup?

    // MARK: r41 hover tracking

    /// The r41 hover model. The macOS 26 failure mode this bridges: a
    /// container-level `.onHover` is NOT reliably kept true while the
    /// pointer moves onto a CHILD Button (the child's own tracking area
    /// can emit the parent's hover-exit), and the r40 single-parent
    /// hover plus `.allowsHitTesting(hidden)` therefore flickered the
    /// plus OFF exactly when the pointer reached it — the control hid
    /// itself before the click could land.
    ///
    /// Robust semantics:
    ///  - Each tab tracks its TWO surfaces independently: the selection
    ///    label (the row surface) and the reserved plus slot (the slot
    ///    surface). Visibility is their UNION — moving label→slot can
    ///    lose the row surface but gains the slot surface in the same
    ///    gesture batch, so the plus is never visible-off while the
    ///    pointer is anywhere in the row.
    ///  - The slot surface is hover-capable BEFORE the reveal: a clear,
    ///    always-hit-testable sentinel occupies the reserved slot, so
    ///    the pointer can arm the plus by moving into it.
    ///  - The plus BUTTON is hit-testable only while armed: a blind
    ///    click on a hidden slot falls through to the sentinel (which
    ///    has no action) and can never create a folder.
    ///  - Hover ENTER is immediate; hover EXIT is deferred by a short
    ///    CANCELLABLE grace (80 ms): if any surface of the same tab is
    ///    re-entered within the window (e.g. the sentinel→button handoff
    ///    when the plus reveals under a stationary cursor), the pending
    ///    exit is invalidated. Leaving the full row hides the plus after
    ///    the grace — imperceptibly.
    ///
    /// Invariant: `armed(tab) == (row or slot surface of tab currently
    /// hovered) && !renaming(tab) && !dragOver`. Selection and plus stay
    /// separate hit targets; clicking the plus never activates the
    /// hovered source tab.
    /// Surfaces currently inside the row/slot (keys: "row|<gid>" /
    /// "slot|<gid>").
    @State private var hoverSurfaces: Set<String> = []
    /// Pending deferred-exit generations per surface key; a newer
    /// generation (from an enter or a later exit) invalidates it.
    @State private var hoverExitGeneration: [String: Int] = [:]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var language: AppLanguage { model.settings.language }

    /// The shared top action shape: the rounded-10 continuous rect of
    /// the original r38 New Sheet button. Folder tabs pass this SAME
    /// value to their glass, so the active/drop tab pill is mechanically
    /// identical to the sidebar action controls (r41: no second radius
    /// literal that could drift).
    private var sidebarButtonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    /// r40: the VISIBLE-list signature — the sheet ids of the ACTIVE
    /// tab plus the tab identity: switching tabs, creating, deleting or
    /// moving visible sheets changes exactly this value; a plain rename
    /// or a change in ANOTHER tab never reflows the visible list.
    private var visibleSignature: String {
        let fid = model.activeGroupID
        let ids = model.sheets(in: fid).map { $0.sheet.id.uuidString }
        return "\(fid?.uuidString ?? "-")|\(ids.joined(separator: ","))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The action row: the original full-width New Sheet button
            // alone (folder creation lives on the hover + of the tabs).
            Button {
                model.newSheet()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.capsule")
                    Text(L10n.t("newSheet", language: language))
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive().tint(.white.opacity(0.10)),
                        in: sidebarButtonShape)
            .help(L10n.t("newSheet", language: language))

            // A hairline between the action row and the list: the
            // native Divider only — no glass, no material, no custom
            // rectangle. Inset 4 pt per side so it sits optically
            // inside the sidebar padding.
            Divider()
                .padding(.horizontal, 4)

            // The upper sheet list: the sheets of the ACTIVE tab only —
            // no group headers, no nesting, no disclosure state. A plain
            // (non-lazy) VStack is DELIBERATE: sheet rows are lightweight
            // sidebar metadata and coherent full-list reflow (tab switch,
            // insert, remove, move) matters more than lazy realization.
            // 50-row lists stay cheap: each row is two text lines and one
            // optional glass pill. The list takes the flexible remaining
            // height between the action row and the bottom tabs.
            ScrollView {
                let entries = model.sheets(in: model.activeGroupID)
                VStack(spacing: 5) {
                    if entries.isEmpty {
                        // A calm localized empty state — no auto-created
                        // sheet, no faked selection.
                        Text(L10n.t("folderEmpty", language: language))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 28)
                    } else {
                        ForEach(entries, id: \.sheet.id) { entry in
                            sheetRow(idx: entry.index, sheet: entry.sheet)
                                .transition(reduceMotion ? .identity : sectionTransition)
                        }
                    }
                }
                // Row insertion/removal/move/tab-switch animates ONLY
                // inside this list: the transaction is scoped here, so
                // the editor and answer column (which also observe the
                // model) never pick up an animated transaction. 0.34 s
                // keeps the reflow visibly progressive at 60 fps without
                // bounce; reduceMotion gets no decorative animation.
                .animation(reduceMotion ? nil : .snappy(duration: 0.34),
                           value: visibleSignature)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
            // Any deletion path that removes the row currently being
            // renamed clears the stale rename state.
            .onChange(of: model.sheets.map(\.id)) { _, ids in
                if let rid = renamingID, !ids.contains(rid) { renamingID = nil }
            }
            // A folder going away clears a stale rename, repairs the
            // active tab (an invalid folder always falls back to
            // General) and drops hover state that could point at a
            // stale row (r41).
            .onChange(of: model.folders.map(\.id)) { _, ids in
                if let fid = renamingFolderID, !ids.contains(fid) {
                    renamingFolderID = nil
                }
                model.repairActiveGroup()
                cleanStaleHover(ids: ids)
            }

            // The native inset hairline separating the scrolling sheets
            // from the pinned tab strip.
            Divider()
                .padding(.horizontal, 4)

            // The pinned bottom folder tabs.
            folderTabs
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(idealWidth: 235, maxWidth: 260)
    }

    /// The shared row transition: insertion is the standard top entry
    /// (slide down from the top edge + fade in, no x motion, no scale),
    /// removal is a short opacity fade plus a slight leading nudge.
    /// reduceMotion callers substitute .identity.
    private var sectionTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity.combined(with: .offset(x: -12)))
    }

    // MARK: r41 hover plumbing

    private enum TabHoverSurface: String { case row, slot }

    private func hoverKey(_ surface: TabHoverSurface, _ group: SidebarGroup) -> String {
        let gid: String
        switch group {
        case .folder(let id): gid = id.uuidString
        case .general, .none: gid = "general"
        }
        return "\(surface.rawValue)|\(gid)"
    }

    /// Enter/exit of one hover surface of one tab. Enter is immediate
    /// and invalidates any pending exit for that surface; exit schedules
    /// a short cancellable removal (see the r41 hover notes above).
    private func hover(_ surface: TabHoverSurface, _ group: SidebarGroup, inside: Bool) {
        let key = hoverKey(surface, group)
        if inside {
            hoverExitGeneration[key, default: 0] += 1
            hoverSurfaces.insert(key)
        } else {
            guard hoverSurfaces.contains(key) else { return }
            let generation = (hoverExitGeneration[key] ?? 0) + 1
            hoverExitGeneration[key] = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard hoverExitGeneration[key] == generation,
                      hoverSurfaces.contains(key) else { return }
                hoverSurfaces.remove(key)
            }
        }
    }

    /// The `+` of a tab is armed while either of its surfaces is hovered
    /// and nothing shadows it (an inline rename on that tab, or a sheet
    /// drag over the row).
    private func plusArmed(_ group: SidebarGroup, isRenaming: Bool) -> Bool {
        guard !isRenaming, dropTargetGroup == nil else { return false }
        return hoverSurfaces.contains(hoverKey(.row, group))
            || hoverSurfaces.contains(hoverKey(.slot, group))
    }

    /// Folds the hover state after the folder list changed: a surface
    /// whose folder no longer exists is dropped and its pending exit is
    /// cancelled, so hover state can never point at a stale row (r41).
    private func cleanStaleHover(ids: [UUID]) {
        let valid = Set(ids)
        hoverSurfaces = hoverSurfaces.filter { key in
            let gid = key.split(separator: "|").last.map(String.init) ?? ""
            return gid == "general" || valid.contains(UUID(uuidString: gid)!)
        }
        for (key, taskGen) in hoverExitGeneration where !hoverSurfaces.contains(key) {
            _ = taskGen // the deferred check re-validates against hoverSurfaces
        }
        hoverExitGeneration = hoverExitGeneration.filter { hoverSurfaces.contains($0.key) }
    }

    // MARK: Bottom folder tabs

    /// The pinned bottom tab strip (r41, adaptive). Up to the visible
    /// cap (General + 5 custom) the rows are a PLAIN fixed VStack pinned
    /// at the bottom — no ScrollView exists at all, so a wheel or
    /// trackpad over the tabs neither scrolls nor bounces and there is
    /// no scroll state to carry. Only when the total rows EXCEED the
    /// cap is a bounded ScrollView constructed, at exactly the capped
    /// height; the sheet list above keeps the remaining space in both
    /// cases. Both presentations share `tabRows`, so the rows — and
    /// with them UUID identity, active selection, rename target, hover
    /// and drop semantics (all model- or SidebarView-level state) — are
    /// geometrically and behaviorally identical across the threshold.
    /// (The one transient that a threshold crossing re-creates is the
    /// field editor of an in-progress rename; it re-opens focused with
    /// the stored title selected.)
    @ViewBuilder
    private var folderTabs: some View {
        if SheetOrganization.tabStripScrolls(customFolderCount: model.folders.count) {
            ScrollView {
                tabRows
            }
            .frame(height: Self.tabStripHeight(rows: SheetOrganization.tabVisibleCap))
            .scrollIndicators(.hidden)
        } else {
            tabRows
                .frame(height: Self.tabStripHeight(rows: model.folders.count + 1))
        }
    }

    /// The shared tab-row stack: General first, then the ordered custom
    /// folders. ONE builder for both presentations (no duplicate row
    /// code, no duplicate identity).
    private var tabRows: some View {
        VStack(spacing: 3) {
            folderTabRow(groupID: nil,
                         title: L10n.t("folderGeneral", language: language),
                         icon: "list.bullet.rectangle",
                         isCustom: false)
            ForEach(model.folders) { folder in
                folderTabRow(groupID: folder.id,
                             title: folder.title,
                             icon: "folder",
                             isCustom: true)
            }
        }
        .padding(.vertical, 1)
    }

    /// Exact stack height for `rows` tab rows (26 pt each, 3 pt
    /// spacing, 1 pt vertical padding) — the fixed and capped
    /// presentations agree mechanically, so crossing the threshold
    /// does not change the strip's footprint when at the cap.
    private static func tabStripHeight(rows: Int) -> CGFloat {
        let r = max(rows, 1)
        return CGFloat(r) * 26 + CGFloat(max(r - 1, 0)) * 3 + 2
    }

    /// One folder tab: a compact full-width row (SF symbol + 13pt
    /// primary title) with a RESERVED trailing control slot. The slot
    /// carries the hover `+` (create a sibling folder): opacity-hidden
    /// and non-hit-testable until armed, but the SLOT ITSELF is always
    /// hover-capable via a clear sentinel, so the reveal is driven by
    /// the pointer alone (r41 hover model). Tab selection and the plus
    /// are SEPARATE hit targets — clicking the plus never first
    /// activates the hovered tab. The whole row is a drop target for
    /// sheet moves; custom tabs additionally keep the Rename and (safe)
    /// Delete context items, General cannot be renamed or deleted.
    @ViewBuilder
    private func folderTabRow(groupID: UUID?, title: String, icon: String,
                              isCustom: Bool) -> some View {
        let thisGroup: SidebarGroup = groupID.map { .folder($0) } ?? .general
        let isRenaming = isCustom && renamingFolderID == groupID
        let armed = plusArmed(thisGroup, isRenaming: isRenaming)
        HStack(spacing: 0) {
            // Selection surface: icon + title (or the inline rename
            // field while renaming). Its own hover feeds the ROW
            // surface of the union.
            Button {
                model.activate(group: thisGroup)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Group {
                        if isRenaming {
                            RenameField(initial: title) { value in
                                model.renameFolder(id: groupID!, to: value)
                                renamingFolderID = nil
                            } onCancel: {
                                renamingFolderID = nil
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text(title)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Double-click renames the custom tab in place.
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    if isCustom { renamingFolderID = groupID }
                }
            )
            .onHover { inside in
                hover(.row, thisGroup, inside: inside)
            }
            // r41: the context menu lives on THIS node (the same one the
            // row hover tracks), never on an ancestor: on macOS 26 a
            // tracking boundary (contextMenu/help) on an ANCESTOR kills
            // the child's .onHover, which would dead the whole reveal.
            // Same-node tracking coexists with the hover (General tab:
            // empty menu, same pattern, shows nothing).
            .contextMenu {
                if isCustom {
                    Button {
                        model.newSheet(in: .folder(groupID!))
                    } label: {
                        Label(L10n.t("newSheetInFolder", language: language), systemImage: "plus")
                    }
                    Button {
                        renamingFolderID = groupID
                    } label: {
                        Label(L10n.t("renameFolder", language: language), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        model.deleteFolder(id: groupID!)
                    } label: {
                        Label(L10n.t("deleteFolder", language: language), systemImage: "trash")
                    }
                    // The wording intentionally does not imply the sheets
                    // are deleted: they are moved to General.
                    .help(L10n.t("deleteFolderHelp", language: language))
                }
            }
            // Reserved trailing control slot: a FIXED 26x26 in every
            // state, so the title and icon never shift when the plus
            // appears or the row becomes active. Two layers:
            //  (1) the SENTINEL — clear, always hit-testable, actionless:
            //      it receives hover even while the plus is hidden, so
            //      the pointer can arm the reveal by entering the slot.
            //  (2) the plus BUTTON — visible and hit-testable ONLY while
            //      armed; a blind click on a hidden slot falls through
            //      to the sentinel and creates nothing.
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hover(.slot, thisGroup, inside: inside)
                    }
                    .contextMenu {
                        if isCustom {
                            Button {
                                model.newSheet(in: .folder(groupID!))
                            } label: {
                                Label(L10n.t("newSheetInFolder", language: language), systemImage: "plus")
                            }
                            Button {
                                renamingFolderID = groupID
                            } label: {
                                Label(L10n.t("renameFolder", language: language), systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                model.deleteFolder(id: groupID!)
                            } label: {
                                Label(L10n.t("deleteFolder", language: language), systemImage: "trash")
                            }
                            .help(L10n.t("deleteFolderHelp", language: language))
                        }
                    }
                Button {
                    renamingFolderID = model.createFolder(after: thisGroup)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(armed ? 1 : 0)
                .allowsHitTesting(armed)
                // .onHover sits BEFORE .help so the tooltip's tracking
                // boundary (if any) wraps the hover source instead of
                // interposing it.
                .onHover { inside in
                    hover(.slot, thisGroup, inside: inside)
                }
                .help(L10n.t("newFolder", language: language))
                .accessibilityLabel(L10n.t("newFolder", language: language))
            }
            .frame(width: 26, height: 26)
        }
        .frame(height: 26)
        // The ONE glass layer. r41: the tab glass is the SAME
        // `sidebarButtonShape` (rounded-10 continuous) as the sidebar
        // action controls — passed in, not re-literalized. The stronger
        // tint appears while a sheet drag hovers the tab (drop feedback,
        // no geometry shift), the regular pill when this tab is the
        // active filter, no material otherwise.
        .modifier(RowGlassModifier(isSelected: model.activeGroup == thisGroup,
                                   isDropTarget: dropTargetGroup == thisGroup,
                                   shape: sidebarButtonShape))
        // Sheet drags land on tabs (General and folders). The plus stays
        // hidden and non-actionable during a drag (armed requires no
        // drop target), the drop target remains the full row.
        .dropDestination(for: SheetDragItem.self) { items, _ in
            for item in items {
                model.moveSheet(id: item.sheetID, to: groupID)
            }
            dropTargetGroup = nil
            return !items.isEmpty
        } isTargeted: { targeted in
            if targeted {
                dropTargetGroup = thisGroup
            } else if dropTargetGroup == thisGroup {
                dropTargetGroup = nil
            }
        }
        // r41: NO contextMenu (or any tracking boundary) on the row
        // container — an ancestor tracking boundary kills the children's
        // .onHover on macOS 26 (verified experimentally on this build).
        // The menu is served from the row and slot nodes themselves.
        // Subtle opacity-only reveal; instant under Reduce Motion.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12),
                   value: armed)
        .accessibilityLabel(isCustom ? title
            : L10n.t("folderGeneral", language: language))
        .accessibilityHint(L10n.t("dropSheetHere", language: language))
    }

    // MARK: Sheet rows

    @ViewBuilder
    private func sheetRow(idx: Int, sheet: Sheet) -> some View {
        let language = model.settings.language
        // Localized line count only ("No lines", "1 line", "N lines");
        // the created-time label is rendered separately in the same row.
        let count: String = {
            if sheet.lineCount == 0 {
                return L10n.t("noLines", language: language)
            }
            let unit = L10n.t(sheet.lineCount == 1 ? "line" : "lines", language: language)
            return "\(sheet.lineCount) \(unit)"
        }()
        let isSelected = idx == model.selectedIndex
        // The row is a plain button for the single-click select (no tap
        // delay). The double-click rename is a simultaneous count-2
        // gesture on the button itself. The row is also the DRAG SOURCE
        // for moving the sheet to another tab (private payload).
        Button {
            model.select(index: idx)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                titleView(sheet: sheet)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Metadata: created time leading, localized line count
                // trailing, both 11pt secondary; the count keeps its
                // trailing alignment across every row.
                HStack(spacing: 8) {
                    Text(sheet.createdLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(count)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                model.select(index: idx)
                renamingID = sheet.id
            }
        )
        // Selection is exactly one layer: the system liquid glass pill,
        // present only on the selected row (the System Settings look and
        // the reference's spirit: an unselected row shows no material).
        // Sheet rows deliberately keep the radius-11 look (the r38
        // sidebar row shape); only the folder tabs adopt the radius-10
        // action shape (r41).
        .modifier(RowGlassModifier(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        // Drag the row onto a bottom tab to move the sheet. The payload
        // carries only the stable UUID (SheetDragItem), so an external
        // drag can never move a sheet.
        .draggable(SheetDragItem(sheetID: sheet.id))
        .contextMenu {
            // Move to Folder: General + every custom folder; the
            // current destination is disabled (native menu affordance).
            Menu(L10n.t("moveToFolder", language: language)) {
                Button(L10n.t("folderGeneral", language: language)) {
                    model.moveSheet(id: sheet.id, to: nil)
                }
                .disabled(sheet.folderID == nil)
                ForEach(model.folders) { folder in
                    Button(folder.title) {
                        model.moveSheet(id: sheet.id, to: folder.id)
                    }
                    .disabled(sheet.folderID == folder.id)
                }
            }
            Button {
                renamingID = sheet.id
            } label: {
                Label(L10n.t("rename", language: language), systemImage: "pencil")
            }
            Button(role: .destructive) {
                model.deleteSheet(at: idx)
            } label: {
                Label(L10n.t("deleteSheet", language: language), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func titleView(sheet: Sheet) -> some View {
        if sheet.id == renamingID {
            RenameField(initial: sheet.title) { value in
                model.renameSheet(id: sheet.id, to: value)
                renamingID = nil
            } onCancel: {
                renamingID = nil
            }
        } else {
            Text(sheet.displayTitle(language: model.settings.language))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// The private in-app drag payload for sheet moves — carries only the
/// STABLE sheet UUID, so an arbitrary external drag (text, files,
/// other apps) can never match the type and move a sheet.
struct SheetDragItem: Codable, Transferable {
    let sheetID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .numlexSheetMove)
    }
}

extension UTType {
    /// The private (app-only) drag type for sheet-to-tab moves.
    static let numlexSheetMove = UTType(exportedAs: "com.numlex.app.sheet-move")
}

/// Selection/drop glass. The shape is EXPLICIT so each caller controls
/// its own corner radius from a single source of truth: sheet rows keep
/// the radius-11 sidebar-row look, folder tabs pass `sidebarButtonShape`
/// (radius-10 continuous — the exact shape of the sidebar action
/// controls), and the drop/selected layers always share the SAME shape
/// as the hit/content row (r41: no duplicated drifting radius literal).
///
/// The LOCAL no-animation transaction is attached to the glass layer
/// ONLY, never to `content`: the glass appearing/disappearing is a
/// structural change that would otherwise inherit the list's
/// transaction and crossfade over the reflow duration (the highlight
/// appeared to travel between rows). With `animation = nil` on the
/// layer, the glass material switches instantly at the correct row,
/// while the row frame — and, for a freshly inserted selected row, the
/// whole composited row including this background — still moves and
/// fades with the caller's insertion transition and layout animation.
/// The layer is pure background: it never intercepts row hit-testing.
private struct RowGlassModifier: ViewModifier {
    var isSelected: Bool
    /// The drop-target state (a sheet drag currently hovers this row)
    /// — the same shape with a stronger tint.
    var isDropTarget: Bool = false
    /// The glass shape (default: the radius-11 sheet-row look).
    var shape: RoundedRectangle = RoundedRectangle(cornerRadius: 11, style: .continuous)

    func body(content: Content) -> some View {
        content.background {
            if isDropTarget {
                Color.clear
                    .glassEffect(.regular.interactive().tint(.white.opacity(0.22)), in: shape)
                    .transaction { $0.animation = nil }
            } else if isSelected {
                Color.clear
                    .glassEffect(.regular.interactive().tint(.white.opacity(0.10)), in: shape)
                    .transaction { $0.animation = nil }
            }
        }
    }
}

/// Inline rename field: commits on submit or focus loss.
/// Inline rename field: takes focus immediately with the whole title
/// selected (type to replace), commits on Return or focus loss, cancels
/// (restoring the original title) on Escape. NSViewRepresentable so the
/// selection and the Escape key are under our control.
private struct RenameField: NSViewRepresentable {
    let initial: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    init(initial: String,
         onCommit: @escaping (String) -> Void,
         onCancel: @escaping () -> Void = {}) {
        self.initial = initial
        self.onCommit = onCommit
        self.onCancel = onCancel
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = RenameFieldView()
        field.delegate = context.coordinator
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        field.textColor = .labelColor
        field.stringValue = initial
        field.onEscape = { context.coordinator.cancel() }
        context.coordinator.field = field
        context.coordinator.onCancel = onCancel
        DispatchQueue.main.async {
            guard let window = field.window,
                  window.makeFirstResponder(field) else { return }
            // Select the whole title in the field editor so typing
            // replaces it. (The field itself answers neither the
            // selectAll: action nor setSelectedRange: until it is the
            // first responder, so the editor is the right handle.)
            if let editor = window.fieldEditor(true, for: field) as? NSTextView {
                editor.setSelectedRange(NSRange(location: 0,
                                                 length: editor.string.count))
            }
        }
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Catches Escape before the field's default handling.
    final class RenameFieldView: NSTextField {
        var onEscape: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { // Esc
                onEscape?()
                return
            }
            super.keyDown(with: event)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameField
        weak var field: RenameFieldView?
        var onCancel: () -> Void = {}
        private var alreadyHandled = false

        init(_ parent: RenameField) { self.parent = parent }

        /// Escape: restore the original title, end editing, no commit.
        func cancel() {
            alreadyHandled = true
            field?.stringValue = parent.initial
            field?.window?.makeFirstResponder(nil)
            onCancel()
        }

        private func currentText() -> String {
            field?.stringValue ?? parent.initial
        }

        // MARK: NSTextFieldDelegate

        func controlTextDidEndEditing(_ notification: Notification) {
            // Focus loss (clicking elsewhere) commits, unless Enter or
            // Escape already handled this edit session.
            if !alreadyHandled {
                alreadyHandled = true
                parent.onCommit(currentText())
            }
            alreadyHandled = false
        }
    }
}
