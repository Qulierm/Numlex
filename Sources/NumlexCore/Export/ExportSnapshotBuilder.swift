import Foundation

/// Builds the ONE immutable export snapshot both the PDF writer and the
/// print operation consume. The builder resolves the FULL sheet once
/// (tokens included), classifies spans from the same captured contexts,
/// then projects the inclusive 1-based source-line range and the
/// display filters onto immutable rows. It never touches the editor.
public enum ExportSnapshotBuilder {

    /// Line-range validity against the captured sheet: the range is
    /// valid only when it is ordered and inside `1...lineCount`.
    public static func validate(range: ExportRange, lineCount: Int) -> Bool {
        switch range {
        case .all:
            return lineCount >= 1
        case .lines(let from, let to):
            return from >= 1 && to <= lineCount && from <= to
        }
    }

    /// How many rows the given options would export (after range and
    /// comment filtering); used by the dialog's inline validation.
    /// `0` = the action must be disabled.
    public static func printableRowCount(context: ExportPresentationContext,
                                         options: ExportOptions) -> Int {
        guard case .success(let snapshot) = build(context: context, options: options) else {
            return 0
        }
        return snapshot.rows.count
    }

    /// Builds the snapshot. Failure is explicit: an invalid range or an
    /// output with no printable row never produces a blank PDF.
    public static func build(context: ExportPresentationContext,
                             options: ExportOptions) -> Result<ExportSnapshot, ExportSnapshotError> {
        let lines = context.sourceLines
        let lineCount = lines.count
        guard lineCount >= 1, !(lineCount == 1 && lines[0].isEmpty) else {
            return .failure(.emptySheet)
        }
        guard validate(range: options.range, lineCount: lineCount) else {
            return .failure(.invalidRange)
        }
        let rangeIndices: [Int]
        switch options.range {
        case .all:
            rangeIndices = Array(0..<lineCount)
        case .lines(let from, let to):
            rangeIndices = Array((from - 1)...(to - 1))
        }

        // ONE full resolve with the captured contexts — tokens and all.
        let (resolvedLines, tokenResolutions) = resolveSheet(
            content: context.content,
            lineIDs: context.lineIDs,
            references: context.references,
            rates: context.rates,
            decimalPlaces: context.decimalPlaces,
            now: context.now,
            calendar: context.calendar,
            constants: context.constants,
            weather: context.weather,
            geo: context.geo,
            context: context.numberContext,
            unitContext: context.unitContext,
            preferences: context.preferences,
            financial: context.financial,
            random: context.random)
        // The classifier shares the same captured pass (same env flow,
        // same date context, same weather/geo/unit/financial inputs).
        let allSpans = SyntaxClassifier.spans(
            for: context.content,
            rates: context.rates,
            decimalPlaces: context.decimalPlaces,
            constants: context.constants,
            context: context.numberContext,
            unitContext: context.unitContext,
            financial: context.financial,
            now: context.now,
            calendar: context.calendar,
            weather: context.weather,
            geo: context.geo,
            preferences: context.preferences)

        // Original document offsets: one UTF-16 start per logical line.
        var docOffsets: [Int] = []
        docOffsets.reserveCapacity(lineCount)
        var acc = 0
        for line in lines {
            docOffsets.append(acc)
            acc += (line as NSString).length + 1
        }
        // Token resolution by document offset.
        var tokenByOffset: [Int: TokenResolution] = [:]
        for t in tokenResolutions { tokenByOffset[t.location] = t }
        let highlightByID = Dictionary(uniqueKeysWithValues:
            context.highlights.map { ($0.lineID, $0.color) })
        let displayByID = Dictionary(uniqueKeysWithValues:
            AnswerDisplay.sanitize(context.answerDisplay, lineIDs: context.lineIDs)
                .map { ($0.lineID, $0) })

        var rows: [ExportRow] = []
        var exportedLines: [SheetLine] = []
        var hasPrintableContent = false
        for index in rangeIndices {
            let raw = lines[index]
            let result = resolvedLines.indices.contains(index)
                ? resolvedLines[index]
                : SheetLine(sourceLineIndex: index, result: .blank)
            let analysis = SheetLineAnalysis.parse(raw)
            let isComment = analysis.kind == .comment || analysis.kind == .commentTitle
            if options.hideComments && isComment { continue }
            // Package 7: strip ONLY the `# ` heading marker (exactly two
            // characters), never a tag hash.
            let stripPrefix: Int = {
                guard options.hideHashMarker, analysis.kind == .heading else { return 0 }
                return 2
            }()
            let displayText = stripPrefix > 0
                ? String(raw.dropFirst(stripPrefix))
                : raw
            let kind: ExportRowKind = {
                switch analysis.kind {
                case .heading: return .heading
                case .comment, .commentTitle: return .comment
                case .divider: return .divider
                case .blank, .tagOnly:
                    return result.isTotal ? .total : .blank
                case .totalCommand, .expression:
                    return result.isTotal ? .total : .expression
                }
            }()
            let lineID = context.lineIDs.indices.contains(index)
                ? context.lineIDs[index]
                : UUID()
            let pref = displayByID[lineID]
            let places = AnswerDisplay.effective(defaultPlaces: context.decimalPlaces,
                                                 override: pref?.decimalPlaces)
            let answer = answerText(for: result.result,
                                    places: places,
                                    notation: pref?.notation?.notation,
                                    context: context)
            let rowSpans: [SyntaxSpan] = options.syntaxHighlighting
                ? remapSpans(allSpans.indices.contains(index) ? allSpans[index] : [],
                             stripPrefix: stripPrefix,
                             displayLength: (displayText as NSString).length)
                : []
            let tokens: [ExportToken] = options.hideComments && isComment
                ? []
                : tokens(inLine: index, lines: lines, docOffsets: docOffsets,
                         stripPrefix: stripPrefix, tokenByOffset: tokenByOffset)
            let isInlineTotal = result.isTotal
            if !(displayText.isEmpty && answer == nil && !isInlineTotal) {
                hasPrintableContent = true
            }
            rows.append(ExportRow(
                sourceLineNumber: index + 1,
                lineID: lineID,
                kind: kind,
                text: displayText,
                answer: answer,
                spans: rowSpans,
                tokens: tokens,
                highlight: highlightByID[lineID],
                isInlineTotal: isInlineTotal))
            exportedLines.append(SheetLine(sourceLineIndex: index,
                                           result: result.result,
                                           isTotal: result.isTotal))
        }
        guard hasPrintableContent else { return .failure(.noPrintableRows) }

        let total = options.showTotal
            ? SheetFooterTotal.aggregate(exportedLines)
            : nil
        let totalText = total.map {
            formatTotal($0, context: context)
        }
        let snapshot = ExportSnapshot(sheetTitle: context.sheetTitle,
                                      rows: rows,
                                      total: total,
                                      totalText: totalText,
                                      options: options,
                                      lineCount: lineCount,
                                      language: context.language)
        return .success(snapshot)
    }

    // MARK: - Row projection helpers

    /// Remaps one line's classified spans onto the display text after
    /// an optional `#`-marker strip. A span the strip consumed is
    /// dropped; a partially consumed span is clamped to the new start.
    static func remapSpans(_ spans: [SyntaxSpan], stripPrefix: Int,
                           displayLength: Int) -> [SyntaxSpan] {
        guard stripPrefix > 0 else {
            return spans.filter {
                $0.range.location >= 0 && $0.range.length > 0
                    && NSMaxRange($0.range) <= displayLength
            }
        }
        var out: [SyntaxSpan] = []
        for span in spans {
            let start = span.range.location - stripPrefix
            let end = NSMaxRange(span.range) - stripPrefix
            let clampedStart = max(start, 0)
            let clampedEnd = min(end, displayLength)
            guard clampedEnd > clampedStart else { continue }
            out.append(SyntaxSpan(role: span.role,
                                  range: NSRange(location: clampedStart,
                                                 length: clampedEnd - clampedStart)))
        }
        return out
    }

    /// The inline tokens of one source line, projected onto the display
    /// text offsets (the `#` strip can only consume prefix characters,
    /// never a marker) with the live capsule labels.
    static func tokens(inLine index: Int, lines: [String], docOffsets: [Int],
                       stripPrefix: Int,
                       tokenByOffset: [Int: TokenResolution]) -> [ExportToken] {
        guard lines.indices.contains(index), docOffsets.indices.contains(index) else {
            return []
        }
        let line = lines[index]
        let ns = line as NSString
        let lineStart = docOffsets[index]
        var out: [ExportToken] = []
        var p = 0
        while p < ns.length {
            if ns.character(at: p) == answerTokenMarkerUTF16 {
                let docOffset = lineStart + p
                if let state = tokenByOffset[docOffset]?.state {
                    let label: String
                    let active: Bool
                    switch state {
                    case .active(_, _, let display):
                        label = display; active = true
                    case .activeKinded(_, _, _, _, let display):
                        label = display; active = true
                    case .activeBool(_, let display):
                        label = display; active = true
                    case .activeInteger(_, _, let display):
                        label = display; active = true
                    case .activeCoordinate(_, _, _, let display):
                        label = display; active = true
                    case .broken(let lineNumber):
                        label = "Line \(lineNumber)"; active = false
                    }
                    out.append(ExportToken(offset: max(p - stripPrefix, 0),
                                           label: label, active: active))
                }
            }
            p += 1
        }
        return out
    }

    /// The answer string exactly as the live answer column would render
    /// it: per-line precision + notation through `AnswerDisplay`, the
    /// localized quiet statuses the live column shows, and nil for
    /// every row whose live column renders nothing.
    static func answerText(for result: LineResult, places: Int,
                           notation: NumberNotation?,
                           context: ExportPresentationContext) -> String? {
        if case .error(let message) = result {
            if WeatherQuery.isUnavailableMessage(message) {
                return L10n.t("weatherUnavailable", language: context.language)
            }
            if GeoQueryParse.isUnavailableMessage(message) {
                return L10n.t("locationUnavailable", language: context.language)
            }
            if message == "Rates unavailable" { return "Rates unavailable" }
            return nil
        }
        return AnswerDisplay.displayText(for: result,
                                         decimalPlaces: places,
                                         context: context.numberContext,
                                         notation: notation,
                                         prefs: context.presentation)
    }

    /// The live footer Total string (identical rounding + formatting
    /// contract as the answer column's `summary`).
    static func formatTotal(_ sum: Double,
                            context: ExportPresentationContext) -> String {
        var value = sum
        if value.truncatingRemainder(dividingBy: 1) != 0 {
            let scale = pow(10, Double(context.decimalPlaces))
            value = (value * scale).rounded() / scale
        }
        if context.presentation.notation == .automatic {
            return formatDisplayValue(value,
                                      decimalPlaces: context.decimalPlaces,
                                      context: context.numberContext)
        }
        return NumberPresentation.format(value,
                                         category: .plain,
                                         notation: context.presentation.notation,
                                         precision: context.decimalPlaces,
                                         prefs: context.presentation,
                                         context: context.numberContext)
    }
}
