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
    /// The tab row the pointer currently hovers (drives the trailing
    /// `+` reveal; presentation-only).
    @State private var hoveredTab: SidebarGroup?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var language: AppLanguage { model.settings.language }

    /// The shared top action shape: the rounded-10 continuous rect of
    /// the original r38 New Sheet button.
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
            // A folder going away clears a stale rename and repairs the
            // active tab (an invalid folder always falls back to
            // General).
            .onChange(of: model.folders.map(\.id)) { _, ids in
                if let fid = renamingFolderID, !ids.contains(fid) {
                    renamingFolderID = nil
                }
                model.repairActiveGroup()
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

    // MARK: Bottom folder tabs

    /// The pinned bottom tab strip: General first, then the ordered
    /// custom folders. The upper list keeps the flexible remaining
    /// height; this strip stays compact — only when the tabs exceed
    /// the visible cap does THIS region scroll (indicators hidden), so
    /// many folders can never consume the sheet area.
    private var folderTabs: some View {
        let rows = model.folders.count + 1
        let visible = min(rows, 6)
        let height = CGFloat(visible) * 26 + CGFloat(max(visible - 1, 0)) * 3
        return ScrollView {
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
        .frame(height: height)
        .scrollIndicators(.hidden)
    }

    /// One folder tab: a compact full-width row (SF symbol + 13pt
    /// primary title) with a RESERVED trailing control slot. The slot
    /// carries the hover `+` (create a sibling folder): opacity-hidden
    /// and non-hit-testable until the row is hovered, so the title
    /// geometry never shifts. Tab selection and the plus are SEPARATE
    /// hit targets inside one hover container — clicking the plus never
    /// first activates the hovered tab. The whole row is a drop target
    /// for sheet moves; custom tabs additionally keep the Rename and
    /// (safe) Delete context items, General cannot be renamed or
    /// deleted.
    @ViewBuilder
    private func folderTabRow(groupID: UUID?, title: String, icon: String,
                              isCustom: Bool) -> some View {
        let thisGroup: SidebarGroup = groupID.map { .folder($0) } ?? .general
        let isRenaming = isCustom && renamingFolderID == groupID
        let plusVisible = hoveredTab == thisGroup
            && !isRenaming
            && dropTargetGroup == nil
        HStack(spacing: 0) {
            // Selection target: icon + title (or the inline rename
            // field while renaming).
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
            // Reserved trailing control slot: a FIXED size in every
            // state, so the title and icon never shift when the plus
            // appears or the row becomes active.
            ZStack {
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
                .opacity(plusVisible ? 1 : 0)
                .allowsHitTesting(plusVisible)
                .help(L10n.t("newFolder", language: language))
                .accessibilityLabel(L10n.t("newFolder", language: language))
            }
            .frame(width: 26, height: 26)
        }
        .frame(height: 26)
        // The ONE glass layer: the stronger tint while a sheet drag
        // hovers the tab (drop feedback, no geometry shift), the
        // regular pill when this tab is the active filter, no material
        // otherwise.
        .modifier(RowGlassModifier(isSelected: model.activeGroup == thisGroup,
                                   isDropTarget: dropTargetGroup == thisGroup))
        // Sheet drags land on tabs (General and folders).
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
        .onHover { hovering in
            if hovering {
                hoveredTab = thisGroup
            } else if hoveredTab == thisGroup {
                hoveredTab = nil
            }
        }
        // Subtle opacity-only reveal; instant under Reduce Motion.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12),
                   value: plusVisible)
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

/// Selection/drop glass: the regular interactive liquid glass pill
/// appears ONLY on the selected row / active tab row, and a stronger
/// tint appears while a sheet drag targets the tab — unselected rows
/// render no material at all (both `Glass.clear` and `.identity` draw a
/// visible frosted panel on macOS 26, which would light up every row
/// like a button instead of staying calm like the system sidebar). The
/// row content itself stays structurally stable in every state (drop
/// feedback is a pure background swap — no geometry shift).
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

    func body(content: Content) -> some View {
        content.background {
            if isDropTarget {
                Color.clear
                    .glassEffect(.regular.interactive().tint(.white.opacity(0.22)),
                                 in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .transaction { $0.animation = nil }
            } else if isSelected {
                Color.clear
                    .glassEffect(.regular.interactive().tint(.white.opacity(0.10)),
                                 in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
