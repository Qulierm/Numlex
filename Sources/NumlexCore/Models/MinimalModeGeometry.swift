import Foundation

/// Pure window-frame arithmetic for Minimal Mode. The AppKit owner supplies
/// the actual frame size returned by `frameRect(forContentRect:)`; no chrome
/// estimate, screen query, persistence, or global window lookup lives here.
public enum MinimalModeGeometry {
    /// The content target is sourced from the existing main-window minima.
    public static var compactContentSize: CGSize {
        CGSize(width: MainWindowGeometry.contentMinWidth,
               height: MainWindowGeometry.minContentHeight)
    }

    /// Enter Minimal Mode, preserving the normal window's top-right corner
    /// where the chosen connected visible frame permits it. The screen with
    /// the greatest positive intersection area wins; ties prefer the supplied
    /// primary rectangle, then retain input order. With no intersection, use
    /// that connected primary screen or the first valid visible rectangle.
    public static func enteringFrame(from normalFrame: CGRect,
                                     compactFrameSize: CGSize,
                                     visibleFrames: [CGRect],
                                     primaryVisibleFrame: CGRect? = nil) -> CGRect? {
        guard isValidFrame(normalFrame), isValidSize(compactFrameSize),
              let screen = selectedVisibleFrame(for: normalFrame,
                                                visibleFrames: visibleFrames,
                                                primaryVisibleFrame: primaryVisibleFrame) else {
            return nil
        }

        // A caller passes the native chrome-converted size. These lower bounds
        // are only a defensive guarantee that content never falls below the
        // existing 600 x 260 pt contract.
        let width = max(compactFrameSize.width, compactContentSize.width)
        let height = max(compactFrameSize.height, compactContentSize.height)
        guard width.isFinite, height.isFinite else { return nil }
        let anchored = CGRect(x: normalFrame.maxX - width,
                              y: normalFrame.maxY - height,
                              width: width,
                              height: height)
        return clampedFrame(anchored, to: screen,
                            minimumSize: CGSize(width: width, height: height))
    }

    /// Restore the pre-entry frame on exit. A fully on-screen cached rectangle
    /// that satisfies the requested normal visibility floor is returned
    /// exactly. Otherwise choose the screen with the greatest remaining
    /// intersection (or deterministic primary fallback), clamp to its visible
    /// area, and enforce the requested sidebar-dependent minimum. If growing
    /// to that floor, keep the previous right/top anchor where possible.
    public static func restoringFrame(cachedNormalFrame: CGRect?,
                                      savedNormalFrame: SavedWindowFrame?,
                                      visibleFrames: [CGRect],
                                      primaryVisibleFrame: CGRect? = nil,
                                      minimumSize: CGSize) -> CGRect? {
        guard let floor = normalizedFloor(minimumSize) else { return nil }
        let cached = cachedNormalFrame.flatMap { isValidFrame($0) ? $0 : nil }
        let saved = savedNormalFrame.flatMap { saved -> CGRect? in
            guard saved.hasUsableSize, isValidFrame(saved.rect) else { return nil }
            return saved.rect
        }
        guard let candidate = cached ?? saved,
              let screen = selectedVisibleFrame(for: candidate,
                                                visibleFrames: visibleFrames,
                                                primaryVisibleFrame: primaryVisibleFrame) else {
            return nil
        }

        if candidate.width >= floor.width, candidate.height >= floor.height,
           isFullyContained(candidate, in: screen) {
            return candidate
        }

        let widthCeiling = max(screen.width, floor.width)
        let heightCeiling = max(screen.height, floor.height)
        let width = min(max(candidate.width, floor.width), widthCeiling)
        let height = min(max(candidate.height, floor.height), heightCeiling)
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }

        let anchored = CGRect(x: candidate.maxX - width,
                              y: candidate.maxY - height,
                              width: width,
                              height: height)
        return clampedFrame(anchored, to: screen, minimumSize: floor)
    }

    /// Clamp an already chosen frame without shrinking below `minimumSize`.
    /// If a display is smaller than that floor, keep the floor and pin the
    /// window's top-left to the visible frame so its titlebar remains reachable.
    public static func clampedFrame(_ frame: CGRect,
                                   to visibleFrame: CGRect,
                                   minimumSize: CGSize) -> CGRect? {
        guard isValidFrame(frame), isValidFrame(visibleFrame),
              let floor = normalizedFloor(minimumSize) else { return nil }

        let width = max(frame.width, floor.width)
        let height = max(frame.height, floor.height)
        guard width.isFinite, height.isFinite else { return nil }

        let x: CGFloat
        if visibleFrame.width >= width {
            x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        } else {
            x = visibleFrame.minX
        }
        let y: CGFloat
        if visibleFrame.height >= height {
            y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        } else {
            y = visibleFrame.maxY - height
        }

        let result = CGRect(x: x, y: y, width: width, height: height)
        return isValidFrame(result) ? result : nil
    }

    /// A frame is usable only when its origin, size, and far edges are finite.
    /// This also rejects finite inputs whose addition would overflow.
    public static func isValidFrame(_ frame: CGRect) -> Bool {
        frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
            && frame.maxX.isFinite && frame.maxY.isFinite
    }

    private static func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite
            && size.width > 0 && size.height > 0
    }

    private static func normalizedFloor(_ size: CGSize) -> CGSize? {
        guard isValidSize(size) else { return nil }
        let floor = CGSize(width: max(size.width, compactContentSize.width),
                           height: max(size.height, compactContentSize.height))
        return isValidSize(floor) ? floor : nil
    }

    private static func selectedVisibleFrame(for frame: CGRect,
                                             visibleFrames: [CGRect],
                                             primaryVisibleFrame: CGRect?) -> CGRect? {
        let screens = visibleFrames.filter(isValidFrame)
        guard !screens.isEmpty else { return nil }
        let primary = primaryVisibleFrame.flatMap { candidate in
            screens.first(where: { $0 == candidate })
        }

        var bestArea: CGFloat = 0
        var bestScreens: [CGRect] = []
        for screen in screens {
            let hit = screen.intersection(frame)
            guard !hit.isNull, hit.width > 0, hit.height > 0 else { continue }
            let product = hit.width * hit.height
            let area = product.isFinite ? product : CGFloat.greatestFiniteMagnitude
            if area > bestArea {
                bestArea = area
                bestScreens = [screen]
            } else if area == bestArea {
                bestScreens.append(screen)
            }
        }

        if bestArea > 0 {
            if let primary, bestScreens.contains(primary) { return primary }
            return bestScreens.first
        }
        return primary ?? screens.first
    }

    private static func isFullyContained(_ frame: CGRect, in visibleFrame: CGRect) -> Bool {
        frame.minX >= visibleFrame.minX && frame.minY >= visibleFrame.minY
            && frame.maxX <= visibleFrame.maxX && frame.maxY <= visibleFrame.maxY
    }
}
