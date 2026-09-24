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
        try expect(view.contains("forced || (preference && collapsed)"),
                   "the rule is forced OR (preference AND collapsed)")
        try expect(view.contains("coord.hidePreference = hideSidebarButtonWhenCollapsed"),
                   "update refreshes the coordinator preference")
        try expect(view.contains("coord.collapsed = columnVisibility != .all"),
                   "update refreshes the coordinator collapse state")
        try expect(view.contains("coord.reapply(to: window)"),
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
        // The configurator owns the flag end to end: declared input,
        // live wiring at the call site, hidden-state applied BEFORE the
        // width-only early return (preference-only toggles apply while
        // collapsed with no resize).
        let view = try r61ReadSource(
            "Sources/NumlexApp/Views/ContentView.swift")
        try expect(view.contains("var hideSidebarButtonWhenCollapsed: Bool"),
                   "configurator declares the preference input")
        try expect(view.contains(
            "hideSidebarButtonWhenCollapsed: model.settings.hideSidebarButtonWhenCollapsed"),
            "call site wires the live setting")
        try expect(view.contains("forceHideSidebarButton: sidebarToggleHiddenForWelcome"),
                   "call site wires the transient welcome force flag")
        let applyRange = view.range(of: "coord.reapply(to: w)")
        let guardRange = view.range(of: "guard coord.lastVisibility != columnVisibility else { return }")
        try expect(applyRange != nil && guardRange != nil,
                   "both hidden apply and width guard present")
        if let a = applyRange, let g = guardRange {
            try expect(a.lowerBound < g.lowerBound,
                       "hidden-state applies before the width-only guard")
        }
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
        // The launch path restores the SAVED frame from the settings
        // store (the single restore source) and keeps the long-standing
        // centered fallback for a legacy store or an unusable frame.
        let view = try r61ReadSource("Sources/NumlexApp/Views/ContentView.swift")
        let app = try r61ReadSource("Sources/NumlexApp/NumlexApp.swift")
        // The restored sidebar visibility is the FIRST value the
        // coordinator sees, so the first updateNSView hits the guard and
        // performs no launch resize.
        try expect(view.contains(
            "_columnVisibility = State(initialValue: model.settings.sidebarVisible ? .all : .detailOnly)"),
            "ContentView seeds the sidebar visibility from the saved setting")
        try expect(view.contains("init(model: AppModel) {"),
                   "the seeding happens in the one explicit initializer")
        try expect(view.contains("context.coordinator.lastVisibility = columnVisibility"),
                   "makeNSView records the RESTORED visibility as the first value")
        // The pure restore rule decides, with the live screens.
        try expect(view.contains("let restored = MainWindowGeometry.restoredFrame("),
                   "the launch path calls the pure restore rule")
        try expect(view.contains("saved: model.settings.windowFrame"),
                   "the saved frame is the input")
        try expect(view.contains("visibleFrames: NSScreen.screens.map(\\.visibleFrame)"),
                   "every connected screen's visible frame is the input")
        try expect(view.contains("let minSize = WindowConfigurator.minFrameSize("),
                   "the visibility floor is computed from the restored state")
        // Saved frame: floor first, then applied AS-IS — no setContentSize,
        // no centering, no sidebar-driven resize.
        guard let branch = view.range(of: "if let restored {") else {
            throw CaseFailure(message: "the saved-frame branch is missing", location: "R61Cases")
        }
        let afterBranch = String(view[branch.upperBound...])
        guard let fallback = afterBranch.range(of: "// r59 fallback:") else {
            throw CaseFailure(message: "the fallback branch is missing", location: "R61Cases")
        }
        let savedBranch = String(afterBranch[..<fallback.lowerBound])
        try expect(savedBranch.contains("window.minSize = minSize"),
                   "the restored floor is set BEFORE the frame is applied")
        try expect(savedBranch.contains("window.setFrame(restored, display: true)"),
                   "the saved frame is applied as-is")
        try expect(!savedBranch.contains("setContentSize"),
                   "the saved frame is never re-sized to the default content size")
        try expect(!savedBranch.contains("window.center()"),
                   "the saved frame is never re-centered")
        // Fallback: today's exact primary-display centering + 800x600.
        let fallbackBlock = String(afterBranch[fallback.lowerBound...])
        try expect(fallbackBlock.contains("window.setContentSize(NSSize(width: MainWindowGeometry.defaultContentWidth,"),
                   "the fallback keeps the designed 800x600 content size")
        try expect(fallbackBlock.contains("let primary = NSScreen.screens.first"),
                   "the fallback keeps the PRIMARY display rule")
        try expect(fallbackBlock.contains("window.center()"),
                   "the fallback keeps the center() last resort")
        // Exactly ONE restore source: SwiftUI restoration stays off and no
        // frame-autosave name is registered anywhere in the app target.
        try expect(app.contains(".restorationBehavior(.disabled)"),
                   "SwiftUI state restoration stays disabled")
        try expect(!app.contains("setFrameAutosaveName"),
                   "no frame-autosave name competes with the store")
        try expect(!view.contains("setFrameAutosaveName"),
                   "no frame-autosave name in ContentView either")
    },
    EngineCase("r61-window-frame-floor-precedes-visibility-guard") {
        // The visibility floor must be correct even when the guard
        // suppresses the width resize — a restored-collapsed launch
        // depends on it.
        let view = try r61ReadSource("Sources/NumlexApp/Views/ContentView.swift")
        guard let floor = view.range(of: "window.minSize = Self.minFrameSize(for: window,"),
              let guardRange = view.range(
                of: "guard coord.lastVisibility != columnVisibility else { return }")
        else {
            throw CaseFailure(message: "floor or guard missing", location: "R61Cases")
        }
        try expect(floor.lowerBound < guardRange.lowerBound,
                   "minSize is assigned BEFORE the visibility guard")
        // ...and the post-guard resize block no longer duplicates it.
        let afterGuard = String(view[guardRange.upperBound...])
        try expect(!afterGuard.contains("minSize = Self.minFrameSize"),
                   "the post-guard block has no duplicate minSize assignment")
        try expect(afterGuard.contains("window.setFrame"),
                   "the post-guard block still performs the width resize")
        // makeNSView uses the ACTUAL visibility, not a hard-coded true.
        try expect(view.contains("sidebarVisible: columnVisibility == .all"),
                   "both minFrameSize calls use the real visibility")
        try expect(!view.contains("minFrameSize(for: window, sidebarVisible: true)"),
                   "the hard-coded expanded floor is gone")
        // The existing guard line and its ordering with the hidden-state
        // apply are untouched (r61-configurator-preference-input).
        guard let apply = view.range(of: "coord.reapply(to: w)") else {
            throw CaseFailure(message: "the hidden-state apply is missing", location: "R61Cases")
        }
        try expect(apply.lowerBound < guardRange.lowerBound,
                   "the hidden-state apply still precedes the guard")
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
        try expect(view.contains("coord.onFrameSettled = onWindowFrameSettled"),
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
        try expect(observers.contains("coord.scheduleFrameSettle(window: window, immediate: false)"),
                   "a motion notification only schedules")
        try expect(observers.contains("coord.scheduleFrameSettle(window: window, immediate: true)"),
                   "termination schedules immediately")
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
        // Teardown removes every new observer and cancels the task.
        guard let dismantle = view.range(of: "func dismantleNSView(") else {
            throw CaseFailure(message: "dismantleNSView is missing", location: "R61Cases")
        }
        let teardown = String(view[dismantle.lowerBound...])
        try expect(teardown.contains("for obs in coordinator.frameObservers"),
                   "the new observers are removed on teardown")
        try expect(teardown.contains("coordinator.frameSettleTask?.cancel()"),
                   "a pending settle is cancelled on teardown")
    },
]
