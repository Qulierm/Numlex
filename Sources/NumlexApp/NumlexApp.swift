import SwiftUI

@main
struct NumlexApp: App {
    // Single shared model instance injected into both the main window
    // and the Settings scene so they always stay in sync.
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                // The SwiftUI content minimum must allow the COLLAPSED
                // window size; the expanded 820pt minimum is enforced
                // dynamically by WindowConfigurator's window.minSize so the
                // system sidebar toggle can shrink the window.
                .frame(minWidth: 600, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        // The window opens at the designed size instead of resurrecting a
        // stale frame from the previous session's state restoration.
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sheet") {
                    NotificationCenter.default.post(name: .newSheet, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            // Explicit File-menu ownership: this ONE group owns the
            // standard import/export placement (replacing it, so exactly
            // one Import Sheet… and one Export Sheet… ever appear —
            // the sidebar carries no file-action buttons). Import/Export
            // post to ContentView's native fileImporter/fileExporter
            // (.nlx, security-scoped); Delete Sheet stays beside them.
            CommandGroup(replacing: .importExport) {
                Button("Import Sheet…") {
                    NotificationCenter.default.post(name: .importSheet, object: nil)
                }
                .keyboardShortcut("i", modifiers: .command)
                Button("Export Sheet…") {
                    NotificationCenter.default.post(name: .exportSheet, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)
                Divider()
                Button("Delete Sheet") {
                    NotificationCenter.default.post(name: .deleteSheet, object: nil)
                }
                .keyboardShortcut("d", modifiers: .command)
            }
            // The system registers the single Settings… item (⌘,) from the
            // Settings scene automatically; replacing the group here makes
            // macOS 26 render a SECOND item with the same shortcut, which
            // also makes ⌘, ambiguous. The gear button in the sidebar uses
            // the environment openSettings action instead.
        }

        Settings {
            NativeSettingsView(model: model)
        }
    }
}

extension Notification.Name {
    static let newSheet = Notification.Name("numlex.newSheet")
    static let deleteSheet = Notification.Name("numlex.deleteSheet")
    // Sheet file actions: posted by the File-menu commands above, caught
    // by ContentView's fileImporter/fileExporter. Declared here (not in
    // the sidebar) because the file actions no longer live in the UI
    // sidebar.
    static let importSheet = Notification.Name("numlex.importSheet")
    static let exportSheet = Notification.Name("numlex.exportSheet")
}
