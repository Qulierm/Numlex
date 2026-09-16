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
/// column, a drag to the RIGHT shrinks it. Every live change calls
/// `onChange` with the preference-clamped width (in memory only —
/// nothing is written to disk mid-drag); `onEnd` fires exactly ONCE
/// when the gesture ends and carries the final preference-clamped
/// width, so the caller persists exactly once (and can skip a no-op
/// by comparing against the value captured at drag start).
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

    /// The drag start width (the displayed width when the first change
    /// of the gesture arrived); nil while not dragging.
    @State private var dragStart: Double?
    /// True while the resize cursor is pushed (keeps the cursor stack
    /// balanced across hover/leave/disappear).
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
                    .onHover { hovering in
                        setCursor(active: hovering)
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
    /// 140...400 preference range by the core helper).
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil { dragStart = displayedWidth }
                guard let start = dragStart else { return }
                onChange(AnswerColumnGeometry.width(
                    afterDrag: start,
                    horizontalTranslation: value.translation.width))
            }
            .onEnded { value in
                let start = dragStart
                dragStart = nil
                setCursor(active: false)
                guard let start else { return }
                onEnd(AnswerColumnGeometry.width(
                    afterDrag: start,
                    horizontalTranslation: value.translation.width))
            }
    }

    /// Balanced cursor push/pop: the resize cursor is pushed exactly
    /// once per hover entry and popped on leave, drag end or
    /// disappear — no unbalanced stack entries.
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
