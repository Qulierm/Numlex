import AppKit
import SwiftUI

/// One native NSScroller pinned to the absolute trailing edge of the detail
/// area. It is a pure bridge over the editor's shared scroll state:
///
///   - the canonical scroll range is the editor's own geometry
///     (documentHeight - editor clip viewportHeight), so the fixed-height
///     Total row in the answer column never distorts the math,
///   - `scroller.doubleValue` stores the normalized topOffset/range in 0...1,
///   - user drags and wheel over the strip emit `doubleValue * scrollRange`
///     content points back through `onOffset`.
///
/// Programmatic value writes never fire the scroller action, so the
/// editor → state → scroller loop converges without recursion or jitter.
struct EdgeScroller: NSViewRepresentable {
    /// The editor coordinator of the current sheet (nil before first layout).
    var coordinator: NotebookEditorCoordinator?
    /// Canonical top-down scroll offset in content points.
    var topOffset: CGFloat
    /// Answer-column content-region height. Used for the visual frame only,
    /// never for scroll math.
    var viewport: CGFloat
    /// User moved the knob (drag or wheel while hovering the scroller).
    var onOffset: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollerView {
        let v = ScrollerView()
        v.onOffset = onOffset
        return v
    }

    func updateNSView(_ v: ScrollerView, context: Context) {
        v.onOffset = onOffset
        var document: CGFloat = 0
        var editorViewport: CGFloat = 0
        if let coordinator {
            document = MainActor.assumeIsolated { coordinator.scrollDocumentHeight }
            editorViewport = MainActor.assumeIsolated { coordinator.scrollViewportHeight }
        }
        editorViewport = max(editorViewport, 1)
        let scrollable = document > editorViewport + 0.5
        let scrollRange = max(document - editorViewport, 0)
        let value01 = scrollRange > 0 ? min(max(0, topOffset) / scrollRange, 1) : 0
        let knob = document > 0 ? min(max(editorViewport / document, 0.03), 1) : 1
        v.sync(
            visible: scrollable,
            knobProportion: knob,
            value: value01,
            scrollRange: scrollRange
        )
    }

    final class ScrollerView: NSView {
        var onOffset: (CGFloat) -> Void = { _ in }
        let scroller = NSScroller()

        /// Canonical content range: documentHeight - editor clip viewport.
        private var scrollRange: CGFloat = 0
        /// Canonical content-point offset, kept in sync from SwiftUI state.
        private var currentOffset: CGFloat = 0
        private var knobProportion: CGFloat = 1
        private var isDragging = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            // Legacy style: a standalone (non-scroll-view) scroller draws
            // its knob without the overlay system's hover/fade management,
            // which would leave it invisible at rest.
            scroller.scrollerStyle = .legacy
            scroller.target = self
            scroller.action = #selector(scrollerChanged)
            // Constraints keep the knob track pinned to the view's full
            // height no matter how SwiftUI sizes the host.
            scroller.translatesAutoresizingMaskIntoConstraints = false
            addSubview(scroller)
            NSLayoutConstraint.activate([
                scroller.leadingAnchor.constraint(equalTo: leadingAnchor),
                scroller.trailingAnchor.constraint(equalTo: trailingAnchor),
                scroller.topAnchor.constraint(equalTo: topAnchor),
                scroller.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        /// Every point in the 15pt strip belongs to this scroller, even in
        /// the areas the knob does not currently occupy.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard !scroller.isHidden, bounds.contains(point) else { return nil }
            return self
        }

        // MARK: State sync

        /// Idempotent sync from the SwiftUI-owned state.
        func sync(visible: Bool, knobProportion: CGFloat, value: CGFloat, scrollRange: CGFloat) {
            scroller.isHidden = !visible
            self.knobProportion = min(max(knobProportion, 0.03), 1)
            self.scrollRange = scrollRange
            currentOffset = value * scrollRange
            guard visible else { return }
            scroller.knobProportion = self.knobProportion
            // Only touch the value when it differs, so an in-flight knob
            // drag is never fought by the sync pass.
            if abs(scroller.doubleValue - value) > 0.002 {
                scroller.doubleValue = value
            }
        }

        // MARK: Interaction

        private func knobHeight() -> CGFloat {
            min(max(knobProportion, 0.03), 1) * bounds.height
        }

        private func updateFromMouse(_ event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            let travel = max(bounds.height - knobHeight(), 1)
            // AppKit y grows upward while the document offset grows
            // downward, so map the press point against the track top.
            let knobCenterFromTop = bounds.height - p.y
            let fraction = min(max((knobCenterFromTop - knobHeight() / 2) / travel, 0), 1)
            guard scrollRange > 0 else { return }
            onOffset(fraction * scrollRange)
        }

        override func mouseDown(with event: NSEvent) {
            guard !scroller.isHidden else { return }
            let knobBottomY = bounds.height - knobOffsetFromTop() - knobHeight()
            let knobRect = NSRect(x: 0, y: knobBottomY, width: bounds.width, height: knobHeight())
            let p = convert(event.locationInWindow, from: nil)
            // A press outside the knob recenters it on the press point
            // (modern overlay behavior); a press on the knob starts a drag.
            if !knobRect.contains(p) {
                updateFromMouse(event)
            }
            isDragging = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDragging else { return }
            updateFromMouse(event)
        }

        override func mouseUp(with event: NSEvent) {
            isDragging = false
        }

        override func scrollWheel(with event: NSEvent) {
            guard !scroller.isHidden, scrollRange > 0 else {
                super.scrollWheel(with: event)
                return
            }
            // Same conversion as the answer column's wheel catcher: a
            // "content down" gesture arrives as a negative raw delta and
            // must increase the top-down offset.
            let raw = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY : event.scrollingDeltaY * 16
            let next = min(max(0, currentOffset - raw), scrollRange)
            onOffset(next)
        }

        private func knobOffsetFromTop() -> CGFloat {
            guard scrollRange > 0 else { return 0 }
            let travel = max(bounds.height - knobHeight(), 1)
            let fraction = min(max(currentOffset / scrollRange, 0), 1)
            return fraction * travel
        }

        /// Fires only if AppKit's own tracking ever drives the scroller
        /// (it normally does not outside a scroll view).
        @objc private func scrollerChanged() {
            onOffset(CGFloat(scroller.doubleValue) * scrollRange)
        }
    }
}
