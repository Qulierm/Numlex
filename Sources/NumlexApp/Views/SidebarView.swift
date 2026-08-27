import SwiftUI
import NumlexCore

/// Sheets sidebar (liquid-glass redesign, matching the reference layout):
/// a padded leading VStack with a full-width New Sheet capsule, a Sheets
/// caption, the selectable sheet list, a compact import/export row and a
/// full-width Settings row. Selection and controls use the system liquid
/// glass materials (regular interactive when selected, clear otherwise),
/// so the sidebar stays calm in inactive windows and both appearances.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // New Sheet: full-width plain button, `plus` symbol (not the
            // circled variant), semibold label, liquid glass capsule.
            // The hit shape stays a Rectangle: a Capsule contentShape
            // suppresses the glass fill on this system even when the
            // glass shape is the same capsule.
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
            .glassEffect(.regular.interactive().tint(.white.opacity(0.10)), in: Capsule())
            .help(L10n.t("newSheet", language: model.settings.language))

            // Sheet list: no caption — the list begins directly below
            // the New Sheet capsule with the VStack's own 10 pt gap.
            // Selection is the system regular-interactive glass pill;
            // unselected rows stay clear. The list sits directly on the
            // window background (rows carry their own 10pt horizontal
            // padding).
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(Array(model.sheets.enumerated()), id: \.element.id) { idx, sheet in
                        sheetRow(idx: idx, sheet: sheet)
                            // Removal: a short opacity fade plus a slight
                            // leading nudge; insertion mirrors it. The
                            // LazyVStack reflow below moves the remaining
                            // rows into the gap.
                            .transition(reduceMotion
                                        ? .identity
                                        : .opacity.combined(with: .offset(x: -12)))
                    }
                }
                // Row removal/reflow animates ONLY inside this list: the
                // value changes exactly when the sheet-ID list changes, and
                // the transaction is scoped here, so the editor and answer
                // column (which also observe the model) never pick up an
                // animated transaction on deletion. reduceMotion gets no
                // decorative animation at all.
                .animation(reduceMotion ? nil : .snappy(duration: 0.22),
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

            // Compact import/export auxiliary row, immediately above the
            // Settings row: restrained clear-glass icon buttons with
            // tooltips, so the file actions stay reachable without
            // crowding the bottom cluster.
            HStack(spacing: 6) {
                importExportButton("square.and.arrow.up", helpKey: "importSheet") {
                    NotificationCenter.default.post(name: .importSheet, object: nil)
                }
                importExportButton("square.and.arrow.down", helpKey: "exportSheet") {
                    NotificationCenter.default.post(name: .exportSheet, object: nil)
                }
                Spacer()
            }

            // Settings: full-width leading labeled row, clear glass in a
            // rounded rect. A real button; the sidebar gear always opens
            // exactly one Settings window (native openSettings action).
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
            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .help(L10n.t("settings", language: model.settings.language))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .frame(idealWidth: 235, maxWidth: 260)
    }

    private func importExportButton(_ symbol: String, helpKey: String,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .frame(width: 34, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .glassEffect(.identity, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help(L10n.t(helpKey, language: model.settings.language))
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
/// ONLY on the selected row (applied conditionally, so the unselected
/// rows render no material at all — both `Glass.clear` and `.identity`
/// draw a visible frosted panel on macOS 26, which would light up every
/// row like a button instead of staying calm like the system sidebar).
private struct RowGlassModifier: ViewModifier {
    var isSelected: Bool
    func body(content: Content) -> some View {
        if isSelected {
            content.glassEffect(.regular.interactive().tint(.white.opacity(0.10)),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            content
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

extension Notification.Name {
    static let importSheet = Notification.Name("numlex.importSheet")
    static let exportSheet = Notification.Name("numlex.exportSheet")
}
