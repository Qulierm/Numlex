import Foundation
import NumlexCore

// MARK: - r20: main window resize with the system sidebar toggle
//
// Pure geometry: right edge and height are fixed, the left edge moves by
// the measured sidebar column width. See Sources/NumlexCore/Models/
// SidebarWindowGeometry.swift.

public let windowGeometryCases: [EngineCase] = [
    EngineCase("window-geometry-collapsed-right-edge-preserved") {
        let f = SidebarWindowGeometry.Edge(originX: 100, width: 890)
        let c = SidebarWindowGeometry.collapsed(from: f, sidebarWidth: 220, minWidth: 600)
        try expectEqual(c.rightEdge, f.rightEdge, "right edge must not move")
        try expectEqual(c.width, 670, "width shrinks by the sidebar width")
        try expectEqual(c.originX, 320, "left edge moves right")
    },
    EngineCase("window-geometry-expanded-grows-leftward") {
        let f = SidebarWindowGeometry.Edge(originX: 320, width: 670)
        let e = SidebarWindowGeometry.expanded(from: f, sidebarWidth: 220)
        try expectEqual(e.rightEdge, 990, "right edge must not move")
        try expectEqual(e.originX, 100, "left edge moves left")
        try expectEqual(e.width, 890, "width grows by the sidebar width")
    },
    EngineCase("window-geometry-roundtrip-no-drift") {
        var f = SidebarWindowGeometry.Edge(originX: 100, width: 890)
        for _ in 0..<12 {
            f = SidebarWindowGeometry.collapsed(from: f, sidebarWidth: 220, minWidth: 600)
            f = SidebarWindowGeometry.expanded(from: f, sidebarWidth: 220)
        }
        try expectEqual(f, SidebarWindowGeometry.Edge(originX: 100, width: 890),
                        "repeated cycles must be drift-free")
    },
    EngineCase("window-geometry-user-resized-sidebar-width") {
        // The measured width is whatever the user dragged (range 200...260),
        // not a hardcoded 220.
        let f = SidebarWindowGeometry.Edge(originX: 40, width: 890)
        let c = SidebarWindowGeometry.collapsed(from: f, sidebarWidth: 260, minWidth: 600)
        try expectEqual(c.width, 630, "shrinks by the user-resized width")
        let back = SidebarWindowGeometry.expanded(from: c, sidebarWidth: 260)
        try expectEqual(back, f, "round trip with a non-default width")
    },
    EngineCase("window-geometry-collapsed-minimum-clamp") {
        // 750 - 220 = 530 < 600 -> clamped to the detail minimum.
        let f = SidebarWindowGeometry.Edge(originX: 0, width: 750)
        let c = SidebarWindowGeometry.collapsed(from: f, sidebarWidth: 220, minWidth: 600)
        try expectEqual(c.width, 600, "collapsed width clamps to the detail minimum")
        try expectEqual(c.rightEdge, 750, "right edge still fixed")
    },
    EngineCase("window-geometry-screen-visible-clamp") {
        // Window partially off the left screen edge: the collapsed result
        // must stay inside the screen's visible span.
        let f = SidebarWindowGeometry.Edge(originX: 30, width: 890)
        let c = SidebarWindowGeometry.collapsed(from: f, sidebarWidth: 220,
                                                minWidth: 600, screenVisible: 0...1512)
        try expect(c.originX >= 0, "origin clamped to the screen left")
        try expect(c.rightEdge <= 1512, "right edge clamped to the screen right")
        // Fully on-screen input is untouched by the clamp.
        let g = SidebarWindowGeometry.Edge(originX: 100, width: 890)
        let d = SidebarWindowGeometry.collapsed(from: g, sidebarWidth: 220,
                                                minWidth: 600, screenVisible: 0...1512)
        try expectEqual(d.originX, 320, "on-screen origin unchanged")
        try expectEqual(d.width, 670, "on-screen width unchanged")
    },

    // MARK: Saved window frame restore rule (the documented off-screen protection)

    EngineCase("window-restore-normal-frame-is-applied-as-is") {
        // A frame that still overlaps a connected screen comes back with
        // its ORIGIN and SIZE untouched: restoring never re-centers.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let restored = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 100, y: 120, width: 900, height: 700),
            visibleFrames: [screen],
            minimumSize: CGSize(width: 800, height: 300))
        try expectEqual(restored, CGRect(x: 100, y: 120, width: 900, height: 700),
                        "a usable saved frame is returned unchanged")
    },

    EngineCase("window-restore-rejects-off-screen-and-slivers") {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let minimum = CGSize(width: 800, height: 300)
        // The documented protection: at least 100 pt of overlap in BOTH
        // dimensions, otherwise the centered default is kept.
        try expectEqual(MainWindowGeometry.minimumVisibleOverlap, 100,
                        "the documented minimum visible overlap")
        let offScreen = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 5000, y: 5000, width: 900, height: 700),
            visibleFrames: [screen], minimumSize: minimum)
        try expect(offScreen == nil, "a fully off-screen frame is discarded")
        // A 50 pt sliver of the window poking onto the screen.
        let sliver = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 1462, y: 120, width: 900, height: 700),
            visibleFrames: [screen], minimumSize: minimum)
        try expect(sliver == nil, "less than 100 pt of overlap is discarded")
        // One tenth of a point under the threshold still fails.
        let justUnder = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 1412.1, y: 120, width: 900, height: 700),
            visibleFrames: [screen], minimumSize: minimum)
        try expect(justUnder == nil, "99.9 pt of overlap is still discarded")
        // Exactly 100 pt is accepted (the rule is inclusive).
        let exactly = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 1412, y: 120, width: 900, height: 700),
            visibleFrames: [screen], minimumSize: minimum)
        try expectEqual(exactly, CGRect(x: 1412, y: 120, width: 900, height: 700),
                        "exactly the minimum overlap is accepted")
        // A window whose titlebar band is off-screen fails on HEIGHT too.
        let bandOff = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 100, y: 900, width: 900, height: 700),
            visibleFrames: [screen], minimumSize: minimum)
        try expect(bandOff == nil, "less than 100 pt of vertical overlap is discarded")
    },

    EngineCase("window-restore-degenerate-inputs") {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let minimum = CGSize(width: 800, height: 300)
        try expect(MainWindowGeometry.restoredFrame(saved: nil, visibleFrames: [screen],
                                                    minimumSize: minimum) == nil,
                   "no saved frame -> centered default")
        try expect(MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 100, y: 120, width: 900, height: 700),
            visibleFrames: [], minimumSize: minimum) == nil,
                   "no connected screen -> centered default")
        for bad in [SavedWindowFrame(x: 100, y: 120, width: 0, height: 700),
                    SavedWindowFrame(x: 100, y: 120, width: 900, height: 0),
                    SavedWindowFrame(x: 100, y: 120, width: -5, height: 700),
                    SavedWindowFrame(x: 100, y: 120, width: 900, height: -5),
                    SavedWindowFrame(x: 100, y: 120, width: .infinity, height: 700),
                    SavedWindowFrame(x: 100, y: 120, width: .nan, height: 700),
                    SavedWindowFrame(x: .nan, y: 120, width: 900, height: 700)] {
            try expect(!bad.hasUsableSize, "unusable size is detected")
            try expect(MainWindowGeometry.restoredFrame(saved: bad, visibleFrames: [screen],
                                                        minimumSize: minimum) == nil,
                       "an unusable size is discarded, never applied")
        }
    },

    EngineCase("window-restore-clamps-size-to-floor-and-screen") {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let minimum = CGSize(width: 800, height: 300)
        // Smaller than the visibility floor -> clamped UP, origin kept.
        let small = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 100, y: 120, width: 300, height: 200),
            visibleFrames: [screen], minimumSize: minimum)
        try expectEqual(small, CGRect(x: 100, y: 120, width: 800, height: 300),
                        "a too-small frame is clamped up to the floor")
        // Larger than the screen -> clamped DOWN to the visible frame.
        let big = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 100, y: 120, width: 2000, height: 1500),
            visibleFrames: [screen], minimumSize: minimum)
        try expectEqual(big, CGRect(x: 100, y: 120, width: 1512, height: 944),
                        "an oversized frame is clamped down to the chosen screen")
        // A screen SMALLER than the floor still never goes below it.
        let tinyScreen = CGRect(x: 0, y: 0, width: 700, height: 500)
        let onTiny = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 10, y: 10, width: 900, height: 700),
            visibleFrames: [tinyScreen], minimumSize: minimum)
        try expectEqual(onTiny, CGRect(x: 10, y: 10, width: 800, height: 500),
                        "the floor wins over a smaller screen for the width")
    },

    EngineCase("window-restore-picks-the-screen-with-the-largest-overlap") {
        let left = CGRect(x: -1512, y: 0, width: 1512, height: 944)
        let right = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let minimum = CGSize(width: 800, height: 300)
        // A frame mostly on the RIGHT screen keeps its (positive) origin.
        let onRight = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 1400, y: 100, width: 900, height: 500),
            visibleFrames: [left, right], minimumSize: minimum)
        try expectEqual(onRight, CGRect(x: 1400, y: 100, width: 900, height: 500),
                        "the screen with the largest intersection wins")
        // The same rule for a frame mostly on the LEFT screen.
        let onLeft = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: -800, y: 100, width: 900, height: 500),
            visibleFrames: [left, right], minimumSize: minimum)
        try expectEqual(onLeft, CGRect(x: -800, y: 100, width: 900, height: 500),
                        "a negative origin on the left screen is preserved")
        // Order in the list must not matter: the AREA decides.
        let reversed = MainWindowGeometry.restoredFrame(
            saved: SavedWindowFrame(x: 1400, y: 100, width: 900, height: 500),
            visibleFrames: [right, left], minimumSize: minimum)
        try expectEqual(reversed, onRight, "screen order does not affect the choice")
    },

    EngineCase("window-saved-frame-accessors-round-trip") {
        let rect = CGRect(x: 12.5, y: -3.25, width: 800, height: 600)
        let saved = SavedWindowFrame(rect)
        try expectEqual(saved.rect, rect, "a rect survives the round trip")
        try expect(saved.hasUsableSize, "a real size is usable")
        try expectEqual(saved.width, 800, "width is stored as a plain Double")
        try expectEqual(saved.height, 600, "height is stored as a plain Double")
        try expectEqual(SavedWindowFrame(x: 0, y: 0, width: 0, height: 600).hasUsableSize,
                        false, "a zero width is unusable")
    },

    EngineCase("window-frame-settle-dedup-rule") {
        // The rule `ContentView.rememberWindowFrame` applies before writing:
        // round the settled rect to whole points, then compare with the
        // stored frame. This case tests the RULE (the call site lives in the
        // app target, which the portable runner cannot import), and it is why
        // a settled move that reproduces the stored frame writes NOTHING.
        func settled(_ r: CGRect) -> SavedWindowFrame {
            SavedWindowFrame(x: r.origin.x.rounded(), y: r.origin.y.rounded(),
                             width: r.size.width.rounded(), height: r.size.height.rounded())
        }
        func wouldWrite(current: SavedWindowFrame?, frame: CGRect) -> Bool {
            guard let current else { return true }
            return current != settled(frame)
        }
        let stored = SavedWindowFrame(x: 100, y: 120, width: 900, height: 700)
        // Sub-point float churn collapses onto the stored value: no write.
        for jitter in [CGRect(x: 100.3, y: 120.4, width: 900.2, height: 699.6),
                       CGRect(x: 100.4, y: 120.4, width: 900.4, height: 700.4),
                       CGRect(x: 100, y: 120, width: 900, height: 700)] {
            try expect(!wouldWrite(current: stored, frame: jitter),
                       "sub-point churn must not write: \(jitter)")
        }
        // A real move or resize does write.
        try expect(wouldWrite(current: stored, frame: CGRect(x: 140, y: 120, width: 900, height: 700)),
                   "a move writes")
        try expect(wouldWrite(current: stored, frame: CGRect(x: 100, y: 120, width: 1000, height: 700)),
                   "a resize writes")
        // The very first settled frame has nothing to compare against.
        try expect(wouldWrite(current: nil, frame: CGRect(x: 100, y: 120, width: 900, height: 700)),
                   "no stored frame writes once")
        // `rounded()` is half-away-from-zero, so exactly half a point is a
        // real change (documented boundary, asserted so it is not a surprise).
        try expect(wouldWrite(current: stored, frame: CGRect(x: 100.5, y: 120, width: 900, height: 700)),
                   "a half-point offset counts as a change")
        // Programmatic restore self-deduplicates: the launch restore applies
        // the STORED frame, so the notification it provokes resolves equal.
        try expect(!wouldWrite(current: stored, frame: stored.rect),
                   "the launch restore can never write back what it just read")
    },
]
