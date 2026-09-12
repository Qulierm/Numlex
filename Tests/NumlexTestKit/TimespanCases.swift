import Foundation
import NumlexCore

// MARK: - temporal Task 3: Timespan mode

private func tsEval3(_ line: String, context: NumberFormatContext = .legacy) -> LineResult? {
    var v: [String: Double] = [:]
    return evalLine(line, variables: &v, rates: Rates(), decimalPlaces: 10,
                    now: Date(timeIntervalSince1970: 1_554_112_800),
                    calendar: Calendar(identifier: .gregorian),
                    context: context, unitContext: .builtIns)
}

private func tsText3(_ line: String, context: NumberFormatContext = .legacy) -> String? {
    guard let r = tsEval3(line, context: context) else { return nil }
    return AnswerDisplay.displayText(for: r, decimalPlaces: 10, context: context)
}

private func expectSpan(_ line: String, _ expected: String) throws {
    guard let text = tsText3(line) else {
        throw CaseFailure(message: "no timespan text for \(line)", location: "Timespan")
    }
    try expectEqual(text, expected, "\(line)")
}

public let timespanCases: [EngineCase] = [

    EngineCase("timespan-official-examples") {
        try expectSpan("5.5 minutes as timespan", "5 min 30 s")
        try expectSpan("4.54 hours as timespan", "4 hours 32 minutes 24 seconds")
        try expectSpan("72 days as timespan", "10 weeks 2 days")
        // The natural (non-timespan) compound keeps its pre-existing shape.
        try expectSpan("3 hours 5 minutes 10 seconds", "3 h 5 min 10 s")
        // Explicit target units reset to the single-unit standard form.
        try expectSpan("3 hours 5 minutes 10 seconds in seconds", "11,110 s")
        try expectSpan("3h 5m 10s in seconds", "11,110 s")
    },

    EngineCase("timespan-contextual-compact-grammar") {
        // Inside a proven duration chain glued m = minute, glued s = second.
        try expectSpan("3h 5m 10s", "3 h 5 min 10 s")
        try expectSpan("1h45min", "1 h 45 min")
        try expectSpan("2h 30m", "2 h 30 min")
        // Assignment/variable path uses the SAME shared parser.
        var v: [String: Double] = [:]
        guard let assigned = evalLine("d = 3h 5m 10s", variables: &v, rates: Rates(),
                                      decimalPlaces: 10, now: Date(),
                                      calendar: Calendar(identifier: .gregorian),
                                      context: .legacy, unitContext: .builtIns),
              case .number(let value, let unit, _, _) = assigned else {
            throw CaseFailure(message: "compact chain assignment", location: "Timespan")
        }
        try expectClose(value, 3 + 5.0 / 60 + 10.0 / 3600, 1e-9, "assigned value in hours")
        try expectEqual(unit, "h", "largest display unit")
        // Standalone `5m` stays 5,000,000; `5 m` stays metres; `10s` is not
        // silently read as a duration.
        try expectSpan("5m", "5,000,000")
        if let metres = tsText3("5 m") {
            try expect(metres.hasPrefix("5 m"), "5 m stays metres, got \(metres)")
        }
        if let tenS = tsEval3("10s"),
           case .number(let v10, _, let kind, _) = tenS {
            try expect(!(kind == .duration && abs(v10 - 10) < 1e-9),
                       "standalone 10s never reads as 10 seconds")
        }
    },

    EngineCase("timespan-explicit-suffix") {
        // The suffix is independent of the global/per-line notation.
        try expectSpan("-5.5 minutes as timespan", "-5 min 30 s")
        try expectSpan("0 s as timespan", "0 s")
        try expectSpan("1.5 yr as timespan", "1 yr 6 mo")
        try expectSpan("01:02:03 as timespan", "1 hour 2 minutes 3 seconds")
        // An unparsable digit-bearing body is a strict error.
        guard let bad = tsEval3("5 kg as timespan"), case .error = bad else {
            throw CaseFailure(message: "5 kg as timespan errors", location: "Timespan")
        }
        // The average factors are the catalog's linear time factors.
        try expectClose(UnitCatalog.resolveExpression("yr")?.unit.toBase ?? 0,
                        31_556_952, 1e-9, "average year")
        try expectClose(UnitCatalog.resolveExpression("mo")?.unit.toBase ?? 0,
                        2_629_746, 1e-9, "average month")
        // Gregorian date arithmetic never becomes an average-factor
        // multiplication: Jan 31 + 1 month is Feb 28/29, not +30.44 days.
        let jan31 = DateArithmetic.detect(
            line: "January 31 + 1 month",
            now: Date(timeIntervalSince1970: 1_554_112_800),
            calendar: Calendar(identifier: .gregorian))
        guard case .value(let result) = jan31 else {
            throw CaseFailure(message: "calendar month arithmetic", location: "Timespan")
        }
        try expectEqual(result.month, 2, "calendar month stays a Calendar component")
        try expectEqual(result.day, 28, "Jan 31 + 1 month = Feb 28 (2019)")
    },

    EngineCase("timespan-notation-mode") {
        // The global/per-line Timespan notation on a time quantity.
        guard let time = tsEval3("4.54 hours"),
              case .number = time else {
            throw CaseFailure(message: "4.54 hours evaluates", location: "Timespan")
        }
        try expectEqual(AnswerDisplay.displayText(
            for: time, decimalPlaces: 10, context: .legacy, notation: .timespan),
            "4 hours 32 minutes 24 seconds", "time quantity takes timespan")
        // Visible == copy (byte parity).
        try expectEqual(AnswerDisplay.text(
            for: time, decimalPlaces: 10, context: .legacy, notation: .timespan),
            "4 hours 32 minutes 24 seconds", "copy parity")
        // A non-time number falls back to Automatic — never blank/error.
        guard let plain = tsEval3("5"), case .number = plain else {
            throw CaseFailure(message: "5 evaluates", location: "Timespan")
        }
        try expectEqual(AnswerDisplay.displayText(
            for: plain, decimalPlaces: 10, context: .legacy, notation: .timespan),
            "5", "non-time falls back to automatic")
        // The enum and the per-answer override carry timespan and decode
        // tolerantly.
        try expect(NumberNotation.allCases.contains(.timespan), "global picker lists Timespan")
        try expectEqual(NumberNotation(rawValue: "timespan"), .timespan, "stable raw value")
        try expectEqual(AnswerNotationOverride(rawValue: "timespan")?.notation, .timespan,
                        "override maps to the notation")
        let prefData = Data(#"{"lineID": "\#(UUID().uuidString)", "decimalPlaces": 6, "notation": "timespan"}"#.utf8)
        let pref = try JSONDecoder().decode(AnswerDisplayPreference.self, from: prefData)
        try expectEqual(pref.notation, .timespan, "per-answer override decodes")
        // A malformed/unknown notation still falls back to Default (nil).
        let badData = Data(#"{"lineID": "\#(UUID().uuidString)", "decimalPlaces": 6, "notation": "warpdrive"}"#.utf8)
        let badPref = try JSONDecoder().decode(AnswerDisplayPreference.self, from: badData)
        try expect(badPref.notation == nil, "unknown notation falls back to Default")
        // Persistence round-trip.
        var prefs = NumberPresentationPreferences.defaults
        prefs.notation = .timespan
        let back = try JSONDecoder().decode(NumberPresentationPreferences.self,
                                            from: try JSONEncoder().encode(prefs))
        try expectEqual(back.notation, .timespan, "global setting persists")
        // The picker label is localized in all six languages.
        for lang in AppLanguage.allCases {
            let label = L10n.t("formatTimespan", language: lang)
            try expect(label != "formatTimespan" && !label.isEmpty,
                       "\(lang.rawValue): Timespan label")
        }
    },

    EngineCase("timespan-carry-sign-and-token-parity") {
        // Carry-safe rounding: the smallest component carries upward.
        try expectEqual(TimespanPresentation.text(seconds: 59.9999, style: .short,
                                                  decimalPlaces: 3, context: .legacy),
                        "1 min", "seconds carry into minutes")
        try expectEqual(TimespanPresentation.text(seconds: 3_599.9999, style: .full,
                                                  decimalPlaces: 3, context: .legacy),
                        "1 hour", "minutes carry into hours")
        try expectEqual(TimespanPresentation.text(seconds: 0.5, style: .short,
                                                  decimalPlaces: 3, context: .legacy),
                        "500 ms", "sub-second presents in ms")
        // One sign, zero components omitted.
        guard let neg = tsText3("-5.5 minutes as timespan") else {
            throw CaseFailure(message: "negative timespan", location: "Timespan")
        }
        try expectEqual(neg.filter { $0 == "-" }.count, 1, "one leading sign")
        // Token byte parity: a token referencing a timespan source shows
        // the same text the source row shows.
        let marker = "\u{FFFC}"
        let id0 = UUID(), id1 = UUID()
        let content = "4.54 hours as timespan\n\(marker)"
        let resolved = resolveSheet(content: content, lineIDs: [id0, id1],
                                    references: [AnswerReference(sourceLineID: id0,
                                                                 labelLine: 1, location: 23)],
                                    rates: Rates(), decimalPlaces: 10)
        guard case .number = resolved.lines[0].result else {
            throw CaseFailure(message: "timespan source row", location: "Timespan")
        }
        // The token line resolves to the same quantity and displays the
        // SAME timespan string as the source row.
        guard case .number(_, _, let tokenKind, _) = resolved.lines[1].result else {
            throw CaseFailure(message: "token line resolves", location: "Timespan")
        }
        try expectEqual(tokenKind, .timespan, "token carries the timespan kind")
        let tokenText = AnswerDisplay.displayText(for: resolved.lines[1].result,
                                                  decimalPlaces: 10, context: .legacy)
        let sourceText = AnswerDisplay.displayText(for: resolved.lines[0].result,
                                                   decimalPlaces: 10, context: .legacy)
        try expectEqual(tokenText, sourceText, "token/source byte parity")
    },
]
