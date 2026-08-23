import SwiftUI

/// Shared design tokens so typography stays coherent across sidebar,
/// notebook editor and answer column. The editor base size is driven
/// by the user's font-size setting; everything else scales from it.
enum Design {
    // MARK: Notebook (editor + answer column share the same rhythm)

    /// Monospaced font for editable notebook text and numeric results.
    static func mono(_ size: Double) -> Font {
        .system(size: size, weight: .regular, design: .monospaced)
    }

    static func monoMedium(_ size: Double) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }

    /// Line-number gutter: small, quiet, secondary.
    static let gutterFont: Font = .system(size: 11, weight: .regular, design: .monospaced)
    static let gutterColor: Color = .secondary

    // MARK: Labels (native semantic scales)

    static let label: Font = .callout        // 13 pt
    static let labelSmall: Font = .caption   // 11 pt

    // MARK: Sidebar geometry

    static let newSheetRowHeight: CGFloat = 32
    static let sidebarIconSize: CGFloat = 13
    static let sidebarButtonSize = CGSize(width: 34, height: 28)
    static let sidebarButtonCorner: CGFloat = 7
}
