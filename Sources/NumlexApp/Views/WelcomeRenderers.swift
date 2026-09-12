import SwiftUI
import NumlexCore

/// r102: the two TRANSIENT renderers of the first-launch welcome.
///
/// The r101 pass batched the drawing into `Canvas` views but left the
/// progress scalars as plain parent state captured by the closure — and a
/// `Canvas` is NOT `Animatable`, so `withAnimation { streamProgress = 1 }`
/// only re-evaluated the body at sparse state snapshots instead of
/// interpolating per display frame. That is the "5 fps" stepping the user
/// reported, and it is invisible to a run-loop latency probe.
///
/// Each renderer below is a real `Animatable` view: EVERY progress scalar
/// lives in `animatableData`, so SwiftUI interpolates the renderer itself on
/// each display frame and the `Canvas` inside its body always draws from the
/// interpolated stored properties.
///
/// Both renderers are finite: their parent retires them once the pass is
/// over, so the settled scene carries no animation state, no ticker and no
/// timer.

// MARK: - Calculation field

/// The whole ten-row calculation field drawn in ONE pass from three
/// interpolated scalars: `stream` (row + run stagger, wipe and fade),
/// `emphasis` (result emphasis) and `converge` (the two-batch gather into
/// the icon). `scale` is the canvas scale and `iconOffset` the icon's
/// vertical anchor.
struct CalculationBloomCanvas: View, @preconcurrency Animatable {
    var stream: Double
    var emphasis: Double
    var converge: Double
    var scale: CGFloat
    var iconOffset: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<Double, Double>,
        AnimatablePair<Double, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(stream, emphasis),
                AnimatablePair(converge, AnimatablePair(scale, iconOffset)))
        }
        set {
            stream = newValue.first.first
            emphasis = newValue.first.second
            converge = newValue.second.first
            scale = newValue.second.second.first
            iconOffset = newValue.second.second.second
        }
    }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let iconCentre = CGPoint(x: centre.x, y: centre.y + iconOffset * scale)
            for (index, expression) in WelcomeView.calculations.enumerated() {
                let rowConverge = Self.convergeAmount(converge, expression)
                let opacity = 1 - rowConverge
                guard opacity > 0.012 else { continue }
                let anchor = WelcomeView.anchor(for: expression)
                let base = CGPoint(x: centre.x + anchor.x * scale,
                                   y: centre.y + anchor.y * scale)
                let position = CGPoint(
                    x: base.x + (iconCentre.x - base.x) * rowConverge * 0.55,
                    y: base.y + (iconCentre.y - base.y) * rowConverge * 0.45)
                let rowScale = scale * (1 - 0.5 * rowConverge)
                Self.drawRow(expression, index: index,
                             at: position, canvasScale: rowScale,
                             stream: stream, emphasis: emphasis,
                             opacity: opacity, in: &context)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: constants

    /// The transient field's one font size (16 pt, rounded, monospaced
    /// digits) — the same appearance the per-token `Text` views had.
    static let fieldFontSize: CGFloat = 16
    /// Per-run stagger for the streaming reveal.
    static let tokenStagger: Double = 0.055
    static let rowStagger: Double = 0.038
    /// The reveal window each run takes (of the normalised row progress).
    static let revealWindow: Double = 0.55

    static func clamp01(_ value: Double) -> Double { min(max(value, 0), 1) }

    /// Two tight batches (left column, then right column) with a small
    /// per-row stagger inside each — the same rhythm the per-row views had,
    /// now expressed as a delay inside the single batched pass.
    static func batchDelay(_ expression: BloomExpression) -> Double {
        let columnBase: Double = expression.column == .left ? 0 : 0.09
        return columnBase + Double(expression.slot) * 0.025
    }

    /// A per-row convergence amount for the batched field.
    static func convergeAmount(_ progress: Double, _ expression: BloomExpression) -> Double {
        let delay = batchDelay(expression)
        let span = max(0.35, 1 - delay)
        return clamp01((progress - delay * 0.35) / span)
    }

    /// Draws one expression centered on `at`, run by run, from the same
    /// palette roles the per-token `Text` views used (numbers, variables,
    /// units, money markers, operators), with the per-run stagger and the
    /// result emphasis computed INSIDE this single pass.
    private static func drawRow(_ expression: BloomExpression, index: Int,
                                at centre: CGPoint, canvasScale: CGFloat,
                                stream: Double, emphasis: Double,
                                opacity: Double,
                                in context: inout GraphicsContext) {
        var runs: [(text: GraphicsContext.ResolvedText, width: CGFloat,
                    isResult: Bool, delay: Double)] = []
        var total: CGFloat = 0
        for (tokenIndex, token) in expression.tokens.enumerated() {
            let styled = Text(token.text)
                .font(.system(size: fieldFontSize, weight: token.weight, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color(nsColor: token.color))
            let resolved = context.resolve(styled)
            let width = resolved.measure(in: CGSize(width: 1e6, height: 1e6)).width
            runs.append((resolved, width, expression.resultIndices.contains(tokenIndex),
                         Double(tokenIndex) * tokenStagger))
            total += width
        }
        guard total > 0 else { return }
        let rowStart = Double(index) * rowStagger
        let rowReveal = clamp01((stream - rowStart) / revealWindow)
        guard rowReveal > 0 else { return }
        let totalScaled = total * canvasScale
        var x = centre.x - totalScaled / 2
        for run in runs {
            let width = run.width * canvasScale
            let tokenReveal = clamp01((rowReveal - run.delay) / max(0.2, 1 - run.delay))
            let alpha = opacity * tokenReveal
            if alpha > 0.012 {
                let rise = (1 - tokenReveal) * 5 * canvasScale
                let wipe = (1 - tokenReveal) * -6 * canvasScale
                var ctx = context
                ctx.opacity = alpha
                if run.isResult, emphasis > 0.01 {
                    // Result emphasis: a cheap 6% scale + brightness pass,
                    // never a blur (the old per-row blur shadow measured
                    // free but was still an extra compositing layer).
                    let scale = canvasScale * (1 + 0.06 * emphasis)
                    var local = ctx
                    local.opacity = alpha * (1 + 0.20 * emphasis)
                    local.translateBy(x: x + width / 2 + wipe, y: centre.y + rise)
                    local.scaleBy(x: scale, y: scale)
                    local.draw(run.text, at: .zero)
                } else {
                    ctx.draw(run.text, at: CGPoint(x: x + width / 2 + wipe,
                                                   y: centre.y + rise))
                }
            }
            x += width
        }
    }
}

// MARK: - Silver splash

/// The whole silver burst — 14 rays, 8 droplets and the expanding wave — in
/// ONE pass from two interpolated scalars plus an interpolated `footprint`
/// (so the burst follows the icon's growth smoothly instead of jumping at a
/// Bool edge).
struct SilverSplashCanvas: View, @preconcurrency Animatable {
    var burst: Double
    var fade: Double
    var footprint: CGFloat
    var scale: CGFloat
    var iconOffset: CGFloat

    var animatableData: AnimatablePair<
        AnimatablePair<Double, Double>,
        AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>
    > {
        get {
            AnimatablePair(
                AnimatablePair(burst, fade),
                AnimatablePair(footprint, AnimatablePair(scale, iconOffset)))
        }
        set {
            burst = newValue.first.first
            fade = newValue.first.second
            footprint = newValue.second.first
            scale = newValue.second.second.first
            iconOffset = newValue.second.second.second
        }
    }

    /// 14 deterministic rays: varied length and delay, fixed values only.
    static let rays: [(angle: Double, length: CGFloat, delay: Double, width: CGFloat)] = [
        (8, 96, 0.00, 2.5), (32, 72, 0.02, 1.5), (56, 88, 0.04, 2.0),
        (80, 64, 0.03, 1.5), (104, 92, 0.05, 2.5), (128, 70, 0.01, 1.5),
        (152, 86, 0.04, 2.0), (176, 66, 0.02, 1.5), (200, 94, 0.05, 2.5),
        (224, 74, 0.03, 1.5), (248, 84, 0.01, 2.0), (272, 62, 0.04, 1.5),
        (296, 90, 0.02, 2.5), (320, 76, 0.05, 1.5),
    ]

    /// 8 droplets placed on a fixed deterministic ring.
    static let droplets: [(angle: Double, radius: CGFloat, size: CGFloat, delay: Double)] = [
        (20, 100, 3.5, 0.02), (66, 116, 2.5, 0.05), (112, 96, 3.0, 0.03),
        (158, 112, 2.0, 0.06), (204, 102, 3.5, 0.04), (250, 118, 2.5, 0.02),
        (296, 98, 3.0, 0.05), (342, 114, 2.0, 0.03),
    ]

    /// Rays start just outside the icon: 79 pt is the FINAL icon's half-size
    /// (76) plus a hair, and the burst is drawn at the icon's own footprint
    /// scale, so the rays emerge from behind the icon at both sizes.
    static let rayOriginRadius: CGFloat = 79

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2 + iconOffset * scale)
            Self.drawWave(&context, centre: centre, scale: scale,
                          footprint: footprint, burst: burst, fade: fade)
            Self.drawRays(&context, centre: centre, scale: scale,
                          footprint: footprint, burst: burst, fade: fade)
            Self.drawDroplets(&context, centre: centre, scale: scale,
                              footprint: footprint, burst: burst, fade: fade)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func clamp01(_ value: Double) -> Double { min(max(value, 0), 1) }

    private static func drawWave(_ context: inout GraphicsContext, centre: CGPoint,
                                 scale: CGFloat, footprint: CGFloat,
                                 burst: Double, fade: Double) {
        let wave = clamp01(burst * 1.15)
        guard wave > 0, fade < 1 else { return }
        let radius = 93 * (0.55 + wave * 1.4) * footprint * scale
        let alpha = min(1, wave * 2) * (1 - wave * 0.55) * (1 - fade)
        let rect = CGRect(x: centre.x - radius, y: centre.y - radius,
                          width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: rect),
                       with: .color(Color(nsColor: .secondaryLabelColor).opacity(0.45 * alpha)),
                       lineWidth: 1.5 * scale)
    }

    private static func drawRays(_ context: inout GraphicsContext, centre: CGPoint,
                                 scale: CGFloat, footprint: CGFloat,
                                 burst: Double, fade: Double) {
        guard fade < 1 else { return }
        let colour = Color(nsColor: Design.baseText)
        for ray in rays {
            let local = clamp01((burst - ray.delay * 2.2) / 0.7)
            guard local > 0.01 else { continue }
            let angle = ray.angle * .pi / 180
            let originRadius = rayOriginRadius * footprint * scale
            let origin = CGPoint(x: centre.x + cos(angle) * originRadius,
                                 y: centre.y + sin(angle) * originRadius)
            let length = ray.length * (0.35 + 0.65 * local) * footprint * scale
            let end = CGPoint(x: origin.x + cos(angle) * length,
                              y: origin.y + sin(angle) * length)
            var path = Path()
            path.move(to: origin)
            path.addLine(to: end)
            context.stroke(path,
                           with: .color(colour.opacity(0.75 * local * (1 - fade))),
                           style: StrokeStyle(lineWidth: ray.width * scale, lineCap: .round))
        }
    }

    private static func drawDroplets(_ context: inout GraphicsContext, centre: CGPoint,
                                     scale: CGFloat, footprint: CGFloat,
                                     burst: Double, fade: Double) {
        guard fade < 1 else { return }
        let colour = Color(nsColor: Design.baseText)
        for drop in droplets {
            let local = clamp01((burst - 0.06 - drop.delay * 2.0) / 0.7)
            guard local > 0.01 else { continue }
            let angle = drop.angle * .pi / 180
            let radius = drop.radius * footprint * scale * (0.35 + 0.65 * local)
            let side = drop.size * scale
            let rect = CGRect(x: centre.x + cos(angle) * radius - side / 2,
                              y: centre.y + sin(angle) * radius - side / 2,
                              width: side, height: side)
            context.fill(Path(ellipseIn: rect),
                         with: .color(colour.opacity(0.9 * local * (1 - fade))))
        }
    }
}
