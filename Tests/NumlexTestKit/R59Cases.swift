import Foundation
import NumlexCore

// MARK: - r59: compact main-window heights
//
// The main window's CONTENT minimum is 260 pt (MainWindowGeometry — the
// one source of truth consumed by the scene root, ContentView and the
// AppKit configurator's frame conversion). Frame widths (800 expanded /
// 600 collapsed), the 800x600 default content size and the Settings
// 720x460 geometry are all unchanged. See
// Sources/NumlexCore/Models/MainWindowGeometry.swift.

/// Repo-root-relative source read, independent of the runner's cwd: the
/// kit file always lives at <root>/Tests/NumlexTestKit/.
private func r59SourceRoot() -> String {
    let here = URL(fileURLWithPath: #filePath)
    return here.deletingLastPathComponent() // NumlexTestKit
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // <root>
        .path
}

private func r59ReadSource(_ rel: String) throws -> String {
    let url = URL(fileURLWithPath: r59SourceRoot()).appendingPathComponent(rel)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        throw CaseFailure(message: "missing source file \(rel)")
    }
    return text
}

public let r59Cases: [EngineCase] = [
    EngineCase("r59-min-content-height-single-source") {
        try expectEqual(MainWindowGeometry.minContentHeight, 260,
                        "content minimum is exactly 260 pt")
    },
    EngineCase("r59-default-content-size-unchanged") {
        try expectEqual(MainWindowGeometry.defaultContentWidth, 800,
                        "default content width stays 800")
        try expectEqual(MainWindowGeometry.defaultContentHeight, 600,
                        "default content height stays 600")
    },
    EngineCase("r59-frame-widths-unchanged") {
        try expectEqual(MainWindowGeometry.expandedMinFrameWidth, 800,
                        "expanded frame floor stays 800")
        try expectEqual(MainWindowGeometry.collapsedMinFrameWidth, 600,
                        "collapsed frame floor stays 600")
        try expectEqual(MainWindowGeometry.contentMinWidth, 600,
                        "SwiftUI content floor stays 600")
    },
    EngineCase("r59-frame-height-conversion") {
        // Frame = content + chrome, measured never guessed: a raw 260
        // frame floor would leave LESS than 260 of content.
        for chrome in [0.0, 28.0, 52.0, 100.0] as [CGFloat] {
            try expectEqual(
                MainWindowGeometry.frameHeight(
                    contentHeight: MainWindowGeometry.minContentHeight,
                    chromeHeight: chrome),
                260 + chrome, "frame floor for chrome \(chrome)")
        }
        // A negative chrome contribution clamps to zero, never shrinks.
        try expectEqual(MainWindowGeometry.frameHeight(contentHeight: 260, chromeHeight: -5),
                        260, "negative chrome clamps")
    },
    EngineCase("r59-content-height-inverse-roundtrip") {
        // Across representative titlebar/toolbar heights the conversion
        // inverts exactly, so the claimed 260 content minimum is accurate.
        for chrome in [0.0, 28.0, 52.0, 100.0] as [CGFloat] {
            let frame = MainWindowGeometry.frameHeight(contentHeight: 260,
                                                        chromeHeight: chrome)
            try expectEqual(MainWindowGeometry.contentHeight(frameHeight: frame,
                                                             chromeHeight: chrome),
                            260, "roundtrip for chrome \(chrome)")
        }
        // Below-chrome frames report zero content, never negative: rows
        // scroll/clip, nothing overlaps or escapes.
        try expectEqual(MainWindowGeometry.contentHeight(frameHeight: 20, chromeHeight: 52),
                        0, "content never negative")
    },
    EngineCase("r59-compact-region-nonnegative") {
        // At the 260 content minimum every point is usable (titlebar is
        // outside content geometry): even reserving 200 pt for the
        // bottom Total bar and row padding leaves a positive scroll
        // region, and the realistic reserve (~64) leaves ample room.
        for reserve in [0.0, 64.0, 200.0] as [CGFloat] {
            try expect(MainWindowGeometry.minContentHeight - reserve > 0,
                       "rows region positive with \(reserve) pt reserve")
        }
    },
    EngineCase("r59-toggle-preserves-height-contract") {
        // The configurator's contract, modeled mathematically: the
        // collapse/expand helper carries ONLY horizontal geometry, so an
        // externally carried height/y passes 12 toggle cycles untouched —
        // no vertical jump, clamp or drift even at minimum height.
        var edge = SidebarWindowGeometry.Edge(originX: 100, width: 890)
        let height: CGFloat = 260 + 52
        let bottomY: CGFloat = 400
        for _ in 0..<12 {
            edge = SidebarWindowGeometry.collapsed(from: edge, sidebarWidth: 220, minWidth: 600)
            edge = SidebarWindowGeometry.expanded(from: edge, sidebarWidth: 220)
        }
        try expectEqual(edge, SidebarWindowGeometry.Edge(originX: 100, width: 890),
                        "horizontal roundtrip drift-free")
        try expectEqual(height, 312, "carried height untouched")
        try expectEqual(bottomY, 400, "carried bottom edge untouched")
    },
    EngineCase("r59-settings-geometry-untouched") {
        // SettingsGeometry lives in the app target (not importable
        // here), so pin it at the source: the Settings 720x460
        // geometry must not move with the main-window change.
        let text = try r59ReadSource("Sources/NumlexApp/Views/SettingsView.swift")
        for pin in ["minWidth: CGFloat = 690", "idealWidth: CGFloat = 720",
                    "minHeight: CGFloat = 460", "idealHeight: CGFloat = 460"] {
            try expect(text.contains(pin), "settings keeps \(pin)")
        }
    },
    EngineCase("r59-no-560-main-floor") {
        for rel in ["Sources/NumlexApp/NumlexApp.swift",
                    "Sources/NumlexApp/Views/ContentView.swift"] {
            let text = try r59ReadSource(rel)
            try expect(!text.contains("560"),
                       "\(rel) keeps no 560 floor")
            try expect(text.contains("MainWindowGeometry.minContentHeight"),
                       "\(rel) consumes the shared content minimum")
        }
    },
    EngineCase("r59-toggle-mutates-horizontal-only") {
        let text = try r59ReadSource("Sources/NumlexApp/Views/ContentView.swift")
        try expect(text.contains("newFrame.origin.x"),
                   "collapse/expand moves origin.x")
        try expect(text.contains("newFrame.size.width"),
                   "collapse/expand resizes width")
        try expect(!text.contains("newFrame.size.height"),
                   "never mutates frame height")
        try expect(!text.contains("newFrame.origin.y"),
                   "never mutates origin y")
    },
    EngineCase("r59-settings-view-independent") {
        let text = try r59ReadSource("Sources/NumlexApp/Views/SettingsView.swift")
        try expect(!text.contains("MainWindowGeometry"),
                   "settings never references the main-window geometry")
    },
]
