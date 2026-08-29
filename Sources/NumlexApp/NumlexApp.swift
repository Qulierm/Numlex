import SwiftUI

/// r36: the ONE app-level native appearance source. Numlex is a
/// permanent light (Aqua) app: every window, menu, popover, the
/// Settings tab chrome, the liquid-glass surfaces and every AppKit
/// NSTextView resolve light system colors regardless of the host
/// system's Light/Dark setting. Setting `NSApp.appearance` once covers
/// the whole process (AppKit windows, context menus, file panels);
/// there are no per-view background overrides for appearance.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
    }
}

@main
struct NumlexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Single shared model instance injected into both the main window
    // and the Settings scene so they always stay in sync.
    @State private var model = AppModel()

    init() {
        // The Aqua pin lives in the AppDelegate hook, not here: at this
        // point NSApplication does not exist yet (NSApp would be nil),
        // and applicationDidFinishLaunching is the earliest guaranteed
        // moment for the one app-level appearance source.
        // r34: the Settings window's NSWindow FRAME AUTOSAVE persists its
        // frame from the previous session, and AppKit restores it at
        // window creation — BEFORE the SwiftUI restoration behavior and
        // the configurator's first setContentSize can apply. Clear the
        // stale key at launch so the window always opens at the designed
        // initial size (SettingsGeometry: content 720x460), even when a
        // previous build or session left it oversized. A session resize
        // is re-persisted on close and simply ignored at the next launch
        // — the open size is deterministic by design.
        UserDefaults.standard.removeObject(
            forKey: "NSWindow Frame com_apple_SwiftUI_Settings_window")
    }

    // The SwiftUI environment color scheme follows the window's effective
    // appearance, which the app-level Aqua override above makes light;
    // declaring it on both scene roots keeps SwiftUI-resolved styles
    // (materials, dynamic text styles) in parity from the very first
    // frame instead of relying on the live re-resolution alone.
    private func lightRoot<Content: View>(_ content: Content) -> some View {
        content.preferredColorScheme(.light)
    }

    var body: some Scene {
        WindowGroup {
            lightRoot(ContentView(model: model))
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
            lightRoot(NativeSettingsView(model: model))
        }
        // r34: the Settings scene used to resurrect its persisted frame
        // from an older (taller) build after every relaunch; with state
        // restoration disabled the window always opens at the designed
        // initial size (SettingsGeometry: content 720x460), and a user
        // resize lives for the session only — the next open is the
        // deterministic initial size again.
        .restorationBehavior(.disabled)
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
