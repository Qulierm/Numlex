import SwiftUI
import AppKit

/// Shared design tokens so typography stays coherent across sidebar,
/// notebook editor and answer column. The editor base size is driven
/// by the user's font-size setting; everything else scales from it.
/// The app uses the native proportional SF system font everywhere.
enum Design {
    // MARK: Notebook (editor + answer column share the same rhythm)

    /// Proportional system font for editable notebook text and numeric results.
    static func body(_ size: Double) -> Font {
        .system(size: size, weight: .regular)
    }

    /// Line-number gutter: quiet, proportional tertiary label.
    static func gutterFont() -> NSFont { NSFont.systemFont(ofSize: 11) }
    /// Inactive gutter numbers: dim in both dark and light.
    static var gutterColor: NSColor { .tertiaryLabelColor }
    /// The gutter number of the line the caret is on: one step brighter.
    static var gutterColorActive: NSColor { .secondaryLabelColor }

    /// Hash-heading `#` marker: a deterministic adaptive neutral gray —
    /// a readable medium gray on the light editor (the app's permanent
    /// Aqua appearance resolves the light branch; the dark value stays
    /// for any future dark surface). Explicit sRGB per appearance, full
    /// alpha; no system dynamic colors.
    static let headingMarkerColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 185.0 / 255.0, green: 185.0 / 255.0, blue: 187.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 122.0 / 255.0, green: 122.0 / 255.0, blue: 126.0 / 255.0, alpha: 1)
    }

    // MARK: Notebook syntax palette (deterministic sRGB values)
    //
    // r36 light theme: every chromatic token is an explicit full-alpha
    // sRGB value on the app's PERMANENT light surfaces (white editor,
    // quiet gray answer panel). The three role colors are the exact
    // user-specified palette: #0070F3 blue (numbers), #46A758 green
    // (variables/constants) and #8E4EC6 purple (units/conversions),
    // each reading clearly on white. The comment titles reuse the
    // requested blue and the currency markers the requested purple,
    // where semantically coherent. No Display P3, no opacity overlays,
    // no accent or dynamic variants for these three.

    /// Numeric literals: #0070F3 — sRGB(0, 112, 243), full alpha.
    static let numberColor = NSColor(srgbRed: 0.0 / 255.0, green: 112.0 / 255.0, blue: 243.0 / 255.0, alpha: 1)
    /// Variable identifiers: #46A758 — sRGB(70, 167, 88), full alpha.
    static let variableColor = NSColor(srgbRed: 70.0 / 255.0, green: 167.0 / 255.0, blue: 88.0 / 255.0, alpha: 1)
    /// Unit words in conversions: #8E4EC6 — sRGB(142, 78, 198), full alpha.
    static let conversionColor = NSColor(srgbRed: 142.0 / 255.0, green: 78.0 / 255.0, blue: 198.0 / 255.0, alpha: 1)
    /// Comment titles: the requested blue #0070F3 — sRGB(0, 112, 243),
    /// reused for semantic coherence with the number role.
    static let titleColor = NSColor(srgbRed: 0.0 / 255.0, green: 112.0 / 255.0, blue: 243.0 / 255.0, alpha: 1)

    /// Currency markers on money lines (`$`, `€`, ISO codes): the
    /// requested purple #8E4EC6 — sRGB(142, 78, 198), reused where
    /// semantically coherent with the unit role.
    static let moneyMarkerColor = NSColor(srgbRed: 142.0 / 255.0, green: 78.0 / 255.0, blue: 198.0 / 255.0, alpha: 1)

    /// Editor caret: sRGB(52, 120, 247) — fixed accent blue matched to
    /// the Soulver reference. Constant across appearances; the caret's
    /// geometry, size, row-box centering and blink are owned by
    /// NotebookTextView, this token only colors the rect.
    static let caretColor = NSColor(srgbRed: 52.0 / 255.0, green: 120.0 / 255.0, blue: 247.0 / 255.0, alpha: 1)
    /// r36 light theme: fixed near-black base for prose, operators,
    /// equals, parentheses, `to`, ANY other plain editor text AND every
    /// answer/result glyph in the answer column and the settings
    /// preview. One centralized token — never raw white/NSColor.white
    /// at a render site. Full alpha, deterministic sRGB.
    static let baseText = NSColor(srgbRed: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, alpha: 1)

    // MARK: Answer reference tokens (r23 premium bubble)

    /// Active token base color: the reference sRGB(195, 220, 255).
    /// Slightly more blue/saturated than the earlier (205, 222, 250)
    /// while staying light and premium — not neon. The capsule fills
    /// with a luminous top-leading to bottom-trailing gradient between
    /// the two alpha stops below — constant across appearances; the
    /// capsule is its own opaque surface.
    static let tokenBase = NSColor(srgbRed: 195.0 / 255.0, green: 220.0 / 255.0, blue: 255.0 / 255.0, alpha: 1)
    static let tokenGradientTopAlpha: CGFloat = 0.98
    static let tokenGradientBottomAlpha: CGFloat = 0.72
    /// Near-black label at 85%, composited over the gradient fill.
    static let tokenText = NSColor.black.withAlphaComponent(0.85)
    /// 1 pt border gradient (white), top-leading to bottom-trailing.
    static let tokenBorderTopAlpha: CGFloat = 0.75
    static let tokenBorderBottomAlpha: CGFloat = 0.18
    /// Soft top sheen: a ~2 pt white capsule strip fading to clear.
    static let tokenHighlightAlpha: CGFloat = 0.35
    static let tokenHighlightHeight: CGFloat = 2
    /// Soft shadow under the active capsule — the reference's
    /// black 28% / 14 blur / 7 y scaled down to the editor's ~23 pt
    /// badge (premium, not neon).
    static let tokenShadowOpacity: CGFloat = 0.28
    static let tokenShadowBlur: CGFloat = 6
    static let tokenShadowOffsetY: CGFloat = 3
    /// Invalidation inset around a capsule: covers the shadow extent
    /// (blur + offset) plus the border and sheen.
    static let tokenInvalidationInset: CGFloat = 20
    /// Inactive (broken) token capsule: a quiet dark-gray FLAT surface
    /// with muted text — no gradient, border, sheen or shadow, so it
    /// can never read as live, but stays legible on the editor
    /// background.
    static let tokenFillInactive = NSColor(srgbRed: 66.0 / 255.0, green: 66.0 / 255.0, blue: 72.0 / 255.0, alpha: 1)
    static let tokenTextInactive = NSColor(srgbRed: 168.0 / 255.0, green: 168.0 / 255.0, blue: 176.0 / 255.0, alpha: 1)
    /// Horizontal reservation on EACH side of the label (8 pt, 16 pt
    /// total) — tightened from the reference bubble's 14 pt per side.
    /// One constant: the reserved layout width and the drawn capsule
    /// always agree.
    static let tokenHPadding: CGFloat = 8
    /// The ONE token label face: medium rounded system typography with
    /// monospaced digits (feature-based, falling back to plain rounded
    /// when the feature cannot be constructed). `applyTokenAttachments`
    /// (reserved width) and `drawTokenCapsules` (ink) both resolve
    /// through this, so width and drawing can never disagree.
    static func tokenFont(size: CGFloat) -> NSFont {
        // Rounded medium with monospaced digits: the monospaced-digit
        // system face keeps its even digit advances through the
        // rounded-design round-trip (verified: .AppleSystemUIFontRounded
        // with 0 pt advance difference between 1 and 2). If either step
        // ever fails, the digit-advance check rejects the candidate and
        // the plain rounded medium wins — the design face is preferred
        // over the digits.
        func advance(_ s: String, in font: NSFont) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: font]).width
        }
        func isMonospaced(_ font: NSFont) -> Bool {
            abs(advance("1", in: font) - advance("2", in: font)) < 0.001
        }
        let medium = NSFont.systemFont(ofSize: size, weight: .regular)
        var rounded: NSFont?
        if let d = medium.fontDescriptor.withDesign(.rounded),
           let f = NSFont(descriptor: d, size: size) {
            rounded = f
        }
        let monoBase = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .regular)
        if let d = monoBase.fontDescriptor.withDesign(.rounded),
           let f = NSFont(descriptor: d, size: size), isMonospaced(f) {
            return f
        }
        if let r = rounded { return r }
        return medium
    }

    // MARK: Source-answer hover outline (r37)

    /// Hovering an ACTIVE answer-token capsule strokes a rounded
    /// rectangle around the SOURCE answer in the answer column (no
    /// fill, stroke only). The color is the reference/caret blue
    /// (Design.caretColor, #3478F7) — one centralized accent, readable
    /// on the light answer panel. The geometry constants below are the
    /// ONLY tuning knobs (tuned against the reference screenshot in QA).
    static let answerHoverLineWidth: CGFloat = 3
    static let answerHoverCornerRadius: CGFloat = 10
    /// Horizontal inset from the panel edge: near-full-width stroke.
    static let answerHoverEdgeInset: CGFloat = 2

    // MARK: Panel surfaces

    /// r36 light theme: the notebook editor background — deterministic
    /// native white (full-alpha sRGB 1,1,1). Applied to the NSTextView,
    /// the SwiftUI editor host and the settings preview from this ONE
    /// token; no dynamic catalog color, so it can never resolve to the
    /// dark surface.
    static let editorBackground = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)

    /// Answer panel background: a quiet light gray visibly distinct from
    /// the editor's white — explicit sRGB per appearance so the value is
    /// deterministic instead of a dynamic system catalog color. The app
    /// runs on the forced Aqua appearance, so this always resolves to
    /// the light value. Dark: sRGB(38, 38, 40) — quiet elevated gray,
    /// just above a dark editor. Light: sRGB(236, 236, 238) — quiet gray
    /// against the editor's white. Applied ONLY to the answer column.
    static let answerPanelBackground = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 38.0 / 255.0, green: 38.0 / 255.0, blue: 40.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 236.0 / 255.0, green: 236.0 / 255.0, blue: 238.0 / 255.0, alpha: 1)
    }

    // MARK: Editor geometry

    /// Top inset of the notebook text (matches the answer column's
    /// content origin, keeping both columns aligned without compensation).
    static let editorTopInset: CGFloat = 6
    /// Width of the quiet line-number gutter inside the text view.
    static let gutterWidth: CGFloat = 36
    /// Distance from the gutter to the first text column. Raising it
    /// moves the text start right WITHOUT moving the numbers, because
    /// the numbers are anchored to `gutterNumberRight` instead.
    static let textLeading: CGFloat = 18
    /// Right edge of the gutter numbers, decoupled from the text start
    /// so the number-to-text gap can be tuned independently.
    static let gutterNumberRight: CGFloat = 42

    // MARK: Labels (native proportional scales)

    static let label: Font = .system(size: 13)       // sidebar titles / controls
    static let labelSmall: Font = .system(size: 11)  // metadata
}
