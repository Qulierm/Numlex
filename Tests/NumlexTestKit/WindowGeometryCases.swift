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

    EngineCase("window-startup-placement-saved-frame-uses-primary-full-display-top-left") {
        let primaryFull = CGRect(x: 0, y: 0, width: 1512, height: 1000)
        // The visible area starts above the bottom edge; saved conversion must
        // use the full primary display, not the menu/dock-excluded rectangle.
        let primaryVisible = CGRect(x: 0, y: 40, width: 1512, height: 900)
        let saved = SavedWindowFrame(x: 102.5, y: 120.25, width: 900, height: 700)
        let original = saved.rect
        let placement = MainWindowGeometry.startupPlacement(
            saved: saved, visibleFrames: [primaryVisible],
            primaryScreenFrame: primaryFull, primaryVisibleFrame: primaryVisible,
            sidebarVisible: true)
        try expectEqual(placement.position, Optional(CGPoint(x: 102.5, y: 179.75)),
                        "AppKit bottom-left frame converts from primary full-frame maxY")
        try expectEqual(placement.size, CGSize(width: 900, height: 700),
                        "accepted saved size is chosen before the scene first appears")
        try expect(placement.isRestoringSavedFrame,
                   "accepted saved geometry is marked as the restore result")

        let position = placement.position!
        let reconstructed = CGRect(
            x: position.x,
            y: primaryFull.maxY - (position.y + placement.size.height),
            width: placement.size.width,
            height: placement.size.height)
        guard let policyFrame = MainWindowGeometry.restoredFrame(
            saved: saved, visibleFrames: [primaryVisible],
            minimumSize: CGSize(width: MainWindowGeometry.expandedMinFrameWidth,
                                height: MainWindowGeometry.minContentHeight)) else {
            throw CaseFailure(message: "valid saved frame was rejected", location: "WindowGeometryCases")
        }
        try expectEqual(reconstructed, policyFrame,
                        "top-left scene placement inversely recovers the accepted AppKit frame")
        for _ in 0..<20 {
            let repeated = MainWindowGeometry.startupPlacement(
                saved: saved, visibleFrames: [primaryVisible],
                primaryScreenFrame: primaryFull, primaryVisibleFrame: primaryVisible,
                sidebarVisible: true)
            try expectEqual(repeated, placement,
                            "repeated selection has no cumulative coordinate drift")
        }
        try expectEqual(saved.rect, original,
                        "choosing initial placement never mutates persisted source geometry")
    },

    EngineCase("window-startup-placement-sidebar-floor-matches-normal-policy") {
        let full = CGRect(x: 0, y: 0, width: 2000, height: 1200)
        let saved = SavedWindowFrame(x: 100, y: 100, width: 500, height: 200)
        let visible = full
        let expanded = MainWindowGeometry.startupPlacement(
            saved: saved, visibleFrames: [visible], primaryScreenFrame: full,
            primaryVisibleFrame: visible, sidebarVisible: true)
        let collapsed = MainWindowGeometry.startupPlacement(
            saved: saved, visibleFrames: [visible], primaryScreenFrame: full,
            primaryVisibleFrame: visible, sidebarVisible: false)
        try expectEqual(expanded.size, CGSize(width: 800, height: 260),
                        "visible sidebar uses the established 800-by-260 frame floor")
        try expectEqual(collapsed.size, CGSize(width: 600, height: 260),
                        "hidden sidebar uses the established 600-by-260 frame floor")
        try expectEqual(expanded.position, Optional(CGPoint(x: 100, y: 840)),
                        "clamped size is converted without shifting the saved origin")
        try expect(expanded.isRestoringSavedFrame && collapsed.isRestoringSavedFrame,
                   "a floor-clamped saved frame remains the selected saved placement")
    },

    EngineCase("window-startup-placement-left-above-and-below-display-coordinates") {
        let primaryFull = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let primaryVisible = CGRect(x: 0, y: 0, width: 1200, height: 850)
        let cases: [(String, CGRect, CGRect, CGPoint)] = [
            ("left", CGRect(x: -1000, y: 0, width: 1000, height: 800),
             CGRect(x: -800, y: 80, width: 900, height: 600),
             CGPoint(x: -800, y: 220)),
            ("above", CGRect(x: 1200, y: 900, width: 1400, height: 1000),
             CGRect(x: 1300, y: 950, width: 900, height: 600),
             CGPoint(x: 1300, y: -650)),
            ("below", CGRect(x: 1200, y: -800, width: 1400, height: 800),
             CGRect(x: 1300, y: -700, width: 900, height: 600),
             CGPoint(x: 1300, y: 1000)),
        ]
        for (name, secondaryVisible, savedFrame, expectedPoint) in cases {
            let placement = MainWindowGeometry.startupPlacement(
                saved: SavedWindowFrame(savedFrame),
                visibleFrames: [primaryVisible, secondaryVisible],
                primaryScreenFrame: primaryFull,
                primaryVisibleFrame: primaryVisible,
                sidebarVisible: true)
            try expectEqual(placement.position, Optional(expectedPoint),
                            "the \(name) monitor uses the primary-full-frame desktop transform")
            try expectEqual(placement.size, savedFrame.size,
                            "the \(name) monitor preserves the accepted saved dimensions")
            try expect(placement.isRestoringSavedFrame,
                       "the \(name) monitor's usable saved frame is accepted")
        }
    },

    EngineCase("window-startup-placement-default-is-centered-on-primary-visible-area") {
        let full = CGRect(x: 0, y: 0, width: 1512, height: 1000)
        let visible = CGRect(x: 0, y: 40, width: 1512, height: 900)
        let placement = MainWindowGeometry.startupPlacement(
            saved: nil, visibleFrames: [visible], primaryScreenFrame: full,
            primaryVisibleFrame: visible, sidebarVisible: false)
        try expectEqual(placement.size,
                        CGSize(width: MainWindowGeometry.defaultContentWidth,
                               height: MainWindowGeometry.defaultContentHeight),
                        "no saved frame selects the designed 800-by-600 default")
        try expectEqual(placement.position, Optional(CGPoint(x: 356, y: 210)),
                        "fallback centers the default in the primary visible area")
        try expect(!placement.isRestoringSavedFrame,
                   "the designed default is not reported as a saved restore")
    },

    EngineCase("window-startup-placement-rejected-saved-frames-use-centered-default") {
        let full = CGRect(x: 0, y: 0, width: 1512, height: 1000)
        let visible = CGRect(x: 0, y: 40, width: 1512, height: 900)
        let expectedPosition: CGPoint? = CGPoint(x: 356, y: 210)
        let invalidSaved: [SavedWindowFrame?] = [
            nil,
            SavedWindowFrame(x: 5000, y: 5000, width: 900, height: 700),
            SavedWindowFrame(x: 1412.1, y: 100, width: 900, height: 700),
            SavedWindowFrame(x: 100, y: 100, width: .nan, height: 700),
            SavedWindowFrame(x: 100, y: 100, width: 0, height: 700),
        ]
        for saved in invalidSaved {
            let placement = MainWindowGeometry.startupPlacement(
                saved: saved, visibleFrames: [visible], primaryScreenFrame: full,
                primaryVisibleFrame: visible, sidebarVisible: true)
            try expectEqual(placement.position, expectedPosition,
                            "rejected/unavailable saved geometry selects primary-visible fallback")
            try expectEqual(placement.size, CGSize(width: 800, height: 600),
                            "rejected saved geometry never contributes its size")
            try expect(!placement.isRestoringSavedFrame,
                       "rejected saved geometry is marked as default placement")
        }

        let exactlyHundred = MainWindowGeometry.startupPlacement(
            saved: SavedWindowFrame(x: 1412, y: 100, width: 900, height: 700),
            visibleFrames: [visible], primaryScreenFrame: full,
            primaryVisibleFrame: visible, sidebarVisible: true)
        try expect(exactlyHundred.isRestoringSavedFrame,
                   "the existing inclusive 100-point overlap boundary is retained")
        try expectEqual(exactlyHundred.position, Optional(CGPoint(x: 1412, y: 200)),
                        "an exactly accepted boundary is placed from the saved frame")

        let noScreens = MainWindowGeometry.startupPlacement(
            saved: SavedWindowFrame(x: 100, y: 100, width: 900, height: 700),
            visibleFrames: [], primaryScreenFrame: nil, primaryVisibleFrame: nil,
            sidebarVisible: true)
        try expectEqual(noScreens.position, nil,
                        "no display reference leaves centering to SwiftUI's default display")
        try expectEqual(noScreens.size, CGSize(width: 800, height: 600),
                        "no screens still selects the designed default size")
        try expect(!noScreens.isRestoringSavedFrame,
                   "no screens cannot accept saved placement")
    },

    EngineCase("window-startup-placement-invalid-reference-and-overflow-never-return-bad-point") {
        let full = CGRect(x: 0, y: 0, width: 1512, height: 1000)
        let visible = CGRect(x: 0, y: 40, width: 1512, height: 900)
        let saved = SavedWindowFrame(x: 100, y: 100, width: 900, height: 700)
        let invalidPrimaryFrames: [CGRect?] = [
            nil,
            .zero,
            CGRect(x: CGFloat.nan, y: 0, width: 1512, height: 1000),
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 1000),
            CGRect(x: 0, y: 0, width: 1512, height: 0),
        ]
        for primaryFrame in invalidPrimaryFrames {
            let placement = MainWindowGeometry.startupPlacement(
                saved: saved, visibleFrames: [visible],
                primaryScreenFrame: primaryFrame, primaryVisibleFrame: visible,
                sidebarVisible: true)
            try expectEqual(placement.position, nil,
                            "invalid primary full-frame reference is never used")
            try expectEqual(placement.size, CGSize(width: 800, height: 600),
                            "invalid conversion falls back to the default size")
            try expect(!placement.isRestoringSavedFrame,
                       "invalid conversion cannot claim a saved-frame restore")
        }

        for primaryVisible in [Optional<CGRect>.none,
                               Optional(CGRect(x: 0, y: 0, width: 700, height: 500)),
                               Optional(CGRect(x: 0, y: 0, width: 1512, height: CGFloat.infinity))] {
            let placement = MainWindowGeometry.startupPlacement(
                saved: nil, visibleFrames: [], primaryScreenFrame: full,
                primaryVisibleFrame: primaryVisible, sidebarVisible: true)
            try expectEqual(placement.position, nil,
                            "missing, invalid, or undersized visible area uses SwiftUI centering")
            try expectEqual(placement.size, CGSize(width: 800, height: 600),
                            "last-resort placement retains the designed default size")
        }

        let largest = CGFloat.greatestFiniteMagnitude
        let overflowPlacement = MainWindowGeometry.startupPlacement(
            saved: nil, visibleFrames: [],
            primaryScreenFrame: CGRect(x: 0, y: 0, width: 1000, height: largest),
            primaryVisibleFrame: CGRect(x: 0, y: -largest / 2,
                                        width: 1000, height: 1000),
            sidebarVisible: true)
        try expectEqual(overflowPlacement.position, nil,
                        "overflow in derived desktop coordinates never escapes as a point")
        try expectEqual(overflowPlacement.size, CGSize(width: 800, height: 600),
                        "coordinate overflow retains default size")
        try expect(!overflowPlacement.isRestoringSavedFrame,
                   "coordinate overflow cannot claim a saved restore")
    },
]
