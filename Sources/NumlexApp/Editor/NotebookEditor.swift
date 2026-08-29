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
    /// The user's input preferences (r19): operator padding/star/
    /// backtick/QuickOperators, thousand grouping and the previous-
    /// answer insertion gate.
    var inputPrefs: InputPreferences
    /// r21: notebook styling (font design + role colors). Resolved
    /// through `NotebookPalette` — the same resolver the settings
    /// preview uses.
    var styling: StylingPreferences
    /// r33: the GLOBAL user constants, seeded into the syntax
    /// classifier so constant names paint green exactly like declared
    /// names (and constant-driven lines evaluate the same way).
    var constants: [UserConstant]
    var onPreviousAnswerTrigger: ((Character, Int) -> Bool)?
    /// Editor scroll offset, top-down points in editor-content coordinates
    /// (0 = top of the document).
    var onScroll: (CGFloat) -> Void
    /// Per-logical-line block metrics in text-container coordinates.
    var onLayout: (LineMetrics) -> Void
    /// User typing — pushes the new string up to the model together with
    /// the edit AppKit announced before performing it (nil when the
    /// coordinator could not attribute the change), so line identity and
    /// token marker positions stay exact.
    var onTextChange: (String, NotebookEdit?) -> Void
    /// Current per-marker token states (from the reference-aware
    /// evaluation) — the editor renders each U+FFFC as a live capsule
    /// from these, never from stored text.
    var tokenStates: [TokenResolution]
    /// The sheet's reference sidecar, needed only to build the clipboard
    /// representation of a copy (internal pastes preserve the link).
    var tokenRefs: [AnswerReference]
    /// A paste carrying Numlex reference data produced these references;
    /// the model registers them once their final marker locations are
    /// known.
    var onPasteReferences: ([AnswerReference]) -> Void
    /// One-shot focus request: the sheet ID the owner wants focused (nil
    /// means none). Consumed exactly once after the editor is attached
    /// to the window — plain sheet switches never carry one.
    var focusRequestID: Sheet.ID?
    /// UTF-16 caret position for the pending focus request (nil = 0).
    /// Used by token insertion to land the caret right after the token.
    var focusPosition: Int?
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
            styling: styling,
            onScroll: onScroll,
            onLayout: onLayout,
            onTextChange: onTextChange,
            tokenStates: tokenStates,
            tokenRefs: tokenRefs,
            onPasteReferences: onPasteReferences,
            focusRequestID: focusRequestID,
            focusPosition: focusPosition,
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
            inputPrefs: inputPrefs,
            styling: styling,
            constants: constants,
            onPreviousAnswerTrigger: onPreviousAnswerTrigger,
            onScroll: onScroll,
            onLayout: onLayout,
            onTextChange: onTextChange,
            tokenStates: tokenStates,
            tokenRefs: tokenRefs,
            onPasteReferences: onPasteReferences,
            focusRequestID: focusRequestID,
            focusPosition: focusPosition,
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
    var onTextChange: (String, NotebookEdit?) -> Void
    var onPasteReferences: ([AnswerReference]) -> Void
    /// The live token states for the current content (the editor draws a
    /// capsule attachment at every U+FFFC from these).
    var tokenStates: [TokenResolution] = []
    /// The sheet's references, used only to build the internal clipboard
    /// representation of a copy.
    var tokenRefs: [AnswerReference] = []
    /// Pure appearance-pass state keyed by the STABLE reference UUIDs
    /// (never marker locations): seeded with the IDs present when this
    /// editor instance attaches (load/relaunch/switch — no replay), so
    /// only newly introduced references animate, once each.
    var appearance = TokenAppearance()
    /// One-shot chained tick for the appearance pass (1/60 s, common
    /// run-loop mode); the chain self-terminates on completion, removal
    /// or window detach, so no perpetual timer survives.
    private var animTimer: Timer?
    private var animRunning = false

    /// The intent of the pending user edit (see `EditIntent` in
    /// NumlexCore), armed by
    /// `textView(_:shouldChangeTextIn:replacementString:)` before every
    /// AppKit-performed edit and consumed by the next `textDidChange`
    /// pass. Only a `.content` intent triggers the canonical-format
    /// pass: a `.whitespace` intent keeps the literal space/tab/newline
    /// in the storage with the caret right after it (so `5` + Space +
    /// `m to cm` types as `5 m to cm`, not `5m`), and `.none` (a pure
    /// deletion) never reformats. Programmatic storage rewrites bypass
    /// the delegate and can never arm it; a value left over from a
    /// cancelled edit is at worst a skipped format pass, never a forced
    /// one.
    private var pendingIntent: EditIntent = .none
    /// The user edit AppKit announced before performing it (armed in
    /// `textView(_:shouldChangeTextIn:replacementString:)`, consumed by
    /// the next `textDidChange` pass) — the exact input the line-identity
    /// reconciliation needs to keep token marker positions exact.
    private var pendingRange: NSRange?
    private var pendingReplacement: String = ""
    /// The last known model text (before the in-flight edit); the
    /// paste-reference remap needs the pre-edit content.
    private var lastText: String = ""
    private var fontSize: Double
    private var lineHeight: Double
    private var lineNumbers: Bool
    private var rates: Rates
    private var decimalPlaces: Int
    private var inputPrefs: InputPreferences = .defaults
    /// r21: notebook styling; the palette is derived from it on every
    /// use (cheap struct), so a setting change re-renders immediately.
    private var styling: StylingPreferences = .defaults
    /// r33: global constants for the highlight pipeline (cheap struct
    /// copy; a settings edit changes this and re-highlights in place).
    private var constants: [UserConstant] = []
    private var onPreviousAnswerTrigger: ((Character, Int) -> Bool)?
    /// The exact UTF-16 map of the format pass applied by the LAST
    /// `applyAutoFormat` call (attached to the edit that follows it).
    private var lastFormatMap: [Int]?
    /// One-shot focus request, armed by init/update and cleared the
    /// moment it is consumed (or the editor leaves the window).
    private var pendingFocusID: Sheet.ID?
    private var pendingFocusPosition: Int?
    var onFocusConsumed: () -> Void = {}
    private var observer: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?

    init(fontSize: Double, lineHeight: Double, lineNumbers: Bool,
         rates: Rates, decimalPlaces: Int,
         styling: StylingPreferences,
         onScroll: @escaping (CGFloat) -> Void,
         onLayout: @escaping (LineMetrics) -> Void,
         onTextChange: @escaping (String, NotebookEdit?) -> Void,
         tokenStates: [TokenResolution],
         tokenRefs: [AnswerReference],
         onPasteReferences: @escaping ([AnswerReference]) -> Void,
         focusRequestID: Sheet.ID?,
         focusPosition: Int?,
         onFocusConsumed: @escaping () -> Void,
         onReady: (NotebookEditorCoordinator) -> Void) {
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.lineNumbers = lineNumbers
        self.rates = rates
        self.decimalPlaces = decimalPlaces
        self.styling = styling
        self.pendingFocusID = focusRequestID
        self.pendingFocusPosition = focusPosition
        self.onFocusConsumed = onFocusConsumed
        self.onScroll = onScroll
        self.onLayout = onLayout
        self.onTextChange = onTextChange
        self.tokenStates = tokenStates
        self.tokenRefs = tokenRefs
        // The references already on the sheet at attach time are KNOWN:
        // a load, relaunch or sheet switch must never replay their
        // appearance pass.
        appearance.seed(ids: tokenRefs.map(\.id))
        self.onPasteReferences = onPasteReferences

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
        // r36: the centralized deterministic white editor surface (the
        // app is permanently Aqua; a dynamic catalog color is avoided so
        // the surface can never resolve to the dark value).
        tv.backgroundColor = Design.editorBackground
        tv.drawsBackground = true
        tv.isRichText = false
        // Undo is off: every edit rewrites the full attributed string for
        // highlighting, which would corrupt character-level undo records.
        tv.allowsUndo = false

        // The editor's own scrollers stay hidden: no pane in the app shows
        // a scroll bar, yet the native NSScrollView keeps full wheel,
        // momentum and elastic-bounce behavior for the shared document.
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
        // Token insertion lands the caret right after the fresh marker;
        // ordinary focus requests keep the historical position 0.
        let pos = min(pendingFocusPosition ?? 0, (textView.string as NSString).length)
        textView.setSelectedRange(NSRange(location: max(0, pos), length: 0))
        window.makeFirstResponder(textView)
        notifyConsumed()
    }

    /// Window attachment changed: consume a pending request on attach,
    /// drop it on detach (window close / sheet switch) so it can never
    /// fire late on a different sheet; a detach also cancels any
    /// in-flight appearance pass.
    private func handleWindowChanged() {
        if scrollView.window != nil {
            tryConsumeFocus()
        } else {
            stopAppearanceTick()
            if pendingFocusID != nil {
                pendingFocusID = nil
                notifyConsumed()
            }
        }
    }

    // MARK: - Answer-token appearance pass

    /// Starts the one-shot chained tick (1/60 s) that drives the
    /// appearance pass. Only the animating capsules' union rect is
    /// invalidated each frame — never the whole document.
    private func startAppearanceTick() {
        guard !animRunning else { return }
        animRunning = true
        scheduleAppearanceTick()
    }

    private func scheduleAppearanceTick() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.appearanceTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animTimer = timer
    }

    private func appearanceTick() {
        let now = ProcessInfo.processInfo.systemUptime
        var locations: Set<Int> = []
        var settled: Set<Int> = []
        var progress: [Int: Double] = [:]
        for ref in tokenRefs {
            if let p = appearance.progress(for: ref.id, now: now) {
                progress[ref.location] = p
                locations.insert(ref.location)
            } else if appearance.inFlight[ref.id] != nil {
                // A pass that settles on THIS frame: the final repaint
                // must cover its capsule too.
                settled.insert(ref.location)
            }
        }
        appearance.expire(now: now)
        textView.tokenAnimProgress = progress
        if appearance.isAnimating {
            if let rect = textView.tokenCapsuleUnionRect(locations: locations) {
                textView.setNeedsDisplay(rect)
            }
            scheduleAppearanceTick()
        } else {
            // Settled: stop the chain and repaint the exact rects in
            // their final state (layout was never touched).
            stopAppearanceTick()
            let all = locations.union(settled)
            if let rect = textView.tokenCapsuleUnionRect(locations: all) {
                textView.setNeedsDisplay(rect)
            }
        }
    }

    private func stopAppearanceTick() {
        animTimer?.invalidate()
        animTimer = nil
        animRunning = false
        textView.tokenAnimProgress = [:]
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
                inputPrefs: InputPreferences,
                styling: StylingPreferences,
                constants: [UserConstant],
                onPreviousAnswerTrigger: ((Character, Int) -> Bool)?,
                onScroll: @escaping (CGFloat) -> Void,
                onLayout: @escaping (LineMetrics) -> Void,
                onTextChange: @escaping (String, NotebookEdit?) -> Void,
                tokenStates: [TokenResolution],
                tokenRefs: [AnswerReference],
                onPasteReferences: @escaping ([AnswerReference]) -> Void,
                focusRequestID: Sheet.ID?,
                focusPosition: Int?,
                onFocusConsumed: @escaping () -> Void) {
        self.inputPrefs = inputPrefs
        self.onPreviousAnswerTrigger = onPreviousAnswerTrigger
        self.onScroll = onScroll
        self.onLayout = onLayout
        self.onTextChange = onTextChange
        self.onPasteReferences = onPasteReferences
        // Compare BEFORE replacing: when the content stays byte-identical
        // but the resolved token states changed (a source edit changed an
        // answer, a token broke or recovered), the capsules must be
        // rebuilt in THIS update — nothing else re-runs the highlight
        // pipeline, and the per-keystroke highlight has already painted
        // with the previous commit's states.
        let statesChanged = self.tokenStates != tokenStates
            || self.tokenRefs != tokenRefs
        self.tokenStates = tokenStates
        self.tokenRefs = tokenRefs
        // Newly introduced reference IDs (double-click insertion, valid
        // internal paste) play ONE appearance pass; live label/source
        // updates and broken/recovered transitions change neither the ID
        // set nor any start time, so they never replay. Reduce Motion
        // renders the final state immediately (no pass scheduled).
        let fresh = appearance.observe(
            ids: tokenRefs.map(\.id),
            now: ProcessInfo.processInfo.systemUptime,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        if !fresh.isEmpty, appearance.isAnimating {
            startAppearanceTick()
        }
        self.onFocusConsumed = onFocusConsumed
        var appearanceChanged = false
        if fontSize != self.fontSize { self.fontSize = fontSize; appearanceChanged = true }
        if lineHeight != self.lineHeight { self.lineHeight = lineHeight; appearanceChanged = true }
        if lineNumbers != self.lineNumbers { self.lineNumbers = lineNumbers; appearanceChanged = true }
        if rates != self.rates { self.rates = rates; appearanceChanged = true }
        if decimalPlaces != self.decimalPlaces { self.decimalPlaces = decimalPlaces; appearanceChanged = true }
        if styling != self.styling { self.styling = styling; appearanceChanged = true }
        // r33: a settings edit changes the constants under an UNCHANGED
        // document: the re-highlight must run here (nothing else re-runs
        // the pipeline), without touching content, selection or caret.
        let constantsChanged = constants != self.constants
        if constantsChanged { self.constants = constants }
        if appearanceChanged {
            textView.lineNumbers = lineNumbers
            applyTypography()
            // Font design/size and palette changes re-lay-out the
            // document so the answer column's metrics (baselines,
            // row heights, wrapping) follow the new font immediately.
            refreshLayoutAndMetrics()
        }
        // The owner may arm a one-shot focus request after the view was
        // created; re-arm and retry while we are (or are about to be)
        // attached to a window.
        if let id = focusRequestID {
            pendingFocusID = id
            pendingFocusPosition = focusPosition
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
            lastText = text
        } else if statesChanged {
            // Content identical, token states fresh: rebuild the capsule
            // attachments and draw states from the just-resolved states
            // and re-lay-out synchronously (label width changes shift
            // following glyphs and wrapping). The string, selection,
            // caret, IME state are untouched and the text pipeline is
            // not re-entered, so this can only run once per commit.
            highlight()
            refreshLayoutAndMetrics()
        } else if constantsChanged {
            // Content identical, constants changed: re-classify every
            // line in place (constant names turn green, constant-driven
            // lines re-evaluate) — string, selection and caret stay.
            highlight()
        }
    }

    /// Forward a raw wheel event (phases, momentum, precise deltas) into
    /// the editor's scroll view so the editor stays the single native
    /// scroll source. Used by the answer column's wheel bridge instead of
    /// manually accumulating CGFloat deltas.
    func forwardScrollWheel(_ event: NSEvent) {
        MainActor.assumeIsolated { scrollView.scrollWheel(with: event) }
    }

    // MARK: - Typography + highlighting

    /// The r21 palette resolver: the same type the settings preview
    /// uses, so role colors and the font design can never diverge.
    private var palette: NotebookPalette { NotebookPalette(styling: styling) }

    private func applyTypography() {
        let font = palette.editorFont(size: fontSize)
        textView.font = font
        textView.textColor = .textColor
        // New characters and new paragraphs inherit the gutter indent and
        // the fixed line height from the first keystroke on.
        textView.typingAttributes = typingAttrs
        textView.needsDisplay = true
        if !textView.string.isEmpty { highlight() }
    }

    /// Attributes every new character/paragraph starts with: the chosen
    /// font design, the fixed dark base color (Design.baseText on the
    /// white light theme) and the indented
    /// fixed-line-height paragraph style. A first char or a newline can
    /// never land left of the gutter; highlight() recolors semantic
    /// spans on the same tick.
    private var typingAttrs: [NSAttributedString.Key: Any] {
        [
            .font: palette.editorFont(size: fontSize),
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
        // The classifier is the single per-LINE source of truth: one
        // spans entry per logical line, aligned 1:1 with the text.
        // evaluateSheet now returns the same strict one-row-per-line
        // shape (indexed SheetLine), but styling is driven purely from
        // the classifier's spans plus the line-kind prefixes the
        // evaluator uses (hash heading, title).
        let spans = SyntaxClassifier.spans(for: text, rates: rates,
                                           decimalPlaces: decimalPlaces,
                                           constants: constants)

        let font = palette.editorFont(size: fontSize)
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
            guard len > 0 else { continue }
            let range = NSRange(location: lineStart, length: len)
            // Hash heading (same `hasPrefix("#")` rule as the
            // evaluator): the `#` marker is a bold-ish (.heavy) gray,
            // the body after it uses the chosen headings color, also
            // .heavy — slightly less heavy than the old .black body.
            if line.hasPrefix("#") {
                storage.addAttribute(
                    .font, value: palette.editorFont(size: fontSize, weight: .heavy),
                    range: NSRange(location: lineStart, length: 1)
                )
                storage.addAttribute(
                    .foregroundColor, value: Design.headingMarkerColor,
                    range: NSRange(location: lineStart, length: 1)
                )
                if len > 1 {
                    let body = NSRange(location: lineStart + 1, length: len - 1)
                    storage.addAttribute(
                        .font, value: palette.editorFont(size: fontSize, weight: .heavy),
                        range: body
                    )
                    storage.addAttribute(.foregroundColor, value: palette.headings, range: body)
                }
                continue
            }
            if line.hasPrefix("// ") {
                storage.addAttribute(
                    .font, value: palette.editorFont(size: fontSize, weight: .semibold),
                    range: range
                )
                storage.addAttribute(.foregroundColor, value: palette.comments, range: range)
                continue
            }
            // Everything else (expressions, assignments, conversions,
            // partial assignments and errors) is painted purely from the
            // line's classified spans; prose carries no spans and keeps
            // the base attributes set above.
            applySpans(i < spans.count ? spans[i] : [],
                       lineStart: lineStart, lineLength: len, in: storage)
        }
        applyTokenAttachments(in: storage)
        storage.endEditing()
        textView.typingAttributes = typingAttrs
        textView.needsDisplay = true
    }

    /// Rebuilds every U+FFFC marker's capsule attachment from the LIVE
    /// token states: the label always comes from the current source-line
    /// result (or the remembered `Line N` when broken), so a source edit
    /// updates the capsule on the next highlight without any stored
    /// value. The base `setAttributes` pass does not touch the
    /// `.attachment` key, so the attribute is rewritten from scratch on
    /// every highlight; a marker without a state never gets a capsule.
    private func applyTokenAttachments(in storage: NSTextStorage) {
        let content = storage.string as NSString
        guard content.length > 0 else { return }
        storage.removeAttribute(.attachment, range: NSRange(location: 0, length: content.length))
        // The ONE token label face (r23): medium rounded with
        // monospaced digits; the width reservation and the capsule ink
        // both resolve through Design.tokenFont.
        let font = Design.tokenFont(size: fontSize)
        var drawStates: [(location: Int, label: String, active: Bool)] = []
        for token in tokenStates {
            let p = token.location
            guard p >= 0, p < content.length,
                  content.character(at: p) == answerTokenMarkerUTF16 else { continue }
            let label: String
            let active: Bool
            switch token.state {
            case .active(_, _, let display):
                label = display
                active = true
            case .broken(let line):
                label = "Line \(line)"
                active = false
            }
            let width = TokenAttachment.capsuleWidth(label: label, font: font)
            storage.addAttribute(
                .attachment,
                value: TokenAttachment(width: width),
                range: NSRange(location: p, length: 1)
            )
            drawStates.append((p, label, active))
        }
        textView.tokenDrawStates = drawStates
        // Clipboard metadata: every marker's sidecar identity plus its
        // live display text (internal pastes preserve the link, external
        // copies expose the plain quantity or the Line N label).
        var meta: [(location: Int, sourceLineID: UUID, labelLine: Int, display: String)] = []
        for ref in tokenRefs {
            guard ref.location >= 0, ref.location < content.length,
                  content.character(at: ref.location) == answerTokenMarkerUTF16 else { continue }
            let state = tokenStates.first { $0.location == ref.location }?.state
            let display: String
            switch state {
            case .active(_, _, let d): display = d
            case .broken(let n): display = "Line \(n)"
            case nil: display = "Line \(ref.labelLine)"
            }
            meta.append((ref.location, ref.sourceLineID, ref.labelLine, display))
        }
        textView.tokenMeta = meta
    }

    /// Paints the classified token spans of one line at its document
    /// offset using the r21 palette (deterministic sRGB values; see
    /// Design.swift for the exact numbers of the fixed roles).
    /// Operators, `to`/`in`/`per`/`as` specifiers and `:` labels use
    /// their own configurable roles; money markers stay fixed; hash
    /// spans are styled by the dedicated hash-heading branch.
    private func applySpans(_ lineSpans: [SyntaxSpan], lineStart: Int,
                            lineLength: Int, in storage: NSTextStorage) {
        let storageLength = (storage.string as NSString).length
        for span in lineSpans {
            let r = NSRange(location: span.range.location + lineStart, length: span.range.length)
            // Hash spans are styled by the dedicated hash-heading branch
            // (heavy gray marker, heavy body), never by the chromatic
            // palette.
            guard let color: NSColor = switch span.role {
                case .number: palette.numbers
                case .operatorGlyph: palette.operators
                case .variable: palette.variables
                case .conversion: palette.units
                case .specifier: palette.specifiers
                case .label: palette.labels
                case .moneyMarker: Design.moneyMarkerColor
                case .hashMarker, .hashBody: nil
            } else { continue }
            // Final document-bound guard: even a malformed span (a bad
            // classifier result, an out-of-range offset, a zero-length
            // or negative range) can never raise NSRangeException — it
            // is simply dropped, so partial highlighting degrades to
            // base color instead of crashing the editor.
            guard r.location >= 0,
                  r.length > 0,
                  NSMaxRange(r) <= storageLength,
                  NSMaxRange(r) <= lineStart + lineLength else { continue }
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
        // Keep the document at least as tall as the viewport so clicks in
        // the empty area below a short document still focus the text view.
        // The padding only kicks in while the document is SHORTER than the
        // viewport, where the scroll range is already zero — so the native
        // scroll range stays tight to the used content with no phantom room.
        let viewport = scrollView.contentView.bounds.height
        let target = max(needed, viewport)
        let frame = textView.frame
        if abs(frame.height - target) > 0.5 {
            textView.frame = NSRect(x: frame.origin.x, y: frame.origin.y,
                                    width: frame.width, height: target)
        }
        let metrics = computeMetrics()
        onLayout(metrics)
        textView.needsDisplay = true
    }

    /// One metric per LOGICAL source line — the same split the evaluator
    /// uses (`components(separatedBy: "\n")`), so `lines[i].index == i`
    /// always holds and the answer column can bind by source index.
    /// Populated lines report the union of all their visual fragments
    /// (wrapped lines included); blank lines (leading, inner, and the
    /// trailing line after a final newline) are synthesized as one fixed
    /// line height right after the previous block — exactly where
    /// TextKit places the empty fragment, the same rule the gutter uses.
    /// Every line also carries the answer's target first-text baseline
    /// (`AnswerBaseline.baseline`) computed from the SAME real NSFont
    /// metrics and the CaretGeometry rule the caret and gutter draw from.
    private func computeMetrics() -> LineMetrics {
        guard let lm = textView.layoutManager, let tc = textView.textContainer else {
            return LineMetrics(lines: [])
        }
        lm.ensureLayout(for: tc)
        let parts = textView.string.components(separatedBy: "\n")
        let font = palette.editorFont(size: fontSize)
        let naturalHeight = font.ascender - font.descender + font.leading
        let fixedLineHeight = CGFloat(lineHeight)

        var lines: [LineMetrics.Line] = []
        var previousBottom: CGFloat = 0
        var offset = 0
        for (index, part) in parts.enumerated() {
            let partLength = (part as NSString).length
            var top: CGFloat
            var bottom: CGFloat
            var fragments = 0
            if partLength > 0 {
                let firstGlyph = lm.glyphIndexForCharacter(at: offset)
                let lastGlyph = lm.glyphIndexForCharacter(at: offset + partLength - 1)
                if firstGlyph != NSNotFound,
                   lastGlyph != NSNotFound, firstGlyph <= lastGlyph {
                    // Union of every visual fragment this line's glyphs
                    // occupy; distinct fragment tops count the wrapped pieces.
                    top = CGFloat.greatestFiniteMagnitude
                    bottom = -CGFloat.greatestFiniteMagnitude
                    var fragmentTops = Set<Double>()
                    var g = firstGlyph
                    while g <= lastGlyph {
                        let frag = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                        top = min(top, frag.minY)
                        bottom = max(bottom, frag.maxY)
                        fragmentTops.insert(frag.minY)
                        g += 1
                    }
                    fragments = fragmentTops.count
                } else {
                    // Defensive: a non-empty line with no mapped glyphs
                    // (should not happen after ensureLayout) still occupies
                    // one fixed line height.
                    top = previousBottom
                    bottom = top + fixedLineHeight
                }
            } else {
                // Synthesized empty line: one fixed line height after the
                // previous block (top = 0 for the first line of an empty
                // document — the same synthetic fragment the caret and
                // gutter use for that line).
                top = previousBottom
                bottom = top + fixedLineHeight
            }
            let height = max(bottom - top, 1)
            let baseline = AnswerBaseline.baseline(
                rowTop: top,
                rowHeight: height,
                fragmentCount: fragments,
                ascender: font.ascender,
                naturalHeight: naturalHeight,
                capHeight: font.capHeight
            )
            lines.append(LineMetrics.Line(
                index: index, top: top, height: height,
                fragmentCount: fragments, answerBaseline: baseline
            ))
            previousBottom = bottom
            offset += partLength + 1
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
            let intent = self.pendingIntent
            // The edit AppKit announced before performing this change —
            // the exact input line-identity reconciliation needs.
            let range = self.pendingRange
            let replacement = self.pendingReplacement
            self.pendingIntent = .none
            self.pendingRange = nil
            self.pendingReplacement = ""
            let oldText = self.lastText
            if self.applyAutoFormat(intent: intent) {
                let formatMap = self.lastFormatMap
                self.lastFormatMap = nil
                let edit = NotebookEdit(range: range, replacement: replacement, formatMap: formatMap)
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
                self.lastText = canonical
                self.onTextChange(canonical, edit)
                self.handlePasteReferences(edit: edit, oldText: oldText, final: canonical)
                self.onScroll(self.scrollView.contentView.bounds.origin.y)
                return
            }
            let edit = NotebookEdit(range: range, replacement: replacement)
            self.textView.caretLine = Self.caretLineIndex(of: self.textView)
            self.highlight()
            self.refreshLayoutAndMetrics()
            self.lastText = new
            self.onTextChange(new, edit)
            self.handlePasteReferences(edit: edit, oldText: oldText, final: new)
            self.onScroll(self.scrollView.contentView.bounds.origin.y)
        }
    }

    /// A paste that carried Numlex reference data left pending metadata on
    /// the text view (source line ID, remembered label, and the marker's
    /// UTF-16 offset INSIDE the pasted string). Once the final content is
    /// known, each marker's document position is derived by applying the
    /// announced edit to the pre-edit text and, when the canonical format
    /// pass followed the edit, replaying the format map. The model then
    /// registers the fresh references (its own reconciliation ran first,
    /// on the old references only).
    private func handlePasteReferences(edit: NotebookEdit, oldText: String, final: String) {
        let paste = textView.pendingPasteRefs
        textView.pendingPasteRefs = nil
        guard let paste, !paste.isEmpty, let range = edit.range, range.location >= 0 else { return }
        let nsOld = oldText as NSString
        guard range.location + range.length <= nsOld.length else { return }
        let intermediate = nsOld.replacingCharacters(in: range, with: edit.replacement)
        let nsFinal = final as NSString
        var refs: [AnswerReference] = []
        for p in paste {
            var pos = range.location + p.offset
            if intermediate != final {
                if let map = edit.formatMap, map.count == (intermediate as NSString).length + 1 {
                    // The editor's actual preference-aware pass: exact.
                    pos = map[min(max(pos, 0), map.count - 1)]
                } else {
                    guard NotebookFormatting.canonicalDocument(intermediate) == final else { continue }
                    let map = NotebookFormatting.mapDocument(from: intermediate, to: final)
                    pos = map[min(max(pos, 0), map.count - 1)]
                }
            }
            if pos >= 0, pos < nsFinal.length, nsFinal.character(at: pos) == answerTokenMarkerUTF16 {
                refs.append(AnswerReference(sourceLineID: p.sourceLineID, labelLine: p.labelLine, location: pos))
            }
        }
        if !refs.isEmpty { onPasteReferences(refs) }
    }

    /// On user INSERTION the mathematical lines are canonicalized IN
    /// PLACE: `*` becomes `×`, one space around binary operators and
    /// `=`, unary signs and `%` attached. The pass is keyed to the edit
    /// intent recorded by
    /// `textView(_:shouldChangeTextIn:replacementString:)`: only a
    /// `.content` edit formats, so a paste that replaces an equal or
    /// longer selection still formats, while pure deletions (Backspace,
    /// delete, cut) never reformat and can remove spaces and operators
    /// without the formatter reinserting them. A `.whitespace` edit
    /// (typed Space, Tab or Enter) is deliberately skipped in the same
    /// pass: the literal whitespace stays in the storage with the caret
    /// right after it, and the next non-whitespace keystroke resumes
    /// canonicalization — this is what makes typing `5 m to cm` space by
    /// space possible. IME composition is never touched mid-conversion: the commit
    /// keystroke flows through this same path with `hasMarkedText()`
    /// false. The selection is remapped to the same semantic insertion
    /// points via the formatter's UTF-16 map, and caret/line state is
    /// recomputed on the re-entrant notification — no reentrancy loop is
    /// possible because the canonical text is a fixed point of the pass.
    private func applyAutoFormat(intent: EditIntent) -> Bool {
        guard let storage = textView.textStorage else { return false }
        guard !textView.hasMarkedText() else { return false }
        guard intent == .content else { return false }
        let newText = storage.string
        // r19: the user's OWN input preferences drive the pass; the
        // returned map is the exact transformation (caret, marker and
        // pasted-reference remapping all reuse it).
        let (canonical, map) = InputFormatting.formatDocument(
            newText, prefs: self.inputPrefs, rates: self.rates, decimalPlaces: self.decimalPlaces)
        guard canonical != newText else { return false }
        self.lastFormatMap = map
        let sel = textView.selectedRange()
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
    /// the reliable signal that classifies the edit into an explicit
    /// `EditIntent` (`.content`, `.whitespace`, `.none`), independent of
    /// how the document's net length changes. Direct storage rewrites
    /// (our own format pass, sheet switches) bypass this hook, so the
    /// intent can never trigger reentrancy. IME composition segments
    /// are ignored; the composition commit is handled by the
    /// `hasMarkedText()` guards in the pipeline.
    nonisolated func textView(_ textView: NSTextView,
                              shouldChangeTextIn charRange: NSRange,
                              replacementString: String?) -> Bool {
        var rejected = false
        MainActor.assumeIsolated {
            guard self.textView === textView, !textView.hasMarkedText() else { return }
            let replacement = replacementString ?? ""
            // r19 previous-answer helper: an operator typed on a BLANK
            // line (right after Return) becomes `token + operator`, the
            // token linking the nearest earlier answerable line. The
            // model plans and inserts atomically; when it consumes the
            // keystroke we reject the raw edit and drop the pending
            // state so the next edit starts clean.
            if self.inputPrefs.insertPreviousAnswer,
               charRange.length == 0,
               replacement.count == 1,
               let op = replacement.first,
               PreviousAnswerPlan.operators.contains(op),
               self.caretLineIsBlank(textView: textView, caret: charRange.location),
               self.onPreviousAnswerTrigger?(op, charRange.location) == true {
                self.pendingIntent = .none
                self.pendingRange = nil
                self.pendingReplacement = ""
                rejected = true
                return
            }
            self.pendingIntent = EditIntent(replacement: replacementString)
            self.pendingRange = charRange
            self.pendingReplacement = replacement
        }
        return !rejected
    }

    /// The caret's logical line is blank (spaces/tabs only) — the gate
    /// for the previous-answer helper. Indentation before the caret is
    /// preserved (the insertion lands at the caret).
    private func caretLineIsBlank(textView: NSTextView, caret: Int) -> Bool {
        let ns = textView.string as NSString
        let c = min(max(caret, 0), ns.length)
        let nl = (ns.substring(to: c) as NSString).range(of: "\n", options: .backwards)
        let start = (nl.location == NSNotFound) ? 0 : nl.location + 1
        let lineEnd = (ns.substring(from: c) as NSString).range(of: "\n")
        let end = (lineEnd.location == NSNotFound) ? ns.length : c + lineEnd.location
        let line = ns.substring(with: NSRange(location: start, length: end - start))
        return line.allSatisfy { $0 == " " || $0 == "\t" }
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
    /// Clipboard metadata for every token marker in the document (the
    /// coordinator refreshes it on every highlight): the sidecar identity
    /// plus the LIVE display text used for the external plain string.
    var tokenMeta: [(location: Int, sourceLineID: UUID, labelLine: Int, display: String)] = []
    /// One-shot: a paste that carried Numlex reference data. Each entry
    /// is (source line ID, remembered label, the marker's UTF-16 offset
    /// inside the PASTED string); the coordinator consumes it after the
    /// paste edit settles and the model registers the fresh references.
    var pendingPasteRefs: [(sourceLineID: UUID, labelLine: Int, offset: Int)]?
    /// Live drawing states of the token capsules (the coordinator
    /// refreshes them on every highlight): marker location, current
    /// label and active flag.
    var tokenDrawStates: [(location: Int, label: String, active: Bool)] = []
    /// Appearance-animation progress (0...1) per marker location; a
    /// missing entry means the final settled state. The layout (the
    /// reserved glyph advance) is NEVER touched — only the drawn
    /// opacity and center scale of the capsule change.
    var tokenAnimProgress: [Int: Double] = [:]

    // MARK: - Clipboard (answer reference tokens)

    /// Copy: the plain string representation replaces every token marker
    /// with its LIVE display quantity (or `Line N` when inactive) so an
    /// external clipboard always gets plain text; when the selection
    /// contains tokens the sidecar link data is additionally written to
    /// the private `com.numlex.answerReferences` type so an internal
    /// paste restores the reference, not a snapshot.
    override func copy(_ sender: Any?) {
        let sel = selectedRange()
        guard sel.length > 0, let storage = textStorage else { return super.copy(sender) }
        // The raw selected text: it carries the U+FFFC markers verbatim.
        let selected = (storage.string as NSString).substring(with: sel)
        let ns = selected as NSString
        // The plain representation: every marker becomes its live display
        // text. This is what external consumers ever see.
        var plain = ""
        var payload: [TokenClipboardItem] = []
        var searchStart = 0
        while searchStart <= ns.length {
            let r = ns.range(of: "\u{FFFC}",
                             range: NSRange(location: searchStart, length: ns.length - searchStart))
            if r.location == NSNotFound { break }
            plain += ns.substring(with: NSRange(location: searchStart, length: r.location - searchStart))
            let docLoc = sel.location + r.location
            if let meta = tokenMeta.first(where: { $0.location == docLoc }) {
                plain += meta.display
                payload.append(TokenClipboardItem(
                    sourceLineID: meta.sourceLineID,
                    labelLine: meta.labelLine
                ))
            }
            searchStart = r.location + 1
        }
        plain += ns.substring(from: searchStart)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(plain, forType: .string)
        if !payload.isEmpty {
            // Internal representations: the marker-carrying text and the
            // sidecar identities, written only for Numlex's own pastes.
            pb.setString(selected, forType: .numlexTokenText)
            if let data = try? JSONEncoder().encode(payload) {
                pb.setData(data, forType: .numlexReferences)
            }
        }
    }

    /// Paste: a Numlex clipboard (the private marker-text and reference
    /// types present, aligned 1:1 with the markers of the marker text) is
    /// inserted WITH the markers and the metadata parked on the view for
    /// the coordinator — the link survives the round trip. Anything else
    /// is sanitized so an orphan U+FFFC can never enter the document.
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .numlexReferences),
           let s = pb.string(forType: .numlexTokenText),
           let items = try? JSONDecoder().decode([TokenClipboardItem].self, from: data) {
            var refs: [(sourceLineID: UUID, labelLine: Int, offset: Int)] = []
            var ok = true
            let ns = s as NSString
            var scan = 0
            for item in items {
                let r = ns.range(of: "\u{FFFC}",
                                 range: NSRange(location: scan, length: ns.length - scan))
                if r.location == NSNotFound { ok = false; break }
                refs.append((item.sourceLineID, item.labelLine, r.location))
                scan = r.location + 1
            }
            let tail = ns.range(of: "\u{FFFC}", range: NSRange(location: scan, length: ns.length - scan))
            if ok, refs.count == items.count, tail.location == NSNotFound {
                pendingPasteRefs = refs
                // insertText (not replaceCharacters) drives the full
                // delegate pipeline — shouldChangeTextIn arms the edit
                // range the paste-reference remap depends on.
                insertText(s, replacementRange: selectedRange())
                return
            }
        }
        if let s = pb.string(forType: .string), s.contains("\u{FFFC}") {
            replaceCharacters(in: selectedRange(), with: s.replacingOccurrences(of: "\u{FFFC}", with: ""))
        } else {
            super.paste(sender)
        }
    }

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
        drawTokenCapsules(dirtyRect)
        // v2: the empty new sheet already has a line, so the gutter draws
        // for every document — drawLineNumbers handles the empty case
        // with an explicit synthetic first-line fragment.
        if lineNumbers {
            drawLineNumbers()
        }
        drawCaret(dirtyRect)
    }

    /// Paints every token capsule over its marker glyph. The geometry is
    /// the fixed-row rule shared with the caret and the gutter: the
    /// capsule is vertically centered in the marker's row and its text
    /// sits on exactly that row's baseline — so a capsule reads as text
    /// on the line at every font size and line height.
    private func drawTokenCapsules(_ dirtyRect: NSRect) {
        guard !tokenDrawStates.isEmpty,
              let lm = layoutManager, let tc = textContainer else { return }
        lm.ensureLayout(for: tc)
        let content = string as NSString
        // The SAME label face applyTokenAttachments sized the reserved
        // advance with — width and ink can never disagree.
        let font = Design.tokenFont(size: (self.font ?? NSFont.systemFont(ofSize: 14)).pointSize)
        let naturalHeight = font.ascender - font.descender + font.leading
        // The ONE transform the gutter and caret use: the container
        // inset added exactly ONCE. textContainerOrigin already carries
        // the container's x position; the y inset is added here and
        // nowhere else (adding origin AND inset would double-count it).
        let insetY = textContainerInset.height
        for t in tokenDrawStates {
            guard t.location >= 0, t.location < content.length,
                  content.character(at: t.location) == answerTokenMarkerUTF16 else { continue }
            let glyph = lm.glyphIndexForCharacter(at: t.location)
            guard glyph != NSNotFound else { continue }
            // The reserved glyph advance gives the capsule's x range.
            let glyphRect = lm.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1), in: tc
            )
            // The SAME actual row box the caret centers on: the marker's
            // fragment plus the measured advance to the next fragment
            // (wrapped lines included), fixed line height as fallback.
            let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            var next: CGRect?
            var found = false
            lm.enumerateLineFragments(
                forGlyphRange: NSMakeRange(0, lm.numberOfGlyphs)
            ) { rect, _, _, _, stop in
                if !found, rect.minY > frag.minY + 0.5 {
                    next = rect
                    found = true
                    stop.pointee = true
                }
            }
            let row = CaretGeometry.rowBox(
                fragment: frag,
                nextFragment: next,
                fixedLineHeight: CGFloat(lineHeight)
            )
            let (capRect, labelBaseline, radius) = CaretGeometry.tokenCapsule(
                rowTop: insetY + row.minY,
                rowHeight: row.height,
                ascender: font.ascender,
                naturalHeight: naturalHeight,
                capHeight: font.capHeight,
                x: textContainerOrigin.x + glyphRect.minX,
                width: glyphRect.width
            )
            // The invalidation union covers the shadow extent (blur +
            // offset), the border and the sheen.
            guard capRect.insetBy(
                dx: -Design.tokenInvalidationInset,
                dy: -Design.tokenInvalidationInset
            ).intersects(dirtyRect) else { continue }
            // Appearance pass: opacity + CENTER scale inside the exact
            // final rect (nil progress = the locked final capsule).
            let progress = tokenAnimProgress[t.location]
            let scale = TokenAppearance.scale(progress: progress)
            let alpha = TokenAppearance.opacity(progress: progress)
            let cap = scale == 1
                ? capRect
                : CGRect(
                    x: capRect.midX - capRect.width * scale / 2,
                    y: capRect.midY - capRect.height * scale / 2,
                    width: capRect.width * scale,
                    height: capRect.height * scale
                )
            let r = radius * scale
            let path = NSBezierPath(roundedRect: cap, xRadius: r, yRadius: r)
            if t.active {
                drawTokenBubble(path: path, rect: cap, radius: r, alpha: alpha)
            } else {
                // Broken: the SAME geometry, flat muted surface — no
                // gradient, border, sheen or shadow, so it can never
                // read as active.
                Design.tokenFillInactive.withAlphaComponent(alpha).setFill()
                path.fill()
            }
            // The label sits on the row's actual text baseline (the same
            // rule the editor's own glyphs sit on), centered horizontally
            // in the reserved advance.
            let labelColor = (t.active ? Design.tokenText : Design.tokenTextInactive)
                .withAlphaComponent(alpha)
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: labelColor
            ]
            let labelSize = (t.label as NSString).size(withAttributes: labelAttrs)
            (t.label as NSString).draw(
                at: NSPoint(x: capRect.midX - labelSize.width / 2, y: labelBaseline - font.ascender),
                withAttributes: labelAttrs
            )
        }
    }

    /// One ACTIVE token bubble: the reference's luminous pass — a soft
    /// shadow, the base gradient (98% to 72%, top-leading to bottom-
    /// trailing in the flipped view space), the 1 pt white gradient
    /// border (an even-odd annulus) and the ~2 pt top sheen. All
    /// constants come from Design, so the look is centralized.
    private func drawTokenBubble(path: NSBezierPath, rect: NSRect,
                                 radius: CGFloat, alpha: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        // Soft shadow under the capsule (positive y in the flipped
        // view paints toward the bottom of the line, like the
        // reference's downward shadow).
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(Design.tokenShadowOpacity * alpha)
        shadow.shadowBlurRadius = Design.tokenShadowBlur
        shadow.shadowOffset = NSSize(width: 0, height: Design.tokenShadowOffsetY)
        shadow.set()
        let top = NSPoint(x: rect.minX, y: rect.minY)
        let bottom = NSPoint(x: rect.maxX, y: rect.maxY)
        // Luminous gradient fill.
        guard let fill = NSGradient(colors: [
            Design.tokenBase.withAlphaComponent(Design.tokenGradientTopAlpha * alpha),
            Design.tokenBase.withAlphaComponent(Design.tokenGradientBottomAlpha * alpha)
        ]) else { return }
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        fill.draw(from: top, to: bottom, options: [])
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.restoreGraphicsState()
        // 1 pt border: even-odd annulus painted with its own gradient.
        let inner = NSBezierPath(
            roundedRect: rect.insetBy(dx: 1, dy: 1),
            xRadius: max(0, radius - 1), yRadius: max(0, radius - 1)
        )
        let ring = path.copy() as! NSBezierPath
        ring.append(inner)
        ring.windingRule = .evenOdd
        guard let border = NSGradient(colors: [
            NSColor.white.withAlphaComponent(Design.tokenBorderTopAlpha * alpha),
            NSColor.white.withAlphaComponent(Design.tokenBorderBottomAlpha * alpha)
        ]) else { return }
        NSGraphicsContext.saveGraphicsState()
        ring.addClip()
        border.draw(from: top, to: bottom, options: [])
        NSGraphicsContext.restoreGraphicsState()
        // ~2 pt top sheen: a soft vertical fade inset like the
        // reference's blurred capsule strip.
        let w = Swift.max(rect.width - 32, 10)
        let h = Design.tokenHighlightHeight + 1
        let strip = CGRect(x: rect.midX - w / 2, y: rect.minY + 2, width: w, height: h)
        guard let sheen = NSGradient(colors: [
            NSColor.white.withAlphaComponent(Design.tokenHighlightAlpha * alpha),
            NSColor.white.withAlphaComponent(0)
        ]) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: strip, xRadius: h / 2, yRadius: h / 2).addClip()
        sheen.draw(
            from: NSPoint(x: rect.midX, y: strip.minY),
            to: NSPoint(x: rect.midX, y: strip.maxY),
            options: []
        )
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The union rect (view coordinates) of the capsule geometry of the
    /// given marker locations — the minimal invalidation target of the
    /// appearance tick. Returns nil when no location resolves to a
    /// drawable capsule.
    func tokenCapsuleUnionRect(locations: Set<Int>) -> NSRect? {
        guard !locations.isEmpty,
              let lm = layoutManager, let tc = textContainer else { return nil }
        lm.ensureLayout(for: tc)
        let content = string as NSString
        let font = self.font ?? NSFont.systemFont(ofSize: 14)
        let naturalHeight = font.ascender - font.descender + font.leading
        let insetY = textContainerInset.height
        var union: NSRect?
        for loc in locations {
            guard loc >= 0, loc < content.length,
                  content.character(at: loc) == answerTokenMarkerUTF16 else { continue }
            let glyph = lm.glyphIndexForCharacter(at: loc)
            guard glyph != NSNotFound else { continue }
            let glyphRect = lm.boundingRect(
                forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
            let frag = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            var next: CGRect?
            var found = false
            lm.enumerateLineFragments(
                forGlyphRange: NSMakeRange(0, lm.numberOfGlyphs)
            ) { rect, _, _, _, stop in
                if !found, rect.minY > frag.minY + 0.5 {
                    next = rect
                    found = true
                    stop.pointee = true
                }
            }
            let row = CaretGeometry.rowBox(
                fragment: frag,
                nextFragment: next,
                fixedLineHeight: CGFloat(lineHeight)
            )
            let (capRect, _, _) = CaretGeometry.tokenCapsule(
                rowTop: insetY + row.minY,
                rowHeight: row.height,
                ascender: font.ascender,
                naturalHeight: naturalHeight,
                capHeight: font.capHeight,
                x: textContainerOrigin.x + glyphRect.minX,
                width: glyphRect.width
            )
            let r = capRect.insetBy(dx: -Design.tokenInvalidationInset, dy: -Design.tokenInvalidationInset)
            union = union.map { $0.union(r) } ?? r
        }
        return union
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

// MARK: - Answer token attachment

extension NSPasteboard.PasteboardType {
    /// Private types written on copies that contain token markers: an
    /// internal paste reads them to preserve the valid reference link,
    /// external consumers only ever see the plain string representation.
    static let numlexTokenText = NSPasteboard.PasteboardType("com.numlex.answerTokenText")
    static let numlexReferences = NSPasteboard.PasteboardType("com.numlex.answerReferences")
}

/// One marker entry of the private clipboard payload (written per marker
/// in order, aligned 1:1 with the U+FFFC characters of the plain string
/// representation).
struct TokenClipboardItem: Codable {
    var sourceLineID: UUID
    var labelLine: Int
}

/// The U+FFFC glyph's attachment: a 1×1 TRANSPARENT image whose only job
/// is to reserve the capsule's horizontal width in the layout. The
/// capsule itself is painted by `NotebookTextView.drawTokenCapsules` at
/// the marker's glyph rect — deterministic geometry from the same fixed-
/// row rule the caret and gutter use, independent of TextKit's opaque
/// image-attachment box metrics.
final class TokenAttachment: NSTextAttachment {
    init(width: CGFloat) {
        super.init(data: nil, ofType: nil)
        let img = NSImage(size: NSSize(width: 1, height: 1))
        img.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        img.unlockFocus()
        image = img
        bounds = NSRect(x: 0, y: 0, width: width, height: 1)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// The capsule's horizontal width for a label: the label's text width
    /// plus the design padding on both sides (Design.tokenHPadding —
    /// 8 pt per side, 16 pt total). One place defines it, so the
    /// reserved layout width and the drawn capsule always agree.
    static func capsuleWidth(label: String, font: NSFont) -> CGFloat {
        let textW = (label as NSString).size(withAttributes: [.font: font]).width
        return ceil(textW) + Design.tokenHPadding * 2
    }
}
