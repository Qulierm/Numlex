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

    // MARK: Exact notebook syntax palette (fixed sRGB values)

    /// Numeric literals: sRGB(59, 221, 236).
    static let numberColor = NSColor(srgbRed: 59.0 / 255.0, green: 221.0 / 255.0, blue: 236.0 / 255.0, alpha: 1)
    /// Variable identifiers: sRGB(74, 217, 104).
    static let variableColor = NSColor(srgbRed: 74.0 / 255.0, green: 217.0 / 255.0, blue: 104.0 / 255.0, alpha: 1)
    /// Unit words in conversions: sRGB(234, 141, 255).
    static let conversionColor = NSColor(srgbRed: 234.0 / 255.0, green: 141.0 / 255.0, blue: 255.0 / 255.0, alpha: 1)
    /// Comment titles: sRGB(92, 184, 255).
    static let titleColor = NSColor(srgbRed: 92.0 / 255.0, green: 184.0 / 255.0, blue: 255.0 / 255.0, alpha: 1)
    /// Fixed white base for prose, operators, equals, parentheses, `to` and any other plain text.
    static let baseText = NSColor.white

    // MARK: Editor geometry

    /// Top inset of the notebook text (matches the answer column's
    /// content origin, keeping both columns aligned without compensation).
    static let editorTopInset: CGFloat = 6
    /// Width of the quiet line-number gutter inside the text view.
    static let gutterWidth: CGFloat = 36
    /// Distance from the gutter to the first text column.
    static let textLeading: CGFloat = 16

    // MARK: Labels (native proportional scales)

    static let label: Font = .system(size: 13)       // sidebar titles / controls
    static let labelSmall: Font = .system(size: 11)  // metadata

    // MARK: Sidebar geometry

    static let sidebarIconSize: CGFloat = 14
    static let sidebarButtonSize = CGSize(width: 34, height: 28)
    static let sidebarButtonCorner: CGFloat = 7
}
