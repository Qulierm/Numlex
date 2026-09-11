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
        // The icon capture must happen BEFORE the persisted choice is
        // applied: it records the icon AppKit itself resolved from the
        // bundle, which is the documented fallback if a host's null reset
        // (`applicationIconImage = nil`) does not take visual effect.
        AppIconController.captureLaunchIcon()
        AppIconController.apply(AppIconController.persistedChoice())
        // r77b: instrumented motion-evidence harness — inert unless the
        // process is launched with `--motion-evidence <dir>` (validation
        // runs with an isolated HOME; never part of normal operation).
        MotionEvidence.startIfRequested()
        // r77c: opt-in event-chain tracing — inert unless launched with
        // `--trace <dir>`.
        Diagnostics.startIfRequested()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MotionEvidence.shared?.finish()
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
        // initial size (SettingsGeometry's compact content size), even
        // when a previous build or session left it oversized. A session
        // resize
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
            model.settings.appearance.colorSchemeIsDarkOverride
                .map { $0 ? ColorScheme.dark : ColorScheme.light })
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
            // Secure in-app updates (Sparkle 2.9.6): the standard
            // "Check for Updates…" item sits directly after About, with
            // Sparkle's own enabled/disabled state. The updater is disabled
            // (item greyed out) when the packaged metadata is unavailable,
            // e.g. `swift run Numlex`.
            CommandGroup(after: .appInfo) {
                Button(NumlexCore.L10n.t("updates.checkNow",
                                         language: model.settings.language)) {
                    model.updates.checkForUpdates()
                }
                .disabled(!model.updates.canCheckForUpdates)
            }
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
            // r87: the ONE native Format menu — its Highlight submenu
            // targets every logical line intersecting the editor's
            // current live selection (a collapsed caret targets its own
            // line, the trailing empty line included). The action posts
            // to ContentView, which revalidates the sheet + line IDs
            // and persists the highlight through the model.
            CommandMenu(NumlexCore.L10n.t("settings.format",
                                          language: model.settings.language)) {
                Menu(NumlexCore.L10n.t("highlight",
                                        language: model.settings.language)) {
                    Button(NumlexCore.L10n.t("highlightNone",
                                              language: model.settings.language)) {
                        NotificationCenter.default.post(
                            name: .applyHighlight,
                            object: HighlightCommandPayload(color: nil))
                    }
                    Divider()
                    Button(NumlexCore.L10n.t("highlightYellow",
                                              language: model.settings.language)) {
                        NotificationCenter.default.post(
                            name: .applyHighlight,
                            object: HighlightCommandPayload(color: .yellow))
                    }
                    Button(NumlexCore.L10n.t("highlightOrange",
                                              language: model.settings.language)) {
                        NotificationCenter.default.post(
                            name: .applyHighlight,
                            object: HighlightCommandPayload(color: .orange))
                    }
                    Button(NumlexCore.L10n.t("highlightGreen",
                                              language: model.settings.language)) {
                        NotificationCenter.default.post(
                            name: .applyHighlight,
                            object: HighlightCommandPayload(color: .green))
                    }
                    Button(NumlexCore.L10n.t("highlightBlue",
                                              language: model.settings.language)) {
                        NotificationCenter.default.post(
                            name: .applyHighlight,
                            object: HighlightCommandPayload(color: .blue))
                    }
                    Button(NumlexCore.L10n.t("highlightPurple",
                                              language: model.settings.language)) {
                        NotificationCenter.default.post(
                            name: .applyHighlight,
                            object: HighlightCommandPayload(color: .purple))
                    }
                    Button(NumlexCore.L10n.t("highlightPink",
                                              language: model.settings.language)) {
                        NotificationCenter.default.post(
                            name: .applyHighlight,
                            object: HighlightCommandPayload(color: .pink))
                    }
                }
            }
            // r60: the ONE native Toggle Sidebar command (View menu +
            // Control-Command-S responder). This is the keyboard-only
            // reopening path when the toolbar button is hidden.
            SidebarCommands()
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
        // r90: the Settings window is resizable WITHIN the designed
        // content range (SettingsGeometry's min/ideal/max): `.contentMinSize`
        // makes SwiftUI honour the frame's minimum instead of fitting the
        // content exactly, which is what the split navigation needs.
        .windowResizability(.contentMinSize)
        // r34: the Settings scene used to resurrect its persisted frame
        // from an older (wider) build after every relaunch; with state
        // restoration disabled the window always opens at the designed
        // initial size (SettingsGeometry's compact content size), and a
        // user
        // resize lives for the session only — the next open is the
        // deterministic initial size again.
        .restorationBehavior(.disabled)
    }
}

/// r87: the Format > Highlight command payload (the notification
/// object; `color == nil` = None, i.e. remove the highlight).
final class HighlightCommandPayload {
    let color: HighlightColor?
    init(color: HighlightColor?) { self.color = color }
}

extension Notification.Name {
    /// r87: Format > Highlight — the object is a
    /// `HighlightCommandPayload` (nil color = None).
    static let applyHighlight = Notification.Name("numlex.applyHighlight")
    static let newSheet = Notification.Name("numlex.newSheet")
    static let deleteSheet = Notification.Name("numlex.deleteSheet")
    // Sheet file actions: posted by the File-menu commands above, caught
    // by ContentView's fileImporter/fileExporter. Declared here (not in
    // the sidebar) because the file actions no longer live in the UI
    // sidebar.
    static let importSheet = Notification.Name("numlex.importSheet")
    static let exportSheet = Notification.Name("numlex.exportSheet")
}
