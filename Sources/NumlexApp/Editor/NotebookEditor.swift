import AppKit
import SwiftUI
import NumlexCore

// MARK: - Line number ruler

final class LineNumberRulerView: NSRulerView {
    var font: NSFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    var textColor: NSColor = .secondaryLabelColor

    init(scrollView: NSScrollView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = scrollView.documentView
        self.ruleThickness = 44
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = clientView as? NSTextView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else { return }

        NSColor.clear.set()
        rect.fill()

        let ns = tv.string as NSString
        guard ns.length > 0 else { return }
        let visible = tv.visibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)

        // 0-based index of the first visible logical line.
        var lineIndex = 0
        if glyphRange.location > 0 {
            let prefix = ns.substring(with: NSRange(location: 0, length: glyphRange.location))
            lineIndex = (prefix.components(separatedBy: "\n").count) - 1
        }

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        // Line fragment rects are in text-container space; shift by the
        // container inset to land in text-view space.
        let insetY = tv.textContainerInset.height
        var glyphIndex = glyphRange.location
        let end = min(NSMaxRange(glyphRange), ns.length)

        while glyphIndex < end {
            var lineRange = NSRange()
            let lineRect = lm.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &lineRange)
            let charRange = lm.characterRange(forGlyphRange: lineRange, actualGlyphRange: nil)
            let isLogicalStart = charRange.location == 0 || ns.character(at: charRange.location - 1) == 10 // '\n'
            if isLogicalStart {
                let str = "\(lineIndex + 1)" as NSString
                let sz = str.size(withAttributes: attrs)
                let y = lineRect.minY + insetY - visible.minY + (lineRect.height - sz.height) / 2
                str.draw(at: NSPoint(x: ruleThickness - sz.width - 10, y: y), withAttributes: attrs)
                lineIndex += 1
            }
            glyphIndex = NSMaxRange(lineRange)
        }
    }
}

// MARK: - Notebook text view

final class NotebookTextView: NSTextView {
    var onChange: ((String) -> Void)?
    var placeholder: String = ""
    var showsLineNumbers = true {
        didSet { enclosingScrollView?.verticalRulerView?.needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Quiet placeholder: exactly editor base size, normal weight, low contrast,
        // aligned with the first editable line.
        if string.isEmpty && !placeholder.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.placeholderTextColor,
                .font: font ?? NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
            ]
            let inset = textContainerInset
            (placeholder as NSString).draw(at: NSPoint(x: inset.width + 1, y: inset.height + 1), withAttributes: attrs)
        }
    }

    override func didChangeText() {
        super.didChangeText()
        onChange?(string)
        needsDisplay = true
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
}

// MARK: - Coordinator

@MainActor
final class NotebookCoordinator: NSObject, NSTextViewDelegate {
    var parent: NotebookEditor
    var textView: NotebookTextView?
    var scrollView: NSScrollView?
    var ruler: LineNumberRulerView?

    init(parent: NotebookEditor) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        parent.text = tv.string
        highlight(tv)
    }

    func scrollViewDidScroll(_ notification: Notification) {
        guard let tv = textView,
              let lm = tv.layoutManager,
              let tc = tv.textContainer else { return }
        let ns = tv.string as NSString
        guard ns.length > 0 else {
            parent.onScroll?(0)
            return
        }
        let visible = tv.visibleRect
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tc)
        let loc = glyphRange.location
        let line = loc == 0 ? 0 : ns.substring(with: NSRange(location: 0, length: loc)).components(separatedBy: "\n").count - 1
        parent.onScroll?(line)
    }

    func highlight(_ tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        storage.removeAttribute(.foregroundColor, range: full)
        storage.removeAttribute(.paragraphStyle, range: full)

        // Fixed line height keeps editor rows and answer rows aligned.
        let para = NSMutableParagraphStyle()
        let lh = CGFloat(parent.lineHeight)
        para.minimumLineHeight = lh
        para.maximumLineHeight = lh
        storage.addAttribute(.paragraphStyle, value: para, range: full)

        storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
        storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular), range: full)

        let str = storage.string as NSString
        let fontSize = parent.fontSize

        // Headings (# title) and comments (// ...)
        str.enumerateSubstrings(in: full, options: .byLines) { line, range, _, _ in
            guard let line = line else { return }
            if line.hasPrefix("#") {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            } else if line.hasPrefix("// ") {
                storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold), range: range)
            } else if line.hasPrefix("//") {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
            }
        }

        // Numbers and operators
        if let numRegex = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?"#, options: []) {
            numRegex.enumerateMatches(in: storage.string, range: full) { m, _, _ in
                guard let r = m?.range else { return }
                storage.addAttribute(.foregroundColor, value: Self.operatorColor, range: r)
            }
        }
        if let opRegex = try? NSRegularExpression(pattern: #"[+\-*/^%]"#, options: []) {
            opRegex.enumerateMatches(in: storage.string, range: full) { m, _, _ in
                guard let r = m?.range else { return }
                storage.addAttribute(.foregroundColor, value: Self.operatorColor, range: r)
            }
        }
        // "to" conversion keyword
        if let toRegex = try? NSRegularExpression(pattern: #"\bto\b"#, options: .caseInsensitive) {
            toRegex.enumerateMatches(in: storage.string, range: full) { m, _, _ in
                guard let r = m?.range else { return }
                storage.addAttribute(.foregroundColor, value: Self.keywordColor, range: r)
            }
        }
        // Declared variables
        for (name, _) in declaredVariables(storage.string) {
            guard let varRegex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b", options: []) else { continue }
            varRegex.enumerateMatches(in: storage.string, range: full) { m, _, _ in
                guard let r = m?.range else { return }
                storage.addAttribute(.foregroundColor, value: Self.variableColor, range: r)
            }
        }
    }

    static let operatorColor = NSColor(red: 0.60, green: 0.82, blue: 1.0, alpha: 1)
    static let keywordColor = NSColor(red: 0.90, green: 0.42, blue: 0.64, alpha: 1)
    static let variableColor = NSColor(red: 0.70, green: 0.85, blue: 1.0, alpha: 1)
}

// MARK: - SwiftUI wrapper

struct NotebookEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var fontSize: Double
    var lineHeight: Double
    var lineNumbers: Bool
    var onScroll: ((Int) -> Void)? = nil
    var onViewCreated: ((NSScrollView, NSTextView) -> Void)? = nil
    var onLayout: (([CGFloat]) -> Void)? = nil

    init(text: Binding<String>,
                placeholder: String = "",
                fontSize: Double = 18,
                lineHeight: Double = 29,
                lineNumbers: Bool = true,
                onScroll: ((Int) -> Void)? = nil,
                onViewCreated: ((NSScrollView, NSTextView) -> Void)? = nil,
                onLayout: (([CGFloat]) -> Void)? = nil) {
        self._text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.lineHeight = lineHeight
        self.lineNumbers = lineNumbers
        self.onScroll = onScroll
        self.onViewCreated = onViewCreated
        self.onLayout = onLayout
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.autoresizingMask = [.width, .height]

        let tv = NotebookTextView()
        tv.isRichText = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.allowsUndo = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 16, height: 12)
        tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.placeholder = placeholder
        tv.showsLineNumbers = lineNumbers
        tv.delegate = context.coordinator
        tv.onChange = { new in
            DispatchQueue.main.async { self.text = new }
        }
        tv.string = text
        context.coordinator.textView = tv
        context.coordinator.scrollView = scroll
        context.coordinator.parent = self

        let ruler = LineNumberRulerView(scrollView: scroll)
        ruler.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        ruler.textColor = .secondaryLabelColor
        context.coordinator.ruler = ruler

        scroll.documentView = tv
        // The ruler must be attached (and its clientView bound) after the
        // document view exists, otherwise clientView is nil and nothing draws.
        ruler.clientView = tv
        scroll.verticalRulerView = ruler
        scroll.hasVerticalRuler = lineNumbers
        scroll.rulersVisible = lineNumbers
        ruler.needsDisplay = true

        context.coordinator.highlight(tv)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NotebookTextView else { return }
        if tv.string != text {
            tv.string = text
            context.coordinator.highlight(tv)
        }
        if let ps = tv.font?.pointSize, ps != CGFloat(fontSize) {
            tv.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            context.coordinator.highlight(tv)
        }
        tv.placeholder = placeholder
        if nsView.hasVerticalRuler != lineNumbers {
            nsView.hasVerticalRuler = lineNumbers
            nsView.rulersVisible = lineNumbers
        }
        context.coordinator.parent = self
    }

    func makeCoordinator() -> NotebookCoordinator { NotebookCoordinator(parent: self) }
}
