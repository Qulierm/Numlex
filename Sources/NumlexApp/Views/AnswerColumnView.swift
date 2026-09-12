import AppKit
import SwiftUI
import NumlexCore

struct AnswerColumnView: View {
    /// One indexed evaluated line per logical source line (strict 1:1
    /// contract from `evaluateSheet`); every rendered answer binds to its
    /// explicit `sourceLineIndex`, never to its position after filtering.
    var rows: [SheetLine]
    /// r77c: the row a stationary multi-pair click run keeps minting.
    /// The first pair (clickCount 2) resolves the row under the cursor;
    /// later pairs of the same run (4, 6, …) reuse it — the first pair's
    /// insertion reflows the document, and a fresh y-remap of a
    /// stationary cursor would land on whichever row merely moved under
    /// it. A new hardware run restarts at clickCount 2 and re-resolves.
    @State private var runMintedRow: Int?
    var metrics: LineMetrics
    /// Shared scroll state: top-down points scrolled from the top of the
    /// document. The editor is the primary surface; this column renders its
    /// rows at `offset(y: -topOffset)` so both stay pixel-exact 1:1.
    var topOffset: CGFloat
    /// Raw wheel events over the answer surface are forwarded verbatim to
    /// the editor's scroll view (phases, momentum, precise deltas intact),
    /// so the editor remains the single native scroll source. This pane has
    /// no visible scroll bar of its own: the wheel catcher is the whole
    /// content width.
    var onWheelScroll: (NSEvent) -> Void
    /// Double-click on a SUCCESSFUL answer row (`.number` / `.variable`)
    /// reports the row's explicit source line index; the owner mints a
    /// token referencing that line. All other rows (errors, titles,
    /// prose, the Total bar) are inert.
    var onAnswerDoubleTap: (Int) -> Void
    var fontSize: Double
    var lineHeight: Double
    var decimalPlaces: Int
    /// r51: stable line IDs parallel to `rows` (the selected sheet's
    /// table) plus the sheet's rounding overrides by line ID. A row's
    /// effective decimals = override ?? global; tokens and Total always
    /// use the global value (no source-display side effects).
    var lineIDs: [UUID] = []
    var roundingOverrides: [UUID: Int] = [:]
    var language: AppLanguage = .en
    /// r51: answer context menu actions, by EXPLICIT source line index.
    /// The model re-validates index + line ID at fire time, so a menu
    /// opened before an evaluation update can never act on a stale row.
    /// `places == nil` clears back to Default.
    var onSetRounding: (Int, Int?) -> Void = { _, _ in }
    var onDeleteLine: (Int) -> Void = { _ in }
    /// r21: the selected font design — answers use the centralized dark
    /// base token (Design.baseText) on the light panel, but the face must
    /// match the editor exactly (same resolver).
    var fontDesign: StylingFontDesign = .system
    var totalLabel: String
    /// r80: the sheet's bottom Total panel (footer bar under the
    /// answers). OFF removes the panel AND its reserved space — the
    /// answers viewport above expands to take it; inline total lines
    /// are unaffected. No animation: the answers' hit surface
    /// (ScrollWheelCatcher, r62 lockstep) must never chase an animated
    /// frame, so the toggle snaps in one layout pass.
    var showTotalBar: Bool = true
    /// r37: the source line whose answer is highlighted (a token
    /// capsule referencing it is hovered). Ephemeral; the outline is a
    /// pure stroke overlay — it never alters layout, row frames,
    /// baselines, hit testing or clipping.
    var highlightedSourceLineIndex: Int? = nil
    /// r73: the app's ONE number context — answers render in its
    /// separators (grouping, decimal comma, compact notation) and the
    /// copy paths read the same value, so the clipboard always matches
    /// the visible row (full-precision copy when the row compacts).
    var numberContext: NumberFormatContext = .legacy
    /// r77: per-line fade-in opacities of the answer appearance pass
    /// (line ID → 0...1; empty = every row fully opaque). Opacity-only:
    /// geometry, baseline placement, hit testing and the display model
    /// are all final from the first frame.
    var answerOpacities: [UUID: Double] = [:]
    /// r87: the GLOBAL number presentation preferences (presentation-
    /// only — engine values are never rounded or scaled by display).
    var presentation: NumberPresentationPreferences = .defaults
    /// r87: per-line NOTATION overrides by stable line UUID; an absent
    /// key = Default (the row follows the global notation).
    var notationOverrides: [UUID: AnswerNotationOverride] = [:]
    /// r87: answer column appearance (styling). `.leading`/`.neutral`
    /// are the pre-r87 layout.
    var columnAlignment: AnswerColumnAlignment = .leading
    var columnSurface: AnswerColumnSurface = .neutral
    /// r87: the persistent per-line highlight fills by stable line
    /// UUID. Overlay/background only — no hit testing, no layout.
    var highlightFills: [UUID: HighlightColor] = [:]
    /// r87: notation override writes by EXPLICIT source line index
    /// (nil = Default: the line resumes live global sync). The model
    /// revalidates index + line ID at fire time.
    var onSetNotation: (Int, AnswerNotationOverride?) -> Void = { _, _ in }
    /// r87: removes BOTH the notation and the precision override so
    /// the line follows the globals again.
    var onRestoreFormatting: (Int) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The result kinds a hovered token may highlight: exactly the
    /// answerable results the token-active semantics resolve to.
    /// Blank/title/skip/error/broken/date never outline.
    private func isHighlightable(_ result: LineResult) -> Bool {
        switch result {
        case .number, .variable, .variableInt, .integer, .money, .boolean, .location:
            return true
        case .dms:
            // r85: DMS answers are not token sources — no outline.
            return false
        case .blank, .skip, .title, .date, .brokenToken, .error:
            return false
        }
    }

    /// r51: the raw override for a row (nil = Default), clamped.
    private func override(for sourceLineIndex: Int) -> Int? {
        guard lineIDs.indices.contains(sourceLineIndex) else { return nil }
        return roundingOverrides[lineIDs[sourceLineIndex]].map(AnswerDisplay.clamped)
    }

    /// r77: this row's appearance-pass opacity (1 = settled final
    /// state). Seeded lines (load/relaunch/sheet switch) are never in
    /// the map, so they render at full opacity from the first frame —
    /// only genuinely new lines fade in, and only their opacity.
    private func rowOpacity(_ line: SheetLine) -> Double {
        guard lineIDs.indices.contains(line.sourceLineIndex) else { return 1 }
        return answerOpacities[lineIDs[line.sourceLineIndex]] ?? 1
    }

    /// r77: the row's displayed answer string — the SAME authoritative
    /// text the Copy Answer path uses (full precision for the automatic
    /// default; every other notation shares ONE string between display
    /// and copy — the r87 contract). nil = a hidden row (no crossfade
    /// identity churn).
    private func answerDisplayText(for line: SheetLine) -> String? {
        guard lineIDs.indices.contains(line.sourceLineIndex) else { return nil }
        return AnswerDisplay.displayText(
            for: line.result,
            decimalPlaces: places(for: line.sourceLineIndex),
            context: numberContext,
            notation: effectiveNotation(for: line.sourceLineIndex),
            prefs: presentation
        )
    }

    /// r87: the row's EFFECTIVE notation (per-line override ?? global).
    private func effectiveNotation(for sourceLineIndex: Int) -> NumberNotation {
        guard lineIDs.indices.contains(sourceLineIndex) else { return presentation.notation }
        if let o = notationOverrides[lineIDs[sourceLineIndex]] {
            return o.notation
        }
        return presentation.notation
    }

    /// r87: this row's highlight fill (nil = unhighlighted).
    private func highlightFill(for line: SheetLine) -> Color? {
        guard lineIDs.indices.contains(line.sourceLineIndex),
              let c = highlightFills[lineIDs[line.sourceLineIndex]] else { return nil }
        return Color(nsColor: Design.highlightFill(c))
    }

    /// r51: effective display decimals for one answer row.
    private func places(for sourceLineIndex: Int) -> Int {
        AnswerDisplay.effective(defaultPlaces: decimalPlaces,
                                override: override(for: sourceLineIndex))
    }

    /// r51/r54: the native right-click menu for one answer row (nil =
    /// hidden row, no menu). Copy uses `AnswerDisplay.text` —
    /// byte-identical to the rendered string. Rounding-eligible rows
    /// get an inline discrete SLIDER (0...10, native tick marks, live
    /// `N dp` label) plus the centered disabled `Edit answer formatting`
    /// caption; money/currency, date, broken-token and rates rows keep
    /// the compact Copy / separator / Delete shape (no slider, no empty
    /// gaps). There is deliberately NO reset/default control and no
    /// speak/formatting buttons. Delete has no AppKit destructive role
    /// (menus offer none); the model confirms nothing — it deletes one
    /// line.
    private func contextMenu(for line: SheetLine) -> NSMenu? {
        guard let kind = AnswerDisplay.menu(for: line.result) else { return nil }
        let idx = line.sourceLineIndex
        let places = places(for: idx)
        let effNotation = effectiveNotation(for: idx)
        guard let text = AnswerDisplay.text(for: line.result, decimalPlaces: places,
                                            context: numberContext,
                                            notation: effNotation,
                                            prefs: presentation) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false  // r54: the custom slider item and
                                       // the disabled caption are enabled
                                       // states we own explicitly.
        func item(_ title: String, checked: Bool = false,
                  enabled: Bool = true,
                  help: String? = nil, run: @escaping () -> Void) -> NSMenuItem {
            let h = MenuAction(run)
            let mi = NSMenuItem(title: title, action: #selector(MenuAction.fire),
                                keyEquivalent: "")
            mi.target = h
            // NSMenuItem retains representedObject (but NOT target):
            // the handler rides along for exactly the item's lifetime.
            mi.representedObject = h
            mi.state = checked ? .on : .off
            mi.isEnabled = enabled
            if let help { mi.toolTip = help }
            return mi
        }
        menu.addItem(item(L10n.t("copyAnswer", language: language)) {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        })
        menu.addItem(.separator())
        if kind.showsRounding {
            // r54: inline slider — initial value is the row's effective
            // precision (override ?? global); moving it writes that
            // row's explicit override through the existing onSetRounding
            // (persist-only repaint; the model revalidates index + line
            // ID at fire time, so a stale open menu can never retarget).
            menu.addItem(AnswerSliderMenuItem.menuItem(
                initial: AnswerDisplay.sliderValue(
                    defaultPlaces: decimalPlaces,
                    override: override(for: idx)),
                language: language,
                onChange: { v in onSetRounding(idx, v) }))
            menu.addItem(AnswerSliderMenuItem.caption(language: language))
            menu.addItem(.separator())
        }
        // r88: the ONE Number Format construction — a single
        // delimiter block builds the submenu once (the checked entry is
        // the row's OWN state: an explicit override checks that mode,
        // otherwise Default; Custom stays enabled only while the global
        // pattern validates and disabled rows carry a help label). The
        // Reset row appears ONLY while this row currently carries a
        // precision and/or notation override — no useless enabled
        // Reset on a clean row.
        let lineID = lineIDs.indices.contains(idx) ? lineIDs[idx] : nil
        let overrideHere = lineID.flatMap { notationOverrides[$0] }
        if let opts = AnswerDisplay.notationOptions(for: line.result) {
            let customValid = NumberPattern.tryValidated(presentation.customPattern) != nil
            let check: (AnswerNotationOverride?) -> Bool = { mode in overrideHere == mode }
            let fmt = NSMenuItem(title: L10n.t("numberFormat", language: language),
                                 action: nil, keyEquivalent: "")
            let sub = NSMenu()
            sub.autoenablesItems = false
            func subItem(_ title: String, mode: AnswerNotationOverride?,
                         enabled: Bool = true, help: String? = nil) {
                sub.addItem(item(title, checked: check(mode),
                                 enabled: enabled, help: help) {
                    onSetNotation(idx, mode)
                })
            }
            subItem(L10n.t("formatDefault", language: language), mode: nil)
            subItem(L10n.t("formatAutomatic", language: language), mode: .automatic)
            subItem(L10n.t("formatDecimal", language: language), mode: .decimal)
            subItem(L10n.t("formatScientific", language: language), mode: .scientific)
            subItem(L10n.t("formatEngineering", language: language), mode: .engineering)
            if opts.allowsFraction {
                subItem(L10n.t("formatFraction", language: language), mode: .fraction)
            }
            subItem(L10n.t("formatCustom", language: language), mode: .custom,
                    enabled: customValid,
                    help: customValid ? nil
                        : L10n.t("customPatternInvalid", language: language))
            fmt.submenu = sub
            menu.addItem(fmt)
            // r88: conditional Reset — only while the row actually
            // carries a precision and/or notation override.
            if override(for: idx) != nil || overrideHere != nil {
                menu.addItem(item(L10n.t("resetFormatting", language: language)) {
                    onRestoreFormatting(idx)
                })
            }
            menu.addItem(.separator())
        }
        menu.addItem(item(L10n.t("deleteLine", language: language)) {
            onDeleteLine(idx)
        })
        return menu
    }

    /// The answer row whose block contains content y `y` (the same
    /// coordinate space the wheel-catcher overlay lives in: row top
    /// minus the shared topOffset), or nil between rows.
    private func rowAt(y: CGFloat) -> SheetLine? {
        for line in rows {
            let g = rowGeometry(line)
            let top = g.top - topOffset
            if y >= top - 0.5, y < top + g.height { return line }
        }
        return nil
    }

    private func rowGeometry(_ line: SheetLine) -> (top: CGFloat, height: CGFloat) {
        // Row frames are expressed in the same coordinates as the editor
        // content: the editor's text starts editorTopInset below the shared
        // column top, so both columns use the same mapping. The index is
        // the line's EXPLICIT source index, so hidden rows (headings,
        // blanks, prose) still hold the later answers on their own lines.
        NotebookLayout.answerRow(
            index: line.sourceLineIndex,
            lines: metrics.lines,
            topInset: Design.editorTopInset
        )
    }

    /// The r21 palette resolver (only the font side is used here:
    /// answers are the fixed dark base (Design.baseText) by design).
    private var palette: NotebookPalette {
        NotebookPalette(styling: StylingPreferences(fontDesign: fontDesign))
    }

    /// Content-coordinate Y of every total divider (r58): the
    /// pixel-snapped midpoint between the previous visible answer's
    /// ink center and the total's ink center, or the nominal fallback
    /// when the section has no previous visible answer. Each center
    /// reuses the EXACT baseline offset its row renders with
    /// (`baselineOffset(for:metric:height:)`) minus half the cap
    /// height of the weight that row renders in (regular for ordinary
    /// rows — the scan never crosses a total boundary — semibold for
    /// totals), so the divider agrees with the drawn ink by
    /// construction. Scrolling stays outside: callers subtract the
    /// shared topOffset exactly like the rows do.
    private func dividerModels(metricByIndex: [Int: LineMetrics.Line]) -> [CGFloat] {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let regularCap = palette.editorFont(size: fontSize).capHeight
        let semiboldCap = palette.editorFont(size: fontSize, weight: .semibold).capHeight
        var ys: [CGFloat] = []
        for (ri, line) in rows.enumerated() where line.isTotal {
            let g = rowGeometry(line)
            let totalBaseline = baselineOffset(
                for: line, metric: metricByIndex[line.sourceLineIndex], height: g.height)
            let totalCenter = TotalDivider.answerInkCenter(
                rowTop: g.top, baselineOffset: totalBaseline, capHeight: semiboldCap)
            if let pi = TotalDivider.previousVisibleIndex(totalIndex: ri, lines: rows) {
                let prev = rows[pi]
                let pg = rowGeometry(prev)
                let prevBaseline = baselineOffset(
                    for: prev, metric: metricByIndex[prev.sourceLineIndex], height: pg.height)
                let prevCenter = TotalDivider.answerInkCenter(
                    rowTop: pg.top, baselineOffset: prevBaseline, capHeight: regularCap)
                ys.append(TotalDivider.midpoint(
                    previousCenter: prevCenter, totalCenter: totalCenter, displayScale: scale))
            } else {
                ys.append(TotalDivider.fallback(
                    totalCenter: totalCenter, totalRowHeight: g.height))
            }
        }
        return ys
    }

    /// Y offset from the top of the row frame to the answer's target
    /// first-text baseline, in row-local coordinates. A measured metric
    /// line supplies it directly (its container-coordinate answer baseline
    /// minus the row's container top — the exact TextKit baseline of the
    /// source line, or the block-centered ink baseline of a wrapped line).
    /// Defensive rows without a metric (e.g. before the first layout
    /// pass) fall back to the single-fragment rule with the real font
    /// metrics — no empirical constant anywhere.
    private func baselineOffset(for line: SheetLine,
                                metric: LineMetrics.Line?,
                                height: CGFloat) -> CGFloat {
        if let metric {
            return metric.answerBaseline - metric.top
        }
        let font = palette.editorFont(size: fontSize)
        let naturalHeight = font.ascender - font.descender + font.leading
        return AnswerBaseline.baseline(
            rowTop: 0,
            rowHeight: height,
            fragmentCount: 1,
            ascender: font.ascender,
            naturalHeight: naturalHeight,
            capHeight: font.capHeight
        )
    }

    /// The footer's content: in expanded mode the localized label, its gap
    /// and the value; in COMPACT mode the value ALONE — no label, no gap and
    /// no spacer claim, so the value gets its full measured width instead of
    /// losing the label gap to truncation.
    @ViewBuilder
    private func footerBarContent(value: String, layout: FooterTotalLayout.Result) -> some View {
        if layout.showsLabel {
            HStack(spacing: FooterTotalLayout.labelGap) {
                Text(totalLabel)
                    .font(Design.labelSmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                totalValue(value)
            }
            .frame(width: layout.contentWidth, alignment: .leading)
        } else {
            HStack(spacing: 0) {
                totalValue(value)
            }
            .frame(width: layout.contentWidth, alignment: .trailing)
        }
    }

    /// The Total's displayed value — one definition shared by both modes so
    /// the font, colour, line limit and the text-only crossfade identity can
    /// never drift between them.
    private func totalValue(_ value: String) -> some View {
        Text(value)
            .font(palette.swiftUIFont(fontSize))
            .foregroundStyle(Color(nsColor: Design.baseText))
            .lineLimit(1)
            // r77: the Total value gets the same short crossfade as changed
            // answers — text identity only; the bar never moves or resizes.
            .id(value)
            .transition(.opacity)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: Motion.answerChange),
                value: value
            )
    }

    /// Pixel-safe width of one string in a given font (ceil + a hair so
    /// subpixel rounding can never make the label overlap the value).
    private static func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        guard width.isFinite, width > 0 else { return 0 }
        return ceil(width) + 0.5
    }

    /// The footer's REAL text metrics: the label in the same 11 pt system
    /// font `Design.labelSmall` uses, the value in the palette's editor font
    /// (system/rounded/serif/monospaced + the live size), so the switch is
    /// driven by rendered widths, never by a row or character count.
    private func footerTextMetrics(value: String) -> (label: CGFloat, value: CGFloat) {
        let label = Self.measuredWidth(totalLabel, font: NSFont.systemFont(ofSize: 11))
        let valueWidth = Self.measuredWidth(value, font: palette.editorFont(size: fontSize))
        return (label, valueWidth)
    }

    /// The one accessibility phrase for the footer: localized label + the
    /// exact displayed value (+ unit when the aggregate ever carries one).
    private func footerAccessibilityLabel(value: String, unit: String?) -> String {
        if let unit, !unit.isEmpty { return "\(totalLabel) \(value) \(unit)" }
        return "\(totalLabel) \(value)"
    }

    private var summary: (value: String, unit: String?)? {
        // The bottom Total is the OVERALL sheet total, dimension-
        // agnostic and unitless: `SheetFooterTotal` owns the whole
        // eligibility contract (every ordinary scalar answer row —
        // unitless numbers, unit-bearing quantities, money, named
        // scalars and exact integers — counted once in display order,
        // with inline `total` rows excluded so the feature never
        // double-counts). The view must not encode result-type
        // eligibility itself: it only formats the aggregate.
        guard var sum = SheetFooterTotal.aggregate(rows) else { return nil }
        if sum.truncatingRemainder(dividingBy: 1) != 0 {
            sum = (sum * pow(10, Double(decimalPlaces))).rounded() / pow(10, Double(decimalPlaces))
        }
        // The shared overflow-safe formatter (automatic = the exact
        // pre-r87 Total shape); r87: non-automatic global notations
        // format the unrounded sum through the ONE presentation API —
        // per-source overrides never touch the Total.
        let value = presentation.notation == .automatic
            ? formatDisplayValue(sum, decimalPlaces: decimalPlaces, context: numberContext)
            : NumberPresentation.format(sum, category: .plain,
                                        notation: presentation.notation,
                                        precision: decimalPlaces,
                                        prefs: presentation, context: numberContext)
        return (value, nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The rows live in one tall VStack; the shared topOffset moves
            // the whole block. No independent scroll view, so the column
            // cannot drift from the editor.
            GeometryReader { geo in
                // Render at the raw shared offset: during trackpad momentum
                // and elastic bounce the editor's clip offset legitimately
                // goes negative (or past the end), and the answer must
                // follow it pixel-exact. Only programmatic targets (knob
                // drag) are clamped, in the coordinator path.
                //
                // Every row is placed ABSOLUTELY at the top/height of its
                // own source line's measured block (wrapped fragments
                // included): hidden rows simply render no content, but
                // their space is held by the metric gap, so an answer can
                // never drift onto a heading or a blank line. A missing
                // metric falls back per-row (NotebookLayout.answerRow)
                // without disturbing the other rows.
                // Every row is placed ABSOLUTELY at the top/height of its
                // own source line's measured block (wrapped fragments
                // included), and INSIDE the row the answer subview is
                // placed by measured first-text baseline (BaselineAnswerRow)
                // so it sits exactly on the editor's TextKit baseline for
                // that source line. Hidden rows simply render no content,
                // but their space is held by the metric gap, so an answer
                // can never drift onto a heading or a blank line. A missing
                // metric falls back per-row (NotebookLayout.answerRow +
                // AnswerBaseline) without disturbing the other rows.
                ZStack(alignment: .topLeading) {
                    let metricByIndex = Dictionary(
                        uniqueKeysWithValues: metrics.lines.map { ($0.index, $0) }
                    )
                    let dividerModels = dividerModels(metricByIndex: metricByIndex)
                    ForEach(rows, id: \.sourceLineIndex) { line in
                        let geo2 = rowGeometry(line)
                        let baseline = baselineOffset(
                            for: line,
                            metric: metricByIndex[line.sourceLineIndex],
                            height: geo2.height
                        )
                        BaselineAnswerRow(
                            width: geo.size.width,
                            height: geo2.height,
                            baselineOffset: baseline
                        ) {
                            AnyView(rowView(line))
                        }
                        // r37: the source-answer hover outline — a
                        // stroke-only rounded rect centered on the
                        // SAME measured answer baseline the text sits
                        // on (AnswerBaseline.hoverOutline), fading in
                        // over ~0.12 s (immediate under Reduce Motion).
                        .overlay {
                            if line.sourceLineIndex == highlightedSourceLineIndex
                                && isHighlightable(line.result) {
                                let font = palette.editorFont(size: fontSize)
                                let o = AnswerBaseline.hoverOutline(
                                    baseline: baseline,
                                    rowHeight: geo2.height,
                                    naturalHeight: font.ascender - font.descender + font.leading,
                                    capHeight: font.capHeight
                                )
                                AnswerHoverOutline(
                                    width: geo.size.width,
                                    centerY: o.centerY,
                                    height: o.height
                                )
                                .transition(.opacity)
                            }
                        }
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.12),
                            value: line.sourceLineIndex == highlightedSourceLineIndex
                                && isHighlightable(line.result)
                        )
                        .offset(y: geo2.top - topOffset)
                        // r77: the ONE opacity-only appearance pass —
                        // a freshly introduced line's answer fades in
                        // over the shared Motion.answerIn duration; the
                        // row's offset/geometry are never animated.
                        .opacity(rowOpacity(line))
                        // r87: the persistent line highlight — a
                        // full-logical-row adaptive fill behind the row
                        // content (the same color the editor draws in
                        // its gutter area). Overlay only: no hit
                        // testing, no layout or baseline effect.
                        .background {
                            if let fill = highlightFill(for: line) {
                                fill.allowsHitTesting(false)
                            }
                        }
                    }
                    // r58: centered total dividers — one 1pt adaptive
                    // neutral hairline (`Design.panelSeparator`) per total
                    // row, placed at the PIXEL-SNAPPED midpoint between
                    // the previous visible answer's ink center and the
                    // total's ink center (TotalDivider over evaluated
                    // metadata + measured metrics, never source text).
                    // A pure overlay layer in the same scrolling ZStack:
                    // no height, no hit testing, no layout extent, no
                    // scroll drift — rows keep their own offsets, clicks,
                    // double-clicks and menus untouched.
                    ForEach(dividerModels, id: \.self) { y in
                        Color(nsColor: Design.panelSeparator)
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                            .allowsHitTesting(false)
                            // The 1pt line centers on the midpoint: its
                            // top sits half a point above it, so the
                            // midpoint stays mathematically centered.
                            .offset(y: y - topOffset - 0.5)
                    }
                }
                // Clamp to the visible content region first, so the overlay
                // below sizes to the region (not the intrinsic content
                // height) and never bleeds over the summary bar.
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .overlay(alignment: .leading) {
                    // The wheel catcher covers the FULL content width —
                    // no scroller strip, no dead zone at the trailing
                    // edge. It also owns double-clicks over the surface:
                    // a hit on a successful answer row mints a token.
                    // r51: it owns right-clicks too — the same `rowAt`
                    // geometry maps the click to its source row and pops
                    // the native answer menu (copy/rounding/delete).
                    // Neither path touches selection, focus or scrolling.
                    ScrollWheelCatcher(
                        onScroll: onWheelScroll,
                        onDoubleTap: { y, count in
                            // r77c: mapping diagnostics (inert w/o --trace).
                            let firstTop = rows.first.map { rowGeometry($0).top - topOffset }
                            let firstH = rows.first.map { rowGeometry($0).height }
                            Diagnostics.shared?.log(String(
                                "catcher.map y=\(Int(y)) count=\(count) topOffset=\(Int(topOffset)) "
                                + "rows=\(rows.count) metrics=\(metrics.lines.count) "
                                + "top0=\(firstTop.map(String.init) ?? "nil") h0=\(firstH.map(String.init) ?? "nil") "
                                + "runRow=\(runMintedRow.map(String.init) ?? "nil")"))
                            // r77c: the run's row (first pair = fresh
                            // resolution, later pairs = reuse).
                            let rowIndex: Int?
                            if count <= 2 {
                                let idx = rowAt(y: y)?.sourceLineIndex
                                runMintedRow = idx
                                rowIndex = idx
                            } else {
                                rowIndex = runMintedRow ?? rowAt(y: y)?.sourceLineIndex
                            }
                            guard let idx = rowIndex else { return }
                            if let line = rows.first(where: { $0.sourceLineIndex == idx }) {
                                switch line.result {
                                case .number, .variable, .money:
                                    // Money answers are tokenizable (their
                                    // tokens carry the ISO code); date
                                    // answers are never minted.
                                    onAnswerDoubleTap(idx)
                                default:
                                    break
                                }
                            }
                        },
                        rowIndexAtY: { y in rowAt(y: y)?.sourceLineIndex },
                        menuForRow: { idx in
                            rows.first(where: { $0.sourceLineIndex == idx })
                                .flatMap { contextMenu(for: $0) }
                        }
                    )
                        .allowsHitTesting(true)
                        // r62: explicit full-size frame — the catcher must
                        // exactly match the GeometryReader's content
                        // region (width AND height, top-anchored). Relying
                        // on the representable's unspecified ideal size
                        // lets the AppKit frame desync from the SwiftUI
                        // layout after a window resize, leaving the
                        // visible answers outside the hit surface.
                        .frame(width: geo.size.width,
                               height: geo.size.height,
                               alignment: .topLeading)
                }
            }
            .clipped()
            .frame(maxHeight: .infinity)

            if showTotalBar, let s = summary {
                let metrics = footerTextMetrics(value: s.value)
                let layout = FooterTotalLayout.layout(containerWidth: FooterTotalLayout.panelWidth,
                                                      labelWidth: metrics.label,
                                                      valueWidth: metrics.value)
                footerBarContent(value: s.value, layout: layout)
                    .padding(.horizontal, FooterTotalLayout.innerPadding)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    // The bubble shrinks from its LEADING edge: the trailing
                    // edge stays put inside the panel's inset slot, and the
                    // reserved vertical space is untouched in both modes.
                    .frame(width: FooterTotalLayout.bubbleWidth, alignment: .trailing)
                    .padding(FooterTotalLayout.outerInset)
                    // ONE announcement, in both modes: the localized label and
                    // the exact displayed value, never duplicated children.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(footerAccessibilityLabel(value: s.value,
                                                                      unit: s.unit)))
                    // Mode changes must not animate the bubble's geometry.
                    .transaction { if !reduceMotion { $0.animation = nil } }
            }
        }
        .frame(width: 200)
        // v2: the answer panel is a DARKER calm gray than the editor
        // (Design.answerPanelBackground: explicit per-appearance sRGB —
        // quiet elevated gray in dark, quiet gray in light), so the
        // result surface reads as its own matte panel without looking
        // light. Editor background and every text token stay untouched.
        // The layer expands vertically so the titlebar-gap strip above
        // the column matches the panel; the editor|answers hairline
        // itself lives once in ContentView (full-height), never here —
        // no double line, no width drift.
        // r87: the Styling answer-column surface choice swaps the
        // panel color through the centralized palette resolver
        // (`.neutral` = the exact pre-r87 panel); the answer glyph
        // color stays the centrally resolved accessible base for every
        // surface.
        .background {
            Color(nsColor: Design.answerSurfaceColor(columnSurface))
                .ignoresSafeArea(edges: .vertical)
        }
    }

    @ViewBuilder
    private func rowView(_ line: SheetLine) -> some View {
        // r51: scalar/variable/unit strings render at the row's EFFECTIVE
        // decimals (override ?? global) — the same inputs Copy Answer
        // feeds through `AnswerDisplay.text`, so clipboard == visible.
        let row = line.result
        let places = places(for: line.sourceLineIndex)
        // Left-aligned content of one answer. Vertical placement is owned
        // by the BaselineAnswerRow layout (measured first-text baseline on
        // the editor's TextKit target baseline); this view only provides
        // the horizontal padding, the fixed dark-base (Design.baseText)
        // regular typography and the single-line clipping.
        Group {
            switch row {
            case .blank, .skip, .title(_):
                Color.clear
            case .number(let v, let unit, let kind, let fraction):
                numberView(v: v, unit: unit, kind: kind, fraction: fraction,
                           line: line, places: places)
            case .integer(let v, let radix), .variableInt(_, let v, let radix):
                // r85: base rows render the EXACT base text — no
                // compact notation, no decimal rounding. r87: decimal-
                // radix rows take the row's effective notation through
                // the exact Int64 digit paths (no Double precision
                // change); radix rows stay canonical.
                let eff = effectiveNotation(for: line.sourceLineIndex)
                let s = (radix == 10)
                    ? NumberPresentation.formatInt64(
                        v, notation: eff, precision: places,
                        prefs: presentation, context: numberContext)
                    : IntLiteral.format(v, radix: radix)
                Text(s)
                    .font(palette.swiftUIFont(fontSize, weight: line.isTotal ? .semibold : .regular))
                    .foregroundStyle(Color(nsColor: Design.baseText))
                    .lineLimit(1)
            case .location(_, _, let c):
                // r85: the retypeable coordinate pair.
                Text(GeoPresentation.coordinateText(c, context: numberContext))
                    .font(palette.swiftUIFont(fontSize))
                    .foregroundStyle(Color(nsColor: Design.baseText))
                    .lineLimit(1)
            case .dms(let p):
                Text(DMSTools.display(p, context: numberContext))
                    .font(palette.swiftUIFont(fontSize))
                    .foregroundStyle(Color(nsColor: Design.baseText))
                    .lineLimit(1)
            case .money(let v, let code):
                // Natural money: shared presentation (`$600.00`),
                // dark-base regular, never enters the numeric Total.
                Text(NumberPresentation.formatMoney(v, code: code,
                                                    notation: effectiveNotation(for: line.sourceLineIndex),
                                                    prefs: presentation,
                                                    context: numberContext))
                    .font(palette.swiftUIFont(fontSize))
                    .foregroundStyle(Color(nsColor: Design.baseText))
                    .lineLimit(1)
            case .date(let y, let m, let d, let showYear):
                // Date answers: compact English, baseline-aligned dark
                // base regular, never tokenized as a number.
                Text(DateArithmetic.display(
                    year: y, month: m, day: d, showYear: showYear))
                    .font(palette.swiftUIFont(fontSize))
                    .foregroundStyle(Color(nsColor: Design.baseText))
                    .lineLimit(1)
            case .variable(_, let v, let kind, let fraction):
                // Assignment rows show ONLY the value — the name and
                // equals sign live in the editor, never in the answers.
                // r83: a semantic kind renders its kinded string; r87:
                // non-automatic notations re-format the numeric
                // component, the fraction kind keeps its exact shape.
                let eff = effectiveNotation(for: line.sourceLineIndex)
                let s = kindedString(v: v, unit: nil, kind: kind, fraction: fraction,
                                      eff: eff, places: places)
                Text(s)
                    .font(palette.swiftUIFont(fontSize))
                    .foregroundStyle(Color(nsColor: Design.baseText))
                    .lineLimit(1)
            case .boolean(let b):
                // r82: a boolean answer renders as its lowercase word
                // with the same dark-base regular glyphs as numbers —
                // no unit suffix, no rounding, exactly what Copy
                // Answer puts on the clipboard.
                Text(b ? "true" : "false")
                    .font(palette.swiftUIFont(fontSize))
                    .foregroundStyle(Color(nsColor: Design.baseText))
                    .lineLimit(1)
            case .brokenToken(let line):
                // An inactive token on its own line: the remembered
                // label, dimmed to read as "not live".
                Text("Line \(line)")
                    .font(Design.labelSmall)
                    .foregroundStyle(.secondary)
            case .error(let msg):
                if WeatherQuery.isUnavailableMessage(msg) {
                    // r55: terminal weather failure with no cache — a
                    // quiet secondary status (localized at render
                    // time), never an answer: no copy, no rounding, no
                    // token, never in the Total.
                    Text(L10n.t("weatherUnavailable", language: language))
                        .font(Design.labelSmall)
                        .foregroundStyle(.secondary)
                } else if GeoQueryParse.isUnavailableMessage(msg) {
                    // r85: terminal geocode failure with no cache —
                    // the same quiet localized status as weather.
                    Text(L10n.t("locationUnavailable", language: language))
                        .font(Design.labelSmall)
                        .foregroundStyle(.secondary)
                } else if msg == "Rates unavailable" {
                    // The explicit no-rate state is preserved and
                    // rendered in the fixed dark base.
                    Text("Rates unavailable")
                        .font(Design.labelSmall)
                        .foregroundStyle(Color(nsColor: Design.baseText))
                } else {
                    // Generic calculation errors render nothing at all
                    // (no "Error" label), leaving the row quiet on the
                    // panel while the expression above carries its
                    // lexical spans.
                    Color.clear
                }
            }
        }
        .lineLimit(1)
        // r77: the displayed value of an EXISTING line changes
        // (re-evaluation, rounding override, region change): a short
        // opacity crossfade via an identity swap in place — no numeric
        // tween, no frame movement, no baseline change (the row's
        // geometry stays owned by BaselineAnswerRow). Under Reduce
        // Motion the swap is immediate. Newly introduced lines are
        // handled separately by the row-opacity pass (rowOpacity).
        .id(answerDisplayText(for: line) ?? "")
        .transition(.opacity)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: Motion.answerChange),
            value: answerDisplayText(for: line)
        )
        // Symmetric row insets; no invisible scroller reservation — the
        // column has no scroll bar of its own.
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: columnAlignment == .leading ? .leading : .trailing)
    }

    /// r87: the semantic-kind display string for one numeric value —
    /// a plain function (never the view builder): automatic keeps the
    /// shared kinded string, the fraction kind its exact reduced
    /// rational, other notations re-format the numeric component.
    private func kindedString(v: Double, unit: String?,
                              kind: NumericKind,
                              fraction: NumlexCore.Rational?,
                              eff: NumberNotation, places: Int) -> String {
        // A duration is SEMANTIC: its natural decomposition never depends on
        // the row's number notation and the display unit is always passed
        // through — the numeric-only path must never be reachable for it.
        if kind == .duration {
            return AnswerDisplay.formatKinded(v, unit: unit, kind: .duration,
                                              fraction: fraction,
                                              decimalPlaces: places,
                                              context: numberContext)
        }
        if eff == .automatic {
            return AnswerDisplay.formatKinded(v, unit: unit, kind: kind,
                                              fraction: fraction,
                                              decimalPlaces: places,
                                              context: numberContext)
        }
        if kind == .fraction, let r = fraction {
            return "\(r.numerator)/\(r.denominator)"
        }
        let category: NumberPresentation.Category
        if kind == .percent {
            category = .percent
        } else if kind == .multiplier {
            category = .multiplier
        } else {
            category = .plain
        }
        return NumberPresentation.format(v, category: category, notation: eff,
                                         precision: places, prefs: presentation,
                                         context: numberContext)
    }

    /// r87: the numeric `.number` branch — extracted so the row
    /// builder stays small enough to type-check. The value takes the
    /// row's effective notation; currency keeps ONE money string, the
    /// plain unit keeps the split value/unit runs (the pre-r87 pixel
    /// layout), semantic kinds render their ONE kinded string and the
    /// fraction kind its exact reduced shape.
    @ViewBuilder
    private func numberView(v: Double, unit: String?,
                            kind: NumericKind, fraction: NumlexCore.Rational?,
                            line: SheetLine, places: Int) -> some View {
        let eff = effectiveNotation(for: line.sourceLineIndex)
        // r57: an evaluated inline `total` row renders its value
        // semibold — same face, size and adaptive base color, only
        // the weight changes, and only for this row.
        let totalWeight: Font.Weight = line.isTotal ? .semibold : .regular
        if let u = unit, isCurrencyCode(u) {
            // Currency results render as ONE money string (`$600.00`,
            // `€107.64`) — symbol and value share the same dark-base
            // regular glyphs, no unit suffix.
            Text(NumberPresentation.formatMoney(v, code: u, notation: eff,
                                                prefs: presentation,
                                                context: numberContext))
                .font(palette.swiftUIFont(fontSize))
                .foregroundStyle(Color(nsColor: Design.baseText))
                .lineLimit(1)
        } else if kind == .duration, let u = unit {
            // A natural duration renders as its ONE semantic string (the
            // same string Copy Answer puts on the clipboard), in the same
            // typography as every other answer: no notation involvement, no
            // decimal-only fallback and the unit is never dropped.
            Text(kindedString(v: v, unit: u, kind: .duration,
                              fraction: fraction, eff: eff, places: places))
                .font(palette.swiftUIFont(fontSize, weight: totalWeight))
                .foregroundStyle(Color(nsColor: Design.baseText))
                .lineLimit(1)
        } else if kind == .plain, let u = unit {
            // r87: the value takes the row's effective notation; the
            // unit run is untouched (same size, weight and baseline as
            // the value — the split keeps the pre-r87 pixel layout for
            // the automatic default).
            let vStr = eff == .automatic
                ? formatDisplayValue(v, decimalPlaces: places, context: numberContext)
                : NumberPresentation.format(v, category: .plain, notation: eff,
                                            precision: places,
                                            prefs: presentation, context: numberContext)
            HStack(spacing: 5) {
                Text(vStr)
                    .font(palette.swiftUIFont(fontSize, weight: totalWeight))
                    // Every answer/result glyph is the fixed dark base
                    // (Design.baseText) regular on the light panel.
                    .foregroundStyle(Color(nsColor: Design.baseText))
                    .lineLimit(1)
                // Units are full answer content: exactly the same size,
                // weight and baseline as the value.
                Text(u)
                    .font(palette.swiftUIFont(fontSize, weight: totalWeight))
                    .foregroundStyle(Color(nsColor: Design.baseText))
            }
        } else {
            // r83: a semantic kind renders its ONE kinded string
            // (`40%`, `1/5`, `1.5x`); r87: non-automatic notations
            // re-format the numeric component while the fraction kind
            // keeps its exact reduced shape.
            let s = kindedString(v: v, unit: unit, kind: kind, fraction: fraction,
                                    eff: eff, places: places)
            Text(s)
                .font(palette.swiftUIFont(fontSize, weight: totalWeight))
                .foregroundStyle(Color(nsColor: Design.baseText))
                .lineLimit(1)
        }
    }
}

/// Thin AppKit bridge: every wheel event over the answer surface (begin,
/// continue, momentum, precise or line deltas) is forwarded verbatim to the
/// editor's scroll view through the coordinator. No manual delta
/// accumulation here, so momentum and elastic bounce match the editor's own
/// native behavior exactly.
/// One answer row: a fixed (width × height) frame whose content is placed
/// by MEASURED first-text baseline instead of SwiftUI's default vertical
/// centering. The content's own first-text-baseline guide
/// (`d[.firstTextBaseline]`, measured during layout) is aligned with a
/// zero-sized target whose guide sits exactly `baselineOffset` below the
/// row's top edge — so the text's baseline lands exactly on the TextKit
/// target baseline of the row's source line. No empirical offset and no
/// font-identity assumption: whatever baseline the subview actually has
/// is the one that gets aligned.
private struct BaselineAnswerRow: View {
    var width: CGFloat
    var height: CGFloat
    var baselineOffset: CGFloat
    var content: AnyView

    init(width: CGFloat, height: CGFloat, baselineOffset: CGFloat,
         @ViewBuilder content: () -> AnyView) {
        self.width = width
        self.height = height
        self.baselineOffset = baselineOffset
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: Alignment(horizontal: .leading, vertical: .answerBaseline)) {
            content
                .alignmentGuide(.answerBaseline) { d in d[.firstTextBaseline] }
            // Zero-sized target: its guide is exactly `baselineOffset`
            // below its top edge. Aligning the two guides puts the
            // content's first-text baseline on the row's target baseline;
            // the top edge of the combined box then coincides with the
            // row's top edge, so the outer frame needs no compensation.
            Color.clear
                .frame(width: 0, height: 0)
                .alignmentGuide(.answerBaseline) { _ in baselineOffset }
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }
}

extension VerticalAlignment {
    private struct AnswerBaseline: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.firstTextBaseline]
        }
    }

    /// Vertical alignment on a view's MEASURED first-text baseline
    /// (falls back to the platform default for views without text).
    static let answerBaseline = VerticalAlignment(AnswerBaseline.self)
}

/// r37: the source-answer hover outline — a near-full-width rounded
/// STROKE (no fill) centered on the answer's ink centerline. Pure
/// overlay: `allowsHitTesting(false)` keeps the wheel bridge and
/// double-tap path untouched; the geometry (center, one-line height)
/// comes from `AnswerBaseline.hoverOutline` — the same measured
/// baseline the answer text is placed on.
private struct AnswerHoverOutline: View {
    var width: CGFloat
    var centerY: CGFloat
    var height: CGFloat

    var body: some View {
        RoundedRectangle(
            cornerRadius: Design.answerHoverCornerRadius,
            style: .continuous
        )
        .stroke(
            Color(nsColor: Design.caretColor),
            lineWidth: Design.answerHoverLineWidth
        )
        .frame(
            width: width - Design.answerHoverEdgeInset * 2,
            height: height
        )
        .position(x: width / 2, y: centerY)
        .allowsHitTesting(false)
    }
}

/// r51: one retained NSMenuItem target — NSMenu does not retain targets,
/// so each built menu holds its holders on `representedObject`.
private final class MenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }
}

private struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (NSEvent) -> Void
    var onDoubleTap: ((CGFloat, Int) -> Void)?
    /// r51: content y (from the TOP, the row-geometry space) to the
    /// row's explicit source line index — the SAME mapping double-tap
    /// uses, so right-click after scroll/bounce hits the same row.
    var rowIndexAtY: ((CGFloat) -> Int?)?
    /// r51: the native menu for a source row (nil = no menu).
    var menuForRow: ((Int) -> NSMenu?)?

    init(onScroll: @escaping (NSEvent) -> Void,
         onDoubleTap: ((CGFloat, Int) -> Void)? = nil,
         rowIndexAtY: ((CGFloat) -> Int?)? = nil,
         menuForRow: ((Int) -> NSMenu?)? = nil) {
        self.onScroll = onScroll
        self.onDoubleTap = onDoubleTap
        self.rowIndexAtY = rowIndexAtY
        self.menuForRow = menuForRow
    }

    func makeNSView(context: Context) -> WheelView {
        let v = WheelView()
        v.onScroll = onScroll
        v.onDoubleTap = onDoubleTap
        v.rowIndexAtY = rowIndexAtY ?? { _ in nil }
        v.menuForRow = menuForRow
        // r77c: one-shot creation marker (hosted wrapper identity).
        Diagnostics.shared?.log("catcher.makeNSView")
        return v
    }

    func updateNSView(_ v: WheelView, context: Context) {
        v.onScroll = onScroll
        v.onDoubleTap = onDoubleTap
        v.rowIndexAtY = rowIndexAtY ?? { _ in nil }
        v.menuForRow = menuForRow
        // r62: keep the AppKit bounds in lockstep with the SwiftUI-
        // proposed full-size frame (the view is hosted to fill it).
        // A zero or stale size here would silently shrink the
        // double-tap/right-click hit surface to the last layout,
        // detaching it from the visible answers after any resize.
        if v.bounds.size == .zero, let sup = v.superview {
            v.frame = sup.bounds
        }
    }
    final class WheelView: NSView {
        /// r62: the hit surface must NEVER desync from the frame SwiftUI
        /// allocates to this view's hosting wrapper. SwiftUI re-lays-out
        /// the wrapper on window resizes, but an AppKit frame that was
        /// only set at first layout silently stays put — detaching the
        /// double-tap/right-click surface from the visible answers (the
        /// r62 regression). Filling the wrapper's bounds on every layout
        /// pass keeps them in lockstep for good.
        override func layout() {
            super.layout()
            if let sup = superview, frame != sup.bounds {
                frame = sup.bounds
                // r77c: frame lockstep events (the r62 desync class).
                Diagnostics.shared?.log(String(
                    "catcher.layout frame=\(Int(frame.width))x\(Int(frame.height)) "
                    + "sup=\(Int(sup.bounds.width))x\(Int(sup.bounds.height))"))
            }
        }

        var onScroll: (NSEvent) -> Void = { _ in }
        /// Double-clicks over the surface, reported as y from the TOP of
        /// the view (the row geometry the owner maps through).
        var onDoubleTap: ((CGFloat, Int) -> Void)?
        var rowIndexAtY: ((CGFloat) -> Int?) = { _ in nil }
        var menuForRow: ((Int) -> NSMenu?)?

        /// r51: right/context click pops the answer menu for the row
        /// under the cursor. No selection, focus, scrolling or token
        /// side effects: the event is consumed here and never reaches
        /// the editor. Clicks on hidden rows (or with no menu) fall
        /// through silently.
        override func rightMouseDown(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            let y = bounds.height - p.y
            let idxOpt = rowIndexAtY(y)
            let menuOpt = idxOpt.flatMap { menuForRow?($0) }
            Diagnostics.shared?.log(String(
                "catcher.rightMouseDown bounds=\(Int(bounds.width))x\(Int(bounds.height)) "
                + "win=\(window?.windowNumber ?? -1) key=\(window?.isKeyWindow ?? false) "
                + "yTop=\(Int(y)) row=\(idxOpt.map(String.init) ?? "nil") menu=\(menuOpt != nil)"))
            guard let idx = idxOpt,
                  let menu = menuOpt else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            self
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll(event)
        }

        override func mouseDown(with event: NSEvent) {
            // Invariant (AnswerDoubleClick.completesPair): a stationary
            // multi-click run counts 1, 2, 3, 4, ... — every positive
            // EVEN count completes one double-click pair, so an unbroken
            // run mints one token per pair (2, 4, 6, ...); odd counts
            // are pair starts and never fire. No per-pair double fire,
            // no timers racing the system doubleClickInterval.
            // r77c: full event record — did the click reach the catcher,
            // with what geometry, and what did it resolve to?
            let p = convert(event.locationInWindow, from: nil)
            let yTop = bounds.height - p.y
            let pair = AnswerDoubleClick.completesPair(at: event.clickCount)
            let row = rowIndexAtY(yTop)
            let rowDesc = row.map(String.init) ?? "nil"
            let msg = "catcher.mouseDown count=\(event.clickCount) pair=\(pair) "
                + "bounds=\(Int(bounds.width))x\(Int(bounds.height)) "
                + "win=\(window?.windowNumber ?? -1) attached=\(window != nil) "
                + "yTop=\(Int(yTop)) row=\(rowDesc)"
            Diagnostics.shared?.log(msg)
            guard pair, let cb = onDoubleTap else { return }
            cb(yTop, event.clickCount)
        }
    }
}
