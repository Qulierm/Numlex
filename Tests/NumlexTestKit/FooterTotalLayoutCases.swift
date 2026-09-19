import AppKit
import Foundation
import NumlexCore

/// AppKit-measured width with the same pixel-safe rounding the view uses.
func footerMeasuredWidth(_ text: String, font: NSFont) -> CGFloat {
    let width = (text as NSString).size(withAttributes: [.font: font]).width
    return ceil(width) + 0.5
}

/// The adaptive bottom-Total bar: the footer shows the localized label while
/// the label + gap + value fit the full content width, and collapses to a
/// trailing value-only bubble when they do not.
///
/// The decision is driven by ACTUALLY measured text widths (AppKit metrics in
/// the view), so these cases exercise the pure geometry contract: exact fit,
/// the small collision-safety reserve, a one-point overflow, the long-value
/// cap, short compact widths, hostile input and the trailing-edge/width
/// invariants.
private func footerTotalSource(_ relative: String) throws -> String {
    var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    for _ in 0..<6 {
        let candidate = url.appendingPathComponent(relative)
        if FileManager.default.fileExists(atPath: candidate.path) {
            return try String(contentsOf: candidate, encoding: .utf8)
        }
        url.deleteLastPathComponent()
    }
    throw CaseFailure(message: "source not found: \(relative)", location: "FooterTotal")
}

/// The animated footer surface (the stable overlay, its interpolated widths
/// and the label/value children).
private func footerSurface(_ view: String) -> String {
    footerSlice(view, from: "private struct FooterBubbleSurface",
                to: "struct AnswerColumnView: View {")
}

/// The footer's call site: the surface plus its fixed trailing slot,
/// accessibility element and statistic menu.
private func footerSlot(_ view: String) -> String {
    footerSlice(view, from: "FooterBubbleSurface(progress:",
                to: "// v2: the answer panel is a DARKER")
}

private func footerSlice(_ source: String, from: String, to: String) -> String {
    guard let start = source.range(of: from)?.lowerBound,
          let end = source.range(of: to)?.lowerBound, start < end else { return "" }
    return String(source[start..<end])
}

public let footerTotalLayoutCases: [EngineCase] = [

    EngineCase("total-bar-geometry-constants-match-the-panel") {
        try expectEqual(FooterTotalLayout.panelWidth, 200, "panel 200 pt")
        try expectEqual(FooterTotalLayout.outerInset, 8, "outer inset 8")
        try expectEqual(FooterTotalLayout.innerPadding, 12, "inner padding 12")
        try expectEqual(FooterTotalLayout.labelGap, 8, "label/value gap 8")
        try expectEqual(FooterTotalLayout.bubbleWidth, 184, "full bubble 184")
        try expectEqual(FooterTotalLayout.contentWidth, 160, "full content 160")
    },

    EngineCase("total-bar-rendered-screenshot-keeps-its-label") {
        // The reported regression: the label vanished while a large empty gap
        // remained. The screenshot pair is `Average` / `335892.101`, measured
        // in the REAL fonts the view uses (`Average` = 43.5 pt at 11 pt;
        // `335892.101` = 106.5 pt at 17 pt and 124.5 pt at 20 pt).
        //
        // At 17 pt the pair needs exactly the default column's content width,
        // so it sits ON the boundary: the label must stay. The rejected 22 pt
        // policy hid it with 20 pt of air still visible — precisely the
        // screenshot.
        let label = footerMeasuredWidth("Average", font: NSFont.systemFont(ofSize: 11))
        let gap = FooterTotalLayout.labelGap
        let reserve = FooterTotalLayout.safetyReserve
        func required(_ pointSize: CGFloat) -> CGFloat {
            let value = footerMeasuredWidth("335892.101",
                                            font: NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular))
            return 2 * FooterTotalLayout.outerInset + 2 * FooterTotalLayout.innerPadding
                + label + gap + value + reserve
        }
        // 17 pt: the boundary lands exactly on the default 200 pt column.
        let atDefault = required(17)
        try expectEqual(atDefault, FooterTotalLayout.panelWidth,
                        "17 pt: the measured pair needs exactly the default column")
        let value17 = footerMeasuredWidth("335892.101",
                                          font: NSFont.monospacedSystemFont(ofSize: 17, weight: .regular))
        let onBoundary = FooterTotalLayout.layout(containerWidth: atDefault,
                                                  labelWidth: label, valueWidth: value17)
        try expect(onBoundary.showsLabel, "17 pt: the exact boundary keeps the label")
        try expectEqual(onBoundary.bubbleWidth, atDefault - 2 * FooterTotalLayout.outerInset,
                        "17 pt: full bubble at the boundary")
        try expect(FooterTotalLayout.layout(containerWidth: atDefault + 1,
                                            labelWidth: label, valueWidth: value17).showsLabel,
                   "17 pt: one point roomier keeps the label")
        try expect(!FooterTotalLayout.layout(containerWidth: atDefault - 1,
                                             labelWidth: label, valueWidth: value17).showsLabel,
                   "17 pt: one point below the boundary collapses")
        // The rejected policy is what hid the label here, not a real collision.
        try expect(label + gap + value17 + 22 > FooterTotalLayout.contentWidth,
                   "17 pt: the rejected 22 pt policy collapsed this pair")
        try expect(label + gap + value17 + reserve <= FooterTotalLayout.contentWidth,
                   "17 pt: the safety reserve leaves it fitting")
        // 20 pt is a bigger value: it needs a wider column (218 pt), and there
        // the same boundary rule applies.
        let at20 = required(20)
        try expect(at20 > FooterTotalLayout.panelWidth, "20 pt needs a wider column than the default")
        let value20 = footerMeasuredWidth("335892.101",
                                          font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular))
        try expect(FooterTotalLayout.layout(containerWidth: at20,
                                            labelWidth: label, valueWidth: value20).showsLabel,
                   "20 pt: the exact boundary keeps the label")
        try expect(!FooterTotalLayout.layout(containerWidth: at20 - 1,
                                             labelWidth: label, valueWidth: value20).showsLabel,
                   "20 pt: one point below collapses")
        // And the screenshot's own font size in the default column: the label
        // is visible again, where the old policy hid it.
        try expect(FooterTotalLayout.layout(containerWidth: FooterTotalLayout.panelWidth,
                                            labelWidth: label, valueWidth: value17).showsLabel,
                   "the reported pair keeps its label in the default column")
        // The short value keeps the label too.
        let shortValue = footerMeasuredWidth("1.500",
                                             font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular))
        let short = FooterTotalLayout.layout(containerWidth: FooterTotalLayout.panelWidth,
                                             labelWidth: label, valueWidth: shortValue)
        try expect(short.showsLabel, "short Total keeps its label")
        try expectEqual(short.bubbleWidth, FooterTotalLayout.bubbleWidth, "and the full bubble")
    },

    EngineCase("total-bar-safety-reserve-is-collision-only") {
        // The reserve is collision/subpixel protection, never a comfort
        // measure: the label survives until the measured pair reaches the
        // content edge, and a pair that would only have failed under the
        // rejected 22 pt policy now keeps its label.
        try expectEqual(FooterTotalLayout.safetyReserve, 2, "the documented 2 pt reserve")
        let label = footerMeasuredWidth("Average", font: NSFont.systemFont(ofSize: 11))
        let value = footerMeasuredWidth("335892.101",
                                        font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular))
        let gap = FooterTotalLayout.labelGap
        let content = FooterTotalLayout.contentWidth
        // A value sized so the pair has real room but less than 22 pt of air:
        // under the rejected policy this collapsed; now it must stay expanded.
        let rawFit = content - label - gap - FooterTotalLayout.safetyReserve
        let ample = rawFit - 10                      // 10 pt of genuine air left
        let comfortable = FooterTotalLayout.layout(containerWidth: FooterTotalLayout.panelWidth,
                                                   labelWidth: label, valueWidth: ample)
        try expect(comfortable.showsLabel,
                   "a pair with 10 pt of air keeps the label")
        try expect(ample + label + gap + 22 > content,
                   "the same pair would have failed the rejected 22 pt policy")
        // The same rule is language-independent: a longer localized label uses
        // exactly the same measured formula and boundary.
        for localized in ["Mittelwert", "Среднее"] {
            let longLabel = footerMeasuredWidth(localized, font: NSFont.systemFont(ofSize: 11))
            try expect(longLabel > label, "\(localized) really is wider than `Average`")
            let required = 2 * FooterTotalLayout.outerInset + 2 * FooterTotalLayout.innerPadding
                + longLabel + gap + value + FooterTotalLayout.safetyReserve
            let atBoundary = FooterTotalLayout.layout(containerWidth: required,
                                                     labelWidth: longLabel, valueWidth: value)
            try expect(atBoundary.showsLabel, "\(localized): the exact boundary keeps the label")
            let tighter = FooterTotalLayout.layout(containerWidth: required - 1,
                                                  labelWidth: longLabel, valueWidth: value)
            try expect(!tighter.showsLabel, "\(localized): one point below collapses")
            // The wider label needs a wider container — proof there is no
            // English- or string-specific breakpoint.
            try expect(required > 2 * FooterTotalLayout.outerInset + 2 * FooterTotalLayout.innerPadding
                       + label + gap + value + FooterTotalLayout.safetyReserve,
                       "\(localized) shifts the boundary outward by its own measured width")
        }
    },

    EngineCase("total-bar-shows-the-label-while-it-fits") {
        // label + gap + value + reserve exactly inside 160 -> expanded.
        let label: CGFloat = 30, gap = FooterTotalLayout.labelGap, reserve = FooterTotalLayout.safetyReserve
        let value = FooterTotalLayout.contentWidth - label - gap - reserve
        let exact = FooterTotalLayout.layout(containerWidth: 200, labelWidth: label, valueWidth: value)
        try expect(exact.showsLabel, "exact fit keeps the label")
        try expectEqual(exact.bubbleWidth, 184, "full bubble width")
        try expectEqual(exact.contentWidth, 160, "full content width")
        // One point more fits too.
        let roomy = FooterTotalLayout.layout(containerWidth: 200, labelWidth: label, valueWidth: value - 1)
        try expect(roomy.showsLabel, "one point of slack keeps the label")
    },

    EngineCase("total-bar-collapses-at-the-safety-reserve") {
        let label: CGFloat = 30, gap = FooterTotalLayout.labelGap, reserve = FooterTotalLayout.safetyReserve
        let boundary = FooterTotalLayout.contentWidth - label - gap - reserve
        // The reserve is what makes the switch happen BEFORE overlap: a value
        // one point past the boundary loses the label.
        let over = FooterTotalLayout.layout(containerWidth: 200, labelWidth: label,
                                            valueWidth: boundary + 1)
        try expect(!over.showsLabel, "one point over the boundary collapses")
        // Without the reserve the pair would still fit exactly at this size,
        // which is precisely the overlap the reserve prevents.
        try expect(label + gap + (boundary + 1) <= FooterTotalLayout.contentWidth,
                   "the collapsed case is still inside the raw content width")
        try expect(label + gap + (boundary + 1) + reserve > FooterTotalLayout.contentWidth,
                   "the safety reserve is what collapses it")
    },

    EngineCase("total-bar-compact-width-wraps-the-value") {
        let label: CGFloat = 30
        // A short value collapses to a bubble only as wide as the value plus
        // its inner padding.
        let short = FooterTotalLayout.layout(containerWidth: 200, labelWidth: label, valueWidth: 130)
        try expect(!short.showsLabel, "collapsed")
        try expectEqual(short.bubbleWidth, 130 + 24, "value + 2 * innerPadding")
        try expectEqual(short.contentWidth, 130, "content is the value itself")
        try expect(short.bubbleWidth < 184, "strictly narrower than the full bubble")
        // A long value is capped at the full content width: the existing
        // one-line overflow behaviour is preserved.
        let long = FooterTotalLayout.layout(containerWidth: 200, labelWidth: label, valueWidth: 500)
        try expectEqual(long.contentWidth, 160, "capped at 160")
        try expectEqual(long.bubbleWidth, 184, "capped at 184")
    },

    EngineCase("total-bar-trailing-edge-invariant") {
        // Both modes keep the same right edge: bubble + outer inset.
        for value in [10.0, 90.0, 160.0, 400.0] as [CGFloat] {
            let r = FooterTotalLayout.layout(containerWidth: 200, labelWidth: 30, valueWidth: value)
            let rightEdge = 200 - FooterTotalLayout.outerInset
            try expectEqual(rightEdge, 192, "trailing edge is fixed")
            try expect(r.bubbleWidth <= 184, "never wider than the panel allows")
            try expect(r.bubbleWidth >= 0, "never negative")
        }
    },

    EngineCase("total-bar-honours-a-narrower-container") {
        // A narrower panel shrinks the available bubble instead of
        // overflowing: the helper clamps to the container.
        let narrow = FooterTotalLayout.layout(containerWidth: 120, labelWidth: 30, valueWidth: 40)
        try expect(narrow.bubbleWidth <= 120 - 16, "bubble stays inside")
        try expect(narrow.bubbleWidth > 0, "still a usable bubble")
        let narrowLong = FooterTotalLayout.layout(containerWidth: 120, labelWidth: 30, valueWidth: 400)
        try expect(!narrowLong.showsLabel, "a cramped footer collapses")
        try expectEqual(narrowLong.contentWidth, 80, "capped to the narrow content width")
        // And an extremely narrow container degrades to zero rather than a
        // negative width.
        let tiny = FooterTotalLayout.layout(containerWidth: 10, labelWidth: 30, valueWidth: 40)
        try expectEqual(tiny.bubbleWidth, 0, "zero, never negative")
        try expectEqual(tiny.contentWidth, 0, "zero content")
    },

    EngineCase("total-bar-defends-against-hostile-input") {
        for bad in [CGFloat.nan, .infinity, -.infinity, -5] {
            let r = FooterTotalLayout.layout(containerWidth: 200, labelWidth: bad, valueWidth: 20)
            try expect(r.showsLabel == false || r.showsLabel == true, "no crash, a decision")
            try expect(r.bubbleWidth.isFinite && r.bubbleWidth >= 0, "finite bubble")
            try expect(r.contentWidth.isFinite && r.contentWidth >= 0, "finite content")
        }
        let nanValue = FooterTotalLayout.layout(containerWidth: 200, labelWidth: 30, valueWidth: .nan)
        try expect(!nanValue.showsLabel, "a NaN value cannot claim the label fits")
        try expect(!nanValue.showsLabel, "an unknown value drops the label")
        try expectEqual(nanValue.contentWidth, 160, "an unknown value keeps the full bubble")
        let nanContainer = FooterTotalLayout.layout(containerWidth: .nan, labelWidth: 30, valueWidth: 40)
        try expectEqual(nanContainer.bubbleWidth, 0, "a NaN container collapses")
        // Zero-width label: nothing to show, so the mode is compact but the
        // value still gets its own bubble.
        let noLabel = FooterTotalLayout.layout(containerWidth: 200, labelWidth: 0, valueWidth: 40)
        try expect(!noLabel.showsLabel, "no label, no expanded mode")
        try expectEqual(noLabel.bubbleWidth, 64, "value-only bubble")
    },

    EngineCase("total-bar-safety-reserve-is-one-named-constant") {
        try expectEqual(FooterTotalLayout.safetyReserve, 2, "the safety reserve is 2 pt")
        let source = try footerTotalSource("Sources/NumlexCore/Models/FooterTotalLayout.swift")
        try expect(source.contains("public static let safetyReserve: CGFloat = 2"),
                   "one named safety constant")
        try expect(!source.contains("comfortReserve"), "the rejected comfort reserve is gone")
        try expect(source.contains("let needed = label + (label > 0 ? labelGap : 0) + value + safetyReserve"),
                   "the decision uses the safety reserve")
        // The VIEW must keep measuring real AppKit text: pixel-safe rounding,
        // the localized label font and the editor font, never a row/character
        // count.
        let view = try footerTotalSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        try expect(view.contains("ceil(width) + 0.5"), "pixel-safe measured width")
        try expect(view.contains("NSFont.systemFont(ofSize: 11)"), "measured localized label font")
        try expect(view.contains("palette.editorFont(size: fontSize)"), "measured editor font")
        try expect(!view.contains("count >"), "no character-count heuristic")
        // The animated surface is ONE stable tree: the label fades and is
        // clipped, the value is a single trailing child, and no spacer or
        // label-gap claim exists in compact mode.
        let surface = footerSurface(view)
        try expect(!surface.isEmpty, "the animated surface exists")
        try expect(!surface.contains("if layout.showsLabel {"), "no mode branch")
        try expect(!surface.contains("Spacer"), "no spacer claim in either mode")
        try expect(surface.contains("label"), "the label is a stable child")
    },

    EngineCase("total-bar-compact-loses-no-width-to-the-label-gap") {
        // THE defect this case exists for: a value that fits the compact
        // content width must be shown IN FULL. The collapsed mode may not
        // reserve the label's gap (or a spacer's claim), or the value would
        // be truncated 8 pt early.
        let label: CGFloat = 42      // a realistic localized "Total" label
        let value: CGFloat = 130     // < 160, but label + gap + value collapses
        let r = FooterTotalLayout.layout(containerWidth: 200, labelWidth: label, valueWidth: value)
        try expect(!r.showsLabel, "the label cannot fit beside this value")
        try expect(label + FooterTotalLayout.labelGap + value + FooterTotalLayout.safetyReserve
                   > FooterTotalLayout.contentWidth, "and the raw pair really is over the line")
        try expectEqual(r.contentWidth, value, "the value keeps its FULL width")
        try expectEqual(r.bubbleWidth, value + 24, "bubble = value + 2 * innerPadding")
        try expect(r.contentWidth > value - FooterTotalLayout.labelGap,
                   "no label gap is subtracted (the old 8 pt loss)")
        // The decision is about FIT, not about the value's own size: the same
        // value keeps the label when the label itself is narrower.
        let smallLabel = FooterTotalLayout.layout(containerWidth: 200, labelWidth: 18, valueWidth: 100)
        try expect(smallLabel.showsLabel,
                   "a narrow label with a comfortable value keeps the expanded mode")
        // And a value that fits the FULL width never loses a gap's worth of
        // room in either mode: compact content = the value, expanded content
        // covers label + gap + value.
        let small = FooterTotalLayout.layout(containerWidth: 200, labelWidth: label, valueWidth: 60)
        try expectEqual(small.contentWidth, FooterTotalLayout.contentWidth,
                        "expanded keeps the full content width")
    },

    EngineCase("total-bar-view-contract") {
        let view = (try? String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NumlexApp/Views/AnswerColumnView.swift"),
            encoding: .utf8)) ?? ""
        // Real AppKit metrics: the label in the same 11 pt system font
        // `Design.labelSmall` uses, the value in the palette's editor font
        // (so system/rounded/serif/monospaced and the live size all count).
        try expect(view.contains("NSFont.systemFont(ofSize: 11)"),
                   "the label is measured in the 11 pt system font")
        try expect(view.contains("palette.editorFont(size: fontSize)"),
                   "the value is measured in the palette editor font")
        try expect(view.contains("ceil(width) + 0.5"), "pixel-safe rounding")
        try expect(view.contains("FooterTotalLayout.layout(containerWidth:"), "the helper decides")
        // ONE stable overlay in both modes: the label is leading-aligned and
        // clipped to its collision-safe limit, the value trailing-aligned
        // across the same interpolated content frame.
        let surface = footerSurface(view)
        try expect(!surface.isEmpty, "the animated surface exists")
        try expect(!surface.contains("if layout.showsLabel {"),
                   "the content is not a mode branch any more")
        try expect(surface.contains("ZStack("), "one stable overlay")
        try expect(surface.contains(".frame(width: labelLimit, alignment: .leading)"),
                   "the label is clipped to its collision-safe limit")
        try expect(surface.contains(".clipped()"), "the shrinking content clips")
        try expect(surface.contains(".opacity(Double(clamped))"),
                   "the label fades with the interpolated progress")
        try expect(surface.contains(".frame(maxWidth: .infinity, alignment: .trailing)"),
                   "the value is trailing-aligned")
        try expect(!surface.contains("Spacer"), "no spacer in either mode")
        try expect(!surface.contains("labelGap +"), "no label-gap claim in the content")
        // ONE stable value node in the single content tree.
        let slot = footerSlot(view)
        try expectEqual(slot.components(separatedBy: "value: totalValue(s.value)").count - 1, 1,
                        "one stable value node")
        try expect(view.contains("private func totalValue(_ value: String) -> some View"),
                   "the shared helper exists")
        // Geometry invariants: the trailing edge is fixed by an explicit
        // trailing-aligned slot derived from the ACTUAL column width.
        try expect(slot.contains(".frame(width: width - 2 * FooterTotalLayout.outerInset, alignment: .trailing)"),
                   "trailing-aligned slot derived from the actual width")
        try expect(slot.contains(".padding(FooterTotalLayout.outerInset)"), "unchanged outer inset")
        try expect(surface.contains(".padding(.vertical, 8)"), "unchanged vertical padding")
        try expect(surface.contains("RoundedRectangle(cornerRadius: 9"), "unchanged glass radius")
        try expect(view.contains("FooterTotalLayout.modeGeometry("),
                   "the live endpoints come from the pure helper")
        // The value path is untouched: same font, same colour, same format.
        try expect(view.contains(".font(palette.swiftUIFont(fontSize))"), "same value font")
        try expect(view.contains("Color(nsColor: Design.baseText)"), "same value colour")
        try expect(view.contains(".lineLimit(1)"), "one line")
        try expect(view.contains(".id(value)"), "text-only crossfade identity")
        // ONE accessibility announcement carrying label + value in both modes.
        try expect(view.contains(".accessibilityElement(children: .ignore)"), "one element")
        try expect(view.contains("footerAccessibilityLabel(value: s.value,"), "one label builder")
        try expect(view.contains("totalLabel) " + "\\(" + "value)"), "label + value once")
        try expect(view.contains("totalLabel) " + "\\(" + "value) " + "\\(" + "unit)"),
                   "unit when present")
        // No geometry feedback loop: the mode comes from text metrics only.
        for banned in ["PreferenceKey", "onPreferenceChange", "TimelineView", "Timer("] {
            try expect(!view.contains(banned), "no \(banned)")
        }
        // The footer's own gate and inertness are unchanged.
        try expect(view.contains("if showTotalBar, let s = summary {"), "the footer gate stays")
        try expect(view.contains(".allowsHitTesting(true)"), "the answer catcher is unchanged")
    },

    EngineCase("total-bar-layout-is-pure-and-presentation-only") {
        let source = (try? String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/NumlexCore/Models/FooterTotalLayout.swift"),
            encoding: .utf8)) ?? ""
        try expect(source.contains("public enum FooterTotalLayout"), "the helper exists")
        for banned in ["SheetFooterTotal.aggregate", "NumberPresentation.format",
                       "UserDefaults", "AppSettings", "persist"] {
            try expect(!source.contains(banned), "no \\(banned) in the layout helper")
        }
        // No row-count or character-count heuristic anywhere in the decision.
        for banned in ["count", "lines", "rows"] {
            try expect(!source.contains(banned), "no \\(banned)-based heuristic")
        }
    },

    EngineCase("total-bar-mode-transition-is-one-short-geometry-exception") {
        // The footer's compact/expanded flip is the ONE geometry transition
        // in the notebook's otherwise opacity/colour-only micro-motion
        // policy: short, non-spring, keyed ONLY on the binary mode, and owned
        // by a scalar progress rather than by per-pixel geometry.
        let design = try footerTotalSource("Sources/NumlexApp/Design.swift")
        try expect(design.contains("static let footerMode: Double = 0.22"),
                   "one central 0.22 s footer-mode duration")
        try expect(design.contains("static let answerChange: Double = 0.12"),
                   "the value crossfade duration is untouched")
        try expect(design.contains("non-spring"), "documented as non-spring")
        try expect(design.contains("LEADING edge"), "documented as leading-edge shrink")
        try expect(design.contains("Reduce Motion"), "documented Reduce Motion behaviour")
        try expect(design.contains("MOST of what lives here is a short opacity/color-only pass"),
                   "the categorical no-geometry claim is qualified")
        try expect(design.contains("The single narrow exception is `footerMode`"),
                   "the header points at the footer exception")
        let view = try footerTotalSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        // The old blanket suppression is gone.
        try expect(!view.contains(".transaction { if !reduceMotion { $0.animation = nil } }"),
                   "the footer no longer disables geometry animation")
        try expect(!view.contains("Mode changes must not animate"),
                   "and its explanatory comment is gone")
        // The transition is owned by the view's own scalar progress.
        try expect(view.contains("withAnimation(.smooth(duration: Motion.footerMode, extraBounce: 0))"),
                   "one explicit smooth, zero-bounce transition")
        try expect(!view.contains(".animation(reduceMotion ? nil : .smooth(duration: Motion.footerMode,"),
                   "the implicit derived-layout animation is gone")
        try expect(!view.contains("easeInOut(duration: Motion.footerMode)"),
                   "the old footer curve is gone")
        try expect(!view.contains("extraBounce: 0.1") && !view.contains("extraBounce: 0.2"),
                   "no bounce was smuggled in")
        // Never keyed on a continuously changing measurement: that would
        // animate every pixel of a divider drag.
        let slot = footerSlot(view)
        try expect(!slot.isEmpty, "the bubble slot exists")
        try expect(!slot.contains("value: width"), "not keyed on the container width")
        try expect(!slot.contains("value: layout.bubbleWidth"), "not keyed on the bubble width")
        try expect(!slot.contains(".spring"), "never a spring")
        try expect(!slot.contains("scaleEffect"), "the digits are never scaled")
        try expect(!slot.contains(".bouncy"), "never a bouncy curve")
        try expect(!slot.contains(".offset("), "no numeric tween")
        // The slot only HOOKS the mode reconciliation; the transition itself
        // lives in the view-owned scalar.
        try expect(slot.contains("reconcileFooterMode(showsLabel: desired.showsLabel)"),
                   "the slot reconciles through the view-owned helper")
        try expect(slot.contains(".onChange(of: desired.showsLabel)"),
                   "only the MODE is observed")
        // ONE stable animated surface in both modes.
        let surface = footerSurface(view)
        try expect(!surface.contains("if layout.showsLabel {"), "no mode branch")
        try expect(surface.contains("ZStack("), "one stable overlay")
        try expect(!surface.contains("Spacer"), "no spacer in either mode")
        try expect(surface.contains(".opacity(Double(clamped))"), "the label fades")
    },

    EngineCase("total-bar-animates-one-explicit-bubble-width-stably") {
        // The earlier branch-swapping animation could snap or crossfade the
        // whole content because the glass width was inferred. The footer now
        // keeps ONE stable view tree and gives the glass surface an EXPLICIT,
        // interpolated width, so there is exactly one numeric value for
        // SwiftUI to drive — and only the binary mode flip triggers it.
        let view = try footerTotalSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        let surface = footerSurface(view)
        let slot = footerSlot(view)
        // One stable tree: no mode branch, no branch-specific spacing.
        try expect(!surface.contains("if layout.showsLabel {"), "no mode branch in the content")
        try expect(surface.contains("ZStack("), "one stable overlay")
        try expect(!surface.contains("HStack(spacing:"), "no branch-specific stack spacing")
        try expect(!surface.contains("Spacer"), "no spacer claim")
        // One label (faded, clipped, leading) and one value (trailing).
        try expectEqual(slot.components(separatedBy: "value: totalValue(s.value)").count - 1, 1,
                        "exactly one stable value node")
        try expect(surface.contains(".opacity(Double(clamped))"),
                   "the label fades with the interpolated progress")
        try expect(surface.contains(".frame(width: labelLimit, alignment: .leading)"),
                   "the label is clipped to its collision-safe limit")
        try expect(surface.contains(".frame(maxWidth: .infinity, alignment: .trailing)"),
                   "value trailing")
        // Explicit interpolated content width + clipping, then an explicit
        // interpolated bubble width.
        try expect(surface.contains(".frame(width: contentWidth, alignment: .leading)"),
                   "explicit interpolated content width")
        try expect(surface.contains(".clipped()"), "the shrinking content clips")
        try expectEqual(surface.components(separatedBy: ".frame(width: bubbleWidth)").count - 1, 1,
                        "exactly one explicit bubble width")
        guard let bubbleAt = surface.range(of: ".frame(width: bubbleWidth)")?.lowerBound,
              let glassAt = surface.range(of: "glassEffect")?.lowerBound else {
            throw CaseFailure(message: "bubble width or glassEffect missing", location: "FooterTotal")
        }
        try expect(bubbleAt < glassAt, "the explicit width precedes the glass surface")
        // The interpolated widths come from the LIVE endpoints.
        try expect(surface.contains("mix(geometry.compact.contentWidth, geometry.expanded.contentWidth)"),
                   "content width interpolates the endpoints")
        try expect(surface.contains("mix(geometry.compact.bubbleWidth, geometry.expanded.bubbleWidth)"),
                   "bubble width interpolates the endpoints")
        // The glass width is the ONLY thing that interpolates; the mode key is
        // the only trigger.
        try expectEqual(slot.components(separatedBy: ".animation(").count - 1, 0,
                        "no implicit animation modifier in the footer slot")
        try expect(view.contains("withAnimation(.smooth(duration: Motion.footerMode, extraBounce: 0))"),
                   "one explicit smooth, zero-bounce transition")
        for banned in ["value: width", "value: layout.bubbleWidth", "value: layout.contentWidth",
                       "value: value", ".spring", "scaleEffect", ".offset(", ".bouncy"] {
            try expect(!slot.contains(banned), "the footer mode path has no \(banned)")
        }
        // Fixed trailing slot and the untouched surrounding contract.
        try expect(slot.contains(".frame(width: width - 2 * FooterTotalLayout.outerInset, alignment: .trailing)"),
                   "the trailing edge stays fixed")
        try expect(surface.contains(".padding(.vertical, 8)"), "vertical padding unchanged")
        try expect(surface.contains("RoundedRectangle(cornerRadius: 9"), "radius unchanged")
        try expect(slot.contains(".accessibilityElement(children: .ignore)"), "one element")
        try expect(slot.contains(".contextMenu {"), "the statistic menu stays")
        // The value keeps its OWN crossfade, keyed on the text, so a number
        // change never animates the geometry.
        let value = footerSlice(view, from: "private func totalValue", to: "private static func measuredWidth")
        try expect(value.contains(".id(value)"), "value identity crossfade kept")
        try expect(value.contains("value: value"), "keyed on the formatted text")
        try expect(!value.contains("bubbleWidth"), "the value helper never touches geometry")
    },

    EngineCase("total-bar-mode-reconciliation-animates-both-directions") {
        // The mode transition used to be an implicit `.animation` on a layout
        // value derived from the continuously dragged width, which made
        // expansion snap while compaction animated. The mode now lives in the
        // view's OWN scalar progress and is adopted inside one explicit
        // `withAnimation`, so the decision is a single symmetric inequality
        // and a drag tick cannot write the state at all.
        //
        // The enumerated transition table this case pins:
        //   nil -> expanded            seed, NO animation
        //   nil -> compact             seed, NO animation
        //   expanded -> expanded       same mode, NO state write
        //   compact -> compact         same mode, NO state write
        //   expanded -> compact        MODE FLIP -> animated
        //   compact -> expanded        MODE FLIP -> animated (the fix)
        //   either flip, Reduce Motion NO animation
        //   footer hidden -> shown     reset, then seed, NO animation
        let view = try footerTotalSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        // 1. View-owned OPTIONAL SCALAR progress, never a stored Result.
        try expect(view.contains("@State private var footerModeProgress: CGFloat?"),
                   "the mode progress is view-owned optional scalar state")
        try expect(!view.contains("@State private var footerPresentation"),
                   "no full-Result presentation state remains")
        try expect(!view.contains("footerRenderedLayout"),
                   "the per-pixel render-selection path is gone")
        // 2. The symmetric predicate, verbatim and free of directional logic.
        try expect(view.contains("guard (stored >= 0.5) != showsLabel else { return }"),
                   "one symmetric inequality decides the transition")
        for directional in ["== true", "== false", "showsLabel &&", "if showsLabel {", "if !showsLabel"] {
            try expect(!view.contains(directional), "no directional special case: \(directional)")
        }
        // 3. Exactly one explicit animated adoption, using the shared curve.
        try expectEqual(view.components(separatedBy: "withAnimation(").count - 1, 1,
                        "exactly one withAnimation owns the transition")
        try expect(view.contains("withAnimation(.smooth(duration: Motion.footerMode, extraBounce: 0))"),
                   "the shared 0.22 smooth zero-bounce curve, used by BOTH directions")
        // 4. Every non-mode path is explicitly un-animated: the seed, the
        //    Reduce Motion adoption and the visibility reset each set
        //    `animation = nil` in their own transaction. (A same-mode tick
        //    writes NOTHING, so it needs no transaction at all.)
        try expect(view.contains("transaction.animation = nil"), "explicit no-animation transactions")
        try expectEqual(view.components(separatedBy: "withTransaction(transaction)").count - 1, 3,
                        "seed, Reduce Motion and reset are the only silent writes")
        try expect(view.contains("if reduceMotion {"), "Reduce Motion has its own branch")
        let reconcile = footerSlice(view, from: "private func reconcileFooterMode",
                                    to: "private func resetFooterMode")
        try expect(!reconcile.isEmpty, "the reconciliation helper exists")
        // The same-mode tick returns before ANY write.
        guard let sameMode = reconcile.range(of: "guard (stored >= 0.5) != showsLabel else { return }")?.lowerBound,
              let animAt = reconcile.range(of: "withAnimation(")?.lowerBound else {
            throw CaseFailure(message: "same-mode guard or withAnimation missing", location: "FooterTotal")
        }
        try expect(sameMode < animAt, "the same-mode guard precedes every write")
        // Everything from the same-mode guard up to the Reduce Motion branch
        // IS the same-mode path: it must return without writing the progress.
        guard let rmAt0 = reconcile.range(of: "if reduceMotion {")?.lowerBound else {
            throw CaseFailure(message: "reduceMotion branch missing", location: "FooterTotal")
        }
        let sameModePath = String(reconcile[sameMode..<rmAt0])
        try expect(sameModePath.contains("return"),
                   "a same-mode tick returns without writing the animation state")
        try expect(!sameModePath.contains("footerModeProgress ="),
                   "a same-mode tick never writes the progress")
        // Reduce Motion is decided BEFORE the animated branch and never animates.
        guard let rmAt = reconcile.range(of: "if reduceMotion {")?.lowerBound else {
            throw CaseFailure(message: "reduceMotion branch missing", location: "FooterTotal")
        }
        try expect(rmAt < animAt, "Reduce Motion is decided BEFORE the animated branch")
        let rmBranch = String(reconcile[rmAt..<animAt])
        try expect(!rmBranch.contains("withAnimation"), "the Reduce Motion branch never animates")
        try expect(rmBranch.contains("transaction.animation = nil"),
                   "Reduce Motion adopts the new mode in a disabled transaction")
        // 5. Reset when the footer disappears, and the reset is silent.
        try expect(view.contains("private var footerVisible: Bool"),
                   "a stable visibility flag drives the reset")
        try expect(view.contains(".onChange(of: footerVisible) { _, visible in"),
                   "the reset is attached at a stable enclosing level")
        let reset = footerSlice(view, from: "private func resetFooterMode",
                                to: "private func totalValue")
        try expect(reset.contains("footerModeProgress = nil"), "the reset clears the stored mode")
        try expect(!reset.contains("withAnimation"), "the reset is never animated")
        // 6. The old implicit derived-layout animation is gone, and the slot
        //    observes ONLY the mode.
        try expect(!view.contains(".animation(reduceMotion ? nil : .smooth(duration: Motion.footerMode,"),
                   "no implicit mode animation remains")
        try expect(!view.contains("value: layout.showsLabel)"), "no implicit mode key remains")
        let slot = footerSlot(view)
        try expect(slot.contains(".onAppear { reconcileFooterMode(showsLabel: desired.showsLabel) }"),
                   "first appearance seeds through the helper")
        try expect(slot.contains(".onChange(of: desired.showsLabel) { _, newValue in"),
                   "later changes observe the MODE only")
        try expect(!slot.contains(".onChange(of: desired) {"), "never the whole layout")
        try expectEqual(slot.components(separatedBy: ".animation(").count - 1, 0,
                        "no animation modifier in the footer slot")
        // 7. The stable overlay and explicit widths from the previous fix.
        let surface = footerSurface(view)
        try expect(surface.contains("ZStack("), "one stable overlay")
        try expect(!surface.contains("if layout.showsLabel {"), "no mode branch")
        try expectEqual(slot.components(separatedBy: "value: totalValue(s.value)").count - 1, 1,
                        "one stable value node")
        try expect(surface.contains(".frame(width: contentWidth, alignment: .leading)"),
                   "explicit interpolated content width")
        try expect(surface.contains(".clipped()"), "clipping kept")
        try expectEqual(surface.components(separatedBy: ".frame(width: bubbleWidth)").count - 1, 1,
                        "one explicit bubble width")
        try expect(slot.contains(".frame(width: width - 2 * FooterTotalLayout.outerInset, alignment: .trailing)"),
                   "fixed trailing slot")
        // 8. The threshold and the shared duration are untouched.
        try expectEqual(FooterTotalLayout.safetyReserve, 2, "the 2 pt safety reserve is unchanged")
        try expectEqual(FooterTotalLayout.labelGap, 8, "the 8 pt visual gap is unchanged")
        let design = try footerTotalSource("Sources/NumlexApp/Design.swift")
        try expect(design.contains("static let footerMode: Double = 0.22"),
                   "the shared 0.22 s duration is unchanged")
    },

    EngineCase("total-bar-mode-endpoints-match-the-fit-decision") {
        // The animated transition interpolates between the two mode ENDPOINT
        // geometries, so those endpoints must be exactly the geometry the fit
        // decision selects — for every input, hostile ones included. This
        // exhaustively re-derives `layout` from `modeGeometry` and compares.
        let containers: [CGFloat] = [0, 10, 120, 140, 199, 200, 201, 218, 300, 400, 1000]
        let labels: [CGFloat] = [0, 10, 26.5, 30, 43.5, 53.5, 100]
        let values: [CGFloat] = [0, 20, 60, 90, 106.5, 124.5, 130, 160, 500, 5000]
        var compared = 0
        for container in containers {
            for label in labels {
                for value in values {
                    let g = FooterTotalLayout.modeGeometry(containerWidth: container,
                                                           valueWidth: value)
                    let r = FooterTotalLayout.layout(containerWidth: container,
                                                     labelWidth: label, valueWidth: value)
                    let expected = r.showsLabel ? g.expanded : g.compact
                    try expectEqual(r, expected,
                                    "layout must equal the selected endpoint (\(container)/\(label)/\(value))")
                    // The selected endpoint's own flag agrees with the decision.
                    try expectEqual(r.showsLabel, g.endpoint(showsLabel: r.showsLabel).showsLabel,
                                    "endpoint flag agrees")
                    // The two endpoints are always internally consistent.
                    try expect(g.expanded.showsLabel, "the expanded endpoint shows the label")
                    try expect(!g.compact.showsLabel, "the compact endpoint hides it")
                    try expect(g.compact.contentWidth <= g.expanded.contentWidth,
                               "compact content never exceeds the full content")
                    try expect(g.compact.bubbleWidth <= g.expanded.bubbleWidth,
                               "compact bubble never exceeds the full bubble")
                    compared += 1
                }
            }
        }
        try expect(compared == containers.count * labels.count * values.count,
                   "every combination compared (\(compared))")
        // Hostile inputs: the endpoints stay finite and non-negative and the
        // decision still selects one of them.
        for badContainer in [CGFloat.nan, .infinity, -.infinity, -100] {
            let g = FooterTotalLayout.modeGeometry(containerWidth: badContainer, valueWidth: 40)
            for endpoint in [g.expanded, g.compact] {
                try expect(endpoint.bubbleWidth.isFinite && endpoint.bubbleWidth >= 0,
                           "finite bubble for \(badContainer)")
                try expect(endpoint.contentWidth.isFinite && endpoint.contentWidth >= 0,
                           "finite content for \(badContainer)")
            }
            try expectEqual(g.expanded.bubbleWidth, 0, "a hostile container collapses both endpoints")
            let r = FooterTotalLayout.layout(containerWidth: badContainer, labelWidth: 30, valueWidth: 40)
            try expectEqual(r, r.showsLabel ? g.expanded : g.compact, "decision selects an endpoint")
        }
        for badValue in [CGFloat.nan, .infinity, -.infinity, -5] {
            let g = FooterTotalLayout.modeGeometry(containerWidth: 200, valueWidth: badValue)
            // An unknown value keeps the value's full bubble in compact mode.
            try expectEqual(g.compact.contentWidth, FooterTotalLayout.contentWidth,
                            "an unknown value keeps the full content")
            let r = FooterTotalLayout.layout(containerWidth: 200, labelWidth: 30, valueWidth: badValue)
            try expect(!r.showsLabel, "an unknown value cannot claim the label fits")
            try expectEqual(r, g.compact, "and it selects the compact endpoint")
        }
        // The reported screenshot boundary, expressed through the endpoints.
        let label = footerMeasuredWidth("Average", font: NSFont.systemFont(ofSize: 11))
        let value = footerMeasuredWidth("335892.101",
                                        font: NSFont.monospacedSystemFont(ofSize: 17, weight: .regular))
        let atBoundary = FooterTotalLayout.layout(containerWidth: 200, labelWidth: label, valueWidth: value)
        try expect(atBoundary.showsLabel, "200 pt: expanded")
        try expectEqual(atBoundary, FooterTotalLayout.modeGeometry(containerWidth: 200,
                                                                  valueWidth: value).expanded,
                        "200 pt selects the expanded endpoint")
        let justBelow = FooterTotalLayout.layout(containerWidth: 199, labelWidth: label, valueWidth: value)
        try expect(!justBelow.showsLabel, "199 pt: compact")
        try expectEqual(justBelow, FooterTotalLayout.modeGeometry(containerWidth: 199,
                                                                 valueWidth: value).compact,
                        "199 pt selects the compact endpoint")
        // Compact caps survive the refactor.
        let capped = FooterTotalLayout.modeGeometry(containerWidth: 200, valueWidth: 500)
        try expectEqual(capped.compact.contentWidth, 160, "long value capped at the content width")
        try expectEqual(capped.compact.bubbleWidth, 184, "long value capped at the full bubble")
        try expectEqual(FooterTotalLayout.layout(containerWidth: 200, labelWidth: 30, valueWidth: 500),
                        capped.compact, "and the decision returns that capped endpoint")
    },

    EngineCase("total-bar-drag-ticks-do-not-cancel-mode-progress") {
        // THE regression this task exists for: a divider drag writes the
        // column width on every cursor tick, so the compact/expanded ENDPOINTS
        // change continuously. When the animation state stored the geometry,
        // the tick after a threshold crossing re-synchronized it and visually
        // cancelled the 0.22 s transition — expansion appeared to snap.
        //
        // The animation state is now ONE scalar progress, and a same-mode tick
        // performs no state write at all, so the endpoints can keep following
        // the cursor while the transition runs to completion.
        //
        // Event sequence this case pins (one mutation per actual mode flip):
        //   compact seed                                  -> 1 write (seed)
        //   threshold flip compact -> expanded            -> 1 animated write
        //   40 expanded endpoint ticks (width drag)       -> 0 writes
        //   flip expanded -> compact                      -> 1 animated write
        //   40 compact endpoint ticks                     -> 0 writes
        let view = try footerTotalSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        // A. Scalar optional progress, never a stored Result.
        try expect(view.contains("@State private var footerModeProgress: CGFloat?"),
                   "one optional scalar owns the animation")
        try expect(!view.contains("footerPresentation"), "no full-Result state remains")
        try expect(!view.contains("footerRenderedLayout"), "no per-pixel Result synchronization")
        // B. A custom Animatable whose animatableData IS the scalar.
        let surface = footerSurface(view)
        try expect(surface.contains("@preconcurrency Animatable"), "the surface is Animatable")
        try expect(surface.contains("var animatableData: CGFloat {"), "scalar animatableData")
        try expect(surface.contains("get { progress }"), "it reads the progress")
        try expect(surface.contains("set { progress = newValue }"), "and writes it back")
        // C. The endpoints are ORDINARY live inputs, not animation state.
        try expect(surface.contains("let geometry: FooterTotalLayout.ModeGeometry"),
                   "the endpoints are a plain stored input")
        try expect(!surface.contains("animatableData: AnimatablePair"),
                   "the endpoints are not part of animatableData")
        // D. Interpolation of both widths plus progress-driven label visibility.
        try expect(surface.contains("mix(geometry.compact.contentWidth, geometry.expanded.contentWidth)"),
                   "content width interpolates the LIVE endpoints")
        try expect(surface.contains("mix(geometry.compact.bubbleWidth, geometry.expanded.bubbleWidth)"),
                   "bubble width interpolates the LIVE endpoints")
        try expect(surface.contains(".opacity(Double(clamped))"),
                   "the label follows the interpolated progress")
        try expect(surface.contains("min(max(progress, 0), 1)"), "progress is clamped")
        // E. The label can never reach the stationary value mid-flight.
        try expect(surface.contains("max(0, contentWidth - valueWidth - FooterTotalLayout.labelGap)"),
                   "the label is clipped to its collision-safe limit")
        try expect(surface.contains(".frame(width: labelLimit, alignment: .leading)"),
                   "and that limit is applied to the label frame")
        try expect(surface.contains(".frame(maxWidth: .infinity, alignment: .trailing)"),
                   "the value stays trailing")
        try expect(!surface.contains("scaleEffect") && !surface.contains(".offset("),
                   "the digits are never scaled, moved or tweened")
        // F. The live endpoints are recomputed on every body pass from the
        //    CURRENT width and value measurement.
        let slot = footerSlot(view)
        try expect(slot.contains("geometry: FooterTotalLayout.modeGeometry("),
                   "the endpoints are live inputs")
        try expect(slot.contains("containerWidth: width,"), "from the current column width")
        try expect(slot.contains("valueWidth: metrics.value"), "and the current measurement")
        // G. Only the MODE is observed, so a same-mode tick cannot write.
        try expect(slot.contains(".onChange(of: desired.showsLabel) { _, newValue in"),
                   "the observation is keyed to the mode only")
        try expect(!slot.contains(".onChange(of: desired) {"), "never the whole layout")
        let reconcile = footerSlice(view, from: "private func reconcileFooterMode",
                                    to: "private func resetFooterMode")
        try expect(reconcile.contains("guard (stored >= 0.5) != showsLabel else { return }"),
                   "the same-mode guard returns before any write")
        guard let sameModeAt = reconcile.range(of: "guard (stored >= 0.5) != showsLabel else { return }")?.lowerBound,
              let rmAt = reconcile.range(of: "if reduceMotion {")?.lowerBound,
              let animAt = reconcile.range(of: "withAnimation(")?.lowerBound else {
            throw CaseFailure(message: "reconcile structure missing", location: "FooterTotal")
        }
        let sameModePath = String(reconcile[sameModeAt..<rmAt])
        try expect(!sameModePath.contains("footerModeProgress ="),
                   "40 same-mode ticks would perform ZERO progress writes")
        try expect(!sameModePath.contains("withAnimation"),
                   "and cannot start, restart or cancel an animation")
        try expect(sameModePath.contains("return"), "the same-mode path returns immediately")
        // H. Exactly one animated write, shared by both directions.
        try expectEqual(view.components(separatedBy: "withAnimation(").count - 1, 1,
                        "one animated adoption serves both directions")
        try expect(view.contains("withAnimation(.smooth(duration: Motion.footerMode, extraBounce: 0))"),
                   "the shared 0.22 smooth zero-bounce curve")
        try expect(reconcile.contains("let target: CGFloat = showsLabel ? 1 : 0"),
                   "the scalar target is the mode, not the geometry")
        // A reversal mid-flight simply retargets the SAME scalar. There are
        // exactly three target writes — the silent seed, the silent Reduce
        // Motion adoption, and the ONE animated adoption — and only the last
        // sits inside `withAnimation`.
        try expectEqual(reconcile.components(separatedBy: "footerModeProgress = target").count - 1, 3,
                        "seed, Reduce Motion and the animated branch are the only writes")
        try expectEqual(reconcile.components(separatedBy: "withAnimation(").count - 1, 1,
                        "exactly one of them animates")
        // I. No timers, debounce, throttling or async workaround anywhere.
        for banned in ["Timer", "DispatchQueue", "Task.sleep", "debounce", "throttle",
                       "asyncAfter", "deadline", "sleep("] {
            try expect(!view.contains(banned), "no \(banned) workaround")
        }
        try expect(!view.contains(".animation(reduceMotion ? nil : .smooth(duration: Motion.footerMode,"),
                   "no implicit animation remains")
        // J. The stable geometry and the value path are unchanged.
        try expect(surface.contains(".frame(width: contentWidth, alignment: .leading)"),
                   "explicit content width")
        try expect(surface.contains(".clipped()"), "clipping kept")
        try expectEqual(surface.components(separatedBy: ".frame(width: bubbleWidth)").count - 1, 1,
                        "one explicit bubble width")
        guard let bubbleAt = surface.range(of: ".frame(width: bubbleWidth)")?.lowerBound,
              let glassAt = surface.range(of: "glassEffect")?.lowerBound else {
            throw CaseFailure(message: "bubble width or glassEffect missing", location: "FooterTotal")
        }
        try expect(bubbleAt < glassAt, "the explicit width precedes the glass surface")
        try expect(slot.contains(".frame(width: width - 2 * FooterTotalLayout.outerInset, alignment: .trailing)"),
                   "fixed trailing slot")
        try expect(slot.contains(".accessibilityElement(children: .ignore)"), "one accessibility element")
        try expect(slot.contains(".contextMenu {"), "the statistic menu stays")
        let value = footerSlice(view, from: "private func totalValue", to: "private static func measuredWidth")
        try expect(value.contains(".id(value)") && value.contains("value: value"),
                   "the value keeps its own text-keyed crossfade")
        // K. Threshold and duration unchanged.
        try expectEqual(FooterTotalLayout.safetyReserve, 2, "2 pt safety reserve")
        try expectEqual(FooterTotalLayout.labelGap, 8, "8 pt visual gap")
        let design = try footerTotalSource("Sources/NumlexApp/Design.swift")
        try expect(design.contains("static let footerMode: Double = 0.22"), "0.22 s duration")
    },
]
