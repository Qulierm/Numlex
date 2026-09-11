import Foundation
import NumlexCore

/// r52: the adaptive sidebar glass **wash** semantics — pure resolver plus
/// deterministic compositing coverage (no pixels, no rendering): Light
/// selected/action is a subtle graphite wash that stays light over white,
/// Dark matches the historical white 10%/22% values, the drop target is
/// stronger than selected, appearance switching resolves both differently,
/// and the wash is composited by the normal fill path (never handed to
/// `Glass.tint`).
public let glassToneCases: [EngineCase] = [
    EngineCase("r52-dark-selected-historical-white10") {
        try expectEqual(SidebarGlassTone.wash(.selected, isDark: true),
                        GlassTone(red: 1, green: 1, blue: 1, alpha: 0.10),
                        "dark selected is the historical white 10% glass")
    },
    EngineCase("r52-dark-drop-historical-white22") {
        try expectEqual(SidebarGlassTone.wash(.dropTarget, isDark: true),
                        GlassTone(red: 1, green: 1, blue: 1, alpha: 0.22),
                        "dark drop is the historical white 22% glass")
    },
    EngineCase("r52-light-selected-subtle-graphite-wash") {
        let t = SidebarGlassTone.wash(.selected, isDark: false)
        try expect(t.luminance < 1, "darker than white", "light selected wash")
        try expect(t.alpha > 0 && t.alpha <= 0.05,
                   "subtle 3–5% surface wash", "light selected wash")
        try expect(t.red == 0 && t.green == 0 && t.blue == 0,
                   "neutral graphite (no chromatic cast)", "light selected wash")
    },
    EngineCase("r52-light-selected-composites-light-over-white") {
        // The regression contract: a normal fill composite of the 4%
        // graphite wash over the white sidebar must stay a LIGHT surface.
        // The Tahoe bug produced ~RGB 96 because the alpha was handed to
        // Glass.tint and read as strength; deterministic compositing gives
        // ~RGB 245.
        let composite = SidebarGlassTone.wash(.selected, isDark: false)
            .composited(over: SidebarGlassTone.lightSidebarBase)
        let rgb = composite.red * 255
        try expect(rgb > 235 && rgb < 252,
                   "selected composite ~245, got \(Int(rgb.rounded()))",
                   "light selected composite")
        try expect(rgb != 96, "must never reach the regressed near-solid 96",
                   "light selected composite")
    },
    EngineCase("r52-light-drop-composites-light-over-white") {
        let composite = SidebarGlassTone.wash(.dropTarget, isDark: false)
            .composited(over: SidebarGlassTone.lightSidebarBase)
        // The drop wash is stronger than selected but must stay a calm
        // light-blue surface, not a dark block.
        try expect(composite.blue > composite.red,
                   "drop composite stays accent-aware", "light drop composite")
        try expect(composite.red * 255 > 200,
                   "drop composite stays light", "light drop composite")
    },
    EngineCase("r52-dark-composites-preserve-calm-contrast") {
        // Dark: white washes over the dark sidebar must stay a calm,
        // readable surface — never blow out to near-white and never
        // collapse into the background.
        for role in [SidebarGlassTone.Role.selected, .dropTarget] {
            let composite = SidebarGlassTone.wash(role, isDark: true)
                .composited(over: SidebarGlassTone.darkSidebarBase)
            let rgb = composite.red * 255
            try expect(rgb > 40 && rgb < 130,
                       "dark \(role) composite calm (got \(Int(rgb.rounded())))",
                       "dark composite")
        }
    },
    EngineCase("r52-light-boundary-stronger-than-wash") {
        let b = SidebarGlassTone.boundary(isDark: false)
        let t = SidebarGlassTone.wash(.selected, isDark: false)
        try expect(b.alpha > t.alpha,
                   "boundary stronger than the surface wash", "light boundary")
        try expect(b.alpha >= 0.08 && b.alpha <= 0.12,
                   "subtle 8–12% dark boundary", "light boundary")
    },
    EngineCase("r52-dark-boundary-clear") {
        try expectEqual(SidebarGlassTone.boundary(isDark: true).alpha, 0.0,
                        "dark boundary is clear — historical look preserved")
    },
    EngineCase("r52-drop-stronger-than-selected-both-appearances") {
        for isDark in [false, true] {
            let d = SidebarGlassTone.wash(.dropTarget, isDark: isDark)
            let s = SidebarGlassTone.wash(.selected, isDark: isDark)
            try expect(d.alpha > s.alpha,
                       "drop target stronger than selected (dark=\(isDark))",
                       "drop vs selected")
        }
    },
    EngineCase("r52-light-drop-accent-aware") {
        let d = SidebarGlassTone.wash(.dropTarget, isDark: false)
        try expect(d.blue > d.red,
                   "accent-blue aware", "light drop wash")
        try expect(d.alpha >= 0.10 && d.alpha < 0.20,
                   "calm but clearly visible", "light drop wash")
    },
    EngineCase("r52-appearance-switch-resolves-differently") {
        try expect(SidebarGlassTone.wash(.selected, isDark: false)
                   != SidebarGlassTone.wash(.selected, isDark: true),
                   "selected wash resolves per appearance", "switch")
        try expect(SidebarGlassTone.boundary(isDark: false)
                   != SidebarGlassTone.boundary(isDark: true),
                   "boundary resolves per appearance", "switch")
        // Light selected is dark-on-white; dark selected is white-on-dark.
        try expect(SidebarGlassTone.wash(.selected, isDark: false).red
                   < SidebarGlassTone.wash(.selected, isDark: true).red,
                   "the wash polarity flips with the appearance", "switch")
    },
    EngineCase("r52-source-wiring-single-glass-surface") {
        // Source-level regression: sidebar glass must be exactly ONE
        // untinted surface per caller, with the wash drawn by a normal
        // fill — never an alpha-bearing `.tint(...)` and never a static
        // dynamic-NSColor bridge.
        guard let view = glassToneRepoFile("Sources/NumlexApp/Views/SidebarView.swift") else {
            throw CaseFailure(message: "SidebarView.swift missing")
        }
        guard let design = glassToneRepoFile("Sources/NumlexApp/Design.swift") else {
            throw CaseFailure(message: "Design.swift missing")
        }
        try expect(view.contains(".tint(Design.sidebar") == false,
                   "no alpha tint handed to Glass", "sidebar view")
        try expect(view.contains(".tint(") == false,
                   "no Glass.tint call at all in the sidebar", "sidebar view")
        // Untinted glass + the wash fill + one boundary, in one primitive.
        // Count CODE only: doc comments legitimately quote the call shape.
        let code = view.split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let glassCalls = code.components(separatedBy: ".glassEffect(").count - 1
        try expect(glassCalls == 1,
                   "exactly one .glassEffect call site in the sidebar (got \(glassCalls))",
                   "sidebar view")
        try expect(view.contains(".glassEffect(.regular.interactive(), in: shape)"),
                   "the single glass surface is untinted", "sidebar view")
        try expect(view.contains("shape.fill(Design.sidebarWash("),
                   "the wash is a normal shape fill under the glass", "sidebar view")
        // One shared primitive for every surface class.
        let primitiveUses = view.components(separatedBy: ".modifier(SidebarGlassSurface(").count - 1
        try expect(primitiveUses >= 3,
                   "New Sheet, sheet rows and folder tabs share the primitive (got \(primitiveUses))",
                   "sidebar view")
        try expect(view.contains("struct SidebarGlassSurface: ViewModifier"),
                   "the shared primitive exists", "sidebar view")
        try expect(view.contains(".modifier(SidebarGlassSurface(role: .selected, shape: sidebarButtonShape))"),
                   "New Sheet uses the shared primitive (no separate tint path)", "sidebar view")
        // Radii are passed in, never re-literalized inside the primitive.
        try expect(view.contains("cornerRadius: 10, style: .continuous")
                   && view.contains("cornerRadius: 11, style: .continuous")
                   && view.contains("cornerRadius: 7, style: .continuous"),
                   "action 10 / row 11 / tab 7 shapes preserved", "sidebar view")
        // Live appearance: the environment drives the resolution.
        try expect(view.contains("@Environment(\\.colorScheme)"),
                   "the surface resolves the appearance per render", "sidebar view")
        try expect(view.contains("Design.sidebarWash(role, isDark: isDark)"),
                   "the wash is resolved from the live color scheme", "sidebar view")
        // No static dynamic SwiftUI color bridge for the sidebar wash.
        try expect(design.contains("sidebarGlassTint") == false
                   && design.contains("sidebarDropTint") == false
                   && design.contains("Color(nsColor: sidebarGlassNSColor") == false,
                   "no static dynamic-NSColor wash bridge remains", "design")
        try expect(design.contains("static func sidebarWash(_ role: SidebarGlassTone.Role, isDark: Bool) -> Color"),
                   "one centralized pure tone -> Color conversion", "design")
    }
]

private func glassToneRepoFile(_ rel: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
    let url = root.appendingPathComponent(rel).standardizedFileURL
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    return try? String(contentsOf: url, encoding: .utf8)
}
