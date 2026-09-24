import Foundation

/// Single source of truth for the MAIN window's geometry (r59).
///
/// The main window can be resized dramatically shorter than before: the
/// CONTENT minimum height is 260 pt (down from the effective ~505 pt the
/// old 560 pt frame floor produced). Everything here is CONTENT geometry
/// except the two `…MinFrameWidth` values, which stay FRAME widths so the
/// expanded/collapsed width behavior is byte-for-byte identical to before.
///
/// The main window's frame as persisted in the app-global settings store.
///
/// Stored as four plain Doubles so the JSON stays obvious and stable; a
/// `CGRect` accessor keeps the AppKit side terse. Additive: a legacy
/// store has no key at all (`AppSettings.windowFrame == nil`, meaning
/// "never saved"), and `StorePayload.currentVersion` is NOT bumped.
///
/// This value is UNTRUSTED on read: it may describe a display that is no
/// longer connected, a resolution that changed or a corrupt hand-edited
/// store. `restoredFrame(saved:visibleFrames:minimumSize:)` is the ONE
/// place that decides whether it may be used.
public struct SavedWindowFrame: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ rect: CGRect) {
        self.init(x: Double(rect.origin.x), y: Double(rect.origin.y),
                  width: Double(rect.size.width), height: Double(rect.size.height))
    }

    /// The frame as a rect. Callers that APPLY a frame still go through
    /// `MainWindowGeometry.restoredFrame`; this accessor is for
    /// comparisons and for the already-validated launch path.
    public var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// True when the four numbers could describe a real window size.
    /// A non-finite, zero or negative width/height is unusable.
    public var hasUsableSize: Bool {
        x.isFinite && y.isFinite
            && width.isFinite && height.isFinite
            && width > 0 && height > 0
    }
}

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

    /// Documented OFF-SCREEN PROTECTION (replaces the previous
    /// "always open centered" rule): a saved frame is only reused when it
    /// still meaningfully intersects a connected screen's visible area —
    /// at least this many points of overlap in BOTH dimensions. A frame
    /// that fails this test, or that has no usable size, is discarded and
    /// the caller keeps the centered 800x600 default.
    public static let minimumVisibleOverlap: CGFloat = 100

    /// The frame to apply on launch, or nil to keep the designed default.
    ///
    /// Pure and AppKit-free so it is deterministic and testable; the app
    /// layer passes `NSScreen.screens.map(\.visibleFrame)`.
    ///
    /// Rules, in order:
    /// 1. no saved frame, or no connected screen -> nil (centered default);
    /// 2. a non-finite, zero or negative size -> nil (unusable);
    /// 3. the screen with the LARGEST intersection AREA wins, and the
    ///    saved frame is discarded unless that intersection is at least
    ///    `minimumVisibleOverlap` in width AND height — so a window whose
    ///    titlebar would be unreachable is never restored off-screen;
    /// 4. the size is clamped UP to `minimumSize` (the visibility floor)
    ///    and DOWN to the chosen screen's visible size (staying at or
    ///    above `minimumSize` even on a screen smaller than it);
    /// 5. the saved ORIGIN is returned unchanged: restoring never
    ///    re-centers and never shifts the window.
    public static func restoredFrame(saved: SavedWindowFrame?,
                                     visibleFrames: [CGRect],
                                     minimumSize: CGSize) -> CGRect? {
        guard let saved, !visibleFrames.isEmpty, saved.hasUsableSize else { return nil }
        let rect = saved.rect
        // The screen it overlaps most wins.
        var best: (frame: CGRect, area: CGFloat)?
        for visible in visibleFrames {
            let hit = visible.intersection(rect)
            guard !hit.isNull else { continue }
            let area = hit.width * hit.height
            if area > (best?.area ?? 0) { best = (visible, area) }
        }
        guard let chosen = best,
              let overlap = chosen.frame.intersection(rect) as CGRect?,
              overlap.width >= minimumVisibleOverlap,
              overlap.height >= minimumVisibleOverlap else { return nil }
        // Never below the visibility floor, never wider/taller than the
        // screen it was restored onto.
        let floorWidth = max(minimumSize.width, 0)
        let floorHeight = max(minimumSize.height, 0)
        let width = min(max(rect.width, floorWidth), max(chosen.frame.width, floorWidth))
        let height = min(max(rect.height, floorHeight), max(chosen.frame.height, floorHeight))
        return CGRect(x: rect.origin.x, y: rect.origin.y, width: width, height: height)
    }
}
