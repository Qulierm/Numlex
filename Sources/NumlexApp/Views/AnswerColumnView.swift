import SwiftUI
import NumlexCore

struct AnswerColumnView: View {
    var rows: [LineResult]
    var metrics: LineMetrics
    /// Shared scroll state: top-down points scrolled from the top of the
    /// document. The editor is the primary surface; this column renders its
    /// rows at `offset(y: -topOffset)` so both stay pixel-exact 1:1.
    var topOffset: CGFloat
    /// Raw wheel events over the answer surface are forwarded verbatim to
    /// the editor's scroll view (phases, momentum, precise deltas intact),
    /// so the editor remains the single native scroll source.
    var onWheelScroll: (NSEvent) -> Void
    /// Editor coordinator for the trailing edge scroller bridge.
    var scrollerCoordinator: NotebookEditorCoordinator?
    /// Knob drag / scroller wheel → shared offset.
    var onScrollerDrag: (CGFloat) -> Void
    var fontSize: Double
    var lineHeight: Double
    var decimalPlaces: Int
    var totalLabel: String

    private func rowGeometry(_ index: Int) -> (top: CGFloat, height: CGFloat) {
        // Row frames are expressed in the same coordinates as the editor
        // content: the editor's text starts editorTopInset below the shared
        // column top, so both columns use the same mapping.
        NotebookLayout.answerRow(
            index: index,
            lines: metrics.lines,
            topInset: Design.editorTopInset
        )
    }

    private func formatted(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.groupingSeparator = ","
            f.locale = Locale(identifier: "en_US")
            return f.string(from: NSNumber(value: Int64(value))) ?? "\(Int64(value))"
        }
        var s = String(format: "%.\(decimalPlaces)f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private var summary: (value: String, unit: String?)? {
        let numeric = rows.compactMap { r -> Double? in
            if case .number(let v, let u) = r, u == nil { return v } else { return nil }
        }
        guard !numeric.isEmpty else { return nil }
        var sum = numeric.reduce(0, +)
        if sum.truncatingRemainder(dividingBy: 1) != 0 {
            sum = (sum * pow(10, Double(decimalPlaces))).rounded() / pow(10, Double(decimalPlaces))
        }
        return (formatted(sum), nil)
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
                VStack(spacing: 0) {
                    Color.clear.frame(height: Design.editorTopInset)
                    ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                        let geo2 = rowGeometry(idx)
                        rowView(row)
                            .frame(height: geo2.height)
                    }
                    Color.clear.frame(height: 80)
                }
                .offset(y: -topOffset)
                // Clamp to the visible content region first, so the overlays
                // below size to the region (not the intrinsic content height)
                // and never bleed over the summary bar.
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .overlay(alignment: .leading) {
                    // The wheel catcher covers the content except the 15pt
                    // strip reserved for the trailing edge scroller.
                    ScrollWheelCatcher(onScroll: onWheelScroll)
                        .allowsHitTesting(true)
                        .frame(width: geo.size.width - 15, alignment: .leading)
                }
                // The single native scrollbar, pinned to the absolute
                // trailing edge of the detail area (the answer column is the
                // rightmost pane). Sits above the summary bar, so it never
                // overlaps the Total row.
                .overlay(alignment: .trailing) {
                    EdgeScroller(
                        coordinator: scrollerCoordinator,
                        topOffset: topOffset,
                        viewport: geo.size.height,
                        onOffset: onScrollerDrag
                    )
                    .frame(width: 15)
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
                        .font(Design.body(fontSize))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .padding(8)
            }
        }
        .frame(width: 200)
        // Subtly distinct, system-aware panel: the native window background
        // (light gray in light mode, lifted charcoal in dark) versus the
        // editor's text background. Calm, low contrast, no custom tint.
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(width: 1), alignment: .leading)
    }

    @ViewBuilder
    private func rowView(_ row: LineResult) -> some View {
        // Left-aligned content inside a row frame whose height equals the
        // logical expression block; the content is vertically centered by
        // the frame, so wrapped 2–3 line expressions get a centered answer.
        Group {
            switch row {
            case .blank, .skip, .title(_):
                Color.clear
            case .number(let v, let unit):
                HStack(spacing: 5) {
                    Text(formatted(v))
                        .font(Design.body(fontSize))
                        // Every answer/result glyph is fixed white
                        // regular, per the design request.
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let u = unit {
                        // Units are full answer content: exactly the
                        // same size, weight and baseline as the value.
                        Text(u)
                            .font(Design.body(fontSize))
                            .foregroundStyle(.white)
                    }
                }
            case .variable(let name, let v):
                HStack(spacing: 5) {
                    Text(name)
                        .font(Design.body(fontSize))
                        .foregroundStyle(.white)
                    Text("=")
                        .font(Design.body(fontSize))
                        .foregroundStyle(.white)
                    Text(formatted(v))
                        .font(Design.body(fontSize))
                        .foregroundStyle(.white)
                }
            case .error(let msg):
                if msg == "Rates unavailable" {
                    // The explicit no-rate state is preserved and
                    // rendered fixed white.
                    Text("Rates unavailable")
                        .font(Design.labelSmall)
                        .foregroundStyle(.white)
                } else {
                    // Generic calculation errors render nothing at all
                    // (no "Error" label), leaving the row quiet white-on-
                    // background while the expression above carries its
                    // lexical spans.
                    Color.clear
                }
            }
        }
        .lineLimit(1)
        .padding(.leading, 20)
        // Keep long values clear of the 15pt edge scroller.
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Thin AppKit bridge: every wheel event over the answer surface (begin,
/// continue, momentum, precise or line deltas) is forwarded verbatim to the
/// editor's scroll view through the coordinator. No manual delta
/// accumulation here, so momentum and elastic bounce match the editor's own
/// native behavior exactly.
private struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (NSEvent) -> Void

    func makeNSView(context: Context) -> WheelView {
        let v = WheelView()
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ v: WheelView, context: Context) {
        v.onScroll = onScroll
    }

    final class WheelView: NSView {
        var onScroll: (NSEvent) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? {
            self
        }

        override func scrollWheel(with event: NSEvent) {
            onScroll(event)
        }
    }
}
