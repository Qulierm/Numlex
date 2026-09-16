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
/// horizontalTranslation:)`): a drag to the LEFT grows the answer
/// column, a drag to the RIGHT shrinks it. Only MATERIAL movement
/// (`AnswerColumnGeometry.isMaterialDrag`, |t| >= 1 pt) counts: a
/// simple click makes no live write and no `onEnd`, so a window-capped
/// display width can never replace the stored preference. Every live
/// change of a real drag calls `onChange` with the preference-clamped
/// width (in memory only — nothing is written to disk mid-drag); `onEnd`
/// fires exactly ONCE when the gesture ends and carries the final
/// preference-clamped width, so the caller persists exactly once (and
/// can skip a no-op by comparing against the value captured at drag
/// start).
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

    /// The drag start width (the displayed width when the first MATERIAL
    /// change of the gesture arrived); nil while not dragging.
    @State private var dragStart: Double?
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

    /// Left drag grows the answer column, right drag shrinks it
    /// (`startWidth - horizontalTranslation`, sanitized to the hard
    /// 140...400 range by the core helper). A simple click or sub-pixel
    /// jitter is NOT material: until the movement clears the core's
    /// material threshold the gesture makes no live write at all, so a
    /// window-capped display width can never replace the stored
    /// preference by accident, and onEnd fires only for real drags.
    ///
    /// The cursor is hover-driven and is deliberately NOT popped on
    /// drag end: while the pointer is still over the zone the resize
    /// cursor stays (SwiftUI will not re-fire onHover(true) for a
    /// stationary pointer). If the pointer left during the drag, the
    /// next move outside re-triggers onHover(false) — or onDisappear
    /// fires — and pops it; every push is matched by exactly one pop.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard AnswerColumnGeometry.isMaterialDrag(
                    horizontalTranslation: value.translation.width)
                else { return }
                if dragStart == nil {
                    // The drag is measured from the displayed (possibly
                    // window-capped) width, so relative drags always
                    // behave against what the user sees.
                    dragStart = displayedWidth
                    // Ensure the resize cursor is up for the drag even
                    // if the hover pass never registered (a click
                    // straight into the zone); no double push when it
                    // is already up.
                    setCursor(active: true)
                }
                guard let start = dragStart else { return }
                onChange(AnswerColumnGeometry.width(
                    afterDrag: start,
                    horizontalTranslation: value.translation.width))
            }
            .onEnded { value in
                let start = dragStart
                dragStart = nil
                // No cursor pop here: the pointer is usually still over
                // the zone and must keep the resize cursor (see above).
                guard let start else { return }
                onEnd(AnswerColumnGeometry.width(
                    afterDrag: start,
                    horizontalTranslation: value.translation.width))
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
