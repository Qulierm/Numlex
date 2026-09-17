import AppKit
import SwiftUI
import NumlexCore

/// The draggable editor|answer divider. Its visible footprint is
/// EXACTLY the old 1 pt `Design.panelSeparator` hairline (same layout
/// width, full height, stretched through the titlebar safe-area gap);
/// overlaid on it — claiming no layout width of its own — is a centered
/// 12 pt transparent hit zone that drags the answer column.
///
/// Drag semantics (see `AnswerColumnGeometry.width(afterDrag:
/// horizontalTranslation:)` and `AnswerColumnDragSession`): a drag to
/// the LEFT grows the answer column, a drag to the RIGHT shrinks it.
/// Pointer motion is measured in the GLOBAL (window) coordinate space,
/// never `.local` — the divider view moves as the width updates, so a
/// local-space translation would feed the applied layout delta back
/// into the next tick and oscillate. One immutable start (displayed
/// width + global pointer x at the press) is captured per drag and all
/// widths derive from it, so the column follows the pointer 1:1 with
/// no feedback and no animation. Only MATERIAL movement
/// (`AnswerColumnGeometry.isMaterialDrag`, |t| >= 1 pt) counts: a
/// simple click makes no live write and no `onEnd`, so a window-capped
/// display width can never replace the stored preference. Every live
/// change of a real drag calls `onChange` with the preference-clamped
/// width (in memory only — nothing is written to disk mid-drag); `onEnd`
/// fires exactly ONCE when the gesture ends and carries the EXACT final
/// formula width, which the caller assigns in memory before persisting
/// exactly once (skipping a no-op by comparing against the value
/// captured at drag start).
///
/// The resize cursor is hover-driven and deliberately stays up when a
/// drag ends with the pointer still over the zone (SwiftUI will not
/// re-fire onHover for a stationary pointer); the next hover-leave — or
/// the view disappearing — pops it, so the cursor stack stays balanced.
///
/// Presentation-only: this handle never touches sheet content, line
/// IDs, references, caret, selection, IME marked text, focus,
/// scrolling or evaluation — it only feeds the answer-column width
/// preference, which is pure presentation state.
struct AnswerColumnResizeHandle: View {
    /// The width the answer column is CURRENTLY displaying (the
    /// window-capped effective width, which can be narrower than the
    /// persisted preference in a narrow window). The drag is measured
    /// from this value, so relative drags always behave against what
    /// the user sees.
    var displayedWidth: Double
    /// The UI language (localized accessibility labels/help).
    var language: AppLanguage
    /// Live in-memory change during the drag (no persistence).
    var onChange: (Double) -> Void
    /// Fires exactly once when the drag ends; the caller persists the
    /// value when it differs from the pre-drag one.
    var onEnd: (Double) -> Void

    /// The centered drag hit zone: 12 pt wide over the 1 pt line
    /// (10...12 pt band), full height, transparent. It claims no
    /// layout width — the divider still occupies exactly 1 pt in-flow.
    static let hitZoneWidth: CGFloat = 12

    /// One immutable start per real drag: the displayed width at the
    /// press plus the pointer position in the STABLE (global) space.
    /// Later view recomputes — including the divider moving under the
    /// pointer — cannot change it.
    @State private var dragSession = AnswerColumnDragSession()
    /// True once the drag produced a MATERIAL live width. A plain
    /// click never sets it, so `onEnd` (and therefore any persist)
    /// fires only for real drags.
    @State private var hasMaterialDrag = false
    /// The last hover report from the hit zone (explicit state: after a
    /// drag ends SwiftUI does not re-fire onHover(true) for a stationary
    /// pointer, so the cursor decision reads this value, not a transient
    /// event).
    @State private var hoverInside = false
    /// True while the resize cursor is pushed (keeps the cursor stack
    /// balanced across hover/drag/disappear).
    @State private var cursorActive = false

    var body: some View {
        Color(nsColor: Design.panelSeparator)
            .frame(width: AnswerColumnGeometry.dividerWidth)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea(edges: .vertical)
            .overlay {
                // The wider transparent hit zone, centered on the 1 pt
                // line. Its center 1 pt is always over the line itself;
                // the outer wings reach 5.5 pt into each pane — and
                // nothing outside the zone, so editor/answer wheel,
                // double-click and context menus are untouched
                // everywhere else.
                Color.clear
                    .frame(width: Self.hitZoneWidth)
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea(edges: .vertical)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .onHover { inside in
                        hoverInside = inside
                        setCursor(active: inside)
                    }
                    .onDisappear {
                        setCursor(active: false)
                    }
                    .accessibilityElement()
                    .accessibilityLabel(
                        Text(L10n.t("styling.column.widthHandle", language: language)))
                    .accessibilityValue(
                        Text("\(Int(displayedWidth.rounded())) pt"))
                    .accessibilityHint(
                        Text(L10n.t("styling.column.widthCap", language: language)))
                    .accessibilityAdjustableAction(adjustColumnWidth)
            }
    }

    /// Keyboard/VoiceOver adjustment: ±10 pt within the hard range
    /// (the same pure drag formula with a synthetic translation),
    /// then the single end-of-gesture commit, so the adjustable action
    /// persists exactly like a completed drag.
    private func adjustColumnWidth(_ direction: AccessibilityAdjustmentDirection) {
        let step: Double
        if direction == .increment { step = 10 }
        else { step = -10 }
        let final = AnswerColumnGeometry.width(
            afterDrag: displayedWidth,
            horizontalTranslation: -step)
        onChange(final)
        onEnd(final)
    }

    /// Left drag grows the answer column, right drag shrinks it.
    ///
    /// Coordinates are measured in the GLOBAL (window) space — never
    /// `.local`: the divider view itself moves as the width updates,
    /// so a local-space translation feeds the applied layout delta
    /// back into the next gesture tick and the column oscillates. The
    /// stable delta is `location.x - startPointerX`, where both come
    /// from that fixed space; the width is `startWidth - delta`,
    /// clamped by the core helper, 1:1 with the pointer until the
    /// hard/window bounds, with no animation.
    ///
    /// A click or sub-pixel jitter is NOT material: until the movement
    /// clears the core threshold the gesture makes no live write at
    /// all and onEnd never fires, so a window-capped display width can
    /// never replace the stored preference. `onEnd` carries the EXACT
    /// final formula result, which the caller assigns in memory before
    /// its single persist (in-memory writes happen live, many times;
    /// disk exactly once per real drag, zero times for a click).
    ///
    /// The cursor is hover-driven and is deliberately NOT popped on
    /// drag end: while the pointer is still over the zone the resize
    /// cursor stays (SwiftUI will not re-fire onHover(true) for a
    /// stationary pointer). If the pointer left during the drag, the
    /// next move outside re-triggers onHover(false) — or onDisappear
    /// fires — and pops it; every push is matched by exactly one pop.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                dragSession.beginIfNeeded(
                    pointerX: value.location.x,
                    displayedWidth: displayedWidth)
                guard let width = dragSession.width(pointerX: value.location.x)
                else { return }
                hasMaterialDrag = true
                // Ensure the resize cursor is up for the drag even if
                // the hover pass never registered (a click straight
                // into the zone); no double push when it is up.
                setCursor(active: true)
                onChange(width)
            }
            .onEnded { value in
                // The final width is the exact formula result at the
                // end pointer position — not "whatever the last
                // onChanged happened to write" — and only for drags
                // that were material.
                let final = hasMaterialDrag
                    ? dragSession.finalWidth(pointerX: value.location.x)
                    : nil
                dragSession.end()
                hasMaterialDrag = false
                // No cursor pop here: the pointer is usually still over
                // the zone and must keep the resize cursor (see above).
                guard let final else { return }
                onEnd(final)
            }
    }

    /// Balanced cursor push/pop: pushed exactly once per transition into
    /// the active state (hover entry or drag start) and popped exactly
    /// once per transition out (hover leave, or disappear while active).
    private func setCursor(active: Bool) {
        guard active != cursorActive else { return }
        cursorActive = active
        if active {
            NSCursor.resizeLeftRight.push()
        } else {
            NSCursor.pop()
        }
    }
}
