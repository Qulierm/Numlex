import Foundation

/// r51: per-answer display preferences (the answer context menu's
/// "Rounding" submenu). Keyed by STABLE line UUID, never by row index,
/// so edits above a line never redirect its override. Presentation-only:
/// the engine keeps evaluating with the global `decimalPlaces` and the
/// override only selects how many decimals the rendered/copied string
/// shows. Not a recalculation mode, not a dependency precision change.
public struct AnswerDisplayPreference: Codable, Equatable, Identifiable, Sendable {
    /// The stable ID of the source logical line (into `Sheet.lineIDs`).
    public var lineID: UUID
    /// Displayed decimal places for this answer's numeric string.
    public var decimalPlaces: Int

    public var id: UUID { lineID }

    public init(lineID: UUID, decimalPlaces: Int) {
        self.lineID = lineID
        self.decimalPlaces = decimalPlaces
    }
}

public enum AnswerDisplay {
    /// Legal per-answer decimals: 0...10 (the global setting stays
    /// 2...10; an override may show fewer or more trailing decimals of
    /// the available engine value).
    public static let minPlaces = 0
    public static let maxPlaces = 10

    public static func clamped(_ places: Int) -> Int {
        min(max(places, minPlaces), maxPlaces)
    }

    /// Effective decimals for one row: the override wins when present,
    /// otherwise the global setting. Tokens and the summary Total always
    /// use the global value (documented r51 choice: no source-display
    /// side effects, no rounded-display summation).
    public static func effective(defaultPlaces: Int, override: Int?) -> Int {
        override.map(clamped) ?? defaultPlaces
    }

    // MARK: - r54: slider menu presentation (pure)

    /// The slider's INITIAL value for one row: the effective per-answer
    /// precision (override ?? global) clamped to 0...10. Moving the
    /// slider writes an explicit per-line override; there is NO reset
    /// control, so an untouched row keeps inheriting the global
    /// precision until its slider is first moved.
    public static func sliderValue(defaultPlaces: Int, override: Int?) -> Int {
        clamped(effective(defaultPlaces: defaultPlaces, override: override))
    }

    /// The compact visible label next to the slider (`0 dp` ... `10 dp`):
    /// always an integer tick value — a fractional value is never
    /// exposed (the slider is discrete by construction).
    public static func sliderLabel(_ places: Int) -> String {
        "\(clamped(places)) dp"
    }

    /// The localized accessibility/spoken value — the count of decimal
    /// places in the active language (the visible label keeps the
    /// conventional compact `dp` suffix).
    public static func sliderAccessibilityValue(_ places: Int, language: AppLanguage) -> String {
        "\(clamped(places)) \(L10n.t("decimalPlaces", language: language))"
    }

    /// Keeps only preferences whose line still exists, clamps every
    /// value to 0...10, drops duplicates (first wins) and returns the
    /// survivors in CURRENT line order — deterministic, index-free.
    public static func sanitize(_ prefs: [AnswerDisplayPreference],
                                lineIDs: [UUID]) -> [AnswerDisplayPreference] {
        let order = Dictionary(uniqueKeysWithValues: lineIDs.enumerated().map { ($1, $0) })
        var seen = Set<UUID>()
        var kept: [AnswerDisplayPreference] = []
        for p in prefs {
            guard order[p.lineID] != nil, !seen.contains(p.lineID) else { continue }
            seen.insert(p.lineID)
            kept.append(AnswerDisplayPreference(lineID: p.lineID,
                                                decimalPlaces: clamped(p.decimalPlaces)))
        }
        return kept.sorted { order[$0.lineID]! < order[$1.lineID]! }
    }

    // MARK: - Shared display string (rendering == Copy Answer)

    /// THE one plain-text rendering of a visible answer row, shared by
    /// `AnswerColumnView.rowView` and Copy Answer so the clipboard always
    /// equals the visible value. Nil = hidden row (blank, prose, title,
    /// generic error): no menu, no copy.
    /// - scalar/variable: the numeric string at the effective decimals;
    /// - unit quantity: `value unit` (currency codes take the money path);
    /// - currency/money: the shared fixed `formatMoney` presentation;
    /// - date: `DateArithmetic.display`; broken token: `Line N`;
    /// - `Rates unavailable`: exactly that text.
    public static func text(for result: LineResult, decimalPlaces: Int) -> String? {
        switch result {
        case .blank, .skip, .title:
            return nil
        case .number(let v, let unit):
            if let u = unit, isCurrencyCode(u) {
                return formatMoney(v, code: u)
            }
            let s = formatDisplayValue(v, decimalPlaces: decimalPlaces)
            if let u = unit { return "\(s) \(u)" }
            return s
        case .variable(_, let v):
            return formatDisplayValue(v, decimalPlaces: decimalPlaces)
        case .money(let v, let code):
            return formatMoney(v, code: code)
        case .date(let y, let m, let d, let showYear):
            return DateArithmetic.display(year: y, month: m, day: d, showYear: showYear)
        case .brokenToken(let line):
            return "Line \(line)"
        case .error(let msg):
            // r55: `Weather unavailable` renders in the view (localized)
            // but is never copied — like other quiet errors it has no
            // clipboard text.
            if WeatherQuery.isUnavailableMessage(msg) { return nil }
            return msg == "Rates unavailable" ? "Rates unavailable" : nil
        }
    }

    // MARK: - Context menu eligibility (pure descriptor)

    /// Which answer-specific actions a row offers. The menu appears only
    /// for rows with visible/meaningful content; Delete is available for
    /// every visible row, Copy for the same set, Rounding only for plain
    /// numeric scalar/variable rows (money keeps its fixed presentation,
    /// dates/broken/rates have no decimals to choose).
    public struct Menu: Equatable, Sendable {
        /// Show Copy Answer + Delete Line.
        public var showsActions: Bool
        /// Show the Rounding submenu (implies showsActions).
        public var showsRounding: Bool
        public init(showsActions: Bool, showsRounding: Bool) {
            self.showsActions = showsActions
            self.showsRounding = showsRounding
        }
    }

    public static func menu(for result: LineResult) -> Menu? {
        switch result {
        case .blank, .skip, .title:
            return nil
        case .error(let msg):
            // r55: weather-unavailable rows offer no menu at all (no
            // Copy, no rounding) — quiet and secondary by design.
            if WeatherQuery.isUnavailableMessage(msg) { return nil }
            return msg == "Rates unavailable"
                ? Menu(showsActions: true, showsRounding: false)
                : nil
        case .number(_, let unit):
            if let u = unit, isCurrencyCode(u) {
                return Menu(showsActions: true, showsRounding: false)
            }
            return Menu(showsActions: true, showsRounding: true)
        case .variable:
            return Menu(showsActions: true, showsRounding: true)
        case .money, .date, .brokenToken:
            return Menu(showsActions: true, showsRounding: false)
        }
    }

    // MARK: - Pure logical-line deletion plan

    /// One deleted logical line as an exact UTF-16 plan: the new content,
    /// the announced `NotebookEdit` (nil range only when the content is
    /// already empty) and the caret landing at the deletion start. The
    /// newline goes with the line — a non-last line deletes its trailing
    /// newline, the last line its preceding one, the sole line the whole
    /// content. The caller reconciles line IDs/references through
    /// `LineIdentity.reconcile` with this exact edit, so survivors keep
    /// stable IDs, markers shift exactly, and tokens on the deleted line
    /// break naturally.
    public struct LineDeletion: Equatable, Sendable {
        public var content: String
        public var edit: NotebookEdit?
        /// UTF-16 offset of the deletion start (= caret landing, caller
        /// clamps to the final content).
        public var caret: Int
    }

    public static func deleteLinePlan(content: String, lineIndex: Int) -> LineDeletion? {
        let lines = content.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return nil }
        let ns = content as NSString
        // UTF-16 start offset of every logical line.
        var starts: [Int] = []
        var off = 0
        for (i, ln) in lines.enumerated() {
            starts.append(off)
            off += (ln as NSString).length + (i < lines.count - 1 ? 1 : 0)
        }
        let start = starts[lineIndex]
        let lineLen = (lines[lineIndex] as NSString).length
        let range: NSRange
        if lines.count == 1 {
            range = NSRange(location: 0, length: ns.length)
        } else if lineIndex < lines.count - 1 {
            // Non-last line: the line plus its following newline.
            range = NSRange(location: start, length: lineLen + 1)
        } else {
            // Last line: the preceding newline plus the line.
            range = NSRange(location: start - 1, length: lineLen + 1)
        }
        let edit = NotebookEdit(range: range, replacement: "")
        let newContent = ns.replacingCharacters(in: range, with: "")
        return LineDeletion(content: newContent, edit: edit, caret: range.location)
    }
}
