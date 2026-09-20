import AppKit
import Foundation
import NumlexCore

/// r37: the pure source-answer hover outline geometry
/// (`AnswerBaseline.hoverOutline`) — the stroke drawn around the SOURCE
/// answer of a hovered token. The app-side hit-testing/bridge is UI
/// state (not exercised here, per the no-inflation rule); the baseline
/// math it feeds is the testable core.
/// Reads an app-target source file (the design token and the outline view
/// live in `NumlexApp`, which the portable runner cannot import).
private func r37Source(_ relative: String) throws -> String {
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for _ in 0..<6 {
        let candidate = url.appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return try String(contentsOf: candidate, encoding: .utf8)
        }
        url.deleteLastPathComponent()
    }
    throw CaseFailure(message: "source not found: \(relative)", location: "R37")
}

public let r37Cases: [EngineCase] = [
    EngineCase("r37-hover-outline-ink-centerline") {
        // Fixed 28 pt row, natural glyph box 16.79, cap 11.42:
        // center = baseline − cap/2 (the shared caret/gutter ink rule),
        // height = one natural line box.
        let g = AnswerBaseline.hoverOutline(
            baseline: 28, rowHeight: 28, naturalHeight: 16.79, capHeight: 11.42)
        try expectClose(g.centerY, 28 - 11.42 / 2, 0.001,
                        "center is the answer's ink centerline")
        try expectEqual(g.centerY, CaretGeometry.inkCenter(baseline: 28, capHeight: 11.42),
                        "identical to the caret/gutter ink centerline")
        try expectEqual(g.height, 16.79, "one natural line box for a normal row")
    },
    EngineCase("r37-hover-outline-wrapped-row-one-line-height") {
        // A wrapped source block (60 pt tall) keeps a single-line-height
        // outline aligned to the centered answer — never a giant block.
        let g = AnswerBaseline.hoverOutline(
            baseline: 55, rowHeight: 60, naturalHeight: 24, capHeight: 15)
        try expectEqual(g.height, 24, "wrapped block keeps the single-line outline")
        try expectClose(g.centerY, 55 - 7.5, 0.001,
                        "center follows the measured answer baseline")
    },
    EngineCase("r37-hover-outline-clamped-to-row") {
        // A stretched/short row never yields an outline taller than it.
        let g = AnswerBaseline.hoverOutline(
            baseline: 10, rowHeight: 12, naturalHeight: 24, capHeight: 10)
        try expectEqual(g.height, 12, "height clamped to the row")
    },
    EngineCase("r37-hover-outline-degenerate-inputs") {
        let g = AnswerBaseline.hoverOutline(
            baseline: 0, rowHeight: 0, naturalHeight: 0, capHeight: 0)
        try expectEqual(g.height, 1, "degenerate height clamped to 1 pt")
        try expectEqual(g.centerY, 0, "center stays on the baseline")
    },
    EngineCase("r37-hover-outline-settings-font-sizes") {
        // The real 18/20/30 pt system faces (dynamic metrics, no
        // hardcoded constants): the outline is one line box, centered
        // on the row's ink centerline, at every settings size.
        for size in [18.0, 20.0, 30.0] {
            let f = NSFont.systemFont(ofSize: size)
            let natural = f.ascender - f.descender + f.leading
            let row = (size * 1.6).rounded()
            let baseline = AnswerBaseline.baseline(
                rowTop: 0, rowHeight: row, fragmentCount: 1,
                ascender: f.ascender, naturalHeight: natural, capHeight: f.capHeight)
            let g = AnswerBaseline.hoverOutline(
                baseline: baseline, rowHeight: row,
                naturalHeight: natural, capHeight: f.capHeight)
            try expectClose(g.centerY, baseline - f.capHeight / 2, 0.001,
                            "center = baseline − cap/2 at \(size) pt")
            try expectClose(g.height, min(natural, row), 0.001,
                            "height = min(natural line box, row) at \(size) pt")
            try expect(g.centerY - g.height / 2 > 0,
                       "outline top stays inside the row at \(size) pt")
            // The SAME centering rule the editor's token capsule uses
            // (ink centerline + natural line box) can descend ≤1 pt
            // past the row bottom (the cap center sits above the box
            // center) — parity with the capsule, not a defect.
            try expect(g.centerY + g.height / 2 <= row + 1.0,
                       "outline bottom stays on the row at \(size) pt")
        }
    },

    EngineCase("r37-hover-outline-restrained-continuous-corners") {
        // The r37 source-answer outline is a restrained rounded rectangle,
        // not a capsule: its continuous corner radius is 6 pt while every
        // other property of the outline stays exactly as tuned (the source
        // contract exists because the app-only token cannot be imported by
        // the portable runner).
        let design = try r37Source("Sources/NumlexApp/Design.swift")
        try expect(design.contains("static let answerHoverCornerRadius: CGFloat = 6"),
                   "the continuous corner radius is 6 pt")
        try expect(!design.contains("answerHoverCornerRadius: CGFloat = 10"),
                   "no stale 10 pt radius definition remains")
        try expect(design.contains("static let answerHoverLineWidth: CGFloat = 3"),
                   "the 3 pt stroke is unchanged")
        try expect(design.contains("static let answerHoverEdgeInset: CGFloat = 2"),
                   "the 2 pt horizontal edge inset is unchanged")
        // The prose wraps across comment lines, so compare it with the
        // doc-comment markers and line breaks collapsed.
        let prose = design
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("///") ? String($0.dropFirst(3)) : $0 }
            .joined(separator: " ")
            .replacingOccurrences(of: "  ", with: " ")
        try expect(prose.contains("reads as a rounded rectangle around the answer"),
                   "documented as a restrained rounded rectangle")
        try expect(prose.contains("never as a pill/capsule"),
                   "documented as explicitly not a capsule")
        // The outline view consumes the centralized token in a continuous,
        // stroke-only shape — never a Capsule, never a fill.
        let view = try r37Source("Sources/NumlexApp/Views/AnswerColumnView.swift")
        let outline = (try? String(view[view.range(of: "private struct AnswerHoverOutline")!.lowerBound...]
            .prefix(while: { _ in true }))) ?? ""
        let slice = String(outline.prefix(700))
        try expect(slice.contains("RoundedRectangle("), "one rounded-rectangle shape")
        try expect(slice.contains("cornerRadius: Design.answerHoverCornerRadius,"),
                   "the shape uses the centralized radius token")
        try expect(slice.contains("style: .continuous"), "continuous corners")
        try expect(slice.contains("Color(nsColor: Design.caretColor)"), "caret/reference blue")
        try expect(slice.contains("lineWidth: Design.answerHoverLineWidth"),
                   "the shared 3 pt stroke width")
        try expect(slice.contains(".stroke("), "STROKE only")
        try expect(!slice.contains(".fill("), "no fill")
        try expect(!slice.contains("Capsule"), "never a capsule")
        try expect(!slice.contains("scaleEffect"), "never scaled")
        // Near-full-width, measured geometry, and presentation-only.
        try expect(slice.contains("width: width - Design.answerHoverEdgeInset * 2"),
                   "the actual width minus the fixed edge inset")
        try expect(slice.contains("height: height"), "the measured one-line height")
        try expect(slice.contains(".position(x: width / 2, y: centerY)"),
                   "centered on the measured baseline geometry")
        try expect(slice.contains(".allowsHitTesting(false)"),
                   "the overlay never intercepts input")
        // The geometry the outline is fed is still the pure, tested helper.
        let g = AnswerBaseline.hoverOutline(
            baseline: 28, rowHeight: 28, naturalHeight: 16.79, capHeight: 11.42)
        try expectEqual(g.height, 16.79, "the one-line height rule is unchanged")
        try expectClose(g.centerY, 28 - 11.42 / 2, 0.001, "ink centerline unchanged")
    },
]
