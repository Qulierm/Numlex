import SwiftUI
import NumlexCore
import UniformTypeIdentifiers

/// Sheets sidebar (liquid-glass redesign, r39 one-level folders):
/// a padded leading VStack with the New Sheet + New Folder action row,
/// the built-in localized General group and the ordered custom folder
/// groups. Every row uses the system liquid glass materials — the
/// selected sheet and the active container show the regular interactive
/// pill, a hovered drop target a stronger tint — so the sidebar stays
/// calm in inactive windows and both appearances.
///
/// r39: the bottom Settings gear row is GONE — the Settings scene is
/// reachable through the system-provided Settings… menu item and ⌘,
/// only; the sidebar bottom is clean with no replacement icon.
///
/// Sheet import/export live in the File menu (NumlexApp commands); the
/// sidebar carries no file-action row. The background is the native
/// window background; there is no fake titlebar, traffic-light row or
/// sidebar toggle.
struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var renamingID: UUID?
    /// r39: the folder currently in inline rename (a fresh folder opens
    /// straight into it).
    @State private var renamingFolderID: UUID?
    /// r39: collapsed custom folders (presentation-only — every folder
    /// is expanded on launch; never persisted).
    @State private var collapsedFolderIDs: Set<UUID> = []
    /// r39: the group a sheet drag currently targets (glass swap only —
    /// no geometry change). SidebarGroup-based so the General group
    /// (nil id) can never match an idle nil by accident.
    @State private var dropTargetGroup: SidebarGroup?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var language: AppLanguage { model.settings.language }

    /// The ONE shared shape of the top action-row buttons (New Sheet,
    /// New Folder): the exact same rounded rect, so the two rows can
    /// never drift apart visually.
    private var sidebarButtonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    /// r39: the list-structure signature — sheet ids WITH their group
    /// membership plus the folder ids: creation, deletion, moves between
    /// groups and folder add/remove all change exactly this value (a
    /// plain rename does not reflow).
    private var listSignature: String {
        var parts = model.sheets.map { "\($0.id.uuidString):\($0.folderID?.uuidString ?? "-")" }
        parts.append(contentsOf: model.folders.map { "f:\($0.id.uuidString)" })
        return parts.joined(separator: ";")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // The action row: New Sheet keeps its label and the full
            // remaining width (prominence unchanged); New Folder is a
            // compact icon-only companion sharing the exact same
            // rounded-10 continuous shape. Both sit below the toolbar
            // traffic lights (the split-view content never extends into
            // the toolbar area).
            HStack(spacing: 6) {
                // New Sheet: explicit destination = the active sidebar
                // container; with none active it inherits the selected
                // sheet's folder (AppModel.newSheet(in:)).
                Button {
                    model.newSheet(in: model.activeGroup)
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

                // New Folder: creates with the generated localized
                // unique name, selects it (active container) and opens
                // its inline rename immediately.
                Button {
                    renamingFolderID = model.createFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .frame(width: 20)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive().tint(.white.opacity(0.10)),
                            in: sidebarButtonShape)
                .help(L10n.t("newFolder", language: language))
                .accessibilityLabel(L10n.t("newFolder", language: language))
            }

            // A hairline between the action row and the list: the
            // native Divider only — no glass, no material, no custom
            // rectangle. Inset 4 pt per side so it sits optically
            // inside the sidebar padding.
            Divider()
                .padding(.horizontal, 4)

            // The grouped sheet list: the built-in General group first
            // (never collapsible), then the custom folders in order.
            // A plain (non-lazy) VStack is DELIBERATE here: sheet rows
            // are lightweight sidebar metadata, and coherent full-list
            // reflow matters more than lazy realization (a lazy stack
            // does not guarantee coordinated insertion reflow). 50-row
            // lists stay cheap: each row is two text lines and one
            // optional glass pill.
            ScrollView {
                VStack(spacing: 5) {
                    groupSection(groupID: nil,
                                 title: L10n.t("folderGeneral", language: language),
                                 icon: "list.bullet.rectangle",
                                 isFolder: false,
                                 isExpanded: true)
                        .transition(reduceMotion ? .identity : sectionTransition)
                    ForEach(model.folders) { folder in
                        groupSection(groupID: folder.id,
                                     title: folder.title,
                                     icon: collapsedFolderIDs.contains(folder.id)
                                         ? "folder" : "folder.fill",
                                     isFolder: true,
                                     isExpanded: !collapsedFolderIDs.contains(folder.id))
                            .transition(reduceMotion ? .identity : sectionTransition)
                    }
                }
                // Row/section insertion/removal/move/reflow animates ONLY
                // inside this list: the value changes exactly when the
                // sheet id + group + folder structure changes, and the
                // transaction is scoped here, so the editor and answer
                // column (which also observe the model) never pick up an
                // animated transaction. 0.34 s keeps the reflow
                // visibly progressive at 60 fps without bounce.
                // reduceMotion gets no decorative animation at all.
                .animation(reduceMotion ? nil : .snappy(duration: 0.34),
                           value: listSignature)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            // Any deletion path that removes the row currently being
            // renamed clears the stale rename state.
            .onChange(of: model.sheets.map(\.id)) { _, ids in
                if let rid = renamingID, !ids.contains(rid) { renamingID = nil }
            }
            // r39: stale folder rename/collapsed IDs clean themselves
            // when a folder goes away.
            .onChange(of: model.folders.map(\.id)) { _, ids in
                if let fid = renamingFolderID, !ids.contains(fid) { renamingFolderID = nil }
                let valid = Set(ids)
                if collapsedFolderIDs.isDisjoint(with: valid) {
                    collapsedFolderIDs = []
                } else {
                    collapsedFolderIDs = collapsedFolderIDs.intersection(valid)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(idealWidth: 235, maxWidth: 260)
    }

    /// The shared asymmetric row/section transition: insertion is the
    /// standard top entry (slide down from the top edge + fade in, no x
    /// motion, no scale), removal is a short opacity fade plus a slight
    /// leading nudge. reduceMotion callers substitute .identity.
    private var sectionTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity.combined(with: .offset(x: -12)))
    }

    // MARK: Group sections

    /// One rendered group: the compact full-width header row (SF symbol
    /// + 13pt primary label, reference-style) plus its child sheet rows
    /// indented one step. Custom folders are collapsible (chevron) and
    /// droppable; the built-in General group is not collapsible but is
    /// an equally valid drop target.
    @ViewBuilder
    private func groupSection(groupID: UUID?, title: String, icon: String,
                              isFolder: Bool, isExpanded: Bool) -> some View {
        let entries = model.sheets(in: groupID)
        // The SidebarGroup identity of this row: .general for the
        // built-in group, .folder(id) for custom ones. Used for the
        // drop-target state so a nil id can never match an idle nil.
        let thisGroup: SidebarGroup = groupID.map { .folder($0) } ?? .general
        HStack(spacing: 2) {
            if isFolder {
                // Disclosure: collapses/expands the group only (the
                // editor sheet is never touched by this).
                Button {
                    if collapsedFolderIDs.contains(groupID!) {
                        collapsedFolderIDs.remove(groupID!)
                    } else {
                        collapsedFolderIDs.insert(groupID!)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 14, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t(isExpanded ? "collapseFolder" : "expandFolder",
                                           language: language))
            } else {
                // Spacers so the General icon aligns under the folder
                // icons (chevron column width).
                Color.clear.frame(width: 14, height: 16)
            }
            Button {
                model.activate(group: isFolder ? .folder(groupID!) : .general)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if isFolder, renamingFolderID == groupID {
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
                    }
                    Spacer(minLength: 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Double-click renames the folder in place.
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    if isFolder { renamingFolderID = groupID }
                }
            )
            .accessibilityLabel(isFolder ? title
                : L10n.t("folderGeneral", language: language))
            .accessibilityValue(isFolder
                ? L10n.t(isExpanded ? "folderExpanded" : "folderCollapsed", language: language)
                : "")
            .accessibilityHint(L10n.t("dropSheetHere", language: language))
        }
        // The ONE glass layer: the stronger tint while a sheet drag
        // hovers the group (drop feedback, no geometry shift), the
        // regular pill when the container is the active selection.
        // (For General, groupID is nil — require a REAL target id so
        // the idle state never matches nil == nil.)
        .modifier(RowGlassModifier(isSelected: isActive(groupID),
                                   isDropTarget: dropTargetGroup == thisGroup))
        // r39: sheet drags land on group rows (General and folders).
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
            if isFolder {
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

        if isExpanded {
            ForEach(entries, id: \.sheet.id) { entry in
                sheetRow(idx: entry.index, sheet: entry.sheet)
                    // One step of indentation under the group icon; the
                    // rows keep their own 10pt horizontal padding, so
                    // the list still fits the 180pt minimum column.
                    .padding(.leading, 14)
            }
        }
    }

    /// r39: whether this group is the active container selection
    /// (the reference-style highlight).
    private func isActive(_ groupID: UUID?) -> Bool {
        switch model.activeGroup {
        case .none:
            return false
        case .general:
            return groupID == nil
        case .folder(let id):
            return id == groupID
        }
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
        // for moving the sheet between groups (private payload).
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
        // r39: drag the row onto a group row to move the sheet. The
        // payload carries only the stable UUID (SheetDragItem), so an
        // external drag can never move a sheet.
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

/// r39: the private in-app drag payload for sheet moves — carries only
/// the STABLE sheet UUID, so an arbitrary external drag (text, files,
/// other apps) can never match the type and move a sheet.
struct SheetDragItem: Codable, Transferable {
    let sheetID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .numlexSheetMove)
    }
}

extension UTType {
    /// The private (app-only) drag type for sheet-to-group moves.
    static let numlexSheetMove = UTType(exportedAs: "com.numlex.app.sheet-move")
}

/// Selection/drop glass: the regular interactive liquid glass pill
/// appears ONLY on the selected row / active container row, and a
/// stronger tint appears while a sheet drag targets the group —
/// unselected rows render no material at all (both `Glass.clear` and
/// `.identity` draw a visible frosted panel on macOS 26, which would
/// light up every row like a button instead of staying calm like the
/// system sidebar). The row content itself stays structurally stable
/// in every state (drop feedback is a pure background swap — no
/// geometry shift).
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
    /// r39: the drop-target state (a sheet drag currently hovers this
    /// group row) — the same shape with a stronger tint.
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
