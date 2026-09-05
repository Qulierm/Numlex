import Foundation

/// Single source of truth for the MAIN window's geometry (r59).
///
/// The main window can be resized dramatically shorter than before: the
/// CONTENT minimum height is 260 pt (down from the effective ~505 pt the
/// old 560 pt frame floor produced). Everything here is CONTENT geometry
/// except the two `…MinFrameWidth` values, which stay FRAME widths so the
/// expanded/collapsed width behavior is byte-for-byte identical to before.
///
/// Content vs frame (the one subtlety this file exists to pin down):
/// SwiftUI `.frame(minWidth:minHeight:)` constrains CONTENT size, while
/// `NSWindow.minSize` constrains FRAME size (content + titlebar/toolbar).
/// The AppKit side therefore never sets a raw frame height of 260 (which
/// would leave LESS than 260 pt of content); it converts via
/// `frameRect(forContentRect:)` — i.e. `frameHeight(contentHeight:chrome:)`
/// below — so the effective content minimum is exactly 260 on macOS 26.
/// The pure helpers carry no AppKit dependency so the arithmetic is
/// deterministic and testable; the app layer feeds them the live chrome
/// measurement.
public enum MainWindowGeometry {
    /// Minimum CONTENT height of the main window (pt).
    public static let minContentHeight: CGFloat = 260
    /// Designed default CONTENT size applied on launch (pt).
    public static let defaultContentWidth: CGFloat = 800
    /// Designed default CONTENT size applied on launch (pt).
    public static let defaultContentHeight: CGFloat = 600
    /// Minimum SwiftUI CONTENT width (the collapsed detail width); the
    /// expanded 800 pt floor is enforced on the frame by the configurator.
    public static let contentMinWidth: CGFloat = 600
    /// Minimum FRAME width with the sidebar visible (unchanged).
    public static let expandedMinFrameWidth: CGFloat = 800
    /// Minimum FRAME width with the sidebar collapsed (unchanged).
    public static let collapsedMinFrameWidth: CGFloat = 600

    /// Frame height for a content height given the window's non-client
    /// (titlebar/toolbar/border) contribution: frame = content + chrome.
    public static func frameHeight(contentHeight: CGFloat,
                                   chromeHeight: CGFloat) -> CGFloat {
        contentHeight + max(chromeHeight, 0)
    }

    /// Inverse: the content height left inside a frame height.
    /// Never negative — a zero/negative result means the whole content
    /// area is consumed by chrome (rows then scroll/clip, nothing
    /// overlaps or escapes).
    public static func contentHeight(frameHeight: CGFloat,
                                     chromeHeight: CGFloat) -> CGFloat {
        max(frameHeight - max(chromeHeight, 0), 0)
    }
}
