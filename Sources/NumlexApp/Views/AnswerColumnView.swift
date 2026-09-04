import AppKit
import SwiftUI
import NumlexCore

struct AnswerColumnView: View {
    /// One indexed evaluated line per logical source line (strict 1:1
    /// contract from `evaluateSheet`); every rendered answer binds to its
    /// explicit `sourceLineIndex`, never to its position after filtering.
    var rows: [SheetLine]
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
    /// r21: the selected font design — answers use the centralized dark
    /// base token (Design.baseText) on the light panel, but the face must
    /// match the editor exactly (same resolver).
    var fontDesign: StylingFontDesign = .system
    var totalLabel: String
    /// r37: the source line whose answer is highlighted (a token
    /// capsule referencing it is hovered). Ephemeral; the outline is a
    /// pure stroke overlay — it never alters layout, row frames,
    /// baselines, hit testing or clipping.
    var highlightedSourceLineIndex: Int? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The result kinds a hovered token may highlight: exactly the
    /// answerable results the token-active semantics resolve to.
    /// Blank/title/skip/error/broken/date never outline.
    private func isHighlightable(_ result: LineResult) -> Bool {
        switch result {
        case .number, .variable, .money:
            return true
        case .blank, .skip, .title, .date, .brokenToken, .error:
            return false
        }
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

    private var summary: (value: String, unit: String?)? {
        let numeric = rows.compactMap { line -> Double? in
            if case .number(let v, let u) = line.result, u == nil { return v } else { return nil }
        }
        guard !numeric.isEmpty else { return nil }
        var sum = numeric.reduce(0, +)
        if sum.truncatingRemainder(dividingBy: 1) != 0 {
            sum = (sum * pow(10, Double(decimalPlaces))).rounded() / pow(10, Double(decimalPlaces))
        }
        // The shared overflow-safe formatter: an overflowing sum (inf)
        // can never trap here.
        return (formatDisplayValue(sum, decimalPlaces: decimalPlaces), nil)
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
                            AnyView(rowView(line.result))
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
                    ScrollWheelCatcher(
                        onScroll: onWheelScroll,
                        onDoubleTap: { y in
                            if let line = rowAt(y: y) {
                                switch line.result {
                                case .number, .variable, .money:
                                    // Money answers are tokenizable (their
                                    // tokens carry the ISO code); date
                                    // answers are never minted.
                                    onAnswerDoubleTap(line.sourceLineIndex)
                                default:
                                    break
                                }
                            }
                        }
                    )
                        .allowsHitTesting(true)
                        .frame(width: geo.size.width, alignment: .leading)
                }
            }
            .clipped()
            .frame(maxHeight: .infinity)

            if let s = summary {
                HStack(spacing: 8) {
                    Text(totalLabel)
                        .font(Design.labelSmall)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(s.value)
                        .font(palette.swiftUIFont(fontSize))
                        .foregroundStyle(Color(nsColor: Design.baseText))
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(8)
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
        .background {
            Color(nsColor: Design.answerPanelBackground).ignoresSafeArea(edges: .vertical)
        }
    }

    @ViewBuilder
    private func rowView(_ row: LineResult) -> some View {
        // Left-aligned content of one answer. Vertical placement is owned
        // by the BaselineAnswerRow layout (measured first-text baseline on
        // the editor's TextKit target baseline); this view only provides
        // the horizontal padding, the fixed dark-base (Design.baseText)
        // regular typography and the single-line clipping.
        Group {
            switch row {
            case .blank, .skip, .title(_):
                Color.clear
            case .number(let v, let unit):
                if let u = unit, isCurrencyCode(u) {
                    // Currency results render as ONE money string
                    // (`$600.00`, `€107.64`) — symbol and value share
                    // the same dark-base regular glyphs, no unit suffix.
                    Text(formatMoney(v, code: u))
                        .font(palette.swiftUIFont(fontSize))
                        .foregroundStyle(Color(nsColor: Design.baseText))
                        .lineLimit(1)
                } else {
                    HStack(spacing: 5) {
                        Text(formatDisplayValue(v, decimalPlaces: decimalPlaces))
                            .font(palette.swiftUIFont(fontSize))
                            // Every answer/result glyph is the fixed dark
                            // base (Design.baseText) regular on the light
                            // panel, per the r36 light theme.
                            .foregroundStyle(Color(nsColor: Design.baseText))
                            .lineLimit(1)
                        if let u = unit {
                            // Units are full answer content: exactly the
                            // same size, weight and baseline as the value.
                            Text(u)
                                .font(palette.swiftUIFont(fontSize))
                                .foregroundStyle(Color(nsColor: Design.baseText))
                        }
                    }
                }
            case .money(let v, let code):
                // Natural money: shared presentation (`$600.00`),
                // dark-base regular, never enters the numeric Total.
                Text(formatMoney(v, code: code))
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
            case .variable(_, let v):
                // Assignment rows show ONLY the value — the name and
                // equals sign live in the editor, never in the answers.
                Text(formatDisplayValue(v, decimalPlaces: decimalPlaces))
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
                if msg == "Rates unavailable" {
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
        // Symmetric row insets; no invisible scroller reservation — the
        // column has no scroll bar of its own.
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (NSEvent) -> Void
    var onDoubleTap: ((CGFloat) -> Void)?

    init(onScroll: @escaping (NSEvent) -> Void, onDoubleTap: ((CGFloat) -> Void)? = nil) {
        self.onScroll = onScroll
        self.onDoubleTap = onDoubleTap
    }

    func makeNSView(context: Context) -> WheelView {
        let v = WheelView()
        v.onScroll = onScroll
        v.onDoubleTap = onDoubleTap
        return v
    }

    func updateNSView(_ v: WheelView, context: Context) {
        v.onScroll = onScroll
        v.onDoubleTap = onDoubleTap
    }

    final class WheelView: NSView {
        var onScroll: (NSEvent) -> Void = { _ in }
        /// Double-clicks over the surface, reported as y from the TOP of
        /// the view (the row geometry the owner maps through).
        var onDoubleTap: ((CGFloat) -> Void)?

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
            guard AnswerDoubleClick.completesPair(at: event.clickCount),
                  let cb = onDoubleTap else { return }
            let p = convert(event.locationInWindow, from: nil)
            cb(bounds.height - p.y)
        }
    }
}
