import Foundation
import NumlexCore

/// r52: the adaptive sidebar glass tone semantics — pure resolver
/// coverage (no pixels, no rendering): Light selected/action is a
/// subtle dark tint with a stronger boundary, Dark matches the
/// historical white 10%/22% values, the drop target is stronger than
/// selected, and appearance switching resolves both differently.
public let glassToneCases: [EngineCase] = [
    EngineCase("r52-dark-selected-historical-white10") {
        try expectEqual(SidebarGlassTone.tint(.selected, isDark: true),
                        GlassTone(red: 1, green: 1, blue: 1, alpha: 0.10),
                        "dark selected is the historical white 10% glass")
    },
    EngineCase("r52-dark-drop-historical-white22") {
        try expectEqual(SidebarGlassTone.tint(.dropTarget, isDark: true),
                        GlassTone(red: 1, green: 1, blue: 1, alpha: 0.22),
                        "dark drop is the historical white 22% glass")
    },
    EngineCase("r52-light-selected-subtle-dark-tint") {
        let t = SidebarGlassTone.tint(.selected, isDark: false)
        try expect(t.luminance < 1, "darker than white", "light selected tint")
        try expect(t.alpha > 0 && t.alpha <= 0.05,
                   "subtle 3–5% surface tint", "light selected tint")
        try expect(t.red == 0 && t.green == 0 && t.blue == 0,
                   "neutral graphite (no chromatic cast)", "light selected tint")
    },
    EngineCase("r52-light-boundary-stronger-than-tint") {
        let b = SidebarGlassTone.boundary(isDark: false)
        let t = SidebarGlassTone.tint(.selected, isDark: false)
        try expect(b.alpha > t.alpha,
                   "boundary stronger than the surface tint", "light boundary")
        try expect(b.alpha >= 0.08 && b.alpha <= 0.12,
                   "subtle 8–12% dark boundary", "light boundary")
    },
    EngineCase("r52-dark-boundary-clear") {
        try expectEqual(SidebarGlassTone.boundary(isDark: true).alpha, 0.0,
                        "dark boundary is clear — historical look preserved")
    },
    EngineCase("r52-drop-stronger-than-selected-both-appearances") {
        for isDark in [false, true] {
            let d = SidebarGlassTone.tint(.dropTarget, isDark: isDark)
            let s = SidebarGlassTone.tint(.selected, isDark: isDark)
            try expect(d.alpha > s.alpha,
                       "drop target stronger than selected (dark=\(isDark))",
                       "drop vs selected")
        }
    },
    EngineCase("r52-light-drop-accent-aware") {
        let d = SidebarGlassTone.tint(.dropTarget, isDark: false)
        try expect(d.blue > d.red,
                   "accent-blue aware", "light drop tint")
        try expect(d.alpha >= 0.10 && d.alpha < 0.20,
                   "calm but clearly visible", "light drop tint")
    },
    EngineCase("r52-appearance-switch-resolves-differently") {
        try expect(SidebarGlassTone.tint(.selected, isDark: false)
                   != SidebarGlassTone.tint(.selected, isDark: true),
                   "selected tint resolves per appearance", "switch")
        try expect(SidebarGlassTone.boundary(isDark: false)
                   != SidebarGlassTone.boundary(isDark: true),
                   "boundary resolves per appearance", "switch")
    }
]
