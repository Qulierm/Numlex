import SwiftUI
import NumlexCore

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var renamingID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Compact text-style "new sheet" control, centered across the
            // full sidebar width: 15pt regular icon + text, plain style, no
            // capsule/glass, adaptive secondary gray. The visible label is
            // top-aligned inside a 28pt hit band with zero top padding, so it
            // sits as high as possible (clear of the traffic lights, which
            // occupy only the left edge) and the sheet list rises right up
            // against the band.
            // Native Liquid Glass surface (macOS 26): the real glass
            // button style — hover, press and focus states come from the
            // system, no matte fill of our own.
            Button {
                model.newSheet()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15))
                    Text(L10n.t("newSheet", language: model.settings.language))
                        .font(.system(size: 15))
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .help(L10n.t("newSheet", language: model.settings.language))

            // Sheet list. Selection is a single system gray pill
            // (unemphasized selected-content color): calm, system-aware,
            // identical in active and inactive state, no accent tint and no
            // double selection layer. The list sits inside the sidebar with
            // a consistent 8pt horizontal inset at every width.
            ScrollView {
                LazyVStack(spacing: 2) {
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
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            // Any deletion path (context menu or app menu) that removes the
            // row currently being renamed clears the stale rename state.
            .onChange(of: model.sheets.map(\.id)) { _, ids in
                if let rid = renamingID, !ids.contains(rid) { renamingID = nil }
            }

            // Bottom actions: one coherent native glass cluster — the
            // GlassEffectContainer coordinates the neighboring glass
            // surfaces (no stacked fake fills).
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    sidebarIconButton("square.and.arrow.up") {
                        NotificationCenter.default.post(name: .importSheet, object: nil)
                    }
                    .help(L10n.t("importSheet", language: model.settings.language))

                    sidebarIconButton("square.and.arrow.down") {
                        NotificationCenter.default.post(name: .exportSheet, object: nil)
                    }
                    .help(L10n.t("exportSheet", language: model.settings.language))

                    Spacer()

                    sidebarIconButton("gearshape") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    .help(L10n.t("settings", language: model.settings.language))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 200, maxWidth: 260)
        .background(Color(nsColor: .windowBackgroundColor))
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
        Button {
            model.select(index: idx)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                titleView(sheet: sheet)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // Metadata row: created time on the leading edge (primary
                // weight of the row), line count pinned to the trailing edge
                // so its right edge aligns across every row.
                HStack(spacing: 8) {
                    Text(sheet.createdLabel)
                        .font(Design.labelSmall)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(count)
                        .font(Design.labelSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            // v2: stable raised tab height (Design.sidebarRowHeight = base * 1.2).
            // The fixed frame replaces the old 4pt vertical padding, so the
            // hit target and the selection pill are exactly 20% taller than
            // the measured content base; the title/metadata block is centered
            // vertically inside, keeping its internal leading alignment.
            .padding(.horizontal, 6)
            .frame(height: Design.sidebarRowHeight, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ONE coherent native glass surface for the selection (macOS
        // 26): the matte pill is gone — the selected sheet reads as a
        // real glass card over the sidebar. Unselected rows stay
        // transparent; there is no second selection layer.
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.clear)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: isSelected)
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
                .font(Design.label)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(count: 2) { renamingID = sheet.id }
        }
    }

    private func sidebarIconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        // Native glass icon button: the system renders the surface,
        // hover, press and keyboard-focus states.
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Design.sidebarIconSize, weight: .regular))
                .frame(width: Design.sidebarButtonSize.width, height: Design.sidebarButtonSize.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: Design.sidebarButtonCorner))
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
            .font(Design.label)
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
