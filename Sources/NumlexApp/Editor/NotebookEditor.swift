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
    var placeholder: String
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
    /// Lets the owner publish the coordinator (for answer→editor sync).
    var onReady: (NotebookEditorCoordinator) -> Void

    func makeCoordinator() -> NotebookEditorCoordinator {
        NotebookEditorCoordinator(
            placeholder: placeholder,
            fontSize: fontSize,
            lineHeight: lineHeight,
            lineNumbers: lineNumbers,
            rates: rates,
            decimalPlaces: decimalPlaces,
            onScroll: onScroll,
            onLayout: onLayout,
            onTextChange: onTextChange,
            onReady: onReady
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScroll()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(
            text: text.wrappedValue,
            placeholder: placeholder,
            fontSize: fontSize,
            lineHeight: lineHeight,
            lineNumbers: lineNumbers,
            rates: rates,
            decimalPlaces: decimalPlaces,
            onScroll: onScroll,
            onLayout: onLayout,
            onTextChange: onTextChange
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

    private var placeholder: String
    private var fontSize: Double
    private var lineHeight: Double
    private var lineNumbers: Bool
    private var rates: Rates
    private var decimalPlaces: Int
    private var observer: NSObjectProtocol?
    private var frameObserver: NSObjectProtocol?

    init(placeholder: String, fontSize: Double, lineHeight: Double, lineNumbers: Bool,
         rates: Rates, decimalPlaces: Int,
         onScroll: @escaping (CGFloat) -> Void,
         onLayout: @escaping (LineMetrics) -> Void,
         onTextChange: @escaping (String) -> Void,
         onReady: (NotebookEditorCoordinator) -> Void) {
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.lineNumbers = lineNumbers
        self.rates = rates
        self.decimalPlaces = decimalPlaces
        self.onScroll = onScroll
        self.onLayout = onLayout
        self.onTextChange = onTextChange

        let contentSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        let tv = NotebookTextView(frame: NSRect(origin: .zero, size: contentSize))
        let sv = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
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
        tv.placeholderText = placeholder

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

        applyTypography()
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

    func update(text: String, placeholder: String, fontSize: Double, lineHeight: Double,
                lineNumbers: Bool, rates: Rates, decimalPlaces: Int,
                onScroll: @escaping (CGFloat) -> Void,
                onLayout: @escaping (LineMetrics) -> Void,
                onTextChange: @escaping (String) -> Void) {
        self.onScroll = onScroll
        self.onLayout = onLayout
        self.onTextChange = onTextChange
        var appearanceChanged = false
        if placeholder != self.placeholder { self.placeholder = placeholder; appearanceChanged = true }
        if fontSize != self.fontSize { self.fontSize = fontSize; appearanceChanged = true }
        if lineHeight != self.lineHeight { self.lineHeight = lineHeight; appearanceChanged = true }
        if lineNumbers != self.lineNumbers { self.lineNumbers = lineNumbers; appearanceChanged = true }
        if rates != self.rates { self.rates = rates; appearanceChanged = true }
        if decimalPlaces != self.decimalPlaces { self.decimalPlaces = decimalPlaces; appearanceChanged = true }
        if appearanceChanged {
            textView.placeholderText = placeholder
            textView.lineNumbers = lineNumbers
            applyTypography()
        }
        if text != textView.string {
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
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

    var scrollDocumentHeight: CGFloat {
        scrollView.contentView.documentView?.frame.height ?? 0
    }

    /// Sets the editor's scroll position so editor-content y `offset` sits
    /// at the top (answer→editor pixel sync). The clip bounds' origin is
    /// the flipped document offset; the scroll is applied as a clamped
    /// relative delta (the same primitive NSTextView's own wheel handling
    /// uses), because clip views re-tile away raw bounds writes.
    func setScrollOffset(_ offset: CGFloat) {
        let clip = scrollView.contentView
        let documentHeight = clip.documentView?.frame.height ?? 0
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
        textView.placeholderFontSize = fontSize
        textView.font = font
        textView.textColor = .textColor
        textView.needsDisplay = true
        if !textView.string.isEmpty { highlight() }
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

    private func highlight() {
        let text = textView.string
        guard !text.isEmpty else {
            textView.textStorage?.setAttributedString(NSAttributedString(string: text))
            return
        }
        let content = text as NSString
        var vars: [String: Double] = [:]
        let rows = evaluateSheet(text, variables: &vars, rates: rates, decimalPlaces: decimalPlaces)

        let attr = NSMutableAttributedString(string: text)
        let font = NSFont.systemFont(ofSize: fontSize)
        attr.addAttribute(.font, value: font, range: NSRange(location: 0, length: content.length))

        var lineStart = 0
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            let len = (line as NSString).length
            guard i < rows.count else { break }
            let range = NSRange(location: lineStart, length: len)
            switch rows[i] {
            case .number:
                attr.addAttribute(.foregroundColor,
                                  value: NSColor(calibratedRed: 0.40, green: 0.62, blue: 0.95, alpha: 1),
                                  range: range)
            case .variable:
                attr.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: range)
            case .error:
                attr.addAttribute(.foregroundColor, value: NSColor.systemRed.withAlphaComponent(0.85), range: range)
            case .title:
                attr.addAttribute(.font, value: NSFont.systemFont(ofSize: fontSize, weight: .semibold), range: range)
                attr.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
            case .blank, .skip:
                break
            }
            lineStart += len
            if i < text.components(separatedBy: "\n").count - 1 { lineStart += 1 }
        }
        attr.addAttribute(.paragraphStyle, value: paragraphStyle(),
                          range: NSRange(location: 0, length: content.length))

        let selection = textView.selectedRanges
        textView.textStorage?.setAttributedString(attr)
        textView.setSelectedRanges(selection, affinity: .upstream, stillSelecting: false)
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
        let frame = textView.frame
        if abs(frame.height - needed) > 0.5 {
            textView.frame = NSRect(x: frame.origin.x, y: frame.origin.y,
                                    width: frame.width, height: needed)
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
    /// The text view is edited directly by the user; re-highlight, re-measure
    /// and push the new string up to the SwiftUI binding.
    nonisolated func textViewDidChangeText(_ sender: NSTextView) {
        Task { @MainActor in
            guard self.textView === sender else { return }
            let new = sender.string
            self.highlight()
            self.refreshLayoutAndMetrics()
            self.onTextChange(new)
            self.onScroll(self.scrollView.contentView.bounds.origin.y)
        }
    }
}

/// Document text view. Draws line numbers and the placeholder.
final class NotebookTextView: NSTextView {
    var lineHeight: Double = 30
    var lineNumbers: Bool = true
    var placeholderText: String = ""

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            drawPlaceholder()
        }
        if lineNumbers && !string.isEmpty {
            drawLineNumbers()
        }
    }

    var placeholderFontSize: Double = 19

    private func drawPlaceholder() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: placeholderFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        (placeholderText as NSString).draw(
            at: NSPoint(x: Design.gutterWidth + Design.textLeading + 1,
                         y: textContainerInset.height + 1),
            withAttributes: attrs
        )
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
        let numberRightX = Design.gutterWidth + Design.textLeading - 10
        var lineIndex = 0
        content.enumerateSubstrings(
            in: NSRange(location: 0, length: content.length),
            options: .byLines
        ) { _, lineRange, _, _ in
            let firstGlyph = lm.glyphIndexForCharacter(at: lineRange.location)
            guard firstGlyph != NSNotFound else {
                lineIndex += 1
                return
            }
            let frag = lm.lineFragmentRect(forGlyphAt: firstGlyph, effectiveRange: nil)
            let y = insetY + frag.minY
            if y + frag.height < visible.minY - 40 || y > visible.maxY + 40 {
                lineIndex += 1
                return
            }
            let fontLineHeight = textFont.ascender - textFont.descender + textFont.leading
            let baseline = insetY + frag.minY
                + max(0, (frag.height - fontLineHeight) / 2)
                + textFont.ascender
            let str = "\(lineIndex + 1)" as NSString
            let size = str.size(withAttributes: [.font: numberFont])
            str.draw(
                at: NSPoint(x: numberRightX - size.width,
                             y: baseline - numberFont.ascender),
                withAttributes: [.font: numberFont, .foregroundColor: NSColor.secondaryLabelColor]
            )
            lineIndex += 1
        }
    }

    override var acceptsFirstResponder: Bool { true }
}
