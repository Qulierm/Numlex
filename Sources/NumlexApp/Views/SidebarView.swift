import SwiftUI
import NumlexCore

struct SidebarView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // One restrained "new sheet" control: icon + label, native height.
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: Design.sidebarIconSize, weight: .medium))
                Text(L10n.t("newSheet", language: model.settings.language))
                    .font(Design.label)
                Spacer()
            }
            .contentShape(Rectangle())
            .frame(height: Design.newSheetRowHeight)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .onTapGesture { model.newSheet() }
            .help(L10n.t("newSheet", language: model.settings.language))
            .accessibilityElement()
            .accessibilityLabel(Text(L10n.t("newSheet", language: model.settings.language)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.newSheet() }

            // Native List selection only — no custom row backgrounds.
            List(selection: Binding(
                get: { model.sheets.indices.contains(model.selectedIndex) ? model.sheets[model.selectedIndex].id : nil },
                set: { newId in
                    if let id = newId, let idx = model.sheets.firstIndex(where: { $0.id == id }) {
                        model.select(index: idx)
                    }
                }
            )) {
                ForEach(Array(model.sheets.enumerated()), id: \.element.id) { idx, sheet in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sheet.title)
                            .font(Design.label.weight(.medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        HStack(spacing: 4) {
                            Text(sheet.createdLabel)
                            Text("·")
                            Text(sheet.lineCount == 0 ? "No lines" : "\(sheet.lineCount) \(sheet.lineCount == 1 ? "line" : "lines")")
                        }
                        .font(Design.labelSmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                    .listRowSeparator(.hidden)
                    .tag(sheet.id)
                    .contextMenu {
                        Button(role: .destructive) {
                            model.deleteSheet(at: idx)
                        } label: {
                            Label(L10n.t("deleteSheet", language: model.settings.language), systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteSheets)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

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

    private func deleteSheets(_ offsets: IndexSet) {
        for idx in offsets.sorted(by: >) {
            model.deleteSheet(at: idx)
        }
    }
}

extension Notification.Name {
    static let importSheet = Notification.Name("numlex.importSheet")
    static let exportSheet = Notification.Name("numlex.exportSheet")
}
