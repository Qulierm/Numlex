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

    // MARK: Notebook syntax palette (fixed matte sRGB values)
    //
    // Every chromatic token is a deterministic matte variant of the
    // original gamut: the same hue direction with roughly 65% of the
    // original saturation and ~92% lightness — calm, low-vibrancy
    // colors that keep their roles distinguishable on the dark
    // notebook background. No opacity layering is used.

    /// Numeric literals: sRGB(72, 189, 200) — matte cyan.
    static let numberColor = NSColor(srgbRed: 72.0 / 255.0, green: 189.0 / 255.0, blue: 200.0 / 255.0, alpha: 1)
    /// Variable identifiers: sRGB(82, 185, 104) — matte green.
    static let variableColor = NSColor(srgbRed: 82.0 / 255.0, green: 185.0 / 255.0, blue: 104.0 / 255.0, alpha: 1)
    /// Unit words in conversions: sRGB(212, 135, 230) — matte purple.
    static let conversionColor = NSColor(srgbRed: 212.0 / 255.0, green: 135.0 / 255.0, blue: 230.0 / 255.0, alpha: 1)
    /// Comment titles: sRGB(98, 168, 222) — matte blue.
    static let titleColor = NSColor(srgbRed: 98.0 / 255.0, green: 168.0 / 255.0, blue: 222.0 / 255.0, alpha: 1)
    /// Fixed white base for prose, operators, equals, parentheses, `to` and any other plain text.
    static let baseText = NSColor.white

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
}
