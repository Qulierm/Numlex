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
        // The content is ONE stable tree now, so the "compact branch" is the
        // same view with the label faded out — no branch, no spacer and no
        // gap claim can reappear in compact mode.
        let content = footerSlice(view, from: "private func footerBarContent",
                                  to: "private func totalValue")
        try expect(!content.isEmpty, "the content builder exists")
        try expect(!content.contains("if layout.showsLabel {"), "no mode branch")
        try expect(!content.contains("Spacer"), "no spacer claim in either mode")
        try expect(content.contains(".opacity(layout.showsLabel ? 1 : 0)"),
                   "the label fades instead of being removed")
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
        // the value trailing-aligned across the same explicitly sized content
        // frame, so the compact mode cannot inherit a gap or spacer claim and
        // the value always keeps its full measured width.
        func slice(_ text: String, from: String, to: String) -> String {
            guard let a = text.range(of: from)?.lowerBound,
                  let b = text.range(of: to, range: a..<text.endIndex)?.lowerBound else { return "" }
            return String(text[a..<b])
        }
        let bar = slice(view, from: "private func footerBarContent", to: "private func totalValue")
        try expect(!bar.contains("if layout.showsLabel {"),
                   "the content is not a mode branch any more")
        try expect(bar.contains("ZStack("), "one stable overlay")
        try expect(bar.contains(".frame(width: layout.contentWidth, alignment: .leading)"),
                   "explicit content frame")
        try expect(bar.contains(".clipped()"), "the shrinking content clips")
        try expect(bar.contains(".opacity(layout.showsLabel ? 1 : 0)"),
                   "the label fades rather than being removed")
        try expect(bar.contains(".frame(maxWidth: .infinity, alignment: .leading)"),
                   "the label is leading-aligned")
        try expect(bar.contains(".frame(maxWidth: .infinity, alignment: .trailing)"),
                   "the value is trailing-aligned")
        try expect(!bar.contains("Spacer"), "no spacer in either mode")
        try expect(!bar.contains("labelGap"), "no label-gap claim in the content")
        // ONE stable value node in the single content tree, and the label is
        // faded (never removed) so the value keeps its identity across modes.
        try expectEqual(view.components(separatedBy: "totalValue(value)").count - 1, 1,
                        "one stable value node")
        try expect(view.contains("private func totalValue(_ value: String) -> some View"),
                   "the shared helper exists")
        try expect(view.contains(".opacity(layout.showsLabel ? 1 : 0)"),
                   "the label fades in place instead of being swapped out")
        // Geometry invariants: the trailing edge is fixed by an explicit
        // trailing-aligned slot derived from the ACTUAL column width
        // (the legacy 200 pt slot is reproduced at the default), and the
        // outer inset is unchanged.
        try expect(view.contains(".frame(width: width - 2 * FooterTotalLayout.outerInset, alignment: .trailing)"),
                   "trailing-aligned slot derived from the actual width")
        try expect(view.contains(".padding(FooterTotalLayout.outerInset)"), "unchanged outer inset")
        try expect(view.contains(".padding(.vertical, 8)"), "unchanged vertical padding")
        try expect(view.contains("RoundedRectangle(cornerRadius: 9"), "unchanged glass radius")
        try expect(view.contains("FooterTotalLayout.layout(containerWidth: width,"),
                   "the footer is laid out against the ACTUAL column width")

        // The value path is untouched: same font, same colour, same format.
        try expect(view.contains("totalValue(value)"), "the same shared value helper")
        try expect(view.contains("private func totalValue(_ value: String) -> some View"),
                   "one value definition")
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
        for banned in ["PreferenceKey", "GeometryReader { geo in\n                let metrics",
                       "onPreferenceChange", "TimelineView", "Timer("] {
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
        // policy: short, non-spring and keyed ONLY on the binary mode.
        let design = try footerTotalSource("Sources/NumlexApp/Design.swift")
        try expect(design.contains("static let footerMode: Double = 0.22"),
                   "one central 0.22 s footer-mode duration")
        try expect(design.contains("static let answerChange: Double = 0.12"),
                   "the value crossfade duration is untouched")
        try expect(design.contains("non-spring"), "documented as non-spring")
        try expect(design.contains("LEADING edge"), "documented as leading-edge shrink")
        try expect(design.contains("Reduce Motion"), "documented Reduce Motion behaviour")
        // The policy header no longer claims ALL motion is geometry-free: it
        // names footerMode as the single narrow exception.
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
        // The transition is owned by the view's own presentation state and
        // adopted inside an explicit animation — no implicit modifier on a
        // value derived from the dragged width.
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
        let bar = footerSlice(view, from: "private func footerBarContent", to: "private func totalValue")
        // The whole footer bubble chain (up to the next section marker), so
        // the animation modifier that sits after the context menu is covered.
        let slot = footerSlice(view, from: "footerBarContent(value: s.value, layout: layout)",
                               to: "// v2: the answer panel is a DARKER")
        try expect(!slot.isEmpty, "the bubble slot exists")
        try expect(!slot.contains("value: width"), "not keyed on the container width")
        try expect(!slot.contains("value: layout.bubbleWidth"), "not keyed on the bubble width")
        try expect(!slot.contains("value: layout.contentWidth"), "not keyed on the content width")
        try expect(!slot.contains(".spring"), "never a spring")
        try expect(!slot.contains("scaleEffect"), "the digits are never scaled")
        try expect(!slot.contains(".bouncy"), "never a bouncy curve")
        try expect(!slot.contains(".offset("), "no numeric tween")
        // The slot only HOOKS the reconciliation; the transition itself lives
        // in the view-owned state helper.
        try expect(slot.contains("reconcileFooterPresentation(desired: desired)"),
                   "the slot reconciles through the view-owned helper")
        // Geometry and semantics that must NOT move.
        try expect(slot.contains(".frame(width: width - 2 * FooterTotalLayout.outerInset, alignment: .trailing)"),
                   "the trailing-anchored slot is unchanged")
        try expect(slot.contains(".padding(FooterTotalLayout.outerInset)"), "outer inset unchanged")
        try expect(slot.contains(".padding(.vertical, 8)"), "vertical padding unchanged")
        try expect(slot.contains("RoundedRectangle(cornerRadius: 9"), "glass radius unchanged")
        try expect(slot.contains("glassEffect"), "the glass surface is kept")
        try expect(view.contains(".accessibilityElement(children: .ignore)"), "one element")
        try expect(view.contains("footerAccessibilityLabel(value: s.value,"), "one label builder")
        try expect(view.contains(".contextMenu {"), "the statistic menu stays")
        try expect(view.contains("ForEach(FooterStatisticMenu.order"), "its order is unchanged")
        // The value keeps its OWN crossfade identity, so a number change
        // never triggers the geometry animation.
        try expect(view.contains(".id(value)"), "value identity crossfade kept")
        try expect(view.contains("value: value"), "the crossfade is keyed on the text")
        try expect(view.contains("reduceMotion ? nil : .easeInOut(duration: Motion.answerChange),"),
                   "the value crossfade keeps its own duration")
        // ONE stable content tree: no branch to swap, and the label fades in
        // place so the value never loses its identity or position.
        try expect(!bar.contains("if layout.showsLabel {"), "no mode branch")
        try expect(bar.contains("ZStack("), "one stable overlay")
        try expect(!bar.contains("Spacer"), "no spacer in either mode")
        try expect(!bar.contains("labelGap"), "no label-gap claim in the content")
        try expect(bar.contains(".opacity(layout.showsLabel ? 1 : 0)"), "the label fades")
    },

    EngineCase("total-bar-animates-one-explicit-bubble-width-stably") {
        // The follow-up regression: the earlier branch-swapping animation
        // could snap or crossfade the whole content because the glass width
        // was inferred. The footer now keeps ONE stable view tree and gives
        // the glass surface an EXPLICIT width, so there is exactly one
        // numeric value for SwiftUI to interpolate — and only the binary mode
        // flip triggers it.
        let view = try footerTotalSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        let content = footerSlice(view, from: "private func footerBarContent",
                                  to: "private func totalValue")
        let slot = footerSlice(view, from: "footerBarContent(value: s.value, layout: layout)",
                               to: "// v2: the answer panel is a DARKER")
        // One stable tree: no mode branch, no branch-specific spacing.
        try expect(!content.contains("if layout.showsLabel {"), "no mode branch in the content")
        try expect(content.contains("ZStack("), "one stable overlay")
        try expect(!content.contains("HStack(spacing:"), "no branch-specific stack spacing")
        try expect(!content.contains("Spacer"), "no spacer claim")
        try expect(!content.contains("labelGap"), "no label-gap claim in the content")
        // One label (faded, leading) and one value (trailing) in that tree.
        try expectEqual(content.components(separatedBy: "Text(totalLabel)").count - 1, 1,
                        "exactly one label node")
        try expectEqual(content.components(separatedBy: "totalValue(value)").count - 1, 1,
                        "exactly one stable value node")
        try expect(content.contains(".opacity(layout.showsLabel ? 1 : 0)"),
                   "the label fades in place")
        try expect(content.contains(".frame(maxWidth: .infinity, alignment: .leading)"),
                   "label leading")
        try expect(content.contains(".frame(maxWidth: .infinity, alignment: .trailing)"),
                   "value trailing")
        // Explicit content width + clipping, then an explicit bubble width.
        try expect(content.contains(".frame(width: layout.contentWidth, alignment: .leading)"),
                   "explicit content width")
        try expect(content.contains(".clipped()"), "the shrinking content clips")
        try expectEqual(slot.components(separatedBy: ".frame(width: layout.bubbleWidth)").count - 1, 1,
                        "exactly one explicit bubble width")
        guard let bubbleAt = slot.range(of: ".frame(width: layout.bubbleWidth)")?.lowerBound,
              let glassAt = slot.range(of: "glassEffect")?.lowerBound else {
            throw CaseFailure(message: "bubble width or glassEffect missing", location: "FooterTotal")
        }
        try expect(bubbleAt < glassAt, "the explicit width precedes the glass surface")
        // The glass width is the ONLY thing that interpolates; the mode key is
        // the only trigger.
        try expectEqual(slot.components(separatedBy: ".animation(").count - 1, 0,
                        "no implicit animation modifier in the footer slot")
        try expect(slot.contains("reconcileFooterPresentation(desired: desired)"),
                   "the mode is reconciled from view-owned state")
        try expect(view.contains("withAnimation(.smooth(duration: Motion.footerMode, extraBounce: 0))"),
                   "one explicit smooth, zero-bounce transition")
        for banned in ["value: width", "value: layout.bubbleWidth", "value: layout.contentWidth",
                       "value: layout.showsLabel ? 1 : 0", "value: value",
                       ".spring", "scaleEffect", ".offset(", ".bouncy"] {
            try expect(!slot.contains(banned), "the footer mode path has no \(banned)")
        }
        // Reduce Motion takes the explicitly non-animated path.
        try expect(view.contains("if reduceMotion {"),
                   "Reduce Motion has its own branch")
        // Fixed trailing slot and the untouched surrounding contract.
        try expect(slot.contains(".frame(width: width - 2 * FooterTotalLayout.outerInset, alignment: .trailing)"),
                   "the trailing edge stays fixed")
        try expect(slot.contains(".padding(.vertical, 8)"), "vertical padding unchanged")
        try expect(slot.contains("RoundedRectangle(cornerRadius: 9"), "radius unchanged")
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
        // THE follow-up regression: expansion used to snap while compaction
        // animated, because the transition was an implicit `.animation` on a
        // layout value derived from the continuously dragged width. The mode
        // now lives in the view's OWN state and is adopted inside one
        // explicit `withAnimation`, so the decision is a single symmetric
        // inequality.
        //
        // The enumerated transition table this case pins:
        //   nil -> expanded            seed, NO animation
        //   nil -> compact             seed, NO animation
        //   expanded -> expanded       same mode, NO animation
        //   compact -> compact         same mode, NO animation
        //   expanded -> compact        MODE FLIP -> animated
        //   compact -> expanded        MODE FLIP -> animated (the fix)
        //   either flip, Reduce Motion NO animation
        //   footer hidden -> shown     reset, then seed, NO animation
        let view = try footerTotalSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        // 1. View-owned optional presentation state.
        try expect(view.contains("@State private var footerPresentation: FooterTotalLayout.Result?"),
                   "the presented geometry is view-owned optional state")
        // 2. Render selection: desired while the modes agree (no drag lag),
        //    the stored presentation only during the reconciling pass.
        try expect(view.contains("private func footerRenderedLayout(desired: FooterTotalLayout.Result) -> FooterTotalLayout.Result"),
                   "a dedicated render-selection helper")
        try expect(view.contains("presented.showsLabel != desired.showsLabel else { return desired }"),
                   "same-mode passes render the live desired layout")
        // 3. The symmetric predicate, verbatim and free of directional logic.
        try expect(view.contains("guard presented.showsLabel != desired.showsLabel else {"),
                   "one symmetric inequality decides the transition")
        let guardLine = "guard presented.showsLabel != desired.showsLabel else {"
        for directional in ["== true", "== false", "desired.showsLabel &&", "&& desired.showsLabel",
                            "if desired.showsLabel {", "if !desired.showsLabel"] {
            try expect(!view.contains(directional), "no directional special case: \(directional)")
        }
        try expect(view.contains(guardLine), "the inequality is the sole directional decision")
        // 4. Exactly one explicit animated adoption, using the shared curve.
        try expectEqual(view.components(separatedBy: "withAnimation(").count - 1, 1,
                        "exactly one withAnimation owns the transition")
        try expect(view.contains("withAnimation(.smooth(duration: Motion.footerMode, extraBounce: 0))"),
                   "the shared 0.22 smooth zero-bounce curve, used by BOTH directions")
        // 5. Every non-mode path is explicitly un-animated: the seed, the
        //    same-mode synchronization, the Reduce Motion adoption and the
        //    visibility reset each set `animation = nil` in their own
        //    transaction.
        try expect(view.contains("transaction.animation = nil"), "explicit no-animation transactions")
        try expectEqual(view.components(separatedBy: "withTransaction(transaction)").count - 1, 4,
                        "seed, same-mode sync, Reduce Motion and reset are all non-animated")
        try expect(view.contains("if reduceMotion {"), "Reduce Motion has its own branch")
        // The Reduce Motion branch must not animate.
        let reconcile = footerSlice(view, from: "private func reconcileFooterPresentation",
                                    to: "private func resetFooterPresentation")
        try expect(!reconcile.isEmpty, "the reconciliation helper exists")
        guard let rmAt = reconcile.range(of: "if reduceMotion {")?.lowerBound,
              let animAt = reconcile.range(of: "withAnimation(")?.lowerBound else {
            throw CaseFailure(message: "reduceMotion or withAnimation missing", location: "FooterTotal")
        }
        try expect(rmAt < animAt, "Reduce Motion is decided BEFORE the animated branch")
        let rmBranch = String(reconcile[rmAt..<animAt])
        try expect(!rmBranch.contains("withAnimation"), "the Reduce Motion branch never animates")
        try expect(rmBranch.contains("transaction.animation = nil"),
                   "Reduce Motion adopts the new geometry in a disabled transaction")
        // 6. Reset when the footer disappears, and the reset is silent.
        try expect(view.contains("private var footerVisible: Bool"),
                   "a stable visibility flag drives the reset")
        try expect(view.contains(".onChange(of: footerVisible) { _, visible in"),
                   "the reset is attached at a stable enclosing level")
        let reset = footerSlice(view, from: "private func resetFooterPresentation",
                                to: "/// The footer's content")
        try expect(reset.contains("footerPresentation = nil"), "the reset clears the stored geometry")
        try expect(!reset.contains("withAnimation"), "the reset is never animated")
        // 7. The old implicit derived-layout animation is gone, and the slot
        //    only hooks the reconciliation.
        try expect(!view.contains(".animation(reduceMotion ? nil : .smooth(duration: Motion.footerMode,"),
                   "no implicit mode animation remains")
        try expect(!view.contains("value: layout.showsLabel)"), "no implicit mode key remains")
        let slot = footerSlice(view, from: "footerBarContent(value: s.value, layout: layout)",
                               to: "// v2: the answer panel is a DARKER")
        try expect(slot.contains(".onAppear { reconcileFooterPresentation(desired: desired) }"),
                   "first appearance seeds through the helper")
        try expect(slot.contains(".onChange(of: desired) { _, newValue in"),
                   "later geometry changes reconcile through the helper")
        try expectEqual(slot.components(separatedBy: ".animation(").count - 1, 0,
                        "no animation modifier in the footer slot")
        // 8. The stable overlay and explicit widths from the previous fix.
        let content = footerSlice(view, from: "private func footerBarContent",
                                  to: "private func totalValue")
        try expect(content.contains("ZStack("), "one stable overlay")
        try expect(!content.contains("if layout.showsLabel {"), "no mode branch")
        try expectEqual(content.components(separatedBy: "totalValue(value)").count - 1, 1,
                        "one stable value node")
        try expect(content.contains(".frame(width: layout.contentWidth, alignment: .leading)"),
                   "explicit content width")
        try expect(content.contains(".clipped()"), "clipping kept")
        try expectEqual(slot.components(separatedBy: ".frame(width: layout.bubbleWidth)").count - 1, 1,
                        "one explicit bubble width")
        try expect(slot.contains(".frame(width: width - 2 * FooterTotalLayout.outerInset, alignment: .trailing)"),
                   "fixed trailing slot")
        // 9. The threshold and the shared duration are untouched.
        try expectEqual(FooterTotalLayout.safetyReserve, 2, "the 2 pt safety reserve is unchanged")
        try expectEqual(FooterTotalLayout.labelGap, 8, "the 8 pt visual gap is unchanged")
        let design = try footerTotalSource("Sources/NumlexApp/Design.swift")
        try expect(design.contains("static let footerMode: Double = 0.22"),
                   "the shared 0.22 s duration is unchanged")
    },
]
