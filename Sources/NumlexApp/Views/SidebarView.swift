import SwiftUI
import NumlexCore

struct SidebarView: View {
    @Bindable var model: AppModel
    @State private var renamingID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Compact text-style "new sheet" control, centered across the
            // full sidebar width: 15pt medium icon + text, plain style,
            // no capsule/glass, raised toward the titlebar with a ~28pt
            // hit target. The titlebar area above holds the traffic
            // lights, so there is no overlap.
            Button {
                model.newSheet()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 15, weight: .medium))
                    Text(L10n.t("newSheet", language: model.settings.language))
                        .font(.system(size: 15, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 5)
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
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }

            // Bottom actions: one coherent cluster, same geometry and icon size.
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 200, maxWidth: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func sheetRow(idx: Int, sheet: Sheet) -> some View {
        let language = model.settings.language
        let meta: String = {
            let count: String
            if sheet.lineCount == 0 {
                count = L10n.t("noLines", language: language)
            } else {
                let unit = L10n.t(sheet.lineCount == 1 ? "line" : "lines", language: language)
                count = "\(sheet.lineCount) \(unit)"
            }
            return "\(sheet.createdLabel) \u{00B7} \(count)"
        }()
        let isSelected = idx == model.selectedIndex
        Button {
            model.select(index: idx)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                titleView(sheet: sheet)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(meta)
                    .font(Design.labelSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected
                      ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                      : Color.clear)
        )
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
                .font(Design.label.weight(.medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .onTapGesture(count: 2) { renamingID = sheet.id }
        }
    }

    private func sidebarIconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Design.sidebarIconSize, weight: .regular))
                .frame(width: Design.sidebarButtonSize.width, height: Design.sidebarButtonSize.height)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: Design.sidebarButtonCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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
            .font(Design.label.weight(.medium))
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
