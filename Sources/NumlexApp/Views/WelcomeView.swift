import SwiftUI
import NumlexCore

/// r98: the first-launch welcome — a native "calculation bloom".
///
/// Ten short calculations in the REAL editor palette stream into place
/// around the app icon, gather into it in batches, and the icon answers
/// with a one-shot MONOCHROME silver splash (radial rays, a soft expanding
/// wave and a few droplets) drawn only from neutral/icon tones. The
/// localized **Get Started** button is monochrome too — silver on Dark,
/// graphite on Light — so nothing competes with the icon.
///
/// The splash then settles into the calm final lockup: a larger icon, the
/// official slogan and the monochrome button, tightly balanced on the same
/// neutral tones.
///
/// It REPLACES the main content until the user starts (nothing from the
/// editor, sidebar or TextKit exists behind it) and keeps the native window
/// chrome and the app's window geometry.
struct WelcomeView: View {
    let language: AppLanguage
    /// Activation begins the reveal (marks completion + mounts the editor
    /// beneath the curtain). The parent owns the actual transition.
    let onGetStarted: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // One-shot staged state. Only opacity/offset/scale/rotation/trim change;
    // every final frame exists from the first layout pass.
    @State private var iconRevealed = false
    /// The icon's spatial entrance: 0 = turned away in shallow depth,
    /// 1 = flat. Interpolated by SwiftUI (a plain Double, not a Bool edge).
    @State private var iconEntry: Double = 0
    // r101: ONE finite scalar per batched pass. The calculation field and
    // the silver splash are each drawn by a single Canvas from these
    // values, so the whole transient animation costs three (field) plus
    // two (splash) animation transactions instead of ~90 per-view ones.
    @State private var streamProgress: Double = 0
    @State private var emphasisProgress: Double = 0
    @State private var convergeProgress: Double = 0
    @State private var burstProgress: Double = 0
    @State private var fadeProgress: Double = 0
    /// Both Canvases leave the hierarchy for good once their pass is over,
    /// so the settled final scene draws nothing transient at all.
    @State private var fieldActive = true
    @State private var splashActive = true
    @State private var pulsed = false
    @State private var sheenProgress: CGFloat = -1.2
    /// Set at the splash finish: the icon grows from its ~110 pt streaming
    /// footprint to the large final frame (scale only — never a frame or
    /// layout change, so nothing else can reflow).
    @State private var iconExpanded = false
    @State private var sloganRevealed = false
    @State private var buttonRevealed = false
    @State private var activating = false
    @FocusState private var buttonFocused: Bool

    /// The design canvas the composition is laid out on; the field scales
    /// (never clips) when the window is smaller than this.
    static let canvas = CGSize(width: 800, height: 600)

    var body: some View {
        GeometryReader { geo in
            // ONE fixed 800x600 design canvas, scaled as a whole. Every
            // element is placed at a fixed canvas coordinate with
            // `.position`, so an element can never move another one and
            // nothing clips at the minimum window geometry.
            let scale = min(1, min(geo.size.width / Self.canvas.width,
                                   geo.size.height / Self.canvas.height))
            ZStack {
                Color(nsColor: Design.editorBackground)

                if fieldActive {
                    CalculationBloomCanvas(stream: streamProgress,
                                           emphasis: emphasisProgress,
                                           converge: convergeProgress,
                                           scale: scale,
                                           iconOffset: Self.iconCanvasOffset.height)
                }
                if splashActive {
                    // The footprint travels with the icon's growth, so the
                    // burst never jumps at the expansion edge.
                    SilverSplashCanvas(
                        burst: burstProgress,
                        fade: fadeProgress,
                        footprint: Self.preFinishIconScale
                            + (1 - Self.preFinishIconScale) * fadeProgress,
                        scale: scale,
                        iconOffset: Self.iconCanvasOffset.height)
                }
                icon(scale: scale)
                slogan(scale: scale)
                button(scale: scale)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .task { await bloom() }
    }

    /// The icon's FINAL frame (logical pt on the 800x600 canvas). It is the
    /// frame from the very first layout pass; only the visual scale changes.
    static let finalIconSize: CGFloat = 176
    /// The icon's rounded corner, kept proportional to the final frame.
    static let iconCornerRadius: CGFloat = 34

    /// While the calculations stream, the icon renders at the old ~110 pt
    /// footprint (110 / 152 of the final frame) and grows to full size once
    /// the silver splash settles.
    static let preFinishIconScale: CGFloat = 110 / finalIconSize

    /// One restrained pulse during the splash, combined deterministically
    /// (never additive) with the streaming and expansion scales.
    static let pulseScale: CGFloat = 1.04

    /// The icon's anchor in canvas coordinates (47 pt above centre).
    static let iconCanvasOffset = CGSize(width: 0, height: -47)

    /// The official slogan — exact wording, curly apostrophe, trailing
    /// period. It is the ONE canonical constant (display and accessibility
    /// both derive from it), revealed last, never before the splash.
    static let sloganPhrase = "Think freely. We\u{2019}ll do the math."

    /// The slogan's anchor, between the icon and the button (the taller
    /// two-line lockup sits a touch lower, and the button follows).
    static let sloganCanvasOffset = CGSize(width: 0, height: 112)

    /// The two-line lockup: line 1 (rounded + serif italic) 31-34 pt,
    /// line 2 (rounded + monospaced) 24-28 pt.
    static let sloganLineOneSize: CGFloat = 38
    static let sloganLineTwoSize: CGFloat = 30
    /// The gap between the two lines (2-5 pt).
    static let sloganLineSpacing: CGFloat = 4

    /// The slogan's reserved frame: it is laid out from the first pass, so
    /// revealing it can never reflow the icon or the button.
    static let sloganReservedWidth: CGFloat = 680
    static let sloganReservedHeight: CGFloat = 94

    /// The button's anchor, below the slogan.
    static let buttonCanvasOffsetY: CGFloat = 218

    /// Canvas offset (from the canvas centre) scaled to the live window.
    /// The composition is expressed purely as OFFSETS inside the flexible
    /// ZStack: `.position`-style placements make the ZStack report an
    /// unbounded ideal size, which `.windowResizability(.contentSize)`
    /// would then apply to the window itself. Offsets never do that.
    private static func scaled(_ offset: CGSize, _ scale: CGFloat) -> CGSize {
        CGSize(width: offset.width * scale, height: offset.height * scale)
    }

    // MARK: - Calculation field (Task 1)

    /// Ten correct, compact calculations in two airy columns of five. Each
    /// row is a sequence of typographic runs whose colors come from the
    /// editor palette, so the field matches the notebook in every theme.
    static let calculations: [BloomExpression] = [
        // Left column.
        .init(column: .left, slot: 0,
              tokens: [.number("128"), .op(" × "), .number("4"), .op(" = "), .number("512")],
              resultIndices: [4]),
        .init(column: .left, slot: 1,
              tokens: [.number("18"), .unit("%"), .op(" of "), .number("240"),
                       .op(" = "), .number("43.2")],
              resultIndices: [5]),
        .init(column: .left, slot: 2,
              tokens: [.number("3.5"), .op(" "), .unit("km"), .op(" → "),
                       .number("3500"), .op(" "), .unit("m")],
              resultIndices: [4, 5]),
        .init(column: .left, slot: 3,
              tokens: [.number("2"), .unit("h"), .op(" "), .number("15"), .unit("m"),
                       .op(" + "), .number("45"), .unit("m"), .op(" = "),
                       .number("3"), .unit("h")],
              resultIndices: [8, 9, 10]),
        .init(column: .left, slot: 4,
              tokens: [.op("√"), .number("144"), .op(" = "), .number("12")],
              resultIndices: [3]),
        // Right column.
        .init(column: .right, slot: 0,
              tokens: [.variable("price"), .op(" = "), .number("24")],
              resultIndices: [2]),
        .init(column: .right, slot: 1,
              tokens: [.money("$"), .number("42"), .op(" + "), .money("$"),
                       .number("18"), .op(" = "), .money("$"), .number("60")],
              resultIndices: [6, 7]),
        .init(column: .right, slot: 2,
              tokens: [.number("12"), .op(" "), .unit("kg"), .op(" ÷ "),
                       .number("3"), .op(" = "), .number("4"), .op(" "), .unit("kg")],
              resultIndices: [6, 7, 8]),
        .init(column: .right, slot: 3,
              tokens: [.number("2"), .op("^"), .number("10"), .op(" = "), .number("1024")],
              resultIndices: [4]),
        .init(column: .right, slot: 4,
              tokens: [.number("9"), .op(" "), .unit("ft"), .op(" → "),
                       .number("2.74"), .op(" "), .unit("m")],
              resultIndices: [4, 5]),
    ]

    /// Column anchor + vertical slot → a fixed canvas position. Rows are
    /// laid out on a stable grid: no row can move another one.
    static func anchor(for expression: BloomExpression) -> CGPoint {
        let x: CGFloat = expression.column == .left ? -238 : 238
        let y: CGFloat = -118 + CGFloat(expression.slot) * 59
        return CGPoint(x: x, y: y)
    }

    /// ONE Canvas draws every transient calculation. The old field was ten
    /// rows of five-to-eleven independently animated `Text` views (each with
    /// its own animation transaction, offset, scale and blur shadow) — the
    /// measured dominant cost. Now a single draw pass per frame produces the
    /// same picture from three finite scalars:
    ///
    /// The transient field is drawn by `CalculationBloomCanvas`, the burst by
    /// `SilverSplashCanvas` (both `Animatable`, see WelcomeRenderers.swift).

    // MARK: - Silver splash (Task 2)

    /// Silver reads as near-white on Dark and graphite on Light — derived
    /// from the icon family / label tones, never from palette hues.
    private var silver: Color { Color(nsColor: Design.baseText) }
    private var silverSoft: Color { Color(nsColor: .secondaryLabelColor) }

    /// The splash follows the icon's own footprint: the streaming size while
    /// the calculations are visible, full size once the icon has grown.

    private func icon(scale: CGFloat) -> some View {
        Group {
            if let image = AppIconResources.previewImage(for: .dark) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(
                        Image(systemName: "app.dashed")
                            .font(.system(size: 34))
                            .foregroundStyle(.secondary)
                    )
            }
        }
        // ONE fixed final frame from the first layout pass: the icon never
        // resizes, and nothing around it can be pushed.
        .frame(width: Self.finalIconSize, height: Self.finalIconSize)
        .overlay(sheen)
        .clipShape(RoundedRectangle(cornerRadius: Self.iconCornerRadius, style: .continuous))
        // No shadow here: an animated halo forces a fresh offscreen blur
        // every frame and measurably cost cadence (p95 16 -> 39 ms), so the
        // depth comes from the tilt, the scale and the burst's own glow.
        .rotation3DEffect(.degrees(6.5 * (1 - iconEntry)),
                          axis: (x: 0.7, y: 0.5, z: 0),
                          perspective: 0.7)
        .scaleEffect(iconVisualScale)
        .opacity(iconRevealed ? 1 : 0)
        .scaleEffect(scale, anchor: .center)
        .offset(y: Self.iconCanvasOffset.height * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Numlex"))
        .animation(.easeOut(duration: 0.35), value: iconRevealed)
        .animation(.easeInOut(duration: 0.20), value: pulsed)
        .animation(.easeOut(duration: 0.55), value: iconExpanded)
    }

    /// The icon's ONE visual scale: streaming footprint, the single splash
    /// pulse and the final expansion multiplied together — never added, so
    /// the pulse and the growth can never fight or overshoot.
    private var iconVisualScale: CGFloat {
        guard iconRevealed else { return 0.88 * Self.preFinishIconScale }
        let base = iconExpanded ? 1 : Self.preFinishIconScale
        return pulsed ? base * Self.pulseScale : base
    }

    // MARK: - Final slogan (Task 2)

    /// The slogan is revealed LAST, after the splash has settled. It is
    /// monochrome (the same neutral as the icon family), one line, with the
    /// two clauses sharing a baseline; it is never hit-testable but is
    /// announced once as a heading with the exact official wording.
    private func slogan(scale: CGFloat) -> some View {
        VStack(spacing: Self.sloganLineSpacing) {
            sloganLineOne
            sloganLineTwo
        }
        .multilineTextAlignment(.center)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: Self.sloganReservedWidth, height: Self.sloganReservedHeight)
        // The WHOLE lockup moves as one composited view: a single opacity +
        // rise, never per-glyph or per-run animation.
        .opacity(sloganRevealed ? 1 : 0)
        .offset(y: Self.sloganCanvasOffset.height * scale
                  + (sloganRevealed ? 0 : 9))
        .scaleEffect(scale, anchor: .center)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.sloganPhrase))
        .accessibilityAddTraits(.isHeader)
        .accessibilityHidden(!sloganRevealed)
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.50), value: sloganRevealed)
    }

    /// Line 1 — standard SF proportional ("Think ") followed by an elegant
    /// serif italic ("freely."). Monochrome: the icon family's own neutral.
    private var sloganLineOne: Text {
        Text("Think ")
            .font(.system(size: Self.sloganLineOneSize, weight: .bold, design: .default))
            .foregroundStyle(Color(nsColor: Design.baseText))
        + Text("freely.")
            .font(.system(size: Self.sloganLineOneSize, weight: .semibold, design: .serif))
            .italic()
            .foregroundStyle(Color(nsColor: Design.baseText))
    }

    /// Line 2 — a quiet clause in STANDARD SF proportional type ("We’ll do
    /// the ") answered by a compact monospaced ("math."). Still monochrome:
    /// the quiet clause uses the secondary label tone, the key word the
    /// bright icon neutral.
    private var sloganLineTwo: Text {
        // Standard SF proportional type (NOT rounded): the rounded face read
        // as a mismatched, over-soft clause against the monospaced accent.
        Text("We’ll do the ")
            .font(.system(size: Self.sloganLineTwoSize, weight: .regular, design: .default))
            .tracking(0.2)
            .foregroundStyle(Color(nsColor: .secondaryLabelColor))
        + Text("math.")
            .font(.system(size: Self.sloganLineTwoSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(nsColor: Design.baseText))
    }

    /// A single silver sheen pass across the icon (icon-masked).
    private var sheen: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, silver.opacity(0.55), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: geo.size.width * 0.34)
                .rotationEffect(.degrees(24))
                .offset(x: sheenProgress * geo.size.width * 1.7)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Button (Task 3)

    private func button(scale: CGFloat) -> some View {
        GetStartedButton(language: language,
                         enabled: !activating,
                         action: activate)
            .scaleEffect(scale, anchor: .center)
            .offset(y: Self.buttonCanvasOffsetY * scale
                      + (buttonRevealed ? 0 : 10))
            .opacity(buttonRevealed ? 1 : 0)
            .focused($buttonFocused)
            .allowsHitTesting(buttonRevealed && !activating)
            .accessibilityHidden(!buttonRevealed)
            .animation(.easeOut(duration: 0.40), value: buttonRevealed)
    }

    // MARK: - One-shot choreography (~2.8 s total)

    private func bloom() async {
        if reduceMotion {
            // Static final state, immediately: no stream, no splash, no
            // sleeps and no animation — large icon + slogan + button, with
            // the button focused.
            iconRevealed = true
            iconEntry = 1
            iconExpanded = true
            sloganRevealed = true
            buttonRevealed = true
            buttonFocused = true
            // No Canvas, no progress, no ticker: the field and the splash
            // never exist in the Reduce Motion presentation.
            fieldActive = false
            splashActive = false
            return
        }
        // 0.00–0.45 the icon turns into place from a shallow depth (a small
        // 3D settle that lands flat) while it fades and scales in.
        withAnimation(.easeOut(duration: 0.45)) { iconRevealed = true; iconEntry = 1 }
        // 0.14–1.1 the calculations stream in (row + token stagger, all
        // derived inside the ONE field Canvas from this single scalar).
        try? await Task.sleep(nanoseconds: 140_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.96)) { streamProgress = 1 }
        // 0.62–0.95 the result runs brighten once.
        try? await Task.sleep(nanoseconds: 480_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.33)) { emphasisProgress = 1 }
        // 0.95–1.45 gather into the icon in two tight batches.
        try? await Task.sleep(nanoseconds: 330_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.52)) { convergeProgress = 1 }
        // 1.30–1.75 the monochrome silver splash.
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        withAnimation { pulsed = true }
        withAnimation(.easeOut(duration: 0.46)) { burstProgress = 1 }
        withAnimation(.easeInOut(duration: 0.34)) { sheenProgress = 1.2 }
        try? await Task.sleep(nanoseconds: 340_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.30)) { fadeProgress = 1 }
        withAnimation(.easeInOut(duration: 0.18)) { pulsed = false }
        // 1.64–2.19 the icon grows from the streaming footprint (110 pt) to
        // the large final frame (152 pt) on one restrained ease. This
        // overlaps the fading tail of the splash.
        withAnimation(.easeOut(duration: 0.55)) { iconExpanded = true }
        // The field has drawn nothing since the convergence finished: retire
        // it on this quiet turn, before any later animation starts.
        await Task.yield()
        fieldActive = false
        // 1.74–2.24 the slogan fades in with a short rise, in its reserved
        // frame: nothing else moves.
        try? await Task.sleep(nanoseconds: 100_000_000)
        if Task.isCancelled { return }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.50)) { sloganRevealed = true }
        // 2.04–2.44 the button fades/rises BELOW the slogan; the keyboard
        // focus arrives only after that fade has fully settled (2.48).
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.40)) { buttonRevealed = true }
        // The focus handoff happens only AFTER the button's opacity/rise has
        // fully settled (0.40 s fade + slack): acquiring focus can cost a
        // frame, and that cost must never land inside a visible animation.
        try? await Task.sleep(nanoseconds: 440_000_000)
        if Task.isCancelled { return }
        // Every visible animation has settled: now the (already blank) splash
        // canvas can leave the hierarchy and the keyboard can be handed over.
        splashActive = false
        buttonFocused = true
    }

    /// One guarded activation: the parent marks completion, mounts the
    /// editor beneath this panel and slides the curtain away.
    private func activate() {
        guard !activating else { return }
        activating = true
        onGetStarted()
    }
}

// MARK: - Model

enum BloomColumn { case left, right }

/// One typographic run in an expression. `text` carries its own spacing so
/// the row reads exactly like a line of the notebook.
struct BloomToken {
    let text: String
    let color: NSColor
    let weight: Font.Weight

    static func number(_ s: String) -> BloomToken {
        BloomToken(text: s, color: Design.numberColor, weight: .medium)
    }
    static func op(_ s: String) -> BloomToken {
        BloomToken(text: s, color: Design.baseText, weight: .regular)
    }
    static func variable(_ s: String) -> BloomToken {
        BloomToken(text: s, color: Design.variableColor, weight: .medium)
    }
    static func unit(_ s: String) -> BloomToken {
        BloomToken(text: s, color: Design.conversionColor, weight: .medium)
    }
    static func money(_ s: String) -> BloomToken {
        BloomToken(text: s, color: Design.moneyMarkerColor, weight: .semibold)
    }
}

struct BloomExpression {
    let column: BloomColumn
    let slot: Int
    let tokens: [BloomToken]
    /// Indices of the runs that are the RESULT (brightened once).
    let resultIndices: [Int]
}

/// The ONE primary action, monochrome to match the icon: silver with a
/// near-black label on Dark, graphite with a white label on Light. It keeps
/// native focus visibility and keyboard activation.
private struct GetStartedButton: View {
    let language: AppLanguage
    let enabled: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Bool
    @State private var hovering = false

    /// The fill IS the icon family's dominant tone: near-white silver in
    /// Dark (Design.baseText = 255,255,255 there) and graphite in Light
    /// (Design.baseText = 28,28,30 there). No accent hue is involved.
    private var fill: Color { Color(nsColor: Design.baseText) }

    /// The label is the opposite end of the same pair: near-black on the
    /// Dark silver fill, white/silver on the Light graphite fill.
    private var label: Color { Color(nsColor: Design.editorBackground) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(L10n.t("welcome.getStarted", language: language))
                    .font(.system(size: 15, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(label)
            .padding(.vertical, 11)
            .padding(.horizontal, 22)
            .frame(minWidth: 196)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6),
                                          lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 0.94 : 1)
        .scaleEffect(hovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? Color(nsColor: .keyboardFocusIndicatorColor)
                              : Color.clear,
                              lineWidth: 2.5)
                .padding(1)
                .allowsHitTesting(false)
        )
        .focused($focused)
        .focusable()
        .focusEffectDisabled()
        .disabled(!enabled)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(Text(L10n.t("welcome.getStarted", language: language)))
        .accessibilityHint(Text(L10n.t("welcome.getStartedHint", language: language)))
    }
}
