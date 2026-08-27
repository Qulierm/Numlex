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
]
