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
    /// clearly lighter than secondaryLabelColor in dark mode (around
    /// sRGB 185 on the editor's near-black background) and a readable
    /// medium gray in light mode. Explicit sRGB per appearance, full
    /// alpha; no system dynamic colors.
    static let headingMarkerColor = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 185.0 / 255.0, green: 185.0 / 255.0, blue: 187.0 / 255.0, alpha: 1)
            : NSColor(srgbRed: 122.0 / 255.0, green: 122.0 / 255.0, blue: 126.0 / 255.0, alpha: 1)
    }

    // MARK: Notebook syntax palette (deterministic sRGB values)
    //
    // Every chromatic token is an explicit sRGB value: the same hue
    // direction as the original gamut, now with coherently RAISED CHROMA
    // (v3 step) on top of the v2 lightness step — a more saturated,
    // still matte finish with no neon clipping: each role's color is
    // pulled further from gray at (roughly) the same lightness, keeping
    // the four role hues clearly distinct, so numbers, variables,
    // conversions and titles each read clearly on both the editor's
    // dark background and the raised answer panel. The fixed white base,
    // operators, `to` and answer values are untouched. No opacity
    // layering is used.

    /// Numeric literals: sRGB(61, 224, 239) — saturated matte cyan (H185 S85 L59).
    static let numberColor = NSColor(srgbRed: 61.0 / 255.0, green: 224.0 / 255.0, blue: 239.0 / 255.0, alpha: 1)
    /// Variable identifiers: sRGB(75, 220, 110) — saturated matte green (H134 S68 L58).
    static let variableColor = NSColor(srgbRed: 75.0 / 255.0, green: 220.0 / 255.0, blue: 110.0 / 255.0, alpha: 1)
    /// Unit words in conversions: sRGB(231, 137, 251) — saturated matte purple (H289 S94 L76).
    static let conversionColor = NSColor(srgbRed: 231.0 / 255.0, green: 137.0 / 255.0, blue: 251.0 / 255.0, alpha: 1)
    /// Comment titles: sRGB(101, 188, 246) — saturated matte blue (H204 S89 L68).
    static let titleColor = NSColor(srgbRed: 101.0 / 255.0, green: 188.0 / 255.0, blue: 246.0 / 255.0, alpha: 1)

    /// Currency markers on money lines (`$`, `€`, ISO codes).
    static let moneyMarkerColor = NSColor(srgbRed: 199.0 / 255.0, green: 128.0 / 255.0, blue: 255.0 / 255.0, alpha: 1)

    /// Editor caret: sRGB(52, 120, 247) — fixed accent blue matched to
    /// the Soulver reference. Constant across appearances; the caret's
    /// geometry, size, row-box centering and blink are owned by
    /// NotebookTextView, this token only colors the rect.
    static let caretColor = NSColor(srgbRed: 52.0 / 255.0, green: 120.0 / 255.0, blue: 247.0 / 255.0, alpha: 1)
    /// Fixed white base for prose, operators, equals, parentheses, `to` and any other plain text.
    static let baseText = NSColor.white

    // MARK: Answer reference tokens

    /// Active token capsule: the light-blue fill of the reference design
    /// (sRGB(201, 223, 253)) with near-black text. Constant across
    /// appearances — the capsule is its own opaque surface.
    static let tokenFill = NSColor(srgbRed: 201.0 / 255.0, green: 223.0 / 255.0, blue: 253.0 / 255.0, alpha: 1)
    static let tokenText = NSColor(srgbRed: 24.0 / 255.0, green: 28.0 / 255.0, blue: 34.0 / 255.0, alpha: 1)
    /// Inactive (broken) token capsule: a quiet dark-gray surface with
    /// muted text — clearly not live, but still legible on the editor
    /// background.
    static let tokenFillInactive = NSColor(srgbRed: 66.0 / 255.0, green: 66.0 / 255.0, blue: 72.0 / 255.0, alpha: 1)
    static let tokenTextInactive = NSColor(srgbRed: 168.0 / 255.0, green: 168.0 / 255.0, blue: 176.0 / 255.0, alpha: 1)

    // MARK: Panel surfaces

    /// Answer panel background: a darker, calm gray that still separates
    /// the results from the editor, explicit sRGB per appearance so the
    /// value is deterministic instead of a dynamic system catalog color.
    /// Dark: sRGB(38, 38, 40) — quiet elevated gray (L 0.155) just above
    /// the editor's sRGB(30, 30, 30) (L 0.118): clearly a raised panel,
    /// never light. Light: sRGB(236, 236, 238) — quiet gray against the
    /// editor's white. Applied ONLY to the answer column.
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
