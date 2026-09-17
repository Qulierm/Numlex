import Foundation
import CoreGraphics

/// Pure, injectable drag-session state for the divider handle.
///
/// One IMMUTABLE start — the displayed width and the stable pointer
/// position recorded when the gesture first moves — is captured per
/// real drag; every subsequent width is derived from that fixed start
/// (`startWidth - (x - startX)`), so view recomputes and the divider's
/// own motion mid-drag can never feed back into the measurement (the
/// oscillation a `.local` coordinate space beneath a moving divider
/// caused). No process globals, no coordinate-space access: the
/// caller hands in pointer positions in ANY stable space (the handle
/// uses `.global`), so the full drag behavior is testable as pure
/// arithmetic.
public struct AnswerColumnDragSession {
    private var start: (width: Double, pointerX: Double)?

    /// A fresh, not-yet-dragging session.
    public init() {}

    /// True once the gesture has recorded a start (a simple click
    /// records one too; materiality is decided by the first movement,
    /// see `width(pointerX:)`).
    public var hasStarted: Bool { start != nil }

    /// Records the immutable start on the first tick (the press); later
    /// ticks and every model/layout change afterwards cannot alter it.
    public mutating func beginIfNeeded(
        pointerX: Double,
        displayedWidth: Double
    ) {
        if start == nil {
            start = (displayedWidth, pointerX)
        }
    }

    /// The live width for a pointer position in a stable coordinate
    /// space, clamped to the hard preference range by the core helper.
    /// `nil` while the movement is not material (click / sub-pixel
    /// jitter) or non-finite — no live write, so a window-capped
    /// display width can never replace the stored preference by
    /// accident.
    public func width(pointerX: Double) -> Double? {
        guard let s = start else { return nil }
        let delta = pointerX - s.pointerX
        guard AnswerColumnGeometry.isMaterialDrag(horizontalTranslation: delta)
        else { return nil }
        return AnswerColumnGeometry.width(
            afterDrag: s.width, horizontalTranslation: delta)
    }

    /// The EXACT final width for the drag-end pointer position (the
    /// caller assigns it to the in-memory preference before its single
    /// persist). `nil` when no drag started or the end input is
    /// non-finite.
    public func finalWidth(pointerX: Double) -> Double? {
        guard let s = start else { return nil }
        let delta = pointerX - s.pointerX
        guard delta.isFinite else { return nil }
        return AnswerColumnGeometry.width(
            afterDrag: s.width, horizontalTranslation: delta)
    }

    /// Forgets the session (drag end, click end, view teardown).
    public mutating func end() {
        start = nil
    }
}

/// The adjustable answer-column geometry: ONE place owns the default,
/// the hard preference bounds and the editor's guaranteed minimum.
///
/// The answer column used to be a fixed 200 pt panel; it is now user
/// adjustable between `minWidth` and `maxWidth` (drag of the editor|
/// answer divider or the Settings → Styling → Answer column width
/// control). The PERSISTED value is the user's preference, clamped to
/// the hard range; at layout time the preference is additionally
/// capped by the available detail width so the editor always keeps at
/// least `editorMinimumWidth` (a 1 pt divider sits between the two
/// panes). Every helper is pure, finite and hostile-input safe: no
/// call can produce a negative, NaN or infinite geometry value.
public enum AnswerColumnGeometry {

    /// The factory default column width (the legacy fixed panel).
    public static let defaultWidth: CGFloat = 200
    /// The smallest width the user may persist.
    public static let minWidth: CGFloat = 140
    /// The largest width the user may persist.
    public static let maxWidth: CGFloat = 400
    /// The editor pane's guaranteed minimum width when the answer
    /// column claims space.
    public static let editorMinimumWidth: CGFloat = 280
    /// The in-flow editor|answer divider footprint (visual AND
    /// layout width; the divider's drag hit zone is wider, centered
    /// over this line, and claims no layout width of its own).
    public static let dividerWidth: CGFloat = 1

    /// Sanitizes a persisted / user-supplied preference to the hard
    /// range `minWidth...maxWidth`. Any FINITE value is clamped into
    /// the range (a negative or zero width is out of range like any
    /// other), while non-finite values — NaN, ±infinity; a serialized
    /// non-finite double encodes as JSON `null` and decodes to the
    /// default separately — resolve to the 200 pt default.
    public static func sanitizePreference(_ width: Double) -> Double {
        guard width.isFinite else { return defaultWidth }
        return min(max(width, minWidth), maxWidth)
    }

    /// The width the answer column should ACTUALLY occupy given the
    /// user's preference and the available detail width: the sanitized
    /// preference, capped so the editor keeps `editorMinimumWidth`
    /// plus the 1 pt divider.
    ///
    /// - The preference is always clamped to `minWidth...maxWidth`.
    /// - A non-finite, zero or negative available width is treated as
    ///   "unknown" and the capped width is simply the sanitized
    ///   preference (never negative/NaN).
    /// - If the window is too narrow to satisfy the editor minimum AND
    ///   the smallest column, the cap wins and can go below
    ///   `minWidth` (down to zero): the editor keeps its minimum and
    ///   the column degrades safely instead of producing invalid
    ///   geometry.
    public static func effectiveWidth(preference: Double,
                                      availableDetailWidth: Double) -> Double {
        let pref = sanitizePreference(preference)
        guard availableDetailWidth.isFinite, availableDetailWidth > 0 else {
            return pref
        }
        let cap = availableDetailWidth - editorMinimumWidth - dividerWidth
        return min(pref, max(cap, 0))
    }

    /// Whether a drag translation is MATERIAL: enough movement to count
    /// as a real drag. Sub-pixel jitter from a simple click (and any
    /// non-finite translation) is not material — a click on the divider
    /// must produce no live width change and no persist, so a
    /// window-capped display width can never replace the stored
    /// preference by accident.
    public static func isMaterialDrag(horizontalTranslation: Double) -> Bool {
        guard horizontalTranslation.isFinite else { return false }
        return abs(horizontalTranslation) >= 1
    }

    /// The pure drag calculation for the divider handle: a drag to the
    /// LEFT grows the answer column, a drag to the RIGHT shrinks it
    /// (`startWidth - horizontalTranslation`; leftward drags report a
    /// negative AppKit/SwiftUI translation). Both inputs finite, the
    /// result is finite and clamped into the hard preference range —
    /// a wild drag can only reach `minWidth`/`maxWidth`, never
    /// anything else. Non-finite input resolves to the 200 pt default.
    public static func width(afterDrag startWidth: Double,
                             horizontalTranslation: Double) -> Double {
        guard startWidth.isFinite, horizontalTranslation.isFinite else {
            return defaultWidth
        }
        let desired = startWidth - horizontalTranslation
        return min(max(desired, minWidth), maxWidth)
    }
}
