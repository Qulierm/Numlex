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

    /// Hash-heading `#` marker: adaptive secondary label gray — clearly
    /// gray against the white, very-bold heading body, in both
    /// appearances.
    static var headingMarkerColor: NSColor { .secondaryLabelColor }

    // MARK: Notebook syntax palette (deterministic sRGB values)
    //
    // Every chromatic token is an explicit sRGB value: the same hue
    // direction as the original gamut with coherently RAISED lightness
    // (v2 step) on top of the v1 matte values — a matte finish, not a
    // washed-out one, and no neon clipping: each role moved ~4-6% in
    // HSL lightness while keeping its own hue and a moderate
    // saturation, so numbers, variables, conversions and titles each
    // read clearly on both the editor's dark background and the raised
    // answer panel. The fixed white base, operators, `to` and answer
    // values are untouched. No opacity layering is used.

    /// Numeric literals: sRGB(83, 217, 229) — brighter matte cyan (H185 S74 L61).
    static let numberColor = NSColor(srgbRed: 83.0 / 255.0, green: 217.0 / 255.0, blue: 229.0 / 255.0, alpha: 1)
    /// Variable identifiers: sRGB(96, 215, 123) — brighter matte green (H134 S69 L66).
    static let variableColor = NSColor(srgbRed: 96.0 / 255.0, green: 215.0 / 255.0, blue: 123.0 / 255.0, alpha: 1)
    /// Unit words in conversions: sRGB(226, 145, 245) — brighter matte purple (H289 S71 L73).
    static let conversionColor = NSColor(srgbRed: 226.0 / 255.0, green: 145.0 / 255.0, blue: 245.0 / 255.0, alpha: 1)
    /// Comment titles: sRGB(117, 190, 242) — brighter matte blue (H205 S83 L70).
    static let titleColor = NSColor(srgbRed: 117.0 / 255.0, green: 190.0 / 255.0, blue: 242.0 / 255.0, alpha: 1)

    /// Editor caret: sRGB(52, 120, 247) — fixed accent blue matched to
    /// the Soulver reference. Constant across appearances; the caret's
    /// geometry, size, row-box centering and blink are owned by
    /// NotebookTextView, this token only colors the rect.
    static let caretColor = NSColor(srgbRed: 52.0 / 255.0, green: 120.0 / 255.0, blue: 247.0 / 255.0, alpha: 1)
    /// Fixed white base for prose, operators, equals, parentheses, `to` and any other plain text.
    static let baseText = NSColor.white

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

    // MARK: Sidebar geometry

    static let sidebarIconSize: CGFloat = 14
    static let sidebarButtonSize = CGSize(width: 34, height: 28)
    static let sidebarButtonCorner: CGFloat = 7

    /// Effective base height of the sheet-row content, measured from the
    /// font metrics: title line (SF 13 → 16.02) + inter-line spacing (3)
    /// + metadata line (SF 11 → 13.56) + vertical padding (4 + 4) = 40.58.
    static let sidebarRowBaseHeight: CGFloat = 40.6
    /// Raised tab/hit-target height: EXACTLY 20% above the base (48.72).
    /// Applied to the whole row so the selection pill and contentShape
    /// grow with it; the title/metadata block stays centered inside.
    static let sidebarRowHeight: CGFloat = sidebarRowBaseHeight * 1.2
}
