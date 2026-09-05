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
        try expect(view.contains("coord.hidePreference && coord.collapsed"),
                   "make/key paths apply preference && collapsed")
        try expect(view.contains("coord.hidePreference = hideSidebarButtonWhenCollapsed"),
                   "update refreshes the coordinator preference")
        try expect(view.contains("coord.collapsed = columnVisibility != .all"),
                   "update refreshes the coordinator collapse state")
        try expect(view.contains("coord.hidePreference && coord.collapsed"),
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
        let applyRange = view.range(of: "applySidebarButtonVisibility(to: w, hide: hideButton)")
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
]
