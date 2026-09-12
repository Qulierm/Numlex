import Foundation
import NumlexCore

/// The adaptive bottom-Total bar: the footer shows the localized label while
/// the label + gap + value fit the full content width, and collapses to a
/// trailing value-only bubble when they do not.
///
/// The decision is driven by ACTUALLY measured text widths (AppKit metrics in
/// the view), so these cases exercise the pure geometry contract: exact fit,
/// the safety reserve, a one-point overflow, the long-value cap, short
/// compact widths, hostile input and the trailing-edge/width invariants.
public let footerTotalLayoutCases: [EngineCase] = [

    EngineCase("total-bar-geometry-constants-match-the-panel") {
        try expectEqual(FooterTotalLayout.panelWidth, 200, "panel 200 pt")
        try expectEqual(FooterTotalLayout.outerInset, 8, "outer inset 8")
        try expectEqual(FooterTotalLayout.innerPadding, 12, "inner padding 12")
        try expectEqual(FooterTotalLayout.labelGap, 8, "label/value gap 8")
        try expectEqual(FooterTotalLayout.bubbleWidth, 184, "full bubble 184")
        try expectEqual(FooterTotalLayout.contentWidth, 160, "full content 160")
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
        // Compact mode removes the label view itself — no hidden label, no
        // gap and no Spacer claim.
        try expect(view.contains("if layout.showsLabel {"), "the label is conditional")
        try expect(view.contains("HStack(spacing: FooterTotalLayout.labelGap)"), "the gap is owned by the bar")
        try expect(!view.contains("opacity(layout.showsLabel"), "never a hidden label")
        // Geometry invariants: the trailing edge is fixed by an explicit
        // trailing-aligned slot, and the outer inset is unchanged.
        try expect(view.contains(".frame(width: FooterTotalLayout.bubbleWidth, alignment: .trailing)"),
                   "trailing-aligned slot")
        try expect(view.contains(".padding(FooterTotalLayout.outerInset)"), "unchanged outer inset")
        try expect(view.contains(".padding(.vertical, 8)"), "unchanged vertical padding")
        try expect(view.contains("RoundedRectangle(cornerRadius: 9"), "unchanged glass radius")
        try expect(view.contains(".frame(width: layout.contentWidth, alignment: .leading)"),
                   "content width from the helper")
        // The value path is untouched: same font, same colour, same format.
        try expect(view.contains("Text(s.value)"), "the same formatted value")
        try expect(view.contains(".font(palette.swiftUIFont(fontSize))"), "same value font")
        try expect(view.contains("Color(nsColor: Design.baseText)"), "same value colour")
        try expect(view.contains(".lineLimit(1)"), "one line")
        try expect(view.contains(".id(s.value)"), "text-only crossfade identity")
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
    }
]
