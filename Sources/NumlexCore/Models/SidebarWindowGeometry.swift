import Foundation

/// Pure window-frame arithmetic for the main window's response to the
/// system sidebar toggle. Invariant: the RIGHT edge and the height never
/// move — hiding the sidebar narrows the window from the left edge by the
/// measured sidebar column width, showing it again widens it leftward.
///
/// Values are plain screen coordinates (no AppKit dependency) so the logic
/// is deterministic and testable; the app layer maps the result onto
/// NSWindow.setFrame.
public enum SidebarWindowGeometry {
    /// Horizontal span of a window: origin x plus width.
    public struct Edge: Equatable, Sendable {
        public var originX: CGFloat
        public var width: CGFloat
        public init(originX: CGFloat, width: CGFloat) {
            self.originX = originX
            self.width = width
        }
        public var rightEdge: CGFloat { originX + width }
    }

    /// Hide the sidebar: the window becomes narrower by `sidebarWidth`
    /// with the right edge fixed. `minWidth` clamps the collapsed width;
    /// `screenVisible` (optional, horizontal span of the screen's visible
    /// frame) clamps the result onto the screen.
    public static func collapsed(from: Edge,
                                 sidebarWidth: CGFloat,
                                 minWidth: CGFloat,
                                 screenVisible: ClosedRange<CGFloat>? = nil) -> Edge {
        var width = max(from.width - sidebarWidth, minWidth)
        var originX = from.rightEdge - width
        if let s = screenVisible {
            if originX < s.lowerBound {
                originX = s.lowerBound
                width = min(width, max(s.upperBound - originX, minWidth))
            } else if originX + width > s.upperBound {
                width = max(s.upperBound - originX, minWidth)
            }
        }
        return Edge(originX: originX, width: width)
    }

    /// Show the sidebar again: the window widens leftward by
    /// `sidebarWidth` with the right edge fixed (exact inverse of
    /// `collapsed` when the sidebar width is unchanged, so repeated
    /// collapse/expand cycles carry no cumulative drift).
    public static func expanded(from: Edge,
                                sidebarWidth: CGFloat,
                                screenVisible: ClosedRange<CGFloat>? = nil) -> Edge {
        var width = from.width + sidebarWidth
        var originX = from.rightEdge - width
        if let s = screenVisible {
            if originX < s.lowerBound {
                originX = s.lowerBound
                width = min(width, max(s.upperBound - originX, 1))
            } else if originX + width > s.upperBound {
                width = max(s.upperBound - originX, 1)
            }
        }
        return Edge(originX: originX, width: width)
    }
}
