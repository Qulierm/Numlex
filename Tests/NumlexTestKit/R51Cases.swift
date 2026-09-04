import Foundation
import NumlexCore

/// r51: answer context menu (copy / per-answer rounding / delete line).
/// Coverage:
/// 1. Model: AnswerDisplayPreference Codable + Sheet backward compat
///    (missing/wrong-typed key decodes []), SheetExport optional prefs,
///    sanitize (stale drop, clamp 0...10, dedupe, line-order).
/// 2. No StorePayload version bump; old payloads decode.
/// 3. Pure line deletion: first/middle/last/sole/trailing-empty,
///    UTF-16/emoji boundaries, caret landing, survivor ID stability
///    through LineIdentity.reconcile, marker shift/drop, token break.
/// 4. Display/copy contract: AnswerDisplay.text per result kind,
///    override vs default, menu eligibility descriptor.
/// 5. Localization keys in all six tables (Russian exact).
/// 6. Interaction regressions: double-click pair semantics unchanged.

private func r51Results(_ content: String, decimalPlaces: Int = 2) -> [LineResult] {
    let lines = content.components(separatedBy: "\n")
    return resolveSheet(content: content,
                        lineIDs: lines.map { _ in UUID() },
                        references: [],
                        rates: Rates(),
                        decimalPlaces: decimalPlaces,
                        constants: []).lines.map(\.result)
}

private func r51Sheet(content: String) -> (sheet: Sheet, ids: [UUID]) {
    let ids = content.components(separatedBy: "\n").map { _ in UUID() }
    let s = Sheet(title: "T", content: content, lineIDs: ids)
    return (s, s.lineIDs)
}

public let r51Cases: [EngineCase] = [
    // MARK: 1. Codable backward compatibility

    EngineCase("r51-sheet-decodes-without-answerDisplay") {
        let json = """
        {"id":"\(UUID().uuidString)","title":"T","content":"1 + 1",\
        "createdAt":0,"modifiedAt":0,"isTitleCustom":true,\
        "titleSeed":"T","lineIDs":["\(UUID().uuidString)"],"references":[]}
        """
        let s = try JSONDecoder().decode(Sheet.self, from: Data(json.utf8))
        try expectEqual(s.answerDisplay, [], "missing key decodes empty")
    },

    EngineCase("r51-sheet-wrong-typed-answerDisplay-decodes-empty") {
        let json = """
        {"id":"\(UUID().uuidString)","title":"T","content":"1 + 1",\
        "createdAt":0,"modifiedAt":0,"answerDisplay":42}
        """
        let s = try JSONDecoder().decode(Sheet.self, from: Data(json.utf8))
        try expectEqual(s.answerDisplay, [], "wrong-typed key falls back to empty")
    },

    EngineCase("r51-sheet-roundtrip-preserves-preferences") {
        let (s0, ids) = r51Sheet(content: "1 + 1\n2 + 2")
        var s = s0
        s.answerDisplay = [AnswerDisplayPreference(lineID: ids[1], decimalPlaces: 4)]
        let back = try JSONDecoder().decode(Sheet.self,
                                            from: JSONEncoder().encode(s))
        try expectEqual(back.answerDisplay,
                        [AnswerDisplayPreference(lineID: ids[1], decimalPlaces: 4)],
                        "round-trip preserves override")
    },

    EngineCase("r51-sheet-init-sanitizes-stale-preferences") {
        let (s0, ids) = r51Sheet(content: "1 + 1\n2 + 2")
        let stale = UUID()
        let s = Sheet(title: "T", content: s0.content, lineIDs: ids,
                      answerDisplay: [AnswerDisplayPreference(lineID: stale, decimalPlaces: 3),
                                      AnswerDisplayPreference(lineID: ids[0], decimalPlaces: 20)])
        try expectEqual(s.answerDisplay,
                        [AnswerDisplayPreference(lineID: ids[0], decimalPlaces: 10)],
                        "stale dropped, out-of-range clamped")
    },

    EngineCase("r51-export-nil-preferences-old-file") {
        let exp = SheetExport(title: "T", content: "1 + 1")
        try expectEqual(exp.answerDisplay, nil, "old files decode nil")
        let back = try JSONDecoder().decode(SheetExport.self,
                                            from: JSONEncoder().encode(exp))
        try expectEqual(back.answerDisplay, nil, "nil survives round-trip")
    },

    EngineCase("r51-export-preserves-preferences") {
        let id = UUID()
        let exp = SheetExport(title: "T", content: "1 + 1",
                              answerDisplay: [AnswerDisplayPreference(lineID: id, decimalPlaces: 0)])
        let back = try JSONDecoder().decode(SheetExport.self,
                                            from: JSONEncoder().encode(exp))
        try expectEqual(back.answerDisplay,
                        [AnswerDisplayPreference(lineID: id, decimalPlaces: 0)],
                        "export preserves rounding prefs")
    },

    // MARK: 2. Sanitize / effective / version

    EngineCase("r51-sanitize-orders-by-line-dedupes") {
        let a = UUID(), b = UUID(), c = UUID()
        let out = AnswerDisplay.sanitize(
            [AnswerDisplayPreference(lineID: c, decimalPlaces: 2),
             AnswerDisplayPreference(lineID: a, decimalPlaces: 5),
             AnswerDisplayPreference(lineID: a, decimalPlaces: 7),
             AnswerDisplayPreference(lineID: UUID(), decimalPlaces: 1)],
            lineIDs: [a, b, c])
        try expectEqual(out.map(\.lineID), [a, c], "line order, first wins, stale dropped")
        try expectEqual(out.map(\.decimalPlaces), [5, 2], "values kept")
    },

    EngineCase("r51-clamp-and-effective") {
        try expectEqual(AnswerDisplay.clamped(-3), 0, "floor 0")
        try expectEqual(AnswerDisplay.clamped(15), 10, "cap 10")
        try expectEqual(AnswerDisplay.effective(defaultPlaces: 2, override: nil), 2, "default")
        try expectEqual(AnswerDisplay.effective(defaultPlaces: 2, override: 9), 9, "override wins")
        try expectEqual(AnswerDisplay.effective(defaultPlaces: 2, override: 99), 10, "override clamped")
    },

    EngineCase("r51-no-store-version-bump") {
        try expectEqual(StorePayload.currentVersion, 2, "payload version stays 2")
    },

    EngineCase("r51-old-payload-decodes") {
        let json = """
        {"sheets":[],"selectedIndex":0,\
        "settings":{"decimalPlaces":10,"fontSizeKey":"tf","language":"en",\
        "sheetName":"Sheet","lineNumbers":true,"fontColor":"white",\
        "input":{"replaceBacktick":false,"insertPreviousAnswer":true,\
        "groupNumbers":true,"padOperators":true,"quickOperators":true,\
        "replaceAsterisk":true},"styling":{"labels":"standardText",\
        "fontDesign":"system","numbers":"cyan","operators":"standardText",\
        "headings":"standardText","specifiers":"standardText",\
        "comments":"blue","variables":"green","units":"pinkPurple"},\
        "customConstants":[],"appearance":"light"},\
        "version":2,"folders":[]}
        """
        let p = try JSONDecoder().decode(StorePayload.self, from: Data(json.utf8))
        try expectEqual(p.version, 2, "old payload decodes")
    },

    // MARK: 3. Pure deletion plans

    EngineCase("r51-delete-middle-line") {
        let plan = AnswerDisplay.deleteLinePlan(content: "1 + 1\n2 + 2\n3 + 3", lineIndex: 1)!
        try expectEqual(plan.content, "1 + 1\n3 + 3", "middle line plus newline gone")
        try expectEqual(plan.caret, 6, "caret at deletion start")
    },

    EngineCase("r51-delete-first-line") {
        let plan = AnswerDisplay.deleteLinePlan(content: "1 + 1\n2 + 2", lineIndex: 0)!
        try expectEqual(plan.content, "2 + 2", "first line plus newline gone")
        try expectEqual(plan.caret, 0, "caret at zero")
    },

    EngineCase("r51-delete-last-line") {
        let plan = AnswerDisplay.deleteLinePlan(content: "1 + 1\n2 + 2", lineIndex: 1)!
        try expectEqual(plan.content, "1 + 1", "preceding newline goes with last line")
        try expectEqual(plan.caret, 5, "caret at deletion start")
    },

    EngineCase("r51-delete-sole-line") {
        let plan = AnswerDisplay.deleteLinePlan(content: "9 × 9", lineIndex: 0)!
        try expectEqual(plan.content, "", "sole line leaves empty sheet")
        try expectEqual(plan.caret, 0, "caret at zero")
    },

    EngineCase("r51-delete-trailing-empty-keeps-lines") {
        let plan = AnswerDisplay.deleteLinePlan(content: "1 + 1\n", lineIndex: 0)!
        try expectEqual(plan.content, "", "expression line removed")
        let rec = LineIdentity.reconcile(oldContent: "1 + 1\n",
                                         oldLineIDs: [UUID(), UUID()],
                                         oldReferences: [],
                                         newContent: plan.content,
                                         edit: plan.edit)
        try expectEqual(rec.lineIDs.count, 1, "valid one-line identity")
    },

    EngineCase("r51-delete-emoji-boundaries") {
        let content = "🎉 x\n2 + 2"
        let plan = AnswerDisplay.deleteLinePlan(content: content, lineIndex: 0)!
        try expectEqual(plan.content, "2 + 2", "emoji line removed exactly")
        try expectEqual(plan.caret, 0, "caret at zero")
        let plan2 = AnswerDisplay.deleteLinePlan(content: content, lineIndex: 1)!
        try expectEqual(plan2.content, "🎉 x", "preceding newline removed, emoji intact")
    },

    EngineCase("r51-delete-out-of-range-nil") {
        try expectEqual(AnswerDisplay.deleteLinePlan(content: "1", lineIndex: 3), nil,
                        "out-of-range index is nil")
    },

    EngineCase("r51-deletion-keeps-survivor-ids") {
        let (s, ids) = r51Sheet(content: "1 + 1\n2 + 2\n3 + 3")
        let plan = AnswerDisplay.deleteLinePlan(content: s.content, lineIndex: 1)!
        let rec = LineIdentity.reconcile(oldContent: s.content,
                                         oldLineIDs: s.lineIDs,
                                         oldReferences: [],
                                         newContent: plan.content,
                                         edit: plan.edit)
        try expectEqual(rec.lineIDs, [ids[0], ids[2]], "survivors keep stable IDs")
    },

    EngineCase("r51-deletion-shifts-later-markers") {
        let m = "\u{FFFC}"
        let content = "1 + 1\n2 + 2\n\(m) + 1"
        let (s, _) = r51Sheet(content: content)
        let loc = (content as NSString).range(of: m).location
        let ref = AnswerReference(sourceLineID: UUID(), labelLine: 9, location: loc)
        let plan = AnswerDisplay.deleteLinePlan(content: content, lineIndex: 1)!
        let rec = LineIdentity.reconcile(oldContent: content,
                                         oldLineIDs: s.lineIDs,
                                         oldReferences: [ref],
                                         newContent: plan.content,
                                         edit: plan.edit)
        try expectEqual(rec.references.count, 1, "later marker survives")
        try expectEqual(rec.references[0].location,
                        (plan.content as NSString).range(of: m).location,
                        "marker shifted exactly onto the merged content")
    },

    EngineCase("r51-deletion-drops-markers-inside") {
        let m = "\u{FFFC}"
        let content = "1 + 1\n2 + \(m)\n3 + 3"
        let (s, _) = r51Sheet(content: content)
        let ref = AnswerReference(sourceLineID: UUID(), labelLine: 9,
                                  location: (content as NSString).range(of: m).location)
        let plan = AnswerDisplay.deleteLinePlan(content: content, lineIndex: 1)!
        let rec = LineIdentity.reconcile(oldContent: content,
                                         oldLineIDs: s.lineIDs,
                                         oldReferences: [ref],
                                         newContent: plan.content,
                                         edit: plan.edit)
        try expectEqual(rec.references, [], "marker inside deleted line dropped")
    },

    EngineCase("r51-deleted-source-breaks-token") {
        let m = "\u{FFFC}"
        let a = UUID(), b = UUID()
        let content = "5 + 5\n\(m)"
        let ref = AnswerReference(sourceLineID: a, labelLine: 1, location: 6)
        let plan = AnswerDisplay.deleteLinePlan(content: content, lineIndex: 0)!
        let rec = LineIdentity.reconcile(oldContent: content,
                                         oldLineIDs: [a, b],
                                         oldReferences: [ref],
                                         newContent: plan.content,
                                         edit: plan.edit)
        try expectEqual(rec.lineIDs, [b], "only the token line ID survives")
        let r = resolveSheet(content: plan.content, lineIDs: rec.lineIDs,
                             references: rec.references, rates: Rates(),
                             decimalPlaces: 2, constants: [])
        guard case .brokenToken(let line) = r.lines[0].result else {
            throw CaseFailure(message: "token line must break, got \(r.lines[0].result)",
                              location: "r51")
        }
        try expectEqual(line, 1, "remembered label line")
    },

    EngineCase("r51-deletion-drops-rounding-prefs") {
        let (s0, ids) = r51Sheet(content: "1 + 1\n2 + 2\n3 + 3")
        var s = s0
        s.answerDisplay = [AnswerDisplayPreference(lineID: ids[1], decimalPlaces: 0),
                           AnswerDisplayPreference(lineID: ids[2], decimalPlaces: 8)]
        let plan = AnswerDisplay.deleteLinePlan(content: s.content, lineIndex: 1)!
        let rec = LineIdentity.reconcile(oldContent: s.content,
                                         oldLineIDs: s.lineIDs,
                                         oldReferences: [],
                                         newContent: plan.content,
                                         edit: plan.edit)
        s.content = plan.content
        s.lineIDs = rec.lineIDs
        s.dropStaleAnswerDisplay()
        try expectEqual(s.answerDisplay,
                        [AnswerDisplayPreference(lineID: ids[2], decimalPlaces: 8)],
                        "deleted line pref dropped, survivor retained")
    },

    EngineCase("r51-deletion-retitles-to-next-calculation") {
        let (s0, _) = r51Sheet(content: "9 × 9\n8 + 8")
        var s = Sheet.retitled(s0, content: s0.content)
        try expectEqual(s.title, "9 × 9", "title follows first line")
        let plan = AnswerDisplay.deleteLinePlan(content: s.content, lineIndex: 0)!
        s.content = plan.content
        s = Sheet.retitled(s, content: s.content)
        try expectEqual(s.title, "8 + 8", "title follows next calculation")
    },

    // MARK: 4. Display/copy contract

    EngineCase("r51-text-scalar-default-vs-override") {
        try expectEqual(AnswerDisplay.text(for: .number(value: 1.0 / 3.0, unit: nil),
                                           decimalPlaces: 2),
                        "0.33", "default decimals")
        try expectEqual(AnswerDisplay.text(for: .number(value: 1.0 / 3.0, unit: nil),
                                           decimalPlaces: 5),
                        "0.33333", "override decimals")
    },

    EngineCase("r51-zero-decimals-keeps-whole-value") {
        // r51: the %.0f path must not trim the value itself away.
        try expectEqual(formatDisplayValue(1.0 / 3.0, decimalPlaces: 0), "0",
                        "0.33 at 0 decimals is 0")
        try expectEqual(formatDisplayValue(2.5, decimalPlaces: 0), "2",
                        "2.5 at 0 decimals is 2")
        try expectEqual(formatDisplayValue(2.5, decimalPlaces: 2), "2.5",
                        "fractional trim unchanged")
        try expectEqual(AnswerDisplay.text(for: .number(value: 1.0 / 3.0, unit: nil),
                                           decimalPlaces: 0),
                        "0", "copy text at 0 decimals")
    },

    EngineCase("r51-text-variable-uses-override") {
        try expectEqual(AnswerDisplay.text(for: .variable(name: "x", value: 10.0 / 4.0),
                                           decimalPlaces: 1),
                        "2.5", "variable value at override")
    },

    EngineCase("r51-text-unit-quantity") {
        try expectEqual(AnswerDisplay.text(for: .number(value: 2, unit: "km"),
                                           decimalPlaces: 2),
                        "2 km", "value plus unit label")
    },

    EngineCase("r51-text-currency-and-money-fixed") {
        try expectEqual(AnswerDisplay.text(for: .number(value: 600, unit: "USD"),
                                           decimalPlaces: 7),
                        formatMoney(600, code: "USD"), "currency takes money path")
        try expectEqual(AnswerDisplay.text(for: .money(value: 600, code: "USD"),
                                           decimalPlaces: 0),
                        "$600.00", "money ignores decimal override")
    },

    EngineCase("r51-text-date-broken-rates") {
        try expectEqual(AnswerDisplay.text(
            for: .date(year: 2026, month: 6, day: 17, showYear: false),
            decimalPlaces: 2), "Jun 17", "compact date")
        try expectEqual(AnswerDisplay.text(for: .brokenToken(line: 4), decimalPlaces: 2),
                        "Line 4", "broken token label")
        try expectEqual(AnswerDisplay.text(for: .error(message: "Rates unavailable"),
                                           decimalPlaces: 2),
                        "Rates unavailable", "rates state copies verbatim")
    },

    EngineCase("r51-text-hidden-rows-nil") {
        for r in [LineResult.blank, .skip, .title("H"),
                  .error(message: "division by zero")] as [LineResult] {
            try expectEqual(AnswerDisplay.text(for: r, decimalPlaces: 2), nil,
                            "hidden row has no copy text: \(r)")
        }
    },

    EngineCase("r51-menu-eligibility") {
        try expectEqual(AnswerDisplay.menu(for: .number(value: 1, unit: nil)),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: true),
                        "scalar offers rounding")
        try expectEqual(AnswerDisplay.menu(for: .variable(name: "x", value: 1)),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: true),
                        "variable offers rounding")
        try expectEqual(AnswerDisplay.menu(for: .number(value: 1, unit: "km")),
                        AnswerDisplay.Menu(showsActions: true, showsRounding: true),
                        "unit quantity offers rounding")
        for r in [LineResult.number(value: 1, unit: "USD"),
                  .money(value: 1, code: "USD"),
                  .date(year: 2026, month: 6, day: 17, showYear: false),
                  .brokenToken(line: 2),
                  .error(message: "Rates unavailable")] as [LineResult] {
            try expectEqual(AnswerDisplay.menu(for: r),
                            AnswerDisplay.Menu(showsActions: true, showsRounding: false),
                            "copy/delete but no rounding: \(r)")
        }
        for r in [LineResult.blank, .skip, .title("H"),
                  .error(message: "division by zero")] as [LineResult] {
            try expectEqual(AnswerDisplay.menu(for: r), nil, "no menu: \(r)")
        }
    },

    EngineCase("r51-rendered-rows-match-copy-text") {
        // The same effective-decimals input feeds both the row string
        // and Copy Answer, so they cannot drift. An override above the
        // global shows the AVAILABLE engine-rounded value (no phantom
        // precision); an override below it trims.
        let rows = r51Results("1 / 3\nx = 10 / 4", decimalPlaces: 2)
        try expectEqual(AnswerDisplay.text(for: rows[0], decimalPlaces: 4), "0.33",
                        "no phantom precision above engine rounding")
        try expectEqual(AnswerDisplay.text(for: rows[1], decimalPlaces: 2), "2.5",
                        "assignment value only")
        let wide = r51Results("1 / 3", decimalPlaces: 6)
        try expectEqual(AnswerDisplay.text(for: wide[0], decimalPlaces: 2), "0.33",
                        "override trims engine value")
        try expectEqual(AnswerDisplay.text(for: wide[0], decimalPlaces: 6), "0.333333",
                        "override shows available precision")
    },

    // MARK: 5. Localization

    EngineCase("r51-l10n-answer-menu-keys") {
        for lang in AppLanguage.allCases {
            for key in ["copyAnswer", "deleteLine", "rounding", "roundingDefault"] {
                let v = L10n.t(key, language: lang)
                try expect(!v.isEmpty && v != key, "key \(key) translated", "\(lang)")
            }
        }
        try expectEqual(L10n.t("copyAnswer", language: .ru), "Копировать ответ", "ru copy")
        try expectEqual(L10n.t("deleteLine", language: .ru), "Удалить строку", "ru delete")
        try expectEqual(L10n.t("rounding", language: .ru), "Округление", "ru rounding")
        try expectEqual(L10n.t("roundingDefault", language: .ru), "По умолчанию", "ru default")
    },

    // MARK: 6. Interaction regressions

    EngineCase("r51-double-click-pair-semantics") {
        for n in [1, 2, 3, 4, 5, 6] {
            try expectEqual(AnswerDoubleClick.completesPair(at: n), n % 2 == 0,
                            "clickCount \(n)")
        }
    },
]
