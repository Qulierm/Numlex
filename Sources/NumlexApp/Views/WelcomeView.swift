import SwiftUI
import NumlexCore

/// r97: the first-launch welcome — a native "calculation bloom".
///
/// Four short expressions in the REAL editor palette float around the app
/// icon, type themselves in left-to-right, converge into the icon and
/// dissolve into a ring of colored arcs while the icon gives one restrained
/// pulse; then the localized **Get Started** button appears. There is no
/// slogan, no marketing copy and no website styling: every color comes from
/// the app's own editor palette, so Auto/Light/Dark match the notebook
/// exactly.
///
/// It REPLACES the main content until the user starts (nothing from the
/// editor, sidebar or TextKit exists behind it) and keeps the native window
/// chrome and the app's window geometry.
struct WelcomeView: View {
    let language: AppLanguage
    let onGetStarted: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // One-shot staged state. Every stage only changes opacity/offset/scale/
    // trim — the final frames exist from the first layout pass, so nothing
    // reflows and the window never resizes.
    @State private var iconRevealed = false
    @State private var tokensRevealed = false
    @State private var emphasized = false
    @State private var converged = false
    @State private var arcProgress: CGFloat = 0
    @State private var arcsFaded = false
    @State private var pulsed = false
    @State private var sheenProgress: CGFloat = -1.2
    @State private var buttonRevealed = false
    @State private var activating = false
    @FocusState private var buttonFocused: Bool

    /// The design canvas the composition is laid out on; the field scales
    /// (never clips) when the window is smaller than this.
    private static let canvas = CGSize(width: 800, height: 600)

    var body: some View {
        GeometryReader { geo in
            let scale = min(1, min(geo.size.width / Self.canvas.width,
                                   geo.size.height / Self.canvas.height))
            ZStack {
                Color(nsColor: Design.editorBackground)

                calculationField(scale: scale)
                arcRing
                icon(scale: scale)
                button(scale: scale)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .task { await bloom() }
        .onDisappear { /* the task is cancelled by SwiftUI */ }
    }

    // MARK: - Composition

    private var expressions: [BloomExpression] {
        [
            BloomExpression(anchor: .topLeft,
                            tokens: [.number("128"), .op(" × "), .number("4"),
                                     .op(" = "), .number("512")],
                            resultIndices: [4]),
            BloomExpression(anchor: .topRight,
                            tokens: [.variable("price"), .op(" = "), .number("24")],
                            resultIndices: [2]),
            BloomExpression(anchor: .bottomLeft,
                            tokens: [.number("3.5"), .op(" "), .unit("km"), .op(" → "),
                                     .number("3500"), .op(" "), .unit("m")],
                            resultIndices: [4, 5]),
            BloomExpression(anchor: .bottomRight,
                            tokens: [.money("$"), .number("42"), .op(" + "), .money("$"),
                                     .number("18"), .op(" = "), .money("$"), .number("60")],
                            resultIndices: [6, 7]),
        ]
    }

    private func expressionOffset(_ anchor: BloomAnchor, scale: CGFloat) -> CGSize {
        let dx = 196 * scale
        let dy = 150 * scale
        switch anchor {
        case .topLeft: return CGSize(width: -dx, height: -dy)
        case .topRight: return CGSize(width: dx, height: -dy)
        case .bottomLeft: return CGSize(width: -dx, height: dy)
        case .bottomRight: return CGSize(width: dx, height: dy)
        }
    }

    /// The four expressions, each a row of typographic runs. Token runs
    /// reveal left-to-right with a small per-token delay; the whole row then
    /// converges into the icon and fades.
    private func calculationField(scale: CGFloat) -> some View {
        ZStack {
            ForEach(Array(expressions.enumerated()), id: \.offset) { index, expression in
                expressionRow(expression, index: index)
                    .scaleEffect(converged ? 0.55 : 1, anchor: .center)
                    .opacity(converged ? 0 : 1)
                    .offset(x: expressionOffset(expression.anchor, scale: scale).width
                                * (converged ? -0.62 : 1),
                            y: expressionOffset(expression.anchor, scale: scale).height
                                * (converged ? -0.62 : 1))
                    .animation(.easeInOut(duration: 0.45).delay(converged ? Double(index) * 0.045 : 0),
                               value: converged)
                    .scaleEffect(scale, anchor: .center)
            }
        }
        .accessibilityHidden(true)
    }

    private func expressionRow(_ expression: BloomExpression, index: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(expression.tokens.enumerated()), id: \.offset) { tokenIndex, token in
                tokenText(token, emphasized: emphasized && expression.resultIndices.contains(tokenIndex))
                    .opacity(tokensRevealed ? 1 : 0)
                    .offset(y: tokensRevealed ? 0 : 6)
                    .scaleEffect(tokensRevealed ? 1 : 0.96)
                    // Token stagger: 40 ms per token, plus a per-row offset.
                    .animation(.easeOut(duration: 0.26)
                        .delay(tokensRevealed
                               ? 0.18 + Double(index) * 0.06 + Double(tokenIndex) * 0.04
                               : 0),
                               value: tokensRevealed)
                    .animation(.easeOut(duration: 0.18)
                        .delay(emphasized ? 0.75 + Double(index) * 0.05 : 0),
                               value: emphasized)
            }
        }
        .shadow(color: emphasized
                ? Color(nsColor: Design.numberColor).opacity(0.35)
                : Color(nsColor: Design.baseText).opacity(0.18),
                radius: emphasized ? 8 : 3)
    }

    /// One typographic run, resolved from the app's own editor palette so
    /// the field matches the notebook in every appearance.
    @ViewBuilder
    private func tokenText(_ token: BloomToken, emphasized: Bool) -> some View {
        Text(token.text)
            .font(.system(size: 20, weight: token.weight, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color(nsColor: token.color))
            .scaleEffect(emphasized ? 1.06 : 1)
            .animation(.easeOut(duration: 0.18), value: emphasized)
    }

    /// 3–4 thin colored arc segments around the icon, each in one palette
    /// color, drawn part-way and faded out. Not a slogan underline.
    private var arcRing: some View {
        ZStack {
            ForEach(Array(arcStyles.enumerated()), id: \.offset) { index, style in
                WelcomeArc(startAngle: style.start, sweep: style.sweep)
                    .trim(from: 0, to: arcProgress)
                    .stroke(Color(nsColor: style.color),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: style.radius * 2, height: style.radius * 2)
                    .rotationEffect(.degrees(arcsFaded ? Double(index) * 34 : 0))
                    .opacity(arcsFaded ? 0 : 1)
                    .animation(.easeInOut(duration: 0.5).delay(converged ? Double(index) * 0.05 : 0),
                               value: arcsFaded)
            }
        }
        .accessibilityHidden(true)
    }

    private var arcStyles: [(start: Angle, sweep: Angle, radius: CGFloat, color: NSColor)] {
        [
            (.degrees(-40), .degrees(120), 96, Design.numberColor),
            (.degrees(60), .degrees(130), 104, Design.variableColor),
            (.degrees(170), .degrees(110), 92, Design.conversionColor),
            (.degrees(270), .degrees(100), 108, Design.moneyMarkerColor),
        ]
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
        .frame(width: 110, height: 110)
        .overlay(sheen)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .scaleEffect(iconRevealed ? (pulsed ? 1.055 : 1) : 0.88)
        .opacity(iconRevealed ? 1 : 0)
        .offset(y: -34 * scale)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Numlex"))
        .animation(.easeOut(duration: 0.35), value: iconRevealed)
        .animation(.easeInOut(duration: 0.20), value: pulsed)
    }

    /// A diagonal light sweep across the icon (one pass, then gone). The
    /// caller clips it to the icon shape, so it never renders as a band.
    private var sheen: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.5), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: geo.size.width * 0.34)
                .rotationEffect(.degrees(24))
                .offset(x: sheenProgress * geo.size.width * 1.7)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func button(scale: CGFloat) -> some View {
        GetStartedButton(language: language,
                         enabled: !activating,
                         action: activate)
            .scaleEffect(scale)
            .offset(y: (160 * scale) + (buttonRevealed ? 0 : 10))
            .opacity(buttonRevealed ? 1 : 0)
            .focused($buttonFocused)
            .allowsHitTesting(buttonRevealed && !activating)
            .accessibilityHidden(!buttonRevealed)
            .animation(.easeOut(duration: 0.4), value: buttonRevealed)
    }

    // MARK: - One-shot choreography (~1.95 s total)

    private func bloom() async {
        if reduceMotion {
            // Static final state: icon + button only, nothing staged.
            iconRevealed = true
            buttonRevealed = true
            buttonFocused = true
            return
        }
        // 0.00–0.35 icon fades/scales in.
        withAnimation(.easeOut(duration: 0.35)) { iconRevealed = true }
        // 0.18–0.80 the expressions type themselves in (per-token delays).
        try? await Task.sleep(nanoseconds: 180_000_000)
        if Task.isCancelled { return }
        withAnimation { tokensRevealed = true }
        // 0.75–1.05 the result runs brighten once.
        try? await Task.sleep(nanoseconds: 570_000_000)
        if Task.isCancelled { return }
        withAnimation { emphasized = true }
        // 1.00–1.45 the expressions converge into the icon.
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled { return }
        withAnimation { converged = true }
        // 1.10–1.60 the colored arcs swing around the icon.
        try? await Task.sleep(nanoseconds: 100_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.5)) { arcProgress = 1 }
        try? await Task.sleep(nanoseconds: 150_000_000)
        if Task.isCancelled { return }
        withAnimation { arcsFaded = true }
        // 1.40–1.78 one restrained charge pulse + a single sheen sweep.
        try? await Task.sleep(nanoseconds: 150_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.20)) { pulsed = true }
        withAnimation(.easeInOut(duration: 0.38)) { sheenProgress = 1.2 }
        try? await Task.sleep(nanoseconds: 150_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeInOut(duration: 0.20)) { pulsed = false }
        // 1.65–2.05 the button fades/rises and takes focus.
        try? await Task.sleep(nanoseconds: 100_000_000)
        if Task.isCancelled { return }
        withAnimation(.easeOut(duration: 0.4)) { buttonRevealed = true }
        buttonFocused = true
    }

    /// One guarded activation with a brief content crossfade (no window or
    /// layout animation).
    private func activate() {
        guard !activating else { return }
        activating = true
        if reduceMotion {
            onGetStarted()
        } else {
            withAnimation(.easeOut(duration: 0.26)) { onGetStarted() }
        }
    }
}

// MARK: - Model

enum BloomAnchor { case topLeft, topRight, bottomLeft, bottomRight }

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
    let anchor: BloomAnchor
    let tokens: [BloomToken]
    /// Indices of the runs that are the RESULT (brightened once).
    let resultIndices: [Int]
}

/// A partial ring segment around the icon.
struct WelcomeArc: Shape {
    let startAngle: Angle
    let sweep: Angle

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                 radius: min(rect.width, rect.height) / 2,
                 startAngle: startAngle,
                 endAngle: startAngle + sweep,
                 clockwise: false)
        return p
    }
}

/// The ONE primary action: a native prominent button at the large control
/// size, sized to its content (never full-width).
private struct GetStartedButton: View {
    let language: AppLanguage
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(L10n.t("welcome.getStarted", language: language))
                    .font(.system(size: 16, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .frame(minWidth: 190)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(!enabled)
        .accessibilityLabel(Text(L10n.t("welcome.getStarted", language: language)))
        .accessibilityHint(Text(L10n.t("welcome.getStartedHint", language: language)))
    }
}
