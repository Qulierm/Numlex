import SwiftUI
import NumlexCore

/// r38: the app-wide appearance follows the PERSISTED Light/Dark
/// choice (AppSettings.appearance — the single source of truth, no
/// duplicate UserDefaults key). The AppDelegate applies the
/// authoritative persisted value once, before the first visible frame,
/// through the one AppAppearanceController; user changes re-apply it
/// live from the model. Every AppKit surface (windows, title bars,
/// native menus, context menus, popovers, file panels) and every
/// Liquid Glass surface follows the process appearance; there are no
/// per-view background overrides for appearance.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppAppearanceController.apply(
            AppAppearanceController.persistedAppearance())
    }
}

@main
struct NumlexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Single shared model instance injected into both the main window
    // and the Settings scene so they always stay in sync.
    @State private var model = AppModel()

    init() {
        // The appearance pin lives in the AppDelegate hook, not here: at
        // this point NSApplication does not exist yet (NSApp would be
        // nil), and applicationDidFinishLaunching is the earliest
        // guaranteed moment for the one app-level appearance source.
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

    // r38: the SwiftUI side of the one appearance mechanism. Both scene
    // roots follow the PERSISTED choice (never the host system), and
    // because the body reads the observable model setting, a user change
    // re-applies it here live — keeping SwiftUI-resolved styles
    // (materials, dynamic text styles, glass) in parity with the AppKit
    // surfaces from the very first frame.
    private func themedRoot<Content: View>(_ content: Content) -> some View {
        content.preferredColorScheme(
            model.settings.appearance == .light ? .light : .dark)
    }

    var body: some Scene {
        WindowGroup {
            themedRoot(ContentView(model: model))
                // r59: the SwiftUI content minimum allows the COLLAPSED
                // window size AND the compact 260 pt content height
                // (MainWindowGeometry.minContentHeight — the one source
                // of truth, also consumed by ContentView and the
                // WindowConfigurator's frame conversion). The expanded
                // 800 pt minimum width is enforced dynamically by
                // WindowConfigurator's window.minSize so the system
                // sidebar toggle can shrink the window.
                .frame(minWidth: MainWindowGeometry.contentMinWidth,
                       minHeight: MainWindowGeometry.minContentHeight)
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
            // also makes ⌘, ambiguous. r39: the sidebar gear row is gone
            // entirely — the system Settings… menu item and ⌘, are the
            // one entry point to the (single) Settings window.
        }

        Settings {
            themedRoot(NativeSettingsView(model: model))
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
