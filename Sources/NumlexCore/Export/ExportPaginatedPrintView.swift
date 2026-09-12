import AppKit
import CoreGraphics

/// The paginated AppKit view backing the standard print panel. Every
/// page is drawn by the SAME `ExportRenderedDocument` that writes the
/// PDF — there is no second rendering path and no viewport capture.
/// It lives in NumlexCore so the noninteractive print-operation QA
/// harness exercises the exact production view.
public final class ExportPaginatedPrintView: NSView {
    public let document: ExportRenderedDocument
    private let pageSize: NSSize

    public init(document: ExportRenderedDocument) {
        self.document = document
        self.pageSize = NSSize(width: document.layout.pageSize.width,
                               height: document.layout.pageSize.height)
        let pages = max(document.pageCount, 1)
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: pageSize.width,
                                 height: pageSize.height * CGFloat(pages)))
    }

    public required init?(coder: NSCoder) {
        fatalError("ExportPaginatedPrintView is created programmatically")
    }

    public override var isFlipped: Bool { false }

    public override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: max(document.pageCount, 1))
        return true
    }

    public override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0,
               y: pageSize.height * CGFloat(max(page - 1, 0)),
               width: pageSize.width,
               height: pageSize.height)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let page = Int(dirtyRect.minY / max(pageSize.height, 1))
        guard document.layout.pages.indices.contains(page) else { return }
        ctx.saveGState()
        // Page-local, bottom-left origin — exactly what the shared
        // renderer expects.
        ctx.translateBy(x: 0, y: -CGFloat(page) * pageSize.height)
        document.draw(page: document.layout.pages[page], in: ctx)
        ctx.restoreGState()
    }
}
