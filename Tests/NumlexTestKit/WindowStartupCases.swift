import Foundation
import NumlexCore

private func windowStartupReadSource(_ relativePath: String) throws -> String {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(relativePath)
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        throw CaseFailure(message: "could not read \(relativePath): \(error)",
                          location: "WindowStartupCases")
    }
}

private func windowStartupScope(_ source: String,
                                from startMarker: String,
                                to endMarker: String) throws -> String {
    guard let start = source.range(of: startMarker),
          let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
        throw CaseFailure(message: "source scope is missing: \(startMarker) -> \(endMarker)",
                          location: "WindowStartupCases")
    }
    return String(source[start.lowerBound..<end.lowerBound])
}

public let windowStartupCases: [EngineCase] = [
    EngineCase("window-startup-main-scene-samples-current-shared-geometry") {
        let app = try windowStartupReadSource("Sources/NumlexApp/NumlexApp.swift")
        let helper = try windowStartupScope(
            app,
            from: "private func mainWindowStartupPlacement() -> WindowPlacement",
            to: "var body: some Scene")
        let mainScene = try windowStartupScope(
            app,
            from: "WindowGroup(id: Self.mainWindowID)",
            to: "Settings {")

        try expectEqual(app.components(separatedBy: ".defaultWindowPlacement").count - 1, 1,
                        "the main scene has exactly one initial placement callback")
        try expect(mainScene.contains(
            ".defaultWindowPlacement { _, _ in mainWindowStartupPlacement() }"),
            "the callback routes directly through the placement decision")
        try expect(!mainScene.contains(".defaultSize(")
                   && !mainScene.contains("sizeThatFits"),
                   "the scene has no competing raw default or ideal-size path")
        try expect(helper.contains("let screens = NSScreen.screens")
                   && helper.contains("let primary = screens.first")
                   && helper.contains("visibleFrames: screens.map(\\.visibleFrame)")
                   && helper.contains("primaryScreenFrame: primary?.frame")
                   && helper.contains("primaryVisibleFrame: primary?.visibleFrame"),
                   "all current visible displays and the primary full/visible frames are sampled")
        try expect(helper.contains("saved: model.settings.windowFrame")
                   && helper.contains("sidebarVisible: model.settings.sidebarVisible")
                   && helper.contains("MainWindowGeometry.startupPlacement("),
                   "current shared settings choose the initial pure placement")
        try expect(helper.contains("WindowPlacement(position, size: result.size)")
                   && helper.contains("WindowPlacement(UnitPoint.center, size: result.size)"),
                   "accepted saved points and last-resort centering use explicit chosen size")
        try expect(app.contains("@MainActor\n    private func mainWindowStartupPlacement() -> WindowPlacement"),
                   "display sampling is synchronous on the main actor")
        try expectEqual(app.components(separatedBy: "mainWindowStartupPlacement()").count - 1, 2,
                        "only the main scene calls the helper; other windows do not restore later")
        try expect(app.contains("@State private var model: AppModel")
                   && app.contains("content: { AnyView(ContentView(model: model)) }")
                   && app.contains("openWindow(id: NumlexApp.mainWindowID)"),
                   "main windows use the same shared model and WindowGroup")
    },

    EngineCase("window-startup-owned-callbacks-cannot-repeat-initial-placement") {
        let app = try windowStartupReadSource("Sources/NumlexApp/NumlexApp.swift")
        let view = try windowStartupReadSource("Sources/NumlexApp/Views/ContentView.swift")
        let initializer = try windowStartupScope(
            view,
            from: "func initializeAttachedWindow(_ window: NSWindow)",
            to: "private func installOwnedWindowObservers(")
        let updates = try windowStartupScope(
            view,
            from: "func updateInputs(view:",
            to: "func windowAttachmentChanged(")
        let attachment = try windowStartupScope(
            view,
            from: "func windowAttachmentChanged(_ newWindow: NSWindow?",
            to: "func initializeAttachedWindow(")
        let observers = try windowStartupScope(
            view,
            from: "private func installOwnedWindowObservers(",
            to: "private func scheduleToolbarReassertions(")
        let toolbar = try windowStartupScope(
            view,
            from: "private func scheduleToolbarReassertions(",
            to: "private func applyLatestInputs()")

        try expect(initializer.contains(
            "guard attachedWindow === window, !didInitializeAttachedWindow else { return }"),
            "attached setup remains identity-scoped and exactly once")
        try expect(initializer.contains("didInitializeAttachedWindow = true")
                   && initializer.contains("window.minSize = minSize")
                   && initializer.contains("applyNoSeparatorChrome(to: window)"),
                   "the owned initializer keeps its guard, live floor, and chrome setup")
        try expect(initializer.contains("isWindowReady = true")
                   && initializer.contains("onWindowReady?(true)")
                   && initializer.contains("publishMinimalModeCommandAvailability()")
                   && initializer.contains("scheduleToolbarReassertions(on: window)"),
                   "readiness, command eligibility, and toolbar setup remain intact")
        for forbidden in ["MainWindowGeometry.restoredFrame", "startupPlacement(",
                          "window.setFrame(", "window.setContentSize(", "window.center()",
                          "NSScreen.screens", "await ", "Task", "sleep(", "DispatchQueue"] {
            try expect(!initializer.contains(forbidden),
                       "owned initialization has no deferred/late initial geometry operation: \(forbidden)")
        }
        try expect(updates.contains("windowAttachmentChanged(view.window, from: view)")
                   && !updates.contains("startupPlacement(")
                   && !updates.contains("MainWindowGeometry.restoredFrame")
                   && !updates.contains("window.setFrame("),
                   "ordinary representable updates cannot recalculate initial placement")
        try expect(attachment.contains("if attachedWindow === newWindow")
                   && attachment.contains("if !didInitializeAttachedWindow { initializeAttachedWindow(newWindow) }")
                   && attachment.contains("didInitializeAttachedWindow = false"),
                   "only a newly attached owner resets setup; repeat callbacks retain the guard")
        try expect(!attachment.contains("startupPlacement(")
                   && !attachment.contains("MainWindowGeometry.restoredFrame")
                   && !attachment.contains("window.setFrame("),
                   "attachment events never set the initial frame")
        try expect(observers.contains("NSWindow.didBecomeKeyNotification")
                   && observers.contains("NSWindow.didResignKeyNotification")
                   && observers.contains("NSToolbar.willAddItemNotification")
                   && observers.contains("publishMinimalModeCommandAvailability()")
                   && observers.contains("reapply(to: window)"),
                   "key and toolbar observers retain eligibility/chrome work")
        try expect(!observers.contains("initializeAttachedWindow(")
                   && !observers.contains("startupPlacement(")
                   && !observers.contains("MainWindowGeometry.restoredFrame")
                   && !observers.contains("window.setFrame("),
                   "key/toolbar callbacks cannot repeat placement or restore a frame")
        try expect(toolbar.contains("self.reapply(to: window)")
                   && !toolbar.contains("initializeAttachedWindow(")
                   && !toolbar.contains("startupPlacement(")
                   && !toolbar.contains("window.setFrame("),
                   "toolbar reassertions remain chrome-only")
        try expect(app.contains(".restorationBehavior(.disabled)")
                   && !app.contains("setFrameAutosaveName"),
                   "native restoration/autosave cannot become a competing source")
    },

    EngineCase("window-startup-settings-sidebar-welcome-and-frame-writers-are-preserved") {
        let app = try windowStartupReadSource("Sources/NumlexApp/NumlexApp.swift")
        let view = try windowStartupReadSource("Sources/NumlexApp/Views/ContentView.swift")
        let settings = try windowStartupReadSource("Sources/NumlexCore/Models/Settings.swift")
        let persistence = try windowStartupReadSource("Sources/NumlexCore/Services/Persistence.swift")
        let helper = try windowStartupScope(
            app,
            from: "private func mainWindowStartupPlacement() -> WindowPlacement",
            to: "var body: some Scene")
        let mainScene = try windowStartupScope(
            app,
            from: "WindowGroup(id: Self.mainWindowID)",
            to: "Settings {")
        let settingsScene = try windowStartupScope(
            app,
            from: "Settings {",
            to: "private struct NewItemCommand")
        let ownedInitializer = try windowStartupScope(
            view,
            from: "func initializeAttachedWindow(_ window: NSWindow)",
            to: "private func installOwnedWindowObservers(")
        let appInit = try windowStartupScope(
            app,
            from: "init() {",
            to: "/// r98: the curtain stages.")
        let launchRoot = try windowStartupScope(
            app,
            from: "private var launchRoot: some View",
            to: "static let productionWelcomeID")
        let launchContainer = try windowStartupScope(
            app,
            from: "struct LaunchContainer: View {",
            to: "struct CurtainPanel<Content: View>")
        let writer = try windowStartupScope(
            view,
            from: "private func rememberWindowFrame(_ frame: CGRect)",
            to: "\n}\n\n/// Grabs the hosting NSView's window")
        let terminationAndSettle = try windowStartupScope(
            view,
            from: "func scheduleFrameSettle(window: NSWindow, immediate: Bool)",
            to: "func reapply(to window: NSWindow?)")
        let normalTransition = try windowStartupScope(
            view,
            from: "private func beginMinimalModeTransition(to minimal: Bool",
            to: "private func scheduleMinimalModeMeasurement(")

        try expect(settings.contains("public var windowFrame: SavedWindowFrame?")
                   && settings.contains("public var sidebarVisible: Bool")
                   && settings.contains("windowFrame = (try? c.decodeIfPresent(SavedWindowFrame.self, forKey: .windowFrame))")
                   && settings.contains("sidebarVisible = (try? c.decodeIfPresent(Bool.self, forKey: .sidebarVisible)) ?? true")
                   && !settings.contains("StartupPlacement")
                   && !settings.contains("isRestoringSavedFrame"),
                   "placement metadata adds no persisted key and legacy frame/sidebar defaults remain")
        try expectEqual(AppSettings.defaults.windowFrame, nil,
                        "legacy/default stores have no saved window rectangle")
        try expect(AppSettings.defaults.sidebarVisible,
                   "legacy/default stores keep the expanded sidebar")
        try expectEqual(StorePayload.currentVersion, 2,
                        "startup placement does not migrate the store schema")
        try expect(persistence.contains("public static let currentVersion = 2"),
                   "the canonical store version remains two")
        try expect(!helper.contains("model.settings.windowFrame =")
                   && !helper.contains("model.settings.sidebarVisible =")
                   && !helper.contains("persist()")
                   && !helper.contains("UserDefaults"),
                   "initial placement only reads settings")
        try expect(view.contains(
            "_columnVisibility = State(initialValue: model.settings.sidebarVisible ? .all : .detailOnly)"),
            "the saved sidebar state is seeded before the ContentView first frame")
        try expect(!settingsScene.contains("defaultWindowPlacement")
                   && settingsScene.contains(".restorationBehavior(.disabled)"),
                   "Settings stays on its existing independent scene policy")
        try expect(!app.contains("setFrameAutosaveName")
                   && !view.contains("setFrameAutosaveName"),
                   "no app or ContentView frame-autosave key is added")
        for forbidden in ["window.alphaValue", "alphaValue =", ".opacity(",
                          "orderOut(", "setIsVisible(false)"] {
            try expect(!helper.contains(forbidden)
                       && !mainScene.contains(forbidden)
                       && !ownedInitializer.contains(forbidden)
                       && !launchRoot.contains(forbidden),
                       "startup placement/welcome root adds no hiding workaround: \(forbidden)")
        }

        try expect(app.contains("FirstLaunch.evaluateAtLaunch(in: dataDirectory)")
                   && appInit.contains("_revealStage = State(initialValue: isNewInstall ? .welcome : .app)")
                   && appInit.contains("_model = State(initialValue: AppModel())"),
                   "the one first-launch decision still precedes the one shared model")
        try expectEqual(app.components(separatedBy: "FirstLaunch.evaluateAtLaunch").count - 1, 1,
                        "new main windows do not rerun first-launch evaluation")
        try expect(launchRoot.contains("LaunchContainer(stage: revealStage")
                   && launchRoot.contains("content: { AnyView(ContentView(model: model)) }")
                   && launchRoot.contains("onGetStarted: beginReveal"),
                   "the stable launch container owns the existing editor closure and Get Started")
        try expect(launchContainer.contains("if stage != .welcome")
                   && launchContainer.contains("content()")
                   && launchContainer.contains(".allowsHitTesting(stage == .app)")
                   && launchContainer.contains("if stage != .app")
                   && launchContainer.contains("NumlexApp.productionWelcomeID"),
                   "the editor remains absent at welcome and mounts under the stable curtain after activation")

        try expect(writer.contains("frame.origin.x.rounded()")
                   && writer.contains("frame.origin.y.rounded()")
                   && writer.contains("guard model.settings.windowFrame != settled else { return }")
                   && writer.contains("model.settings.windowFrame = settled")
                   && writer.contains("model.persist()"),
                   "normal frame persistence remains rounded, equality-guarded, and coalesced at its caller")
        try expect(view.contains("onCaptureNormalFrame: rememberWindowFrame")
                   && view.contains("onWindowFrameSettled: rememberWindowFrame")
                   && view.contains("onCaptureNormalFrame?(normalFrame)"),
                   "mode-entry snapshot and settled normal-frame writers remain wired")
        try expect(normalTransition.contains("if normalFrameSnapshot == nil")
                   && normalTransition.contains("onCaptureNormalFrame?(normalFrame)")
                   && normalTransition.contains("cachedNormalFrame: normalFrameSnapshot")
                   && normalTransition.contains("savedNormalFrame: savedNormalFrame")
                   && normalTransition.contains("MinimalModeGeometry.restoringFrame("),
                   "Minimal Mode retains its snapshot and normal restore fallback")
        try expect(terminationAndSettle.contains("guard owns(window), isWindowReady, mayPersistNormalFrame else { return }")
                   && terminationAndSettle.contains("guard !immediate else {")
                   && terminationAndSettle.contains("onFrameSettled?(window.frame)")
                   && terminationAndSettle.contains("Task.sleep(for: Coordinator.frameSettleDelay)")
                   && terminationAndSettle.contains("self.mayPersistNormalFrame"),
                   "termination and coalesced settled-frame persistence keep their existing mode/fullscreen guards")
    },

    EngineCase("window-startup-placement-is-deterministic-and-rate-clock-independent") {
        let app = try windowStartupReadSource("Sources/NumlexApp/NumlexApp.swift")
        let view = try windowStartupReadSource("Sources/NumlexApp/Views/ContentView.swift")
        let geometry = try windowStartupReadSource(
            "Sources/NumlexCore/Models/MainWindowGeometry.swift")
        let helper = try windowStartupScope(
            app,
            from: "private func mainWindowStartupPlacement() -> WindowPlacement",
            to: "var body: some Scene")
        let startupPolicy = try windowStartupScope(
            geometry,
            from: "public static func startupPlacement(",
            to: "private static func centeredDefaultPlacement(")
        let ratesAppear = try windowStartupScope(
            view,
            from: ".onAppear {",
            to: ".onChange(of: columnVisibility)")
        let initializer = try windowStartupScope(
            view,
            from: "func initializeAttachedWindow(_ window: NSWindow)",
            to: "private func installOwnedWindowObservers(")

        try expect(geometry.hasPrefix("import Foundation")
                   && !geometry.contains("import AppKit")
                   && !startupPolicy.contains("Rates")
                   && !startupPolicy.contains("Date")
                   && !startupPolicy.contains("Clock")
                   && !startupPolicy.contains("URLSession"),
                   "the core startup policy is Foundation-only and has no network or clock input")
        try expect(!helper.contains("loadRates")
                   && !helper.contains("RateRefresher")
                   && !helper.contains("await")
                   && !helper.contains("Task")
                   && !helper.contains("Date")
                   && !helper.contains("Clock"),
                   "the scene placement closure is independent of rates and time")
        try expect(ratesAppear.contains("Task { @MainActor in await model.loadRates() }")
                   && !ratesAppear.contains("MainWindowGeometry")
                   && !ratesAppear.contains("windowFrame")
                   && !ratesAppear.contains("setFrame("),
                   "rates load separately and their appearance callback has no geometry work")
        try expect(!initializer.contains("await ")
                   && !initializer.contains("Task")
                   && !initializer.contains("sleep(")
                   && !initializer.contains("DispatchQueue")
                   && !initializer.contains("MainWindowGeometry.restoredFrame")
                   && !initializer.contains("setFrame(")
                   && !initializer.contains("setContentSize(")
                   && !initializer.contains("center()"),
                   "attached setup has no polling, waiting, rate await, or delayed initial frame action")

        let full = CGRect(x: 0, y: 0, width: 1512, height: 1000)
        let visible = CGRect(x: 0, y: 40, width: 1512, height: 900)
        let saved = SavedWindowFrame(x: 100.5, y: 120.25, width: 900, height: 700)
        let rateSnapshots: [[String: Double]] = [[:], ["USD": 1.25, "EUR": 1.08]]
        let clockSnapshots = [Date(timeIntervalSince1970: 0),
                              Date(timeIntervalSince1970: 1_000_000)]
        var results: [MainWindowGeometry.StartupPlacement] = []
        for (rates, clock) in zip(rateSnapshots, clockSnapshots) {
            // These values deliberately remain outside the placement API.
            _ = rates.count
            _ = clock.timeIntervalSince1970
            results.append(MainWindowGeometry.startupPlacement(
                saved: saved, visibleFrames: [visible], primaryScreenFrame: full,
                primaryVisibleFrame: visible, sidebarVisible: true))
        }
        try expectEqual(results.count, 2,
                        "two distinct external rate/clock contexts are represented")
        try expectEqual(results[0], results[1],
                        "identical geometry inputs yield identical startup placement")
    },
]
