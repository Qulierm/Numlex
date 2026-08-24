import AppKit
import Combine
import NumlexCore
import SwiftUI

/// NSTextView-backed editor for a sheet.
///
/// Each logical line is highlighted by its evaluation result; per-line
/// metrics (the union of all wrapped fragments) are reported to the answer
/// column, and the clip view's bounds origin drives pixel-exact scroll
/// sync. Line numbers are drawn in a leading strip inside the same view,
/// so the gutter shares the editor's background and has no divider.
struct NotebookEditor: NSViewRepresentable {
    var text: Binding<String>
    var fontSize: Double
    var lineHeight: Double
    var lineNumbers: Bool
    var rates: Rates
    var decimalPlaces: Int
    /// Editor scroll offset, top-down points in editor-content coordinates
    /// (0 = top of the document).
    var onScroll: (CGFloat) -> Void
    /// Per-logical-line block metrics in text-container coordinates.
    var onLayout: (LineMetrics) -> Void
    /// User typing — pushes the new string up to the model.
    var onTextChange: (String) -> Void
    /// One-shot focus request: the sheet ID the owner wants focused (nil
    /// means none). Consumed exactly once after the editor is attached
    /// to the window — plain sheet switches never carry one.
    var focusRequestID: Sheet.ID?
    /// Called exactly once after the request was consumed (or to clear
    /// the owner's token when the editor goes away unconsumed).
    var onFocusConsumed: () -> Void
    /// Lets the owner publish the coordinator (for answer→editor sync).
    var onReady: (NotebookEditorCoordinator) -> Void

    func makeCoordinator() -> NotebookEditorCoordinator {
        NotebookEditorCoordinator(
            fontSize: fontSize,
            lineHeight: lineHeight,
            lineNumbers: lineNumbers,
            rates: rates,
            decimalPlaces: decimalPlaces,
            onScroll: onScroll,
            onLayout: onLayout,
            onTextChange: onTextChange,
            focusRequestID: focusRequestID,
            onFocusConsumed: onFocusConsumed,
            onReady: onReady
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScroll()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(
            text: text.wrappedValue,
            fontSize: fontSize,
            lineHeight: lineHeight,
            lineNumbers: lineNumbers,
            rates: rates,
            decimalPlaces: decimalPlaces,
            onScroll: onScroll,
            onLayout: onLayout,
            onTextChange: onTextChange,
            focusRequestID: focusRequestID,
            onFocusConsumed: onFocusConsumed
        )
    }
}

/// Owns the NSScrollView/NSTextView pair and all TextKit bookkeeping.
@MainActor
final class NotebookEditorCoordinator: NSObject {
    let scrollView: NSScrollView
    let textView: NotebookTextView
    var onScroll: (CGFloat) -> Void
    var onLayout: (LineMetrics) -> Void
    var onTextChange: (String) -> Void

    /// Set by `textView(_:shouldChangeTextIn:replacementString:)` when
    /// the pending AppKit edit carries a non-empty replacement (typing or
    /// paste), i.e. a user insertion; consumed and cleared on the next
    /// `textDidChange` pass. Programmatic storage rewrites bypass the
    /// delegate, so they can never arm the flag.
    private var pendingInsertion = false
    private var fontSize: Double
    private var lineHeight: Double
    private var lineNumbers: Bool
    private var rates: Rates
    private var decimalPlaces: Int
    /// One-shot focus request, armed by init/update and cleared the
    /// moment it is consumed (or the editor leaves the window).
    private var pendingFocusID: Sheet.ID?
    var onFocusConsumed: () -> Void = {}
    private var observer: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?
    /// True used document height (content + insets), independent of the
    /// frame padding that keeps the whole surface focusable.
    private(set) var usedDocumentHeight: CGFloat = 0

    init(fontSize: Double, lineHeight: Double, lineNumbers: Bool,
         rates: Rates, decimalPlaces: Int,
         onScroll: @escaping (CGFloat) -> Void,
         onLayout: @escaping (LineMetrics) -> Void,
         onTextChange: @escaping (String) -> Void,
         focusRequestID: Sheet.ID?,
         onFocusConsumed: @escaping () -> Void,
         onReady: (NotebookEditorCoordinator) -> Void) {
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.lineNumbers = lineNumbers
        self.rates = rates
        self.decimalPlaces = decimalPlaces
        self.pendingFocusID = focusRequestID
        self.onFocusConsumed = onFocusConsumed
        self.onScroll = onScroll
        self.onLayout = onLayout
        self.onTextChange = onTextChange

        let contentSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let tv = NotebookTextView(frame: NSRect(origin: .zero, size: contentSize))
        let sv = EditorScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        self.textView = tv
        self.scrollView = sv
        super.init()

        tv.delegate = self
        tv.string = ""
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = contentSize
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.containerSize = contentSize
        tv.textContainer?.widthTracksTextView = true
        // Width 0: the text is indented via the paragraph style so the whole
        // container (gutter included) stays inside the drawable area — the
        // text view clips drawing to the text container.
        tv.textContainerInset = NSSize(width: 0, height: Design.editorTopInset)
        tv.backgroundColor = .textBackgroundColor
        tv.drawsBackground = true
        tv.isRichText = false
        // Undo is off: every edit rewrites the full attributed string for
        // highlighting, which would corrupt character-level undo records.
        tv.allowsUndo = false

        // The editor's own scroller is hidden: a single native NSScroller
        // at the window's trailing edge (EdgeScroller) represents the shared
        // document/viewport/offset, so there is exactly one scroll state.
        sv.hasVerticalScroller = false
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.scrollerStyle = .overlay
        sv.documentView = tv
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.automaticallyAdjustsContentInsets = false

        // The focus handshake: the request may already be armed from
        // init, but focus can only be taken once the view is in a
        // window — EditorScrollView reports attachment via
        // viewDidMoveToWindow, and update() re-arms/retries meanwhile.
        sv.onWindowChanged = { [weak self] in
            MainActor.assumeIsolated { self?.handleWindowChanged() }
        }
        handleWindowChanged()

        applyTypography()
        textView.typingAttributes = typingAttrs
        onReady(self)

        // The flipped document view makes the clip bounds' y origin the
        // top-down scroll offset used for answer-column sync.
        sv.contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: sv.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onScroll(self.scrollView.contentView.bounds.origin.y)
            }
        }
        // Wrapping changes when the width changes.
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: tv,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshLayoutAndMetrics()
            }
        }
    }

    func makeScroll() -> NSScrollView {
        scrollView
    }

    /// Consumes the one-shot focus request exactly once, and only while
    /// this editor is attached to a window: the caret goes to UTF-16
    /// position 0 and the text view becomes first responder. The request
    /// is armed per sheet ID and this representable is recreated per
    /// sheet (`.id(sheet.id)`), so it can only ever land on the right
    /// editor; ordinary switches, renames, settings and imports never
    /// arm it.
    private func tryConsumeFocus() {
        guard pendingFocusID != nil, let window = scrollView.window else { return }
        pendingFocusID = nil
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        window.makeFirstResponder(textView)
        notifyConsumed()
    }

    /// Window attachment changed: consume a pending request on attach,
    /// drop it on detach (window close / sheet switch) so it can never
    /// fire late on a different sheet.
    private func handleWindowChanged() {
        if scrollView.window != nil {
            tryConsumeFocus()
        } else {
            if pendingFocusID != nil {
                pendingFocusID = nil
                notifyConsumed()
            }
        }
    }

    /// Clears the owner's token on the next main-queue turn: updateNSView
    /// runs during SwiftUI's commit, and mutating observable state
    /// synchronously there could re-enter the update cycle. The request
    /// itself was already cleared locally, so this can only clear the
    /// token once (a repeat call is a no-op).
    private func notifyConsumed() {
        DispatchQueue.main.async { [onFocusConsumed] in
            onFocusConsumed()
        }
    }

    func update(text: String, fontSize: Double, lineHeight: Double,
                lineNumbers: Bool, rates: Rates, decimalPlaces: Int,
                onScroll: @escaping (CGFloat) -> Void,
                onLayout: @escaping (LineMetrics) -> Void,
                onTextChange: @escaping (String) -> Void,
                focusRequestID: Sheet.ID?,
                onFocusConsumed: @escaping () -> Void) {
        self.onScroll = onScroll
        self.onLayout = onLayout
        self.onTextChange = onTextChange
        self.onFocusConsumed = onFocusConsumed
        var appearanceChanged = false
        if fontSize != self.fontSize { self.fontSize = fontSize; appearanceChanged = true }
        if lineHeight != self.lineHeight { self.lineHeight = lineHeight; appearanceChanged = true }
        if lineNumbers != self.lineNumbers { self.lineNumbers = lineNumbers; appearanceChanged = true }
        if rates != self.rates { self.rates = rates; appearanceChanged = true }
        if decimalPlaces != self.decimalPlaces { self.decimalPlaces = decimalPlaces; appearanceChanged = true }
        if appearanceChanged {
            textView.lineNumbers = lineNumbers
            applyTypography()
        }
        // The owner may arm a one-shot focus request after the view was
        // created; re-arm and retry while we are (or are about to be)
        // attached to a window.
        if let id = focusRequestID {
            pendingFocusID = id
            if scrollView.window != nil { tryConsumeFocus() }
        }
        if text != textView.string {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
            // Sheet switches load pre-migrated content. This bypasses
            // shouldChangeTextIn, so no insertion flag is armed and the
            // load is never treated as a user edit.
            highlight()
            refreshLayoutAndMetrics()
            // Sheet switches carry new content back to the top.
            let clip = scrollView.contentView
            let delta = -clip.bounds.origin.y
            if abs(delta) > 0.5 { clip.scroll(NSPoint(x: 0, y: delta)) }
        }
    }

    /// Document height in content points, for the edge scroller's knob
    /// proportion. The coordinator is recreated per sheet, so this never
    /// carries stale metrics across sheets.
    /// Editor viewport height in content points (the clip view's bounds),
    /// the canonical denominator for scroll ranges. Distinct from any
    /// SwiftUI-side measurement: the answer column's own viewport is
    /// shorter because the Total row occupies fixed space.
    var scrollViewportHeight: CGFloat {
        MainActor.assumeIsolated { scrollView.contentView.bounds.height }
    }

    /// Forward a raw wheel event (phases, momentum, precise deltas) into
    /// the editor's scroll view so the editor stays the single native
    /// scroll source. Used by the answer column's wheel bridge instead of
    /// manually accumulating CGFloat deltas.
    func forwardScrollWheel(_ event: NSEvent) {
        MainActor.assumeIsolated { scrollView.scrollWheel(with: event) }
    }

    /// True document height for the edge scroller's knob proportion. Never
    /// the padded frame height: padding exists only to keep the empty area
    /// focusable and must not create a phantom scroll range.
    var scrollDocumentHeight: CGFloat {
        usedDocumentHeight
    }

    /// Sets the editor's scroll position so editor-content y `offset` sits
    /// at the top (answer→editor pixel sync). The clip bounds' origin is
    /// the flipped document offset; the scroll is applied as a clamped
    /// relative delta (the same primitive NSTextView's own wheel handling
    /// uses), because clip views re-tile away raw bounds writes.
    func setScrollOffset(_ offset: CGFloat) {
        let clip = scrollView.contentView
        // The frame is padded to the viewport height, so the true scroll
        // range comes from the used document height, not the frame.
        let documentHeight = usedDocumentHeight
        let maxOffset = max(0, documentHeight - clip.bounds.height)
        let target = min(max(0, offset), maxOffset)
        guard abs(target - clip.bounds.origin.y) > 0.5 else { return }
        // Write the clip bounds directly: NSView.scroll(_:) has
        // "make the point visible" semantics and is a no-op while the
        // target point is already inside the visible rectangle.
        clip.bounds = NSRect(
            x: clip.bounds.origin.x, y: target,
            width: clip.bounds.width, height: clip.bounds.height
        )
    }

    // MARK: - Typography + highlighting

    private func applyTypography() {
        let font = NSFont.systemFont(ofSize: fontSize)
        textView.font = font
        textView.textColor = .textColor
        // New characters and new paragraphs inherit the gutter indent and
        // the fixed line height from the first keystroke on.
        textView.typingAttributes = typingAttrs
        textView.needsDisplay = true
        if !textView.string.isEmpty { highlight() }
    }

    /// Attributes every new character/paragraph starts with: system font,
    /// the fixed white base color and the indented fixed-line-height
    /// paragraph style. A first char or a newline can never land left of
    /// the gutter; highlight() recolors semantic spans on the same tick.
    private var typingAttrs: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: Design.baseText,
            .paragraphStyle: paragraphStyle()
        ]
    }

    private var textIndent: CGFloat { Design.gutterWidth + Design.textLeading }

    private func paragraphStyle() -> NSMutableParagraphStyle {
        let para = NSMutableParagraphStyle()
        let lh = CGFloat(lineHeight)
        para.minimumLineHeight = lh
        para.maximumLineHeight = lh
        para.firstLineHeadIndent = textIndent
        para.headIndent = textIndent
        return para
    }

    /// Restyles the current text IN PLACE on the shared text storage: base
    /// attributes first, then per-result colors/fonts. The characters are
    /// never replaced, so the selection, caret, IME marked text and undo
    /// records are untouched (the old full-string replacement clobbered
    /// them on every keystroke).
    private func highlight() {
        guard let storage = textView.textStorage else { return }
        let text = storage.string
        guard !text.isEmpty else {
            // Empty: keep the typing/default attributes, do not reset the
            // storage to an unstyled attributed string.
            textView.typingAttributes = typingAttrs
            return
        }
        // IME conversion in flight: leave the marked text untouched and
        // restyle fully when the conversion commits (hasMarkedText flips
        // back to false on the next edit).
        guard !textView.hasMarkedText() else {
            textView.typingAttributes = typingAttrs
            return
        }
        let content = text as NSString
        var vars: [String: Double] = [:]
        let rows = evaluateSheet(text, variables: &vars, rates: rates, decimalPlaces: decimalPlaces)
        let spans = SyntaxClassifier.spans(for: text, rates: rates, decimalPlaces: decimalPlaces)

        let font = NSFont.systemFont(ofSize: fontSize)
        let base: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Design.baseText,
            .paragraphStyle: paragraphStyle()
        ]

        storage.beginEditing()
        storage.setAttributes(base, range: NSRange(location: 0, length: content.length))

        var lineStart = 0
        let parts = text.components(separatedBy: "\n")
        for (i, line) in parts.enumerated() {
            let len = (line as NSString).length
            defer { lineStart += len + (i < parts.count - 1 ? 1 : 0) }
            guard i < rows.count, len > 0 else { continue }
            let range = NSRange(location: lineStart, length: len)
            switch rows[i] {
            case .error:
                // No whole-line red: errors are painted from their
                // lexical spans only, everything else stays white base.
                applySpans(i < spans.count ? spans[i] : [], lineStart: lineStart, in: storage)
            case .title:
                storage.addAttribute(.font,
                                     value: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                                     range: range)
                storage.addAttribute(.foregroundColor, value: Design.titleColor, range: range)
            case .number, .variable:
                applySpans(i < spans.count ? spans[i] : [], lineStart: lineStart, in: storage)
            case .blank, .skip:
                break
            }
        }
        storage.endEditing()
        textView.typingAttributes = typingAttrs
        textView.needsDisplay = true
    }

    /// Paints the classified token spans of one line at its document
    /// offset using the Design palette tokens (raised matte sRGB values;
    /// see Design.swift for the exact numbers). Operators, `to` and
    /// unknown words keep the fixed white base.
    private func applySpans(_ lineSpans: [SyntaxSpan], lineStart: Int, in storage: NSTextStorage) {
        for span in lineSpans {
            let r = NSRange(location: span.range.location + lineStart, length: span.range.length)
            let color: NSColor
            switch span.role {
            case .number: color = Design.numberColor
            case .variable: color = Design.variableColor
            case .conversion: color = Design.conversionColor
            }
            storage.addAttribute(.foregroundColor, value: color, range: r)
        }
    }

    // MARK: - Metrics

    /// Recomputes layout and reports per-line block metrics (container
    /// coordinates). Called after edits, setting changes and width changes.
    func refreshLayoutAndMetrics() {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        lm.ensureLayout(for: tc)
        // NSTextView grows its frame with content but never shrinks it;
        // a stale tall document leaves phantom scroll room after a sheet
        // switch. Keep the frame tight to the used content height.
        let used = lm.usedRect(for: tc)
        let needed = ceil(used.height) + textView.textContainerInset.height * 2
        usedDocumentHeight = needed
        // Keep the document at least as tall as the viewport so clicks in
        // the empty area below a short document still focus the text view.
        // The true scroll range always comes from usedDocumentHeight, so
        // this padding never creates phantom scroll room.
        let viewport = scrollView.contentView.bounds.height
        let target = max(needed, viewport)
        let frame = textView.frame
        if abs(frame.height - target) > 0.5 {
            textView.frame = NSRect(x: frame.origin.x, y: frame.origin.y,
                                    width: frame.width, height: target)
        }
        onLayout(computeMetrics())
        textView.needsDisplay = true
    }

    private func computeMetrics() -> LineMetrics {
        guard let lm = textView.layoutManager else {
            return LineMetrics(lines: [])
        }
        let content = textView.string as NSString
        guard content.length > 0 else { return LineMetrics(lines: []) }
        var lines: [LineMetrics.Line] = []
        var index = 0
        var finished = false
        content.enumerateSubstrings(
            in: NSRange(location: 0, length: content.length),
            options: .byLines
        ) { _, lineRange, _, _ in
            guard !finished else { return }
            let firstGlyph = lm.glyphIndexForCharacter(at: lineRange.location)
            guard firstGlyph != NSNotFound else {
                finished = true
                return
            }
            let lastChar = lineRange.location + lineRange.length - 1
            let lastGlyph = lm.glyphIndexForCharacter(at: lastChar)
            guard lastGlyph != NSNotFound else {
                finished = true
                return
            }
            var top = CGFloat.greatestFiniteMagnitude
            var bottom = -CGFloat.greatestFiniteMagnitude
            var g = firstGlyph
            while g <= lastGlyph {
                let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                top = min(top, frag.minY)
                bottom = max(bottom, frag.maxY)
                g += 1
            }
            if top <= bottom {
                lines.append(LineMetrics.Line(index: index, top: top, height: max(bottom - top, 1)))
            }
            index += 1
            if lastChar >= content.length - 1 { finished = true }
        }
        return LineMetrics(lines: lines)
    }
}

extension NotebookEditorCoordinator: NSTextViewDelegate {
    /// NSTextViewDelegate's user-edit hook (keyboard input, paste, delete,
    /// newline all flow through here). The coordinator is @MainActor, so
    /// the nonisolated requirement runs under assumeIsolated. Re-highlight
    /// in place, re-measure and push the new string up to the model; the
    /// resulting SwiftUI update re-enters update() with an equal string
    /// and stops there, so no reentrancy loop is possible.
    nonisolated func textDidChange(_ notification: Notification) {
        // AppKit delivers this on the main thread. The pipeline runs
        // synchronously (not in a queued Task) so that a fast user edit
        // is always canonicalized before the NEXT keystroke lands; an
        // async hop let stale format passes race with fresh input and
        // scramble selections.
        let sender = notification.object as? NSTextView
        MainActor.assumeIsolated {
            guard let sender, self.textView === sender else { return }
            let new = sender.string
            let insertion = self.pendingInsertion
            self.pendingInsertion = false
            if self.applyAutoFormat(insertion: insertion) {
                // The programmatic storage rewrite does NOT reliably
                // re-post textDidChange (AppKit suppresses it within the
                // same editing pass), so the rest of the pipeline runs
                // here, on the already-canonical text. If a re-entrant
                // notification does fire it is idempotent: same string,
                // no second format pass (fixed point), equal model state.
                let canonical = self.textView.string
                self.textView.caretLine = Self.caretLineIndex(of: self.textView)
                self.highlight()
                self.refreshLayoutAndMetrics()
                self.onTextChange(canonical)
                self.onScroll(self.scrollView.contentView.bounds.origin.y)
                return
            }
            self.textView.caretLine = Self.caretLineIndex(of: self.textView)
            self.highlight()
            self.refreshLayoutAndMetrics()
            self.onTextChange(new)
            self.onScroll(self.scrollView.contentView.bounds.origin.y)
        }
    }

    /// On user INSERTION the mathematical lines are canonicalized IN
    /// PLACE: `*` becomes `×`, one space around binary operators and
    /// `=`, unary signs and `%` attached. The pass is keyed to a
    /// non-empty replacement recorded by
    /// `textView(_:shouldChangeTextIn:replacementString:)` — so a paste
    /// that replaces an equal or longer selection still formats, while
    /// pure deletions (Backspace, delete, cut) never reformat and can
    /// remove spaces and operators without the formatter reinserting
    /// them. IME composition is never touched mid-conversion: the commit
    /// keystroke flows through this same path with `hasMarkedText()`
    /// false. The selection is remapped to the same semantic insertion
    /// points via the formatter's UTF-16 map, and caret/line state is
    /// recomputed on the re-entrant notification — no reentrancy loop is
    /// possible because the canonical text is a fixed point of the pass.
    private func applyAutoFormat(insertion: Bool) -> Bool {
        guard let storage = textView.textStorage else { return false }
        guard !textView.hasMarkedText() else { return false }
        guard insertion else { return false }
        let newText = storage.string
        let canonical = NotebookFormatting.canonicalDocument(newText)
        guard canonical != newText else { return false }
        let sel = textView.selectedRange()
        let map = NotebookFormatting.mapDocument(from: newText, to: canonical)
        let start = map[sel.location]
        let end = min(map[sel.location + sel.length], (canonical as NSString).length)
        storage.beginEditing()
        storage.replaceCharacters(
            in: NSRange(location: 0, length: (newText as NSString).length),
            with: canonical)
        storage.endEditing()
        textView.setSelectedRange(NSRange(location: start, length: max(0, end - start)))
        return true
    }

    /// Selection changed (arrow keys, mouse click/drag, selection by
    /// keyboard, paste). The AppKit requirement passes a Notification,
    /// not the text view — a mistyped parameter would silently stop the
    /// delegate from ever firing. Update the gutter's active line and
    /// repaint: the current line must change visually without any edit.
    /// AppKit asks the delegate before every edit it performs itself
    /// (typing, paste, cut, delete keys) with the replacement string —
    /// the reliable signal that distinguishes an insertion from a pure
    /// deletion, independent of how the document's net length changes.
    /// Direct storage rewrites (our own format pass, sheet switches)
    /// bypass this hook, so the flag can never trigger reentrancy.
    /// IME composition segments are ignored; the composition commit is
    /// handled by the `hasMarkedText()` guards in the pipeline.
    nonisolated func textView(_ textView: NSTextView,
                              shouldChangeTextIn charRange: NSRange,
                              replacementString: String?) -> Bool {
        MainActor.assumeIsolated {
            guard self.textView === textView, !textView.hasMarkedText() else { return }
            self.pendingInsertion = !(replacementString ?? "").isEmpty
        }
        return true
    }

    nonisolated func textViewDidChangeSelection(_ notification: Notification) {
        let sender = notification.object as? NSTextView
        Task { @MainActor in
            guard let sender, self.textView === sender else { return }
            self.textView.caretLine = Self.caretLineIndex(of: self.textView)
            self.textView.needsDisplay = true
        }
    }

    /// 1-based logical line the caret sits on: the number of newlines
    /// before the caret's UTF-16 location, plus one. That matches
    /// TextKit's visual line, including the trailing empty line that
    /// follows a final newline.
    private static func caretLineIndex(of tv: NSTextView) -> Int {
        let caret = tv.selectedRange().location
        let content = tv.string as NSString
        guard caret > 0, content.length > 0 else { return 1 }
        let prefix = content.substring(with: NSRange(location: 0, length: min(caret, content.length)))
        return prefix.components(separatedBy: "\n").count
    }
}

/// The editor's scroll view, reporting every window attachment change so
/// the coordinator can complete (or cancel) the one-shot focus handshake.
private final class EditorScrollView: NSScrollView {
    var onWindowChanged: (() -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChanged?()
    }
}

/// Document text view. Draws the line numbers (the caret's line brighter).
final class NotebookTextView: NSTextView {
    var lineHeight: Double = 30
    var lineNumbers: Bool = true
    /// 1-based logical line the caret currently sits on (set by the
    /// coordinator on every selection change).
    var caretLine: Int = 1

    // MARK: Caret blink (self-managed)

    /// v2.1: AppKit's blinker invalidates only the *default* thin
    /// insertion area, so letting it drive the turns makes its small
    /// rect alternate with our large custom one. The view now owns the
    /// blink: a repeating timer toggles `caretBlinkOn` and invalidates
    /// OUR rect — the very same rect that draw() paints — so erasure
    /// and drawing can never disagree about size. `drawInsertionPoint`
    /// is a no-op that suppresses AppKit's own caret entirely. Focus,
    /// selection and IME are preserved: the caret is drawn only while
    /// this view is the first responder with an empty (insertion)
    /// selection, and every selection/text change snaps it back to fully on.
    private var caretBlinkTimer: Timer?
    private var caretBlinkOn = true
    private var selectionObserver: NSObjectProtocol?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // v2: the empty new sheet already has a line, so the gutter draws
        // for every document — drawLineNumbers handles the empty case
        // with an explicit synthetic first-line fragment.
        if lineNumbers {
            drawLineNumbers()
        }
        drawCaret(dirtyRect)
    }

    /// Paint the large custom caret while the blink phase is on. The
    /// rect comes from the SAME CaretGeometry math the on-turn used to
    /// draw, so the visible caret is one constant shape in every
    /// document state (empty, populated, caret-at-end, trailing empty
    /// line, wrapped lines).
    private func drawCaret(_ dirtyRect: NSRect) {
        guard window?.firstResponder === self,
              selectedRange().length == 0,
              caretBlinkOn,
              let caretRect = currentCaretRect(),
              dirtyRect.intersects(caretRect) else { return }
        Design.caretColor.set()
        NSBezierPath(rect: caretRect).fill()
    }

    private func startCaretBlink() {
        caretBlinkOn = true
        caretBlinkTimer?.invalidate()
        let timer = Timer(timeInterval: 0.53, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.caretBlinkOn.toggle()
                // Invalidate exactly the rect drawCaret paints — one
                // geometry for both erasure (off) and drawing (on).
                if let rect = self.currentCaretRect() {
                    self.setNeedsDisplay(rect)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        caretBlinkTimer = timer
        setNeedsDisplay(bounds)
    }

    private func stopCaretBlink() {
        caretBlinkTimer?.invalidate()
        caretBlinkTimer = nil
    }

    /// Any selection or text change snaps the caret back to fully on
    /// and restarts the rhythm (standard editor behavior).
    private func resetCaretBlink() {
        guard window?.firstResponder === self else { return }
        startCaretBlink()
        if let rect = currentCaretRect() {
            setNeedsDisplay(rect)
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            if selectionObserver == nil {
                selectionObserver = NotificationCenter.default.addObserver(
                    forName: Notification.Name("NSTextDidChangeSelectionNotification"),
                    object: self,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.resetCaretBlink()
                    }
                }
            }
            startCaretBlink()
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            stopCaretBlink()
            if let observer = selectionObserver {
                NotificationCenter.default.removeObserver(observer)
                selectionObserver = nil
            }
            // Erase a drawn caret now that the view has lost focus.
            setNeedsDisplay(bounds)
        }
        return ok
    }

    override func didChangeText() {
        super.didChangeText()
        resetCaretBlink()
    }

    /// The fragment (container coordinates) the caret must be centered on
    /// for the CURRENT selection, covering every document shape:
    /// - empty document (no glyphs at all): synthetic first-line fragment
    ///   at the top inset with the fixed line height;
    /// - populated document, caret on a real character: that character's
    ///   TextKit line fragment (glyphs and gutter share this exact rect);
    /// - caret at the very END of a document without a final newline:
    ///   the last glyph's fragment;
    /// - document ending in a newline, caret on the trailing empty line:
    ///   the synthetic trailing fragment (usedRect minus one fixed line
    ///   height — the same math the gutter uses for that number);
    /// - wrapped lines fall out for free because each fragment is per
    ///   visual line.
    private func caretAnchor() -> (fragment: CGRect, glyph: Int)? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let lh = CGFloat(lineHeight)
        if lm.numberOfGlyphs == 0 {
            return (CaretGeometry.emptyLineFragment(top: 0, lineHeight: lh), NSNotFound)
        }
        let caret = selectedRange().location
        let charCount = (string as NSString).length
        if caret >= charCount {
            if string.hasSuffix("\n") {
                let used = lm.usedRect(for: tc)
                return (CaretGeometry.emptyLineFragment(top: used.height - lh, lineHeight: lh), NSNotFound)
            }
            return (lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil),
                    lm.numberOfGlyphs - 1)
        }
        let glyph = lm.glyphIndexForCharacter(at: caret)
        guard glyph != NSNotFound, glyph < lm.numberOfGlyphs else {
            return (lm.lineFragmentRect(forGlyphAt: lm.numberOfGlyphs - 1, effectiveRange: nil),
                    lm.numberOfGlyphs - 1)
        }
        return (lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil), glyph)
    }

    /// The shared visual ROW BOX the caret centers on: the anchor
    /// fragment's row origin with the fixed line height (or the exact
    /// measured advance to the next fragment — see
    /// CaretGeometry.rowBox). Centering on the natural TextKit fragment
    /// midline instead sits the caret too high whenever the fixed line
    /// height exceeds the natural fragment height.
    private func caretRowBox() -> CGRect? {
        guard let anchor = caretAnchor(), let lm = layoutManager else { return nil }
        var next: CGRect?
        if anchor.glyph != NSNotFound {
            // The first fragment below the anchor is the next visual row
            // (wrapped lines included); its advance is the exact extra-
            // line geometry the row box uses.
            var found = false
            lm.enumerateLineFragments(
                forGlyphRange: NSMakeRange(0, lm.numberOfGlyphs)
            ) { rect, _, _, _, stop in
                if !found, rect.minY > anchor.fragment.minY + 0.5 {
                    next = rect
                    found = true
                    stop.pointee = true
                }
            }
        }
        return CaretGeometry.rowBox(
            fragment: anchor.fragment,
            nextFragment: next,
            fixedLineHeight: CGFloat(lineHeight)
        )
    }

    /// v2 caret: the configured line height stretches every line fragment
    /// beyond the font's natural line box, so AppKit's default insertion
    /// point (thin, hugging the fragment top) sits visibly high and too
    /// light. We draw a 2 pt caret pixel aligned and centered on the SAME
    /// TextKit fragment the glyphs and gutter use (caretFragment), with
    /// the x AppKit computed for the selection. The rect is in view
    /// coordinates because the fragment rect is in container coordinates
    /// plus the container inset.
    /// The final caret rect in VIEW coordinates: `CaretGeometry.caretRect`
    /// centered on the shared row box (`caretRowBox()`), with the x taken
    /// from TextKit's own selection geometry (head indent, wrapped-line
    /// origins and the empty-document position — no arbitrary global
    /// offset).
    private func caretViewRect(passedX: CGFloat) -> NSRect? {
        guard let rowBox = caretRowBox() else { return nil }
        let font = self.font ?? NSFont.systemFont(ofSize: 14)
        let naturalHeight = font.ascender - font.descender + font.leading
        // Center the caret on the row's INK centerline (baseline minus
        // half a cap height), not on the raw row-box midline: the fixed
        // row's extra space is taken from above the natural line box, so
        // the midline lands visibly too high next to the glyphs.
        let bl = CaretGeometry.baseline(
            rowTop: rowBox.minY, rowHeight: rowBox.height,
            ascender: font.ascender, naturalHeight: naturalHeight
        )
        let center = CaretGeometry.inkCenter(baseline: bl, capHeight: font.capHeight)
        let centerBox = CGRect(
            x: 0, y: center - rowBox.height / 2, width: 0, height: rowBox.height
        )
        return CaretGeometry.caretRect(
            x: passedX,
            fragment: centerBox,
            containerInsetY: textContainerInset.height,
            naturalGlyphHeight: naturalHeight
        )
    }

    /// The insertion-point x in VIEW coordinates, computed from the
    /// layout manager's own geometry: `boundingRect(forGlyphRange:in:)`
    /// for the current selection (head indent, wrapped-line origins and
    /// the caret-at-end position all come from TextKit — no arbitrary
    /// global offset), and the paragraph's first-line head indent for
    /// the empty document, where AppKit itself places the insertion
    /// point.
    private func caretX() -> CGFloat {
        guard let lm = layoutManager, let tc = textContainer else {
            return textContainerOrigin.x
        }
        lm.ensureLayout(for: tc)
        let content = string as NSString
        if lm.numberOfGlyphs == 0 {
            let indent = (typingAttributes[.paragraphStyle] as? NSParagraphStyle)?
                .firstLineHeadIndent ?? 0
            // TextKit anchors every line fragment at lineFragmentPadding
            // (default 5 pt) inside the container, so the empty-document
            // insertion point must include it too — exactly where the
            // first typed character (and AppKit's own insertion point)
            // will land.
            return textContainerOrigin.x + tc.lineFragmentPadding + indent
        }
        let sel = selectedRange()
        let start = min(sel.location, content.length)
        let end = min(sel.location + sel.length, content.length)
        let rect = lm.boundingRect(
            forGlyphRange: NSRange(location: start, length: end - start),
            in: tc
        )
        return textContainerOrigin.x + rect.minX
    }

    /// The current custom caret rect in VIEW coordinates (nil while the
    /// layout manager has no selection to anchor on). Used by both the
    /// blink timer (invalidation) and drawCaret (painting).
    private func currentCaretRect() -> NSRect? {
        caretViewRect(passedX: caretX())
    }

    /// v2.1: intentionally empty — the view owns the blink
    /// (caretBlinkTimer + drawCaret). Drawing anything here would let
    /// AppKit's thin default insertion rect alternate with the large
    /// custom rect.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn: Bool) {
        // Suppressed on purpose; see the v2.1 notes above.
    }

    private func drawLineNumbers() {
        guard let lm = layoutManager, let tc = textContainer else { return }
        lm.ensureLayout(for: tc)
        let content = string as NSString
        let visible = bounds
        let insetY = textContainerInset.height
        let numberFont = Design.gutterFont()
        // Baseline alignment uses real font metrics: the line's baseline sits
        // `ascender` below the centered font line box inside the (possibly
        // stretched) fragment, and the number is placed on the same baseline.
        let textFont = self.font ?? NSFont.systemFont(ofSize: 14)
        // Numbers anchor to a fixed x token; the gap to the text is
        // Design.textLeading relative to the gutter, independent of it.
        let numberRightX = Design.gutterNumberRight

        func drawNumber(_ n: Int, fragmentTop: CGFloat, fragmentHeight: CGFloat) {
            let y = insetY + fragmentTop
            if y + fragmentHeight < visible.minY - 40 || y > visible.maxY + 40 { return }
            // SAME centerline as the caret: the row's baseline (the font
            // descender sits on the fixed row's bottom edge) minus half a
            // cap height of the TEXT font; the number then sits on that
            // center with its own cap height (one shared rule for caret
            // and gutter in every document state).
            let rowBaseline = CaretGeometry.baseline(
                rowTop: y, rowHeight: fragmentHeight,
                ascender: textFont.ascender,
                naturalHeight: textFont.ascender - textFont.descender + textFont.leading
            )
            let center = CaretGeometry.inkCenter(
                baseline: rowBaseline, capHeight: textFont.capHeight
            )
            let baseline = center + numberFont.capHeight / 2
            let str = "\(n)" as NSString
            let size = str.size(withAttributes: [.font: numberFont])
            // The caret's line is one semantic step brighter than the rest.
            let color: NSColor = (n == caretLine)
                ? Design.gutterColorActive
                : Design.gutterColor
            str.draw(
                at: NSPoint(x: numberRightX - size.width,
                             y: baseline - numberFont.ascender),
                withAttributes: [.font: numberFont, .foregroundColor: color]
            )
        }

        // Empty new sheet: line 1 exists before any typing. It uses the
        // SAME synthetic first-line fragment the caret centers on (top =
        // 0 in container coordinates, fixed line height), so the number
        // aligns exactly with the caret. No text is inserted and nothing
        // feeds the evaluator — this is pure gutter drawing. caretLine is
        // 1 on a fresh sheet, so the number renders with the active color.
        if content.length == 0 {
            let lh = CGFloat(self.lineHeight)
            drawNumber(1, fragmentTop: 0, fragmentHeight: lh)
            return
        }

        // Collect the visual fragments first so each number can be
        // centered in the SAME shared row box the caret uses: row origin
        // + exact advance to the next fragment (or the fixed line height
        // on the last line) — never the shorter natural fragment height.
        var rowTops: [CGFloat] = []
        var rowFragHeights: [CGFloat] = []
        content.enumerateSubstrings(
            in: NSRange(location: 0, length: content.length),
            options: .byLines
        ) { _, lineRange, _, _ in
            let firstGlyph = lm.glyphIndexForCharacter(at: lineRange.location)
            guard firstGlyph != NSNotFound else { return }
            let frag = lm.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
            rowTops.append(frag.minY)
            rowFragHeights.append(frag.height)
        }
        // A document ending in a newline has a trailing empty line that
        // byLines does not enumerate; the caret can sit on it, so draw its
        // number too (fixed line height keeps the geometry exact).
        if content.hasSuffix("\n") {
            let used = lm.usedRect(for: tc)
            let trailingTop = used.height - CGFloat(self.lineHeight)
            if trailingTop >= 0 {
                rowTops.append(trailingTop)
                rowFragHeights.append(CGFloat(self.lineHeight))
            }
        }
        for i in rowTops.indices {
            let nextTop: CGFloat? = i + 1 < rowTops.count ? rowTops[i + 1] : nil
            let box = CaretGeometry.rowBox(
                fragment: CGRect(x: 0, y: rowTops[i], width: 0, height: rowFragHeights[i]),
                nextFragment: nextTop.map { CGRect(x: 0, y: $0, width: 0, height: 0) },
                fixedLineHeight: CGFloat(self.lineHeight)
            )
            drawNumber(i + 1, fragmentTop: box.minY, fragmentHeight: box.height)
        }
    }

    override var acceptsFirstResponder: Bool { true }
}
