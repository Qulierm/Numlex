import Foundation

// MARK: - Export options (session-only; never persisted)

/// The inclusive 1-based source-line range selected for one export.
public enum ExportRange: Equatable, Sendable {
    case all
    case lines(from: Int, to: Int)
}

/// The options the native export/print dialog collects. They are
/// SESSION-ONLY: they never enter `AppSettings`, the store or `.nlx`.
public struct ExportOptions: Equatable, Sendable {
    /// A chosen installed font family (nil = the app's notebook font).
    public var fontFamily: String?
    /// A chosen face inside `fontFamily` (nil = the family's regular face).
    public var fontFace: String?
    /// Point size, clamped to 8...36.
    public var fontPointSize: Double
    /// Paint the classified syntax roles.
    public var syntaxHighlighting: Bool
    /// Draw the original source line numbers in the gutter.
    public var lineNumbers: Bool
    /// Draw the footer Total after the final exported row.
    public var showTotal: Bool
    /// Omit the evaluator's `//` comment rows entirely.
    public var hideComments: Bool
    /// Strip one semantic leading `#` marker (and at most one
    /// separator space) from heading rows.
    public var hideHashMarker: Bool
    /// The exported source-line range.
    public var range: ExportRange

    public static let sizeRange: ClosedRange<Double> = 8...36

    public init(fontFamily: String? = nil,
                fontFace: String? = nil,
                fontPointSize: Double = 20,
                syntaxHighlighting: Bool = true,
                lineNumbers: Bool = true,
                showTotal: Bool = true,
                hideComments: Bool = false,
                hideHashMarker: Bool = false,
                range: ExportRange = .all) {
        self.fontFamily = fontFamily
        self.fontFace = fontFace
        self.fontPointSize = Self.clampedSize(fontPointSize)
        self.syntaxHighlighting = syntaxHighlighting
        self.lineNumbers = lineNumbers
        self.showTotal = showTotal
        self.hideComments = hideComments
        self.hideHashMarker = hideHashMarker
        self.range = range
    }

    public static func clampedSize(_ size: Double) -> Double {
        guard size.isFinite else { return sizeRange.lowerBound }
        return min(max(size, sizeRange.lowerBound), sizeRange.upperBound)
    }

    /// Keeps the session options valid for a NEWLY selected sheet: the
    /// point size is clamped and the line range is clamped into
    /// `1...lineCount` (a stale range from a longer sheet can never
    /// survive as an invalid range on a shorter one).
    public func clamped(toLineCount lineCount: Int) -> ExportOptions {
        var copy = self
        copy.fontPointSize = Self.clampedSize(fontPointSize)
        if case .lines(let from, let to) = range {
            if lineCount < 1 {
                copy.range = .all
            } else {
                let lo = min(max(from, 1), lineCount)
                let hi = min(max(to, lo), lineCount)
                copy.range = .lines(from: lo, to: hi)
            }
        }
        return copy
    }
}

// MARK: - Captured presentation/evaluation context

/// Every app-global evaluation and presentation input the snapshot
/// needs, captured ONCE when the dialog is presented. The snapshot
/// builder resolves the FULL sheet with exactly these values, so the
/// dialog's preview and the written PDF can never disagree, and a
/// later edit/settings change cannot leak into an export in flight.
public struct ExportPresentationContext {
    public let sheetID: UUID
    public let sheetTitle: String
    public let content: String
    public let lineIDs: [UUID]
    public let references: [AnswerReference]
    public let answerDisplay: [AnswerDisplayPreference]
    public let highlights: [LineHighlightPreference]

    public let rates: Rates
    public let decimalPlaces: Int
    public let now: Date
    public let calendar: Calendar
    public let constants: [UserConstant]
    public let weather: WeatherContext
    public let geo: GeoContext
    public let numberContext: NumberFormatContext
    public let unitContext: UnitContext
    public let preferences: TemporalPreferences
    public let financial: FinancialContext
    public let presentation: NumberPresentationPreferences
    public let language: AppLanguage
    /// The notebook styling (font design + role colors) captured at
    /// presentation — document construction never re-reads live
    /// settings after this point.
    public let styling: StylingPreferences
    /// Package 7: the frozen random epoch (a rand row keeps the sample
    /// it showed at presentation).
    public let random: RandomEvaluationContext?

    public init(sheetID: UUID,
                sheetTitle: String,
                content: String,
                lineIDs: [UUID],
                references: [AnswerReference],
                answerDisplay: [AnswerDisplayPreference],
                highlights: [LineHighlightPreference],
                rates: Rates,
                decimalPlaces: Int,
                now: Date,
                calendar: Calendar,
                constants: [UserConstant],
                weather: WeatherContext,
                geo: GeoContext,
                numberContext: NumberFormatContext,
                unitContext: UnitContext,
                preferences: TemporalPreferences,
                financial: FinancialContext,
                presentation: NumberPresentationPreferences,
                language: AppLanguage,
                styling: StylingPreferences = .defaults,
                random: RandomEvaluationContext? = nil) {
        self.sheetID = sheetID
        self.sheetTitle = sheetTitle
        self.content = content
        self.lineIDs = lineIDs
        self.references = references
        self.answerDisplay = answerDisplay
        self.highlights = highlights
        self.rates = rates
        self.decimalPlaces = decimalPlaces
        self.now = now
        self.calendar = calendar
        self.constants = constants
        self.weather = weather
        self.geo = geo
        self.numberContext = numberContext
        self.unitContext = unitContext
        self.preferences = preferences
        self.financial = financial
        self.presentation = presentation
        self.language = language
        self.styling = styling
        self.random = random
    }

    /// Logical source lines (the evaluator's exact split).
    public var sourceLines: [String] { content.components(separatedBy: "\n") }
    public var lineCount: Int { sourceLines.count }
}

// MARK: - Snapshot rows

public enum ExportRowKind: String, Equatable, Sendable {
    /// An ordinary expression row (evaluated or prose).
    case expression
    /// A `#` heading row (role preserved through marker stripping).
    case heading
    /// A `//` comment/title row (the evaluator's semantic prefix).
    case comment
    /// A row that is ONLY an inline `total` command (semibold answer).
    case total
    /// An empty source row (kept for stable spacing).
    case blank
    /// Package 7: an exact `---` divider row (drawn as a rule).
    case divider
}

/// One inline answer token (U+FFFC) inside an exported row. `offset`
/// is a UTF-16 offset into the row's DISPLAY text (after `#` stripping).
public struct ExportToken: Equatable, Sendable {
    public let offset: Int
    public let label: String
    public let active: Bool

    public init(offset: Int, label: String, active: Bool) {
        self.offset = offset
        self.label = label
        self.active = active
    }
}

/// One printable row of the snapshot. Immutable and fully resolved:
/// text, answer, spans and tokens all belong to the same captured pass.
public struct ExportRow: Equatable, Sendable {
    /// The ORIGINAL 1-based source line number (never renumbered by
    /// range selection or filtering).
    public let sourceLineNumber: Int
    /// The stable source line UUID (display prefs are keyed by it).
    public let lineID: UUID
    public let kind: ExportRowKind
    /// The display text (after the optional `#` marker strip).
    public let text: String
    /// The answer string exactly as the live answer column would show
    /// it (nil = the live column shows nothing on this row).
    public let answer: String?
    /// Classified spans relative to `text`; empty when highlighting is
    /// off. Ranges are UTF-16 and already shifted for marker stripping.
    public let spans: [SyntaxSpan]
    /// Inline token capsules at their display-text offsets.
    public let tokens: [ExportToken]
    /// The persistent line fill, when the row is highlighted.
    public let highlight: HighlightColor?
    /// True for a derived inline `total` row (semibold answer, and
    /// never a footer-total contribution).
    public let isInlineTotal: Bool

    public init(sourceLineNumber: Int, lineID: UUID, kind: ExportRowKind,
                text: String, answer: String?, spans: [SyntaxSpan],
                tokens: [ExportToken], highlight: HighlightColor?,
                isInlineTotal: Bool) {
        self.sourceLineNumber = sourceLineNumber
        self.lineID = lineID
        self.kind = kind
        self.text = text
        self.answer = answer
        self.spans = spans
        self.tokens = tokens
        self.highlight = highlight
        self.isInlineTotal = isInlineTotal
    }
}

/// The immutable export snapshot: one captured pass, one row list, one
/// footer total. Both the PDF and the print pipeline consume exactly
/// this value — never the viewport, never the editor.
public struct ExportSnapshot: Equatable, Sendable {
    public let sheetTitle: String
    public let rows: [ExportRow]
    /// The footer total over the EXPORTED evaluated rows only, using
    /// `SheetFooterTotal.aggregate` semantics. nil = no eligible row.
    public let total: Double?
    /// The formatted Total string exactly as the live footer shows it.
    public let totalText: String?
    /// The resolved display options (font size seeded by the dialog,
    /// range/filters as chosen).
    public let options: ExportOptions
    public let lineCount: Int
    /// The captured UI language (localized Total label and statuses).
    public let language: AppLanguage

    public init(sheetTitle: String, rows: [ExportRow], total: Double?,
                totalText: String?, options: ExportOptions, lineCount: Int,
                language: AppLanguage = .en) {
        self.sheetTitle = sheetTitle
        self.rows = rows
        self.total = total
        self.totalText = totalText
        self.options = options
        self.lineCount = lineCount
        self.language = language
    }
}

public enum ExportSnapshotError: Error, Equatable {
    case emptySheet
    case invalidRange
    case noPrintableRows
}
