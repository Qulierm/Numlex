import Foundation
import NumlexCore

// MARK: - r61: keyboard-only sidebar reopening
//
// The R60 `.toolbar(removing: .sidebarToggle)` conditional never hid the
// already-installed AppKit item at runtime (reproduced on a fresh debug
// build: flag ON + collapsed still showed the native button). The fix
// keeps the native item installed and drives the standard
// `NSToolbarItem.Identifier.toggleSidebar` item's `isHidden` from the
// existing WindowConfigurator (preference + collapsed state, applied
// before the width-only guard and re-asserted on key). `SidebarCommands`
// stays exactly once (native View-menu Toggle Sidebar + Control-Command-S,
// verified working at runtime). The setting itself stays additive:
// default OFF, old stores decode, StorePayload version untouched. See
// Sources/NumlexApp/Views/ContentView.swift.

/// Repo-root-relative source read, independent of the runner's cwd: the
/// kit file always lives at <root>/Tests/NumlexTestKit/.
private func r61SourceRoot() -> String {
    let here = URL(fileURLWithPath: #filePath)
    return here.deletingLastPathComponent() // NumlexTestKit
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // <root>
        .path
}

private func r61ReadSource(_ rel: String) throws -> String {
    let url = URL(fileURLWithPath: r61SourceRoot()).appendingPathComponent(rel)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        throw CaseFailure(message: "missing source file \(rel)")
    }
    return text
}

/// Minimal AppSettings JSON: every key the custom decoder REQUIRES.
/// The r61 flag is never required — old stores omit it entirely.
private func r61SettingsJSON(extra: String) throws -> String {
    """
    {"decimalPlaces":10,"fontSizeKey":"tf","language":"en",\
    "sheetName":"Sheet","lineNumbers":true,"fontColor":"white"\(extra)}
    """
}

private func r61DecodeSettings(_ json: String) throws -> AppSettings {
    try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
}

public let r61Cases: [EngineCase] = [
    EngineCase("r61-default-off") {
        // Backward-compatible default: existing behavior unchanged
        // unless the user opts in.
        try expectEqual(AppSettings.defaults.hideSidebarButtonWhenCollapsed,
                        false, "static defaults stay OFF")
        try expectEqual(AppSettings().hideSidebarButtonWhenCollapsed,
                        false, "memberwise init defaults OFF")
    },
    EngineCase("r61-decode-missing-key") {
        // Pre-r61 stores carry no key and must decode to OFF, not fail.
        let s = try r61DecodeSettings(r61SettingsJSON(extra: ""))
        try expectEqual(s.hideSidebarButtonWhenCollapsed, false,
                        "missing key falls back to false")
    },
    EngineCase("r61-decode-true-and-false") {
        let on = try r61DecodeSettings(
            r61SettingsJSON(extra: #","hideSidebarButtonWhenCollapsed":true"#))
        try expectEqual(on.hideSidebarButtonWhenCollapsed, true,
                        "persisted true decodes true")
        let off = try r61DecodeSettings(
            r61SettingsJSON(extra: #","hideSidebarButtonWhenCollapsed":false"#))
        try expectEqual(off.hideSidebarButtonWhenCollapsed, false,
                        "persisted false decodes false")
    },
    EngineCase("r61-decode-invalid-type") {
        // A malformed value (wrong JSON type) falls back to OFF instead
        // of failing the whole store — same failure-proof convention as
        // the r38 appearance key.
        let s = try r61DecodeSettings(
            r61SettingsJSON(extra: #","hideSidebarButtonWhenCollapsed":"yes""#))
        try expectEqual(s.hideSidebarButtonWhenCollapsed, false,
                        "wrong-type value falls back to false")
    },
    EngineCase("r61-settings-roundtrip") {
        // Encode→decode preserves both states (the persist path the
        // Settings toggle writes through).
        for flag in [true, false] {
            var s = AppSettings.defaults
            s.hideSidebarButtonWhenCollapsed = flag
            let data = try JSONEncoder().encode(s)
            let back = try JSONDecoder().decode(AppSettings.self, from: data)
            try expectEqual(back.hideSidebarButtonWhenCollapsed, flag,
                            "roundtrip preserves \(flag)")
        }
    },
    EngineCase("r61-store-payload-version-unchanged") {
        // Purely additive: no migration, no version bump.
        let persistence = try r61ReadSource(
            "Sources/NumlexCore/Services/Persistence.swift")
        try expect(persistence.contains("version stays 2"),
                   "StorePayload version stays 2")
        try expect(!persistence.contains("version = 3"),
                   "no version-3 bump")
    },
    EngineCase("r61-hidden-rule-source") {
        // The hide rule is preference AND collapsed — OFF either way
        // keeps the native button; ON+expanded keeps it (collapse path).
        let view = try r61ReadSource(
            "Sources/NumlexApp/Views/ContentView.swift")
        try expect(view.contains("static func effectiveSidebarButtonHidden(preference: Bool,"),
                   "ONE effective rule")
        try expect(view.contains("minimalMode || forced || (preference && collapsed)"),
                   "Minimal Mode ORs with forced OR (preference AND collapsed)")
        try expect(view.contains("self.hidePreference = hidePreference"),
                   "update refreshes the coordinator preference")
        try expect(view.contains("self.collapsed = effectiveVisibility != .all"),
                   "update refreshes the coordinator collapse state")
        try expect(view.contains("self.reapply(to: window)"),
                   "key reassertion reads latest coordinator inputs")
        try expect(!view.contains("self.hideSidebarButtonWhenCollapsed"),
                   "no stale struct capture in the observer")
    },
    EngineCase("r61-no-swiftui-removal") {
        // The R60 conditional-removal approach is gone (it never hid the
        // installed AppKit item); the unrelated title removal stays.
        let view = try r61ReadSource(
            "Sources/NumlexApp/Views/ContentView.swift")
        try expect(!view.contains("sidebarToggleScope"),
                   "conditional SwiftUI scope removed")
        try expect(!view.contains(".toolbar(removing: .sidebarToggle)"),
                   "SwiftUI sidebarToggle removal removed")
        try expect(view.contains(".toolbar(removing: .title)"),
                   "detail title removal preserved")
    },
    EngineCase("r61-native-identifier-source") {
        // Exactly the standard item by SDK identity, hidden not removed;
        // never view-snooping, never remove/reinsert.
        let view = try r61ReadSource(
            "Sources/NumlexApp/Views/ContentView.swift")
        try expect(view.contains("itemIdentifier == .toggleSidebar"),
                   "classic toggleSidebar identity fallback")
        try expect(view.contains("com.apple.SwiftUI.navigationSplitView.toggleSidebar"),
                   "SwiftUI namespaced toggle identity (runtime-observed)")
        try expect(view.contains("applySidebarButtonVisibility"),
                   "dedicated visibility helper")
        try expect(view.contains("item.isHidden"),
                   "AppKit isHidden, not removal")
        try expect(!view.contains("removeItem("),
                   "never removes the toolbar item")
        try expect(!view.contains("insertItem("),
                   "never reinserts the toolbar item")
    },
    EngineCase("r61-configurator-preference-input") {
        // The configurator owns the flag end to end: declared input, live
        // call-site wiring, and hidden-state application before a normal
        // visibility-only resize can early-return.
        let view = try r61ReadSource(
            "Sources/NumlexApp/Views/ContentView.swift")
        try expect(view.contains("var hideSidebarButtonWhenCollapsed: Bool"),
                   "configurator declares the preference input")
        try expect(view.contains(
            "hideSidebarButtonWhenCollapsed: model.settings.hideSidebarButtonWhenCollapsed"),
            "call site wires the live setting")
        try expect(view.contains("forceHideSidebarButton: sidebarToggleHiddenForWelcome"),
                   "call site wires the transient welcome force flag")
        try expect(view.contains("minimalMode: isMinimalMode"),
                   "the per-window mode state reaches the coordinator")
        guard let start = view.range(of: "private func applyLatestInputs()"),
              let end = view.range(of: "private func beginMinimalModeTransition(",
                                   range: start.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "latest-input application is missing", location: "R61Cases")
        }
        let applyBlock = String(view[start.lowerBound..<end.lowerBound])
        guard let applyRange = applyBlock.range(of: "reapply(to: window)"),
              let guardRange = applyBlock.range(of: "guard visibilityChanged else { return }") else {
            throw CaseFailure(message: "hidden apply or visibility guard is missing", location: "R61Cases")
        }
        try expect(applyRange.lowerBound < guardRange.lowerBound,
                   "hidden-state applies before the normal visibility guard")
        try expect(applyBlock.contains("window.minSize = minSize"),
                   "the latest sidebar-dependent floor is set before the guard")
    },
    EngineCase("r61-single-sidebar-command") {
        // Exactly one system command path — no duplicate Toggle Sidebar
        // menu item competing with the responder chain.
        let app = try r61ReadSource("Sources/NumlexApp/NumlexApp.swift")
        let count = app.components(separatedBy: "SidebarCommands").count - 1
        try expectEqual(count, 1, "exactly one SidebarCommands")
    },
    EngineCase("r61-localization-keys") {
        // Title + caption exist in all six languages, non-empty, and
        // the en/ru strings match the approved UX copy.
        for lang in AppLanguage.allCases {
            let title = L10n.t("hideSidebarBtn", language: lang)
            let cap = L10n.t("hideSidebarBtnCap", language: lang)
            try expect(!title.isEmpty && title != "hideSidebarBtn",
                       "\(lang) title present")
            try expect(!cap.isEmpty && cap != "hideSidebarBtnCap",
                       "\(lang) caption present")
        }
        try expectEqual(
            L10n.t("hideSidebarBtn", language: .en),
            "Hide sidebar button when collapsed", "en title exact")
        try expectEqual(
            L10n.t("hideSidebarBtn", language: .ru),
            "Скрывать кнопку боковой панели после сворачивания", "ru title exact")
    },
    EngineCase("r61-settings-toggle-wired") {
        // The General card binds the same persisted key it persists.
        let settings = try r61ReadSource(
            "Sources/NumlexApp/Views/SettingsView.swift")
        try expect(settings.contains("hideSidebarBtn"),
                   "title key used")
        try expect(settings.contains("hideSidebarBtnCap"),
                   "caption key used")
        try expect(settings.contains(
            "boolBinding(\\AppSettings.hideSidebarButtonWhenCollapsed)"),
            "toggle binds the persisted key")
    },
    EngineCase("r61-geometry-unchanged") {
        // The fix touches visibility only: R59 content/frame floors and
        // the 800x600 default stand exactly.
        try expectEqual(MainWindowGeometry.minContentHeight, 260,
                        "content minimum still 260")
        try expectEqual(MainWindowGeometry.expandedMinFrameWidth, 800,
                        "expanded floor still 800")
        try expectEqual(MainWindowGeometry.collapsedMinFrameWidth, 600,
                        "collapsed floor still 600")
        try expectEqual(MainWindowGeometry.defaultContentWidth, 800,
                        "default width still 800")
        try expectEqual(MainWindowGeometry.defaultContentHeight, 600,
                        "default height still 600")
    },

    EngineCase("r61-window-restore-launch-contract") {
        // Restore belongs to each attached NSView.window, not rates loading,
        // NSApp's key window, or another visible Settings/main window.
        let view = try r61ReadSource("Sources/NumlexApp/Views/ContentView.swift")
        let app = try r61ReadSource("Sources/NumlexApp/NumlexApp.swift")
        try expect(view.contains(
            "_columnVisibility = State(initialValue: model.settings.sidebarVisible ? .all : .detailOnly)"),
            "ContentView seeds normal sidebar visibility from the saved setting")
        try expect(view.contains("override func viewDidMoveToWindow()"),
                   "an attached-view lifecycle callback detects its native owner")
        try expect(view.contains("windowAttachmentChanged?(window)"),
                   "the lifecycle callback passes only view.window")
        try expect(view.contains("coord.windowAttachmentChanged(window, from: view)"),
                   "the coordinator receives its owned window")
        try expect(view.contains("Task { @MainActor in await model.loadRates() }"),
                   "rates continue loading independently")
        guard let appear = view.range(of: ".onAppear {"),
              let sidebarChange = view.range(of: ".onChange(of: columnVisibility)",
                                             range: appear.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "independent rates onAppear is missing", location: "R61Cases")
        }
        let appearBlock = String(view[appear.lowerBound..<sidebarChange.lowerBound])
        try expect(!appearBlock.contains("MainWindowGeometry.restoredFrame"),
                   "rate loading no longer owns window restoration")

        guard let initStart = view.range(of: "func initializeAttachedWindow(_ window: NSWindow)"),
              let nextMethod = view.range(of: "private func installOwnedWindowObservers(",
                                          range: initStart.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "owned-window initialization is missing", location: "R61Cases")
        }
        let initialize = String(view[initStart.lowerBound..<nextMethod.lowerBound])
        try expect(!initialize.contains("NSApp.keyWindow")
                   && !initialize.contains("NSApp.windows.first"),
                   "the attached owner never targets another AppKit window")
        try expect(initialize.contains(
            "guard attachedWindow === window, !didInitializeAttachedWindow else { return }"),
            "normal restore is exactly once for the attached owner")
        try expect(initialize.contains("saved: savedNormalFrame"),
                   "the current saved settings frame is the restore input")
        try expect(initialize.contains("visibleFrames: NSScreen.screens.map(\\.visibleFrame)"),
                   "every connected screen's visible frame is the input")
        guard let floor = initialize.range(of: "window.minSize = minSize"),
              let restore = initialize.range(of: "let restored = MainWindowGeometry.restoredFrame(") else {
            throw CaseFailure(message: "restore rule or frame floor is missing", location: "R61Cases")
        }
        try expect(floor.lowerBound < restore.lowerBound,
                   "the visibility-dependent frame floor is applied first")
        guard let branch = initialize.range(of: "if let restored {"),
              let fallback = initialize.range(of: "// Preserve the established centered 800x600 CONTENT fallback",
                                              range: branch.upperBound..<initialize.endIndex) else {
            throw CaseFailure(message: "saved-frame or fallback branch is missing", location: "R61Cases")
        }
        let savedBranch = String(initialize[branch.upperBound..<fallback.lowerBound])
        try expect(savedBranch.contains("window.setFrame(restored, display: true)"),
                   "the accepted saved origin is applied as-is")
        try expect(!savedBranch.contains("setContentSize"),
                   "the saved frame is never re-sized to the default content size")
        try expect(!savedBranch.contains("window.center()"),
                   "the saved frame is never re-centered")
        let fallbackBlock = String(initialize[fallback.lowerBound...])
        try expect(fallbackBlock.contains("window.setContentSize(NSSize(width: MainWindowGeometry.defaultContentWidth,"),
                   "fallback keeps the designed 800x600 content size")
        try expect(fallbackBlock.contains("let primary = NSScreen.screens.first"),
                   "fallback keeps the primary-display rule")
        try expect(fallbackBlock.contains("window.center()"),
                   "fallback keeps center() as the last resort")
        try expect(initialize.contains("didInitializeAttachedWindow = true"),
                   "the initialization guard is claimed before frame work")

        // Exactly ONE restore source: SwiftUI restoration stays off and no
        // frame-autosave name competes with the saved settings frame.
        try expect(app.contains(".restorationBehavior(.disabled)"),
                   "SwiftUI state restoration stays disabled")
        try expect(!app.contains("setFrameAutosaveName"),
                   "no frame-autosave name competes with the store")
        try expect(!view.contains("setFrameAutosaveName"),
                   "no frame-autosave name in ContentView")
    },
    EngineCase("r61-minimal-mode-owned-window-transition-safety") {
        let view = try r61ReadSource("Sources/NumlexApp/Views/ContentView.swift")
        let settings = try r61ReadSource("Sources/NumlexCore/Models/Settings.swift")
        try expect(view.contains("weak var attachedWindow: NSWindow?"),
                   "the coordinator weakly owns only its attached window")
        try expect(view.contains("guard attachedWindow === window, !didInitializeAttachedWindow else { return }"),
                   "launch restore is exactly once and identity-scoped")
        try expect(view.contains("if normalFrameSnapshot == nil"),
                   "entry never overwrites an existing pre-entry snapshot")
        try expect(view.contains("normalFrameSnapshot = window.frame"),
                   "entry captures the current owning window frame")
        try expect(view.contains("onCaptureNormalFrame?(window.frame)"),
                   "the normal snapshot goes through the existing guarded writer")
        try expect(view.contains("cachedNormalFrame: normalFrameSnapshot"),
                   "exit restores the cached normal rectangle")
        try expect(view.contains("savedNormalFrame: savedNormalFrame"),
                   "saved normal geometry remains the validated fallback")
        try expect(view.contains("geometryRequestGeneration &+= 1"),
                   "every geometry request has a generation")
        try expect(view.contains("isCurrentGeometryRequest(generation, window: window)"),
                   "only the latest still-owned-window request may complete")
        guard let applyStart = view.range(of: "private func applyLatestInputs()"),
              let applyEnd = view.range(of: "private func beginMinimalModeTransition(",
                                        range: applyStart.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "latest-input geometry path is missing", location: "R61Cases")
        }
        let apply = String(view[applyStart.lowerBound..<applyEnd.lowerBound])
        guard let modeChange = apply.range(of: "if modeChanged {"),
              let consumeVisibility = apply.range(of: "lastVisibility = effectiveVisibility"),
              let transition = apply.range(of: "beginMinimalModeTransition(to: requestedMinimalMode"),
              let visibilityGuard = apply.range(of: "guard visibilityChanged else { return }"),
              let sidebarResize = apply.range(of: "scheduleSidebarResize(window: window,") else {
            throw CaseFailure(message: "mode/visibility ordering is missing", location: "R61Cases")
        }
        try expect(modeChange.lowerBound < visibilityGuard.lowerBound
                   && consumeVisibility.lowerBound < transition.lowerBound
                   && transition.lowerBound < visibilityGuard.lowerBound
                   && visibilityGuard.lowerBound < sidebarResize.lowerBound,
                   "mode geometry consumes the projected visibility before any ordinary sidebar delta")
        try expect(view.contains("sidebarResizeTask?.cancel()"),
                   "mode transitions cancel queued ordinary sidebar work")
        try expect(view.contains("window.frameRect(forContentRect: contentRect).size"),
                   "compact geometry uses AppKit's live content-to-frame conversion")
        try expect(view.contains("MinimalModeGeometry.enteringFrame("),
                   "entry uses the pure top-right/screen-clamp policy")
        try expect(view.contains("MinimalModeGeometry.restoringFrame("),
                   "exit uses the cached-frame restore policy")
        try expect(view.contains("context.duration = Coordinator.minimalModeAnimationDuration"),
                   "normal-motion transitions use the restrained native animation")
        try expect(view.contains("static let minimalModeAnimationDuration: TimeInterval = 0.18"),
                   "native mode animation is 0.18 seconds")
        try expect(view.contains("if reduceMotion {\n                window.setFrame(frame, display: true)"),
                   "Reduce Motion applies the frame immediately")
        try expect(view.contains("isMinimalMode: requestedMinimalMode || activeMinimalMode"),
                   "pending and active compact frames cannot be persisted")
        try expect(view.contains("guard owns(window), isWindowReady, mayPersistNormalFrame else { return }"),
                   "settled and termination writes are guarded by mode/full-screen state")
        try expect(view.contains("for name in [NSWindow.willEnterFullScreenNotification"),
                   "full-screen state observes only the owning NSWindow")
        try expect(view.contains("private func publishFullscreenAvailability()"),
                   "the coordinator reports when the titlebar action is available")
        try expect(view.contains("for observer in frameObservers + fullScreenObservers"),
                   "owned observers are removed during teardown")
        try expect(view.contains("toolbarReassertionTask?.cancel()"),
                   "all bounded asynchronous work is cancelled during teardown")
        try expect(!settings.contains("minimalMode"),
                   "Minimal Mode adds no persisted AppSettings key")
        guard let ownerStart = view.range(of: "private struct WindowConfigurator"),
              let ownerEnd = view.range(of: "private func applySidebarButtonVisibility(",
                                        range: ownerStart.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "owned configurator scope is missing", location: "R61Cases")
        }
        let owner = String(view[ownerStart.lowerBound..<ownerEnd.lowerBound])
        try expect(!owner.contains("NSApp.keyWindow") && !owner.contains("NSApp.windows.first"),
                   "all new geometry targets come from the attached view")
    },
    EngineCase("r61-minimal-mode-titlebar-and-sidebar-command-contract") {
        let view = try r61ReadSource("Sources/NumlexApp/Views/ContentView.swift")
        try expect(view.contains("@State private var isMinimalMode = false"),
                   "each ContentView starts in session-only normal mode")
        try expect(view.contains("@State private var owningWindowReady = false"),
                   "the owning window begins unavailable until its restore completes")
        try expect(view.contains("@State private var minimalModeFullscreenAvailable = false"),
                   "native full-screen availability begins false")
        try expect(view.contains("NavigationSplitView(columnVisibility: effectiveColumnVisibility)"),
                   "the split view receives the projected binding")
        try expect(view.contains("minimalMode: isMinimalMode"),
                   "the same per-window mode reaches the frame coordinator")
        try expectEqual(view.components(separatedBy: "effectiveVisibility: minimalMode ? .detailOnly : normalColumnVisibility,").count - 1,
                        2, "make and update use the same effective visibility")
        guard let bindingStart = view.range(of: "private var effectiveColumnVisibility: Binding<NavigationSplitViewVisibility>"),
              let bindingEnd = view.range(of: "/// Live measured width of the sidebar column",
                                          range: bindingStart.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "effective visibility binding is missing", location: "R61Cases")
        }
        let binding = String(view[bindingStart.lowerBound..<bindingEnd.lowerBound])
        try expect(binding.contains("if isMinimalMode { return .detailOnly }"),
                   "Minimal Mode projects detail-only without changing the normal state")
        try expect(binding.contains("return visible ? .all : columnVisibility"),
                   "the normal getter preserves the underlying visibility value")
        try expect(binding.contains("if isMinimalMode && requested == .detailOnly { return }"),
                   "idempotent collapsed writes do not mutate normal state")
        try expect(binding.contains("if isMinimalMode { isMinimalMode = false }"),
                   "a real sidebar request exits Minimal Mode")
        try expect(binding.contains("guard columnVisibility != requested else { return }"),
                   "only an actual normal-visibility change updates state")
        try expect(binding.contains("columnVisibility = requested"),
                   "the command's requested normal visibility is honored")
        try expect(view.contains(".onChange(of: columnVisibility)"),
                   "only normal visibility enters the existing persistence path")
        try expect(!view.contains(".onChange(of: effectiveColumnVisibility)"),
                   "the temporary sidebar projection is never persisted")

        guard let toolbarStart = view.range(of: "ToolbarItem(placement: .primaryAction)"),
              let toolbarEnd = view.range(of: "// r59: the compact content minimum",
                                          range: toolbarStart.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "stable primary-action toolbar item is missing", location: "R61Cases")
        }
        let toolbar = String(view[toolbarStart.lowerBound..<toolbarEnd.lowerBound])
        try expect(toolbar.contains("Button {\n                    isMinimalMode.toggle()"),
                   "the installed button toggles this window's mode")
        try expect(toolbar.contains("arrow.down.right.and.arrow.up.left"),
                   "the entry icon is the specified system symbol")
        try expect(toolbar.contains("arrow.up.left.and.arrow.down.right"),
                   "the exit icon is the specified system symbol")
        try expect(toolbar.contains(".help(L10n.t("),
                   "the icon-only button has a localized tooltip")
        try expect(toolbar.contains(".accessibilityLabel(L10n.t("),
                   "the button has a localized action label")
        try expect(toolbar.contains(".accessibilityValue(L10n.t("),
                   "the current on/off value is explicitly localized")
        try expect(toolbar.contains(".accessibilityAddTraits(isMinimalMode ? .isSelected : [])"),
                   "the selected state is explicit")
        try expect(toolbar.contains(".disabled(!owningWindowReady || !minimalModeFullscreenAvailable)"),
                   "the button waits for restore and native full-screen ownership")
        try expect(view.contains("onWindowReady: { owningWindowReady = $0 }"),
                   "the owning-window readiness callback is wired")
        try expect(view.contains("onFullscreenAvailability: { minimalModeFullscreenAvailable = $0 }"),
                   "full-screen availability updates button state")
        try expect(view.contains("onMinimalModeRequestRejected: { isMinimalMode = $0 }"),
                   "rejected geometry requests restore the coordinator's actual mode")
        try expect(!view.contains(".id(isMinimalMode)"),
                   "mode changes never reconstruct the editor subtree")
    },
    EngineCase("r61-window-frame-floor-precedes-visibility-guard") {
        // The normal/sidebar floor is always updated before resize suppression;
        // Minimal Mode instead uses the requested normal visibility on exit.
        let view = try r61ReadSource("Sources/NumlexApp/Views/ContentView.swift")
        guard let start = view.range(of: "private func applyLatestInputs()"),
              let end = view.range(of: "private func beginMinimalModeTransition(",
                                   range: start.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "latest-input block is missing", location: "R61Cases")
        }
        let block = String(view[start.lowerBound..<end.lowerBound])
        guard let floor = block.range(of: "window.minSize = minSize"),
              let apply = block.range(of: "reapply(to: window)"),
              let guardRange = block.range(of: "guard visibilityChanged else { return }") else {
            throw CaseFailure(message: "floor, hidden apply, or visibility guard missing", location: "R61Cases")
        }
        try expect(floor.lowerBound < guardRange.lowerBound,
                   "minSize is assigned BEFORE the visibility guard")
        try expect(apply.lowerBound < guardRange.lowerBound,
                   "hidden-state applies before the visibility guard")
        try expect(block.contains("let shouldShowSidebar = !requestedMinimalMode && normalVisibility == .all"),
                   "the floor uses normal visibility but collapses during Minimal Mode")
        try expect(!block.contains("window.setFrame"),
                   "frame mutation remains in the separately queued geometry path")
        try expect(view.contains("sidebarVisible: normalVisibility == .all"),
                   "exit floor uses the requested normal sidebar visibility")
        try expect(!view.contains("minFrameSize(for: window, sidebarVisible: true)"),
                   "the hard-coded expanded floor is absent")
    },
    EngineCase("r61-sidebar-visibility-persists-once-per-change") {
        // The sidebar's shown/hidden state is persisted with ONE guarded
        // write — a no-op change never touches the disk.
        let view = try r61ReadSource("Sources/NumlexApp/Views/ContentView.swift")
        try expect(view.contains(".onChange(of: columnVisibility)"),
                   "the sidebar state is observed")
        try expect(view.contains("guard model.settings.sidebarVisible != visible else { return }"),
                   "the write is behind an equality guard")
        try expect(view.contains("model.settings.sidebarVisible = visible"),
                   "the setting is updated in memory first")
        // Bound the slice at the NEXT member declaration, so the count
        // below is about the sidebar write-back alone and cannot be
        // satisfied by an unrelated writer elsewhere in the type.
        guard let change = view.range(of: ".onChange(of: columnVisibility)"),
              let end = view.range(of: "/// Remember the frame the user left the window in.",
                                   range: change.upperBound..<view.endIndex) else {
            throw CaseFailure(message: "the sidebar observer block is not delimited",
                              location: "R61Cases")
        }
        // The observer runs to the end of ContentView's body (the next
        // file-scope declaration bounds it), so the count below is about
        // the sidebar write-back specifically — not the whole file.
        let observer = String(view[change.lowerBound..<end.lowerBound])
        try expectEqual(observer.components(separatedBy: "model.persist()").count - 1, 1,
                        "exactly one persist in the sidebar observer")
        guard let guardRange = observer.range(
                of: "guard model.settings.sidebarVisible != visible else { return }"),
              let persistRange = observer.range(of: "model.persist()") else {
            throw CaseFailure(message: "guard or persist missing from the observer",
                              location: "R61Cases")
        }
        try expect(guardRange.lowerBound < persistRange.lowerBound,
                   "the equality guard precedes the one persist")
        try expect(!observer.contains("Task.sleep"),
                   "the sidebar write is not debounced-per-frame either")
    },

    EngineCase("r61-window-frame-saved-on-settled-motion") {
        // A window move posts a long stream of notifications, so the
        // coordinator only RESCHEDULES a coalescing task and the write
        // happens once, after the motion stops — the answer-column width
        // drag discipline, applied to the frame.
        let view = try r61ReadSource("Sources/NumlexApp/Views/ContentView.swift")
        // The settle callback is an input, refreshed on every update so it
        // can never capture a stale model.
        try expect(view.contains("var onWindowFrameSettled: (CGRect) -> Void"),
                   "the configurator declares the settle callback input")
        try expect(view.contains("onWindowFrameSettled: rememberWindowFrame"),
                   "the call site wires the live ContentView handler")
        try expect(view.contains("self.onFrameSettled = onFrameSettled"),
                   "the coordinator is refreshed with the latest callback")
        // Both motion sources plus the termination backstop.
        try expect(view.contains("for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification]"),
                   "moves and live-resize ends are both observed")
        try expect(view.contains("forName: NSApplication.willTerminateNotification"),
                   "termination is observed as the move-and-quit backstop")
        // Coalescing, not per-notification writes.
        guard let sched = view.range(of: "func scheduleFrameSettle(window: NSWindow, immediate: Bool)") else {
            throw CaseFailure(message: "the coalescing entry point is missing", location: "R61Cases")
        }
        let scheduler = String(view[sched.lowerBound...])
        guard let nextMember = scheduler.range(of: "\n    }\n") else {
            throw CaseFailure(message: "the coalescing body is not delimited", location: "R61Cases")
        }
        let body = String(scheduler[..<nextMember.upperBound])
        try expect(body.contains("frameSettleTask?.cancel()"),
                   "each new notification cancels the pending settle")
        try expect(body.contains("onFrameSettled?(window.frame)"),
                   "the pending settle hands over the CURRENT frame")
        try expectEqual(body.components(separatedBy: "onFrameSettled?(").count - 1, 2,
                        "handled exactly twice: the immediate path and the settled path")
        try expect(body.contains("Task.sleep(for: Coordinator.frameSettleDelay)"),
                   "the settled path is delayed, not immediate")
        try expect(!body.contains("model.persist()"),
                   "the scheduler itself never persists")
        try expect(view.contains("static let frameSettleDelay: Duration = .milliseconds(400)"),
                   "the debounce window is a named constant")
        // The observer closures only reschedule.
        guard let moves = view.range(of: "for name in [NSWindow.didMoveNotification") else {
            throw CaseFailure(message: "the motion observers are missing", location: "R61Cases")
        }
        let observers = String(view[moves.lowerBound...])
        try expect(observers.contains("self.scheduleFrameSettle(window: window, immediate: false)"),
                   "an owned-window motion notification only schedules")
        try expect(observers.contains("self.scheduleFrameSettle(window: window, immediate: true)"),
                   "termination schedules immediately for the owned window")
        // The write path compares BEFORE persisting, and rounds first.
        guard let write = view.range(of: "private func rememberWindowFrame(_ frame: CGRect)") else {
            throw CaseFailure(message: "the write path is missing", location: "R61Cases")
        }
        let writer = String(view[write.lowerBound...])
        guard let compare = writer.range(of: "guard model.settings.windowFrame != settled else { return }"),
              let persist = writer.range(of: "model.persist()") else {
            throw CaseFailure(message: "the comparison or the write is missing", location: "R61Cases")
        }
        try expect(compare.lowerBound < persist.lowerBound,
                   "the stored-frame comparison precedes the single persist")
        try expect(writer.contains("frame.origin.x.rounded()"),
                   "the settled rect is rounded to whole points first")
        try expectEqual(writer.components(separatedBy: "model.persist()").count - 1, 1,
                        "exactly one persist in the write path")
        // Teardown removes every owned observer and cancels all geometry tasks.
        guard let dismantle = view.range(of: "func dismantleNSView(") else {
            throw CaseFailure(message: "dismantleNSView is missing", location: "R61Cases")
        }
        let teardown = String(view[dismantle.lowerBound...])
        try expect(teardown.contains("coordinator.dismantle(view: view)"),
                   "the representable tears down its owner coordinator")
        try expect(view.contains("for observer in frameObservers + fullScreenObservers"),
                   "window, termination, and full-screen observers are removed")
        try expect(view.contains("frameSettleTask?.cancel()"),
                   "a pending normal-frame settle is cancelled")
        try expect(view.contains("sidebarResizeTask?.cancel()"),
                   "a queued sidebar geometry task is cancelled")
        try expect(view.contains("toolbarReassertionTask?.cancel()"),
                   "bounded toolbar work is cancelled on teardown")
    },
]
