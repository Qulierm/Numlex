import SwiftUI
import NumlexCore

/// Sheets sidebar (liquid-glass redesign, matching the reference layout):
/// a padded leading VStack with a full-width New Sheet button, the
/// selectable sheet list and a full-width Settings button. Both buttons
/// share the exact same rounded-10 continuous shape. Selection and
/// controls use the system liquid glass materials (regular interactive
/// when selected, clear otherwise), so the sidebar stays calm in inactive
/// windows and both appearances. Sheet import/export live in the File
/// menu (NumlexApp commands); the sidebar carries no file-action row.
/// The background is the native window background; there is no fake
/// titlebar, traffic-light row or sidebar toggle.
struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var renamingID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Native SwiftUI settings action: opens the Settings scene and brings
    /// an already-open settings window forward (no duplicates, no AppKit
    /// selector bridge).
    @Environment(\.openSettings) private var openSettings

    /// The ONE shared shape of the two full-width sidebar buttons
    /// (New Sheet, Settings): the exact same rounded rect, so the two
    /// rows can never drift apart visually.
    private var sidebarButtonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // New Sheet: full-width plain button, `plus.capsule` symbol,
            // semibold label, regular interactive glass in the shared
            // sidebarButtonShape (the exact same rounded-10 continuous
            // shape as the Settings row). The hit shape stays a
            // Rectangle: a non-rect contentShape suppresses the glass
            // fill on this system even when the glass shape matches.
            // Sits below the toolbar traffic lights (the split-view
            // content never extends into the toolbar area).
            Button {
                model.newSheet()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.capsule")
                    Text(L10n.t("newSheet", language: model.settings.language))
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive().tint(.white.opacity(0.10)),
                        in: sidebarButtonShape)
            .help(L10n.t("newSheet", language: model.settings.language))

            // A hairline between New Sheet and the list: the native
            // Divider only — no glass, no material, no custom rectangle.
            // Inset 4 pt per side so it sits optically inside the
            // sidebar padding; the VStack's 10 pt spacing on both sides
            // is the breathing room (within the 8–10 pt design band).
            Divider()
                .padding(.horizontal, 4)

            // Sheet list: no caption — the list begins below the New
            // Sheet button, separated by the hairline Divider. Selection
            // is the system regular-interactive glass pill;
            // unselected rows stay clear. The list sits directly on the
            // window background (rows carry their own 10pt horizontal
            // padding).
            ScrollView {
                // A plain (non-lazy) VStack is DELIBERATE here: sheet rows
                // are lightweight sidebar metadata, and coherent full-list
                // reflow matters more than lazy realization. SwiftUI lazy
                // stacks do not guarantee coordinated insertion reflow — on
                // a top insertion only the first realized rows animate and
                // the rest snap, which is exactly the two-top-row movement
                // this list had. A non-lazy stack lays out every row in the
                // same transaction, so the .animation below moves ALL
                // surviving rows down by exactly one row height together
                // (50-row lists stay cheap: each row is two text lines and
                // one optional glass pill).
                VStack(spacing: 5) {
                    ForEach(Array(model.sheets.enumerated()), id: \.element.id) { idx, sheet in
                        sheetRow(idx: idx, sheet: sheet)
                            // Asymmetric: insertion is the standard top
                            // entry — the new row slides down from under
                            // the divider while fading in (no x motion,
                            // no scale), so creation is clearly visible
                            // against the list reflow; removal is a short
                            // opacity fade plus a slight leading nudge.
                            // reduceMotion gets identity (no transition at
                            // all).
                            .transition(reduceMotion
                                        ? .identity
                                        : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                      removal: .opacity.combined(with: .offset(x: -12))))
                    }
                }
                // Row insertion/removal/reflow animates ONLY inside this
                // list: the value changes exactly when the sheet-ID list
                // changes, and the transaction is scoped here, so the
                // editor and answer column (which also observe the model)
                // never pick up an animated transaction on add/delete.
                // 0.34 s keeps the top-entry visibly progressive at 60fps
                // without extra bounce. reduceMotion gets no decorative
                // animation at all.
                .animation(reduceMotion ? nil : .snappy(duration: 0.34),
                           value: model.sheets.map(\.id))
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            // Any deletion path (context menu or app menu) that removes the
            // row currently being renamed clears the stale rename state.
            .onChange(of: model.sheets.map(\.id)) { _, ids in
                if let rid = renamingID, !ids.contains(rid) { renamingID = nil }
            }

            Spacer(minLength: 0)

            // Settings: the lone bottom row, full-width leading label,
            // clear glass in the shared sidebarButtonShape (the exact
            // same rounded-10 continuous shape as New Sheet). A real
            // button; the sidebar gear always opens exactly one Settings
            // window (native openSettings action). Sheet import/export
            // are File-menu commands (Import Sheet… ⌘I / Export Sheet…
            // ⌘E) — no arrow buttons live in the sidebar.
            Button {
                openSettings()
            } label: {
                Label(L10n.t("settings", language: model.settings.language),
                      systemImage: "gear")
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .glassEffect(.clear, in: sidebarButtonShape)
            .help(L10n.t("settings", language: model.settings.language))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(idealWidth: 235, maxWidth: 260)
    }

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
        // gesture on the button itself: a tap gesture on the label would
        // be swallowed by the button, so the gesture owns the whole hit
        // area. On a double tap the button just selects again, which the
        // rename handler already does; on a single tap the select action
        // fires immediately.
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
        .contextMenu {
            Button {
                renamingID = sheet.id
            } label: {
                Label(L10n.t("rename", language: model.settings.language), systemImage: "pencil")
            }
            Button(role: .destructive) {
                model.deleteSheet(at: idx)
            } label: {
                Label(L10n.t("deleteSheet", language: model.settings.language), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func titleView(sheet: Sheet) -> some View {
        if sheet.id == renamingID {
            RenameField(initial: sheet.title) { value in
                model.renameSheet(id: sheet.id, to: value)
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

/// Selection glass: the regular interactive liquid glass pill appears
/// ONLY on the selected row, as a dedicated BACKGROUND layer — the
/// unselected rows render no material at all (both `Glass.clear` and
/// `.identity` draw a visible frosted panel on macOS 26, which would
/// light up every row like a button instead of staying calm like the
/// system sidebar), and the row content itself stays structurally
/// stable in both states.
///
/// The LOCAL no-animation transaction is attached to the glass layer
/// ONLY, never to `content`: the glass appearing/disappearing is a
/// structural change that would otherwise inherit the list's sheet-ID
/// transaction and crossfade over the reflow duration (the highlight
/// appeared to travel between rows). With `animation = nil` on the
/// layer, the glass material switches instantly at the correct row,
/// while the row frame — and, for a freshly inserted selected row, the
/// whole composited row including this background — still moves and
/// fades with the caller's insertion transition and layout animation.
/// The layer is pure background: it never intercepts row hit-testing.
private struct RowGlassModifier: ViewModifier {
    var isSelected: Bool
    func body(content: Content) -> some View {
        content.background {
            if isSelected {
                Color.clear
                    .glassEffect(.regular.interactive().tint(.white.opacity(0.10)),
                                 in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .transaction { $0.animation = nil }
            }
        }
    }
}

/// Inline rename field: commits on submit or focus loss.
private struct RenameField: View {
    let initial: String
    let onCommit: (String) -> Void
    @State private var value: String
    @FocusState private var focused: Bool

    init(initial: String, onCommit: @escaping (String) -> Void) {
        self.initial = initial
        self.onCommit = onCommit
        _value = State(initialValue: initial)
    }

    var body: some View {
        TextField("", text: $value)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { onCommit(value) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { onCommit(value) }
            }
            .onAppear { focused = true }
    }
}
