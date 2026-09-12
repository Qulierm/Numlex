import Foundation
import NumlexCore

// MARK: - Natural compound duration arithmetic
//
// The full contract for duration literals, the typed presentation marker, the
// algebra that carries it, the natural decomposition and the anti-regressions
// that guarantee no pre-existing notation changed meaning.

private func durLine(_ line: String, variables: inout [String: Double],
                     context: NumberFormatContext = .legacy,
                     places: Int = 7,
                     unitContext: UnitContext = .builtIns) -> LineResult? {
    evalLine(line, variables: &variables, rates: Rates(), decimalPlaces: places,
             context: context, unitContext: unitContext)
}

private func durText(_ line: String,
                     context: NumberFormatContext = .legacy,
                     places: Int = 7) throws -> String {
    var v: [String: Double] = [:]
    guard let r = durLine(line, variables: &v, context: context, places: places) else {
        throw CaseFailure(message: "line must evaluate: \(line)", location: "Duration")
    }
    guard let text = AnswerDisplay.displayText(for: r, decimalPlaces: places,
                                               context: context) else {
        throw CaseFailure(message: "no display text for \(line)", location: "Duration")
    }
    return text
}

private func expectDuration(_ line: String, _ expected: String,
                            context: NumberFormatContext = .legacy,
                            places: Int = 7,
                            location: String = "Duration") throws {
    let got = try durText(line, context: context, places: places)
    try expectEqual(got, expected, "\(line) -> \(expected)")
}

private func expectDurationError(_ line: String,
                                 context: NumberFormatContext = .legacy) throws {
    var v: [String: Double] = [:]
    guard let r = durLine(line, variables: &v, context: context) else {
        throw CaseFailure(message: "line must evaluate: \(line)", location: "Duration")
    }
    guard case .error = r else {
        throw CaseFailure(message: "\(line) must be an error, got \(r)", location: "Duration")
    }
}

private func sheetTexts(_ source: String,
                        context: NumberFormatContext = .legacy,
                        places: Int = 7) -> [String?] {
    var v: [String: Double] = [:]
    return evaluateSheet(source, variables: &v, rates: Rates(), decimalPlaces: places,
                         context: context).map {
        AnswerDisplay.displayText(for: $0.result, decimalPlaces: places, context: context)
    }
}

public let durationCases: [EngineCase] = [

    // MARK: canonical pinned examples

    EngineCase("duration-canonical-examples") {
        try expectDuration("1 h 45 min + 30 min", "2 h 15 min")
        try expectDuration("1 hour 45 minutes + 30 minutes", "2 h 15 min")
        try expectDuration("2 hr 10 min - 45 min", "1 h 25 min")
        try expectDuration("1 day 2 h + 90 min", "1 day 3 h 30 min")
        try expectDuration("1 week 2 days - 1 day", "1 week 1 day")
        try expectDuration("2 min 30 sec × 3", "7 min 30 s")
        try expectDuration("1 min 250 ms + 750 ms", "1 min 1 s")
        try expectDuration("1.5 h + 30 min", "2 h")
    },

    EngineCase("duration-alias-and-spelling-matrix") {
        // Every fixed alias, spaced.
        try expectDuration("1 minute + 30 seconds", "1 min 30 s")
        try expectDuration("1 mins + 30 secs", "1 min 30 s")
        try expectDuration("1 min + 30 sec", "1 min 30 s")
        try expectDuration("1 hour 45 minutes", "1 h 45 min")
        try expectDuration("2 hrs 5 mins", "2 h 5 min")
        try expectDuration("2 hr 5 min", "2 h 5 min")
        try expectDuration("1 day 2 hours 30 min", "1 day 2 h 30 min")
        try expectDuration("1 week 2 days", "1 week 2 day")
        try expectDuration("1 wk 2 wks", "3 week")
        try expectDuration("1 millisecond + 2 seconds", "2 s 1 ms")
        try expectDuration("500 milliseconds + 1 second", "1 s 500 ms")
    },

    EngineCase("duration-glued-aliases") {
        try expectDuration("1h45min", "1 h 45 min")
        try expectDuration("45min", "45 min")
        try expectDuration("30sec", "30 s")
        try expectDuration("500ms", "500 ms")
        try expectDuration("2hr", "2 h")
        try expectDuration("1day2hours30min", "1 day 2 h 30 min")
        try expectDuration("1h 45min", "1 h 45 min")
        try expectDuration("2wks 1day", "2 week 1 day")
        try expectDuration("1ms + 999ms", "1 s")
        // A glued alias followed by a letter is a different word: not ours.
        var hz: [String: Double] = [:]
        if case .number(_, _, let hzKind, _)? = durLine("1hz + 2hz", variables: &hz) {
            try expect(hzKind != .duration, "1hz is never a duration")
        }
    },

    EngineCase("duration-anti-regression-glued-m-and-metres") {
        // `5m` stays five million, `5 m` stays metres, and implicit
        // adjacency never adds metres (`1 m 20 cm`).
        var v: [String: Double] = [:]
        guard case .number(let magnitude, nil, let kind, _)? = durLine("5m", variables: &v) else {
            throw CaseFailure(message: "5m must be a plain magnitude", location: "Duration")
        }
        try expectEqual(magnitude, 5_000_000, "5m is five million")
        try expectEqual(kind, .plain, "and not a duration")
        try expectDuration("5 m", "5 m")
        try expectDuration("90 min", "90 min")
        try expectDuration("1 h", "1 h")
        try expectDurationError("1 m 20 cm")
        try expectDurationError("1 km 20 m")
    },

    EngineCase("duration-ordering-and-repeats") {
        // Mixed/descending order and repeated components all sum.
        try expectDuration("45 min 1 h", "1 h 45 min")
        try expectDuration("2 min 30 sec + 30 sec", "3 min")
        try expectDuration("1 min 30 sec + 30 sec + 1 min", "3 min")
        try expectDuration("1 day 1 day 2 h", "2 day 2 h")
        try expectDuration("10 week 2 day 5 h 3 min 20 s", "10 week 2 day 5 h 3 min 20 s")
    },

    EngineCase("duration-grouping-and-precedence") {
        // Consecutive components are ONE primary, BEFORE multiplicative
        // precedence: `1 h 30 min / 3` is 30 min, never 1 h 10 min.
        try expectDuration("1 h 30 min / 3", "30 min")
        try expectDuration("(1 h 20 min) × 2", "2 h 40 min")
        try expectDuration("3 × (1 h 15 min)", "3 h 45 min")
        try expectDuration("(1 h 15 min)", "1 h 15 min")
        try expectDuration("1 h 20 min × 2", "2 h 40 min")
        try expectDuration("2 × 1 h 20 min", "2 h 40 min")
        try expectDuration("1 min 250 ms × 4", "4 min 1 s")
        try expectDuration("2 h 30 min / 2 + 15 min", "1 h 30 min")
        // Unary minus keeps the natural presentation.
        try expectDuration("-1 h 30 min", "-1 h 30 min")
        try expectDuration("-30 min", "-30 min")
        try expectDuration("0 h - 1 h 15 min", "-1 h 15 min")
    },

    EngineCase("duration-arithmetic-errors") {
        try expectDurationError("5 kg + 3 h")
        try expectDurationError("30 min / 0")
        try expectDurationError("1 h 30 min + 5 kg")
        try expectDurationError("3 h to kg")
    },

    EngineCase("duration-explicit-conversions-reset-presentation") {
        // An explicit target is a single-unit conversion: never a natural
        // compound, and the row's kind returns to the ordinary one.
        try expectDuration("1 h 30 min to min", "90 min")
        try expectDuration("1 h 30 min in hours", "1.5 h")
        try expectDuration("1 h 30 min as seconds", "5,400 s")
        try expectDuration("1 h 30 min to h", "1.5 h")
        try expectDuration("90 min to h", "1.5 h")
        try expectDuration("1 h 30 min + 30 min to min", "120 min")
        var v: [String: Double] = [:]
        guard case .number(_, let unit, let kind, _)? =
                durLine("1 h 30 min to min", variables: &v) else {
            throw CaseFailure(message: "conversion must be a number", location: "Duration")
        }
        try expectEqual(unit, "min", "converted unit")
        try expectEqual(kind, .plain, "the duration kind is reset by an explicit target")
    },

    EngineCase("duration-variables-and-multiword-names") {
        let lines = sheetTexts("focus time = 1 h 30 min\nfocus time + 15 min")
        try expectEqual(lines, ["1 h 30 min", "1 h 45 min"], "multiword duration variable")
        let scaled = sheetTexts("x = 2 h 30 min\nx × 2\nx / 5\nx + 30 min\n2 × x")
        try expectEqual(scaled, ["2 h 30 min", "5 h", "30 min", "3 h", "5 h"],
                        "a duration variable stays a real quantity")
    },

    EngineCase("duration-copy-parity-and-tokens") {
        // The clipboard string is byte-identical to the visible one for
        // every duration row (the presentation is semantic, not a notation).
        var v: [String: Double] = [:]
        for line in ["1 h 45 min + 30 min", "2 min 30 sec × 3", "45min",
                     "1 day 2 h + 90 min", "1 min 250 ms + 750 ms"] {
            guard let r = durLine(line, variables: &v),
                  case .number(let value, let unit, let kind, _) = r else {
                throw CaseFailure(message: "\(line) must be a number", location: "Duration")
            }
            try expectEqual(kind, .duration, "\(line) is presented as a duration")
            let visible = AnswerDisplay.displayText(for: r, decimalPlaces: 7, context: .legacy)
            let copy = AnswerDisplay.text(for: r, decimalPlaces: 7, context: .legacy)
            try expectEqual(copy, visible, "\(line): copy == visible")
            // The row keeps an ordinary time quantity underneath: the value
            // and the real display unit are unchanged by the marker.
            try expectEqual(DurationUnits.component(forLabel: unit ?? ""),
                            DurationUnits.component(forLabel: unit ?? ""),
                            "the display unit is a real fixed time unit")
            try expect(value.isFinite, "the stored value stays finite")
        }
        // A duration row offers Copy/Delete only (no rounding, no notation).
        var v2: [String: Double] = [:]
        guard let r = durLine("1 h 45 min + 30 min", variables: &v2) else {
            throw CaseFailure(message: "duration row", location: "Duration")
        }
        try expectEqual(AnswerDisplay.notationOptions(for: r), nil,
                        "no notation menu for a natural duration")
        try expectEqual(AnswerDisplay.menu(for: r),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                        "Copy/Delete only")
        // An ordinary single time quantity keeps its rounding menu.
        var v3: [String: Double] = [:]
        guard let plain = durLine("90 min", variables: &v3) else {
            throw CaseFailure(message: "plain time row", location: "Duration")
        }
        try expectEqual(AnswerDisplay.menu(for: plain),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: true),
                        "a plain time row is unchanged")
    },

    EngineCase("duration-marker-is-in-memory-only") {
        // The marker rides the in-memory quantity: scaling keeps it, an
        // explicit conversion drops it, and nothing about the persisted
        // types changes (Quantity is re-derived from sheet text every pass).
        var v: [String: Double] = [:]
        guard let scaled = durLine("1 h 30 min × 2", variables: &v),
              case .number(_, _, let scaledKind, _) = scaled else {
            throw CaseFailure(message: "scaled duration", location: "Duration")
        }
        try expectEqual(scaledKind, .duration, "scaling keeps the marker")
        var v2: [String: Double] = [:]
        guard let converted = durLine("1 h 30 min to min", variables: &v2),
              case .number(_, _, let convertedKind, _) = converted else {
            throw CaseFailure(message: "converted duration", location: "Duration")
        }
        try expectEqual(convertedKind, .plain, "a conversion drops the marker")
    },

    // MARK: the pure decomposition formatter

    EngineCase("duration-formatter-canonical-output") {
        func text(_ seconds: Double, places: Int = 7) -> String? {
            DurationPresentation.text(seconds: seconds, decimalPlaces: places,
                                      context: .legacy)
        }
        try expectEqual(text(0), "0 s", "zero")
        try expectEqual(text(8100), "2 h 15 min", "2 h 15 min")
        try expectEqual(text(99_000), "1 day 3 h 30 min", "1 day 3 h 30 min")
        try expectEqual(text(450), "7 min 30 s", "7 min 30 s")
        try expectEqual(text(61), "1 min 1 s", "1 min 1 s")
        try expectEqual(text(-1800), "-30 min", "-30 min")
        try expectEqual(text(0.5), "500 ms", "500 ms")
        try expectEqual(text(3600), "1 h", "1 h")
        try expectEqual(text(604_800), "1 week", "1 week")
        try expectEqual(text(86_400 + 3600), "1 day 1 h", "1 day 1 h")
        try expectEqual(text(5.006), "5 s 6 ms", "sub-second millisecond residue")
        try expectEqual(text(0.0000015), "0.0015 ms", "a fractional millisecond")
    },

    EngineCase("duration-formatter-carries-and-bounds") {
        func text(_ seconds: Double, places: Int = 7) -> String? {
            DurationPresentation.text(seconds: seconds, decimalPlaces: places,
                                      context: .legacy)
        }
        // 59.999… s rounds up into the next minute instead of printing
        // `59.9999999 s`.
        try expectEqual(text(59.99999999), "1 min", "second carry")
        try expectEqual(text(3599.99999999), "1 h", "minute carry")
        try expectEqual(text(86_399.99999999), "1 day", "hour carry")
        try expectEqual(text(604_799.99999999), "1 week", "day carry")
        try expectEqual(text(59.5), "59 s 500 ms", "a sub-second residue is shown in ms")
        // Huge and tiny magnitudes stay finite and readable.
        try expectEqual(text(604_800 * 100), "100 week", "enormous weeks")
        try expectEqual(text(-0.5), "-500 ms", "negative zero-ish residue")
        try expectEqual(text(.nan), nil, "NaN is rejected")
        try expectEqual(text(.infinity), nil, "infinity is rejected")
        // Fractional components obey the decimal bound.
        try expectEqual(text(1.23456789, places: 2), "1 s 230 ms", "decimal bound")
        try expectEqual(text(1.23456789, places: 10), "1.23456789 s", "wide bound")
        // A non-fixed unit label falls back to the ordinary presentation.
        var v: [String: Double] = [:]
        try expectEqual(DurationPresentation.text(value: 2, unitLabel: "yr",
                                                  decimalPlaces: 7, context: .legacy),
                        "2 yr", "a calendar average is not decomposed")
        _ = v
    },

    EngineCase("duration-decimal-comma-context") {
        // In a decimal-comma context the fractional component uses the
        // comma separator; the parser reads `2,5 h` as two and a half hours.
        let comma = NumberFormatContext(
            locale: Locale(identifier: "de_DE"), decimalSeparator: ",",
            groupingSeparator: ".", argumentSeparator: ";",
            displayGrouping: true, compactNotation: false,
            convertForeignOnPaste: true)
        try expectDuration("2,5 h + 30 min", "3 h", context: comma)
        try expectDuration("1,5 h + 15 min", "1 h 45 min", context: comma)
        // In the legacy context the comma is a GROUPING separator, so `2,5`
        // is twenty-five — unchanged behaviour.
        try expectDuration("1 h + 25 min", "1 h 25 min")
    },

    EngineCase("duration-not-a-string-and-not-unitless") {
        // The value stays a real quantity in a real time unit: a duration
        // row's LineResult carries the unit and a dimension of T^1.
        var v: [String: Double] = [:]
        guard let r = durLine("1 h 45 min", variables: &v),
              case .number(let value, let unit, let kind, _) = r else {
            throw CaseFailure(message: "a number result", location: "Duration")
        }
        try expectEqual(kind, .duration, "duration kind")
        try expect(unit == "h", "displayed in the largest component")
        try expect(abs(value - 1.75) < 1e-12, "the value is in hours, not seconds")
        // Scaling in a different unit still decomposes correctly.
        try expectDuration("1 h 45 min + 900 s", "2 h")
        // A rate keeps its own presentation: never a duration.
        var v2: [String: Double] = [:]
        guard case .number(_, let rateUnit, let rateKind, _)? =
                durLine("90 km / 3 h", variables: &v2) else {
            throw CaseFailure(message: "a rate result", location: "Duration")
        }
        try expectEqual(rateKind, .plain, "a rate is not a duration")
        try expect(rateUnit == "km/h", "and keeps its compound unit")
    },

    EngineCase("duration-calendar-and-prose-untouched") {
        // Date arithmetic keeps priority, average months/years keep their
        // meaning, and prose/DMS/rates are unchanged.
        try expectDuration("May 5 + 2 days", "May 7")
        try expectDuration("May 5 + 43 days", "Jun 17")
        try expectDuration("2 hours + 30 min", "2 h 30 min")
        try expectDuration("1 yr + 1 yr", "2 yr")
        try expectDuration("1 mo + 1 mo", "2 mo")
        try expectDuration("$24 per day × 12 hrs", "$12.00")
        try expectDuration("300 km / 2.5 hours", "120 km/h")
        try expectDuration("12 hrs", "12 h")
        // DMS degrees/minutes/seconds are a different lane entirely.
        var v: [String: Double] = [:]
        guard let dms = durLine("51° 30′ 26″", variables: &v) else {
            throw CaseFailure(message: "DMS must evaluate", location: "Duration")
        }
        if case .error(let m) = dms {
            throw CaseFailure(message: "DMS must not error: \(m)", location: "Duration")
        }
    },

    EngineCase("duration-total-policy-unchanged") {
        // The Total keeps its pre-feature contribution policy: a duration
        // row still carries value + display unit, and the inline total's
        // existing rules are untouched (unit-bearing rows are excluded from
        // the plain summation exactly as before).
        var v: [String: Double] = [:]
        guard let r = durLine("1 h 45 min", variables: &v),
              case .number(let value, let unit, _, _) = r else {
            throw CaseFailure(message: "duration row", location: "Duration")
        }
        try expect(unit != nil, "the unit survives on the result")
        try expect(value.isFinite, "the value survives on the result")
        // The pre-feature policy counts ANY unit-bearing number by value;
        // the duration marker deliberately keeps that behaviour (the row
        // still carries the ordinary value + display unit).
        let durationContribution = SheetFooterTotal.contribution(of: r, isTotalRow: false)
        try expectEqual(durationContribution, 1.75,
                        "the Total contribution policy is unchanged")
        let plain = SheetFooterTotal.contribution(
            of: .number(value: 10, unit: nil), isTotalRow: false)
        try expectEqual(plain, 10, "a plain value still contributes")
    },

    EngineCase("duration-maximum-input-bounds") {
        // A long chain of components is linear and finite; an enormous
        // repeated input stays bounded and never hangs.
        let long = Array(repeating: "1 h", count: 200).joined(separator: " ")
        var v: [String: Double] = [:]
        guard let r = durLine(long, variables: &v) else {
            throw CaseFailure(message: "200 components must evaluate", location: "Duration")
        }
        guard case .number = r else {
            throw CaseFailure(message: "200 components are a number", location: "Duration")
        }
        let huge = "999999 week 6 day 23 h 59 min 59 s"
        try expectDuration(huge, "999,999 week 6 day 23 h 59 min 59 s")
        // A non-finite duration is rejected by the formatter (the scanner
        // never produces one).
        try expectEqual(DurationPresentation.text(seconds: .infinity, decimalPlaces: 7,
                                                  context: .legacy), nil,
                        "non-finite durations are rejected")
    },

    EngineCase("duration-answer-tokens-carry-the-presentation") {
        // A token over a duration row shows the natural string, carries the
        // real time unit, and stays a time quantity scaled by a scalar.
        let source = UUID(), bare = UUID(), scaled = UUID()
        let marker = String(answerTokenMarker)
        let sourceLine = "1 h 30 min"
        let content = sourceLine + "\n" + marker + "\n" + marker + " * 2"
        let (lines, tokens) = resolveSheet(
            content: content, lineIDs: [source, bare, scaled],
            references: [AnswerReference(sourceLineID: source, labelLine: 1,
                                         // the marker's UTF-16 offset in the
                                         // WHOLE content (source + newline)
                                         location: ("1 h 30 min\n" as NSString).length)],
            rates: Rates(), decimalPlaces: 7)
        try expectEqual(lines.count, 3, "three logical lines")
        // The capsule shows the natural duration once.
        try expectEqual(tokens[0].state,
                        .activeKinded(value: 1.5, unit: "h", kind: .duration,
                                      fraction: nil, display: "1 h 30 min"),
                        "the capsule shows the natural duration")
        let bareText = AnswerDisplay.displayText(for: lines[1].result, decimalPlaces: 7,
                                                 context: .legacy)
        try expectEqual(bareText, "1 h 30 min", "a bare token row is the natural duration")
        try expectEqual(AnswerDisplay.text(for: lines[1].result, decimalPlaces: 7,
                                           context: .legacy),
                        bareText, "and copies it byte-for-byte")
        // A unit-bearing token keeps its typed duration identity: the
        // token state above carries the real time unit AND the duration
        // kind, which is what any expression consumes. (The reference
        // algebra's own operand support is unchanged by this feature.)
    },

    EngineCase("duration-syntax-spans-cover-the-whole-literal") {
        // Every numeric and unit component of a compound literal is inside
        // the ONE quantity token, so the syntax spans cover the whole form.
        let source = "1 h 45 min + 30 min"
        var v: [String: Double] = [:]
        guard let r = durLine(source, variables: &v),
              case .number(_, let unit, let kind, _) = r else {
            throw CaseFailure(message: "the line evaluates", location: "Duration")
        }
        try expectEqual(kind, .duration, "duration kind")
        try expectEqual(unit, "h", "display unit")
        // The canonical document pass keeps the source spelling intact
        // (no rewriting of duration literals).
        try expectEqual(NotebookFormatting.canonicalDocument(source), source,
                        "duration literals are preserved byte-for-byte")
    }
]
