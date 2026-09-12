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
    @State private var tokensRevealed = false
    @State private var emphasized = false
    @State private var converged = false
    @State private var splashBurst = false
    @State private var splashFaded = false
    @State private var waveProgress: CGFloat = 0
    @State private var waveFaded = false
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

                calculationField(scale: scale)
                splash(scale: scale)
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
    static let finalIconSize: CGFloat = 152

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

    /// The slogan's anchor, between the icon and the button.
    static let sloganCanvasOffset = CGSize(width: 0, height: 96)

    /// ~27 pt on the 800x600 canvas (the brief asks for 25-30).
    static let sloganFontSize: CGFloat = 27

    /// The slogan's reserved width: it is laid out from the first pass, so
    /// revealing it can never reflow the icon or the button.
    static let sloganReservedWidth: CGFloat = 620

    /// The button's anchor, below the slogan.
    static let buttonCanvasOffsetY: CGFloat = 183

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

    private func calculationField(scale: CGFloat) -> some View {
        ZStack {
            ForEach(Array(Self.calculations.enumerated()), id: \.offset) { index, expression in
                let anchor = Self.anchor(for: expression)
                expressionRow(expression, index: index)
                    .scaleEffect(scale, anchor: .center)
                    .offset(x: anchor.x * scale, y: anchor.y * scale)
                    // Gather into the icon (batched per column/slot), then
                    // disappear: no row survives into the calm final state.
                    .scaleEffect(converged ? 0.5 : 1, anchor: .center)
                    .opacity(converged ? 0 : 1)
                    .offset(x: anchor.x * (converged ? -0.55 : 0),
                            y: anchor.y * (converged ? -0.45 : 0))
                    .animation(.easeInOut(duration: 0.34)
                        .delay(converged ? Self.batchDelay(expression) : 0),
                               value: converged)
            }
        }
        .accessibilityHidden(true)
    }

    /// Two tight batches (left column, then right column) with a small
    /// per-row stagger inside each.
    private static func batchDelay(_ expression: BloomExpression) -> Double {
        let columnBase: Double = expression.column == .left ? 0 : 0.09
        return columnBase + Double(expression.slot) * 0.025
    }

    private func expressionRow(_ expression: BloomExpression, index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(expression.tokens.enumerated()), id: \.offset) { tokenIndex, token in
                tokenText(token, emphasized: emphasized && expression.resultIndices.contains(tokenIndex))
                    .opacity(tokensRevealed ? 1 : 0)
                    .offset(y: tokensRevealed ? 0 : 5)
                    .scaleEffect(tokensRevealed ? 1 : 0.97)
                    // Stream: a small per-row offset plus a per-token stagger.
                    .animation(.easeOut(duration: 0.22)
                        .delay(tokensRevealed
                               ? 0.14 + Double(index) * 0.035 + Double(tokenIndex) * 0.022
                               : 0),
                               value: tokensRevealed)
                    .animation(.easeOut(duration: 0.16)
                        .delay(emphasized ? 0.62 + Double(index) * 0.022 : 0),
                               value: emphasized)
            }
        }
        .shadow(color: emphasized
                ? Color(nsColor: Design.baseText).opacity(0.30)
                : Color(nsColor: Design.baseText).opacity(0.14),
                radius: emphasized ? 7 : 2)
    }

    /// One typographic run, resolved from the app's own editor palette.
    @ViewBuilder
    private func tokenText(_ token: BloomToken, emphasized: Bool) -> some View {
        Text(token.text)
            .font(.system(size: 16, weight: token.weight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color(nsColor: token.color))
            .scaleEffect(emphasized ? 1.06 : 1)
            .animation(.easeOut(duration: 0.16), value: emphasized)
    }

    // MARK: - Silver splash (Task 2)

    /// Silver reads as near-white on Dark and graphite on Light — derived
    /// from the icon family / label tones, never from palette hues.
    private var silver: Color { Color(nsColor: Design.baseText) }
    private var silverSoft: Color { Color(nsColor: .secondaryLabelColor) }

    /// 14 deterministic rays: varied length and delay, fixed values only.
    private static let rays: [(angle: Double, length: CGFloat, delay: Double, width: CGFloat)] = [
        (8, 96, 0.00, 2.5), (32, 72, 0.02, 1.5), (56, 88, 0.04, 2.0),
        (80, 64, 0.03, 1.5), (104, 92, 0.05, 2.5), (128, 70, 0.01, 1.5),
        (152, 86, 0.04, 2.0), (176, 66, 0.02, 1.5), (200, 94, 0.05, 2.5),
        (224, 74, 0.03, 1.5), (248, 84, 0.01, 2.0), (272, 62, 0.04, 1.5),
        (296, 90, 0.02, 2.5), (320, 76, 0.05, 1.5),
    ]

    /// 8 droplets placed on a fixed deterministic ring.
    private static let droplets: [(angle: Double, radius: CGFloat, size: CGFloat, delay: Double)] = [
        (20, 100, 3.5, 0.02), (66, 116, 2.5, 0.05), (112, 96, 3.0, 0.03),
        (158, 112, 2.0, 0.06), (204, 102, 3.5, 0.04), (250, 118, 2.5, 0.02),
        (296, 98, 3.0, 0.05), (342, 114, 2.0, 0.03),
    ]

    /// Rays start just outside the icon: 79 pt is the FINAL icon's half-size
    /// (76) plus a hair, and the whole splash is drawn at the icon's own
    /// pre-finish scale while the calculations are streaming, so the rays
    /// emerge from behind the icon at BOTH sizes instead of floating
    /// disconnected from the small one or being swallowed by the large one.
    private static let rayOriginRadius: CGFloat = 79

    private func splash(scale: CGFloat) -> some View {
        ZStack {
            // Soft expanding wave.
            Circle()
                .stroke(silverSoft.opacity(waveFaded ? 0 : 0.45), lineWidth: 1.5)
                .frame(width: 186, height: 186)
                .scaleEffect(waveProgress == 0 ? 0.55 : 0.55 + waveProgress * 1.4)
                .opacity(waveFaded ? 0 : min(1, waveProgress * 2) * (1 - waveProgress * 0.55))

            // Fine radial rays.
            ForEach(Array(Self.rays.enumerated()), id: \.offset) { _, ray in
                Capsule()
                    .fill(silver.opacity(splashFaded ? 0 : 0.75))
                    .frame(width: ray.width, height: ray.length)
                    .offset(y: -ray.length / 2 - Self.rayOriginRadius)
                    .rotationEffect(.degrees(ray.angle))
                    .scaleEffect(splashBurst ? 1 : 0.35, anchor: .bottom)
                    .opacity(splashFaded ? 0 : 1)
                    .animation(.easeOut(duration: 0.42).delay(ray.delay), value: splashBurst)
                    .animation(.easeOut(duration: 0.26), value: splashFaded)
            }

            // Droplets.
            ForEach(Array(Self.droplets.enumerated()), id: \.offset) { _, drop in
                let rad = drop.angle * .pi / 180
                Circle()
                    .fill(silver.opacity(splashFaded ? 0 : 0.8))
                    .frame(width: drop.size, height: drop.size)
                    .offset(x: splashBurst ? cos(rad) * drop.radius : 0,
                            y: splashBurst ? sin(rad) * drop.radius : 0)
                    .opacity(splashBurst ? (splashFaded ? 0 : 0.9) : 0)
                    .animation(.easeOut(duration: 0.40).delay(0.06 + drop.delay), value: splashBurst)
                    .animation(.easeOut(duration: 0.24), value: splashFaded)
            }
        }
        // The splash tracks the icon's own footprint: ~110 pt while the
        // field is streaming, full size once the icon has grown.
        .scaleEffect(iconExpanded ? 1 : Self.preFinishIconScale, anchor: .center)
        .animation(.easeOut(duration: 0.55), value: iconExpanded)
        .scaleEffect(scale, anchor: .center)
        .offset(y: Self.iconCanvasOffset.height * scale)
        .accessibilityHidden(true)
    }

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
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
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
        sloganText
            .font(.system(size: Self.sloganFontSize, weight: .medium, design: .rounded))
            .foregroundStyle(Color(nsColor: Design.baseText))
            .lineLimit(1)
            .minimumScaleFactor(0.62)
            .multilineTextAlignment(.center)
            .frame(width: Self.sloganReservedWidth, height: Self.sloganFontSize * 1.5)
            .opacity(sloganRevealed ? 1 : 0)
            .offset(y: Self.sloganCanvasOffset.height * scale
                      + (sloganRevealed ? 0 : 10))
            .scaleEffect(scale, anchor: .center)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Self.sloganPhrase))
            .accessibilityAddTraits(.isHeader)
            .accessibilityHidden(!sloganRevealed)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.50),
                       value: sloganRevealed)
    }

    /// One Text run split at the first sentence, so both clauses keep one
    /// baseline. Both halves come from `sloganPhrase` alone.
    private var sloganText: Text {
        let phrase = Self.sloganPhrase
        guard let stop = phrase.range(of: ". ") else { return Text(phrase) }
        let lead = String(phrase[phrase.startIndex...stop.lowerBound])
        let tail = String(phrase[stop.upperBound...])
        return Text(lead).fontWeight(.semibold) + Text(" " + tail)
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

    // MARK: - One-shot choreography (~2.5 s total)

    private func bloom() async {
        if reduceMotion {
            // Static final state, immediately: no stream, no splash, no
            // sleeps and no animation — large icon + slogan + button, with
            // the button focused.
            iconRevealed = true
            iconExpanded = true
            sloganRevealed = true
            buttonRevealed = true
            buttonFocused = true
            return
        }
        // 0.00–0.35 icon fades/scales in.
        withAnimation(.easeOut(duration: 0.35)) { iconRevealed = true }
        // 0.14–1.1 the calculations stream in (row + token stagger).
        try? await Task.sleep(nanoseconds: 140_000_000)
        if Task.isCancelled { return }
        withAnimation { tokensRevealed = true }
        // 0.62–0.95 the result runs brighten once.
        try? await Task.sleep(nanoseconds: 480_000_000)
        if Task.isCancelled { return }
        withAnimation { emphasized = true }
        // 0.95–1.45 gather into the icon in two tight batches.
        try? await Task.sleep(nanoseconds: 330_000_000)
        if Task.isCancelled { return }
        withAnimation { converged = true }
        // 1.30–1.75 the monochrome silver splash.
        try? await Task.sleep(nanoseconds: 350_000_000)
        if Task.isCancelled { return }
        withAnimation { pulsed = true }
        withAnimation(.easeOut(duration: 0.55)) { waveProgress = 1 }
        withAnimation { splashBurst = true }
        withAnimation(.easeInOut(duration: 0.34)) { sheenProgress = 1.2 }
        try? await Task.sleep(nanoseconds: 340_000_000)
        if Task.isCancelled { return }
        withAnimation { splashFaded = true; waveFaded = true }
        withAnimation(.easeInOut(duration: 0.18)) { pulsed = false }
        // 1.64–2.19 the icon grows from the streaming footprint (110 pt) to
        // the large final frame (152 pt) on one restrained ease. This
        // overlaps the fading tail of the splash.
        withAnimation(.easeOut(duration: 0.55)) { iconExpanded = true }
        // 1.74–2.24 the slogan fades in with a short rise, in its reserved
        // frame: nothing else moves.
        try? await Task.sleep(nanoseconds: 100_000_000)
        if Task.isCancelled { return }
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.50)) { sloganRevealed = true }
        // 2.04–2.44 the button fades/rises BELOW the slogan, and only once
        // it is visible does the keyboard focus arrive (2.16).
        try? await Task.sleep(nanoseconds: 300_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.40)) { buttonRevealed = true }
        try? await Task.sleep(nanoseconds: 120_000_000)
        if Task.isCancelled { return }
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
