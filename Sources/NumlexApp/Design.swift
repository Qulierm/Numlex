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

    static func bodyMedium(_ size: Double) -> Font {
        .system(size: size, weight: .medium)
    }

    /// Line-number gutter: quiet, proportional secondary label.
    static func gutterFont() -> NSFont { NSFont.systemFont(ofSize: 12) }
    static var gutterColor: NSColor { .secondaryLabelColor }

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
