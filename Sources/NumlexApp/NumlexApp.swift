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
        // applied: it records the PRIMARY bundle icon (the named modern
        // `AppIcon` asset, or AppKit's own bundle image), which is the
        // fallback when Assets.car is unavailable. It can never record a
        // previously applied alternate, because AppModel.init no longer
        // applies the icon (r91) — the delegate owns this lifecycle.
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

/// r98: the curtain timing, in one place (shared by the animation and the
/// completion task so they can never disagree).
enum RevealTiming {
    /// The curtain's upward travel: a deliberate, smooth 0.90 s ease with no
    /// bounce and no overshoot of the final (fully cleared) position.
    static let duration: Double = 0.90
    static let animation: Animation = .timingCurve(0.42, 0.0, 0.20, 1.0, duration: duration)
    /// The slide uses the same curve in production and replay.
    static var curtainAnimation: Animation { animation }
    /// The panel travels past the clipped content height by this much, so no
    /// bottom or titlebar sliver can survive the slide.
    static let overscan: CGFloat = 80
    /// The curtain's travel is read from the LIVE overlay bounds
    /// (`proxy.size.height + overscan`) inside `visualEffect`, so it clears the
    /// panel at any window height — the main window is vertically resizable and
    /// `defaultContentHeight` is not a maximum. Reading geometry for a visual
    /// transform never participates in layout, so no fixed distance and no
    /// sizing `GeometryReader` are needed.
    /// One committed render turn before the slide starts (a mounted underlay
    /// must exist on screen first, or the editor would appear mid-travel).
    static let mountCommitNanoseconds: UInt64 = 24_000_000
    /// The completion wait is the travel duration plus one frame of slack, so
    /// the removal happens strictly after the panel has cleared.
    static let travelNanoseconds: UInt64 = 950_000_000
}

@main
struct NumlexApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Single shared model instance injected into both the main window
    // and the Settings scene so they always stay in sync.
    @State private var model: AppModel
    /// r97: the FIRST-LAUNCH decision, captured in `init()` BEFORE the
    /// model (and therefore `Persistence.load`/`dataDirectory`) runs, so
    /// "is this a genuinely new install?" is never answered by the app's
    /// own side effects. The welcome screen replaces the main content
    /// until the user starts; no store, settings or `.nlx` byte changes.
    /// r98: the curtain stage. While the welcome covers the window the
    /// editor is NOT mounted; on activation it mounts UNDERNEATH and the
    /// welcome panel slides fully upward inside the fixed native window.
    /// The NSWindow itself is never moved or resized.
    @State private var revealStage: RevealStage = .welcome
    /// r98: drives the curtain's upward travel. The welcome panel keeps its
    /// IDENTITY through the whole reveal (it is never re-created), and this
    /// offset — animated inside an explicit `withAnimation` — moves it fully
    /// out of the clipped content bounds. The NSWindow is never touched.
    @State private var curtainRequested = false
    /// The pending curtain completion (cancelled when the window closes).
    @State private var curtainTask: Task<Void, Never>?

    // MARK: TEMPORARY QA CONTROL — remove after onboarding sign-off
    //
    // A session-only replay of the welcome animation, for visual testing.
    // It is deliberately SEPARATE from the production first-launch stages:
    // `revealStage` is never set back to `.welcome`, so ContentView/TextKit
    // are neither unmounted nor recreated and the caret, scroll position,
    // selection and sheet UUIDs are untouched. Nothing here reads or writes
    // `welcome-v1`, calls `FirstLaunch`, or persists anything at all.
    /// True only while the replay overlay is on screen.
    @State private var replayWelcomePresented = false
    /// Drives the replay panel's upward travel (same stable-offset contract
    /// as the production curtain).
    @State private var replayLiftRequested = false
    /// Re-identified on every presentation, so each replay mounts a BRAND
    /// NEW WelcomeView whose staged @State restarts from its initial values.
    @State private var replaySession = UUID()
    /// The pending replay completion (cancelled on re-presentation, finish
    /// or window closure).
    @State private var replayTask: Task<Void, Never>?
    /// The base editor's compositing is suspended while the fully opaque
    /// welcome covers it (the live ContentView/TextKit stays MOUNTED with
    /// its identity, caret, scroll and selection intact). It becomes visible
    /// again one frame BEFORE the curtain lifts, so the reveal itself always
    /// shows the real interface.
    @State private var replayContentReady = false
    /// The editor text view that owned the keyboard just before the replay
    /// covered it. Restoring THIS responder (never a fresh model focus
    /// request) is what keeps the caret, selection, typing attributes,
    /// scroll origin and marked text exactly as the user left them.
    @State private var replayRestoreResponder: NotebookTextView?

    init() {
        // 1) Decide first (non-creating directory lookup)…
        let dataDirectory = Persistence.dataDirectory(createIfNeeded: false)
        let isNewInstall = FirstLaunch.evaluateAtLaunch(in: dataDirectory)
        // Existing installs mount the editor IMMEDIATELY (`.app`), so they
        // never see a flash of the welcome.
        _revealStage = State(initialValue: isNewInstall ? .welcome : .app)
        // 2) …then build the model (which may create/load the directory).
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
        _model = State(initialValue: AppModel())
    }

    /// r98: the curtain stages.
    ///  * `.welcome`  — only the welcome is mounted (no editor, no TextKit,
    ///                  no rates work behind it);
    ///  * `.revealing` — the editor is mounted BENEATH the welcome, which
    ///                  slides up out of the content bounds;
    ///  * `.app`      — the welcome is gone and the editor owns the window.
    enum RevealStage { case welcome, revealing, app }

    /// r97/r98: the ONE dismissal path. Records the versioned completion
    /// marker (best effort — a failed write still enters the app for this
    /// session and simply shows the welcome again next launch), mounts the
    /// editor beneath, slides the curtain away and hands the keyboard focus
    /// to the already-selected sheet. It never creates, edits or persists a
    /// sheet, and it never touches the NSWindow frame.
    private func beginReveal() {
        _ = FirstLaunch.markCompleted(in: Persistence.dataDirectory())
        // Under Reduce Motion the welcome is removed immediately: no mount
        // step, no slide, no delay, and the editor then takes focus.
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            revealStage = .app
            focusSelectedEditor()
            return
        }
        // 1) Mount the editor BENEATH the still-covering welcome. This step
        //    is deliberately NOT animated: it only changes what exists.
        curtainTask?.cancel()
        revealStage = .revealing
        curtainTask = Task { @MainActor in
            // 2) Let the mounted editor COMMIT and be drawn: a bounded async
            //    delay is a real render turn, where a bare Task.yield only
            //    advances the run loop. The welcome stays fully opaque and
            //    stationary for this beat, so the slide always reveals a
            //    finished editor rather than a half-drawn one.
            try? await Task.sleep(nanoseconds: RevealTiming.mountCommitNanoseconds)
            guard !Task.isCancelled, revealStage == .revealing else { return }
            curtainRequested = true
            // 3) Once the panel is fully out of the content bounds, drop it
            //    definitively and hand the keyboard focus to the editor.
            try? await Task.sleep(nanoseconds: RevealTiming.travelNanoseconds)
            guard !Task.isCancelled else { return }
            revealStage = .app
            focusSelectedEditor()
        }
    }

    /// Transient one-shot focus request for the EXISTING selection (the same
    /// mechanism freshly created sheets use); consumed by the editor and
    /// never persisted. Only ever called once the editor is visible.
    private func focusSelectedEditor() {
        if let id = model.selectedSheet?.id {
            model.focusSheetID = id
        }
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

    /// r98: the launch root. The welcome REPLACES the notebook until
    /// activation (nothing from ContentView/TextKit/the sidebar exists
    /// behind it), then the editor mounts BENEATH and the welcome panel
    /// slides fully upward inside the fixed window — the "window moves up"
    /// feel without touching the real NSWindow. The window geometry
    /// contract below is shared by every stage.
    @ViewBuilder
    private var launchRoot: some View {
        // ONE stable container for every launch stage (see LaunchContainer):
        // the production WelcomeView lives in a single branch with an
        // explicit stable id, so moving from `.welcome` to `.revealing`
        // neither re-creates it nor restarts its bloom, and the curtain's
        // progress is view-owned so SwiftUI really interpolates the slide.
        LaunchContainer(stage: revealStage,
                        language: model.settings.language,
                        content: { AnyView(ContentView(model: model)) },
                        onGetStarted: beginReveal,
                        revealRequested: curtainRequested)
    }

    /// Stable structural identity for the production welcome.
    static let productionWelcomeID = "production-welcome"

    /// True while a welcome reveal (production or replay) owns the window:
    /// the native sidebar toggle stays hidden until the transition has
    /// finished. Transient view state only — never persisted anywhere.
    private var sidebarToggleHiddenForWelcome: Bool {
        revealStage != .app || replayWelcomePresented
    }

    /// TEMPORARY QA CONTROL — remove after onboarding sign-off.
    ///
    /// The scene root is a STABLE container: the production `launchRoot`
    /// stays mounted (and keeps its own identity and state) whether or not a
    /// replay is running. A replay only INSERTS a sibling overlay above it,
    /// so the editor, its TextKit storage, caret, scroll offset, selection
    /// and the model are never re-created.
    @ViewBuilder
    private var sessionRoot: some View {
        // The production root is the SIZING BASE and nothing about a replay
        // may change its proposal, frame, bounds, safe area or alignment: the
        // overlay is attached with `.overlay`, which is explicitly a
        // non-sizing layer, and the base itself keeps its identity and its
        // TextKit storage. Hit testing and compositing are the only things a
        // replay touches on the base (both geometry-neutral).
        launchRoot
            .allowsHitTesting(!replayWelcomePresented)
            .opacity(replayWelcomePresented && !replayContentReady ? 0 : 1)
            .overlay {
                if replayWelcomePresented {
                    ReplayOverlay(language: model.settings.language,
                                  onGetStarted: finishReplay,
                                  liftRequested: replayLiftRequested)
                        // A fresh identity per presentation restarts the whole
                        // staged animation from its initial frame.
                        .id(replaySession)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .replayWelcome)) { _ in
                presentReplayWelcome()
            }
            .environment(\.sidebarToggleHiddenForWelcome, sidebarToggleHiddenForWelcome)
    }

    /// TEMPORARY QA CONTROL — remove after onboarding sign-off.
    /// Presents the replay overlay once: only after the production reveal has
    /// finished, never twice, and always from a clean curtain state.
    private func presentReplayWelcome() {
        guard revealStage == .app, !replayWelcomePresented else { return }
        replayTask?.cancel()
        // Capture the LIVE first responder (the editor's own text view)
        // BEFORE anything covers it: restoring that exact responder after
        // the curtain is what preserves the caret and selection, where a
        // fresh model focus request would reset the caret to position 0.
        replayRestoreResponder = Self.liveEditorResponder()
        // Protect the document: the editor keeps its captured reference and
        // its exact state, but stops owning the keyboard while the overlay
        // plays, so nothing can be typed into an invisible document. This
        // does not change the selection, typing attributes, scroll origin or
        // marked text — the view is merely resigned.
        if let textView = replayRestoreResponder, let window = textView.window {
            window.makeFirstResponder(nil)
        }
        replayContentReady = false
        replayLiftRequested = false
        replaySession = UUID()
        replayWelcomePresented = true
    }

    /// The editor text view that currently owns the keyboard, or — if the
    /// window is not focused — the live one found in the main window's view
    /// tree. Purely observational: nothing is mutated.
    private static func liveEditorResponder() -> NotebookTextView? {
        let window = NSApp.mainWindow
            ?? NSApp.windows.first(where: { $0.isVisible && $0.styleMask.contains(.titled) })
        guard let window else { return nil }
        if let responder = window.firstResponder as? NotebookTextView { return responder }
        return findTextView(in: window.contentView)
    }

    private static func findTextView(in view: NSView?) -> NotebookTextView? {
        guard let view else { return nil }
        if let textView = view as? NotebookTextView { return textView }
        for subview in view.subviews {
            if let found = findTextView(in: subview) { return found }
        }
        return nil
    }

    /// TEMPORARY QA CONTROL — remove after onboarding sign-off.
    /// The replay's Get Started: the SAME stable overlay panel slides fully
    /// out of the content bounds (identical timing contract to the production
    /// curtain), then only the overlay is removed and focus returns to the
    /// current sheet. No marker is written and nothing is persisted.
    private func finishReplay() {
        guard replayWelcomePresented else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        replayTask?.cancel()
        if reduceMotion {
            replayContentReady = true
            replayWelcomePresented = false
            replayLiftRequested = false
            restoreReplayResponder()
                return
        }
        replayTask = Task { @MainActor in
            // The editor becomes visible BEFORE the panel starts lifting, and
            // a bounded delay gives it a real committed frame, so the reveal
            // always shows the finished interface from its first frame.
                replayContentReady = true
            try? await Task.sleep(nanoseconds: RevealTiming.mountCommitNanoseconds)
            guard !Task.isCancelled, replayWelcomePresented else { return }
            replayLiftRequested = true
            try? await Task.sleep(nanoseconds: RevealTiming.travelNanoseconds)
            guard !Task.isCancelled else { return }
            replayWelcomePresented = false
            replayLiftRequested = false
            restoreReplayResponder()
        }
    }

    /// Hands the keyboard back to the SAME text view that had it before the
    /// replay. `makeFirstResponder` alone does not touch the selection,
    /// typing attributes, scroll origin or marked text, so the caret the
    /// user left behind is exactly where it was. If the view is gone (sheet
    /// switch, window closed) nothing happens — the content is never
    /// altered as a fallback.
    private func restoreReplayResponder() {
        defer { replayRestoreResponder = nil }
        guard let textView = replayRestoreResponder,
              let window = textView.window else { return }
        window.makeFirstResponder(textView)
    }

    var body: some Scene {
        WindowGroup {
            themedRoot(sessionRoot)
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

/// The production launch container. The curtain's progress lives in THIS
/// view's own state, because a state mutation inside `withAnimation` only
/// produces an interpolated transaction for view-owned state — an App-level
/// flag jumped straight to its target.
struct LaunchContainer: View {
    let stage: NumlexApp.RevealStage
    let language: AppLanguage
    let content: () -> AnyView
    let onGetStarted: () -> Void
    /// Flipped by the app when the reveal begins.
    let revealRequested: Bool

    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            // The editor is the SIZING BASE from the moment it exists; it is
            // never clipped, offset or safe-area-shifted by the curtain.
            if stage != .welcome {
                content()
                    .allowsHitTesting(stage == .app)
            }
            // The curtain is ONE branch with a stable id, so the production
            // WelcomeView keeps its identity (and its running bloom) when the
            // editor appears beneath it. It carries no sizing GeometryReader
            // and no `.clipped()`: the travel comes from the panel's own live
            // bounds inside `visualEffect`, which is a purely visual transform,
            // and the window itself clips anything beyond its edges.
            if stage != .app {
                CurtainPanel(progress: progress,
                             shadowOpacity: progress > 0.001 ? 0 : 0.28,
                             content: WelcomeView(language: language, onGetStarted: onGetStarted))
                    .id(NumlexApp.productionWelcomeID)
                    .zIndex(1)
                    .allowsHitTesting(stage == .welcome)
            }
        }
        .onChange(of: revealRequested) { _, requested in
            withAnimation(requested ? RevealTiming.curtainAnimation : nil) {
                progress = requested ? 1 : 0
            }
        }
    }
}

/// The replay overlay, same contract: the overlay owns its own animated
/// progress and lifts when the app asks it to.
struct ReplayOverlay: View {
    let language: AppLanguage
    let onGetStarted: () -> Void
    let liftRequested: Bool

    @State private var progress: Double = 0

    var body: some View {
        CurtainPanel(progress: progress,
                     shadowOpacity: progress > 0.001 ? 0 : 0.28,
                     content: WelcomeView(language: language, onGetStarted: onGetStarted))
            // The overlay layer covers the whole window, titlebar strip
            // included. Because it is attached with `.overlay`, its
            // `.ignoresSafeArea()` cannot reach the base view's layout.
            .ignoresSafeArea()
            .onChange(of: liftRequested) { _, requested in
                withAnimation(requested ? RevealTiming.curtainAnimation : nil) {
                    progress = requested ? 1 : 0
                }
            }
    }
}

/// The moving welcome panel. `progress` is an interpolated scalar (0 = fully
/// covering, 1 = fully retired), so the slide is produced by SwiftUI's
/// Animatable machinery on every display frame — the same guarantee the
/// welcome canvases use. A plain `.offset(y: lifted ? -travel : 0)` on a
/// state flag measurably JUMPED instead of travelling.
///
/// The distance travelled is the panel's OWN live height plus the overscan,
/// read through `visualEffect`. `visualEffect` hands the closure a proxy whose
/// geometry is used ONLY to build a visual transform, so the read can never
/// feed back into layout: the panel stays exactly as large as the space it is
/// given, at 600 pt or at any taller resizable window height, and still clears
/// completely because the distance always exceeds its own height.
struct CurtainPanel<Content: View>: View, @preconcurrency Animatable {
    var progress: Double
    var shadowOpacity: Double
    var content: Content

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(progress, shadowOpacity) }
        set {
            progress = newValue.first
            shadowOpacity = newValue.second
        }
    }

    var body: some View {
        content
            .visualEffect { content, proxy in
                content.offset(y: -(proxy.size.height + RevealTiming.overscan) * CGFloat(progress))
            }
            .shadow(color: .black.opacity(shadowOpacity), radius: 10, y: 4)
    }
}

/// Transient view-environment flag: TRUE while a welcome reveal (production
/// or replay) owns the window, so the NATIVE sidebar toggle can be hidden
/// while the curtain covers or travels. It is deliberately NOT part of
/// AppModel, settings, the store, UserDefaults, the marker or any export —
/// it exists only for the lifetime of the transition.
private struct SidebarToggleHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sidebarToggleHiddenForWelcome: Bool {
        get { self[SidebarToggleHiddenKey.self] }
        set { self[SidebarToggleHiddenKey.self] = newValue }
    }
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
    /// TEMPORARY QA CONTROL — remove after onboarding sign-off.
    /// Posted by the temporary sidebar "Replay Welcome" button; caught by the
    /// scene root, which owns the session-only replay overlay.
    static let replayWelcome = Notification.Name("numlex.replayWelcome")
}
