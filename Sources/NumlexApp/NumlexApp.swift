import SwiftUI

@main
struct NumlexApp: App {
    // Single shared model instance injected into both the main window
    // and the Settings scene so they always stay in sync.
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 820, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1050, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Sheet") {
                    NotificationCenter.default.post(name: .newSheet, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .importExport) {
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
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Settings {
            NativeSettingsView(model: model)
        }
    }
}

extension Notification.Name {
    static let newSheet = Notification.Name("numlex.newSheet")
    static let deleteSheet = Notification.Name("numlex.deleteSheet")
}
