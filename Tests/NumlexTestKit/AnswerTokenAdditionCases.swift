import Foundation
import NumlexCore

/// A newly added linked value is one live marker. The planner receives
/// the destination's already-resolved typed result; context-free callers
/// intentionally retain the legacy marker-only insertion.
private let additionM = String(answerTokenMarker)

private func additionIDs(_ count: Int) -> [UUID] {
    (0..<count).map { _ in UUID() }
}

private func additionResolve(_ content: String,
                             ids: [UUID],
                             refs: [AnswerReference] = [],
                             context: NumberFormatContext = .legacy) -> (lines: [SheetLine], tokens: [TokenResolution]) {
    resolveSheet(content: content, lineIDs: ids, references: refs,
                 rates: Rates(), decimalPlaces: 10, context: context)
}

private func additionPlan(_ content: String,
                          ids: [UUID],
                          refs: [AnswerReference] = [],
                          source: Int = 0,
                          caret: Int,
                          length: Int = 0,
                          result: LineResult? = .number(value: 1200),
                          padded: Bool = true) -> AnswerTokenInsertion.Plan? {
    AnswerTokenInsertion.plan(
        content: content, lineIDs: ids, references: refs,
        sourceLineIndex: source,
        selection: NSRange(location: caret, length: length),
        destinationResult: result,
        padOperators: padded)
}

private func additionNumber(_ line: SheetLine, equals expected: Double,
                            _ message: String) throws {
    guard case .number(let value, _, _, _) = line.result else {
        throw CaseFailure(message: "\(message): expected number, got \(line.result)",
                          location: "AnswerTokenAdditionCases")
    }
    try expectEqual(value, expected, message)
}

private func additionSource(_ relativePath: String) -> String? {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // NumlexTestKit
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
    return try? String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
}

private func additionSourceCount(_ needle: String, in source: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var remaining = source
    while let range = remaining.range(of: needle) {
        count += 1
        remaining = String(remaining[range.upperBound...])
    }
    return count
}

private func additionInsertTokenBody(in source: String) -> String? {
    guard let start = source.range(of: "    func insertToken(sourceLineIndex: Int, selection: NSRange?) {"),
          let end = source.range(of: "\n    // MARK: - Package 7: subtotal / grand-total commands",
                                range: start.lowerBound..<source.endIndex) else {
        return nil
    }
    return String(source[start.lowerBound..<end.lowerBound])
}

public let answerTokenAdditionCases: [EngineCase] = [
    EngineCase("linked-addition-appended-token-is-live-and-shifts-following-reference") {
        let content = "340\n1200\n" + additionM
        let ids = additionIDs(3)
        let oldID = UUID()
        let oldReference = AnswerReference(id: oldID, sourceLineID: ids[0],
                                           labelLine: 1, location: 9)
        let before = additionResolve(content, ids: ids, refs: [oldReference])
        try additionNumber(before.lines[0], equals: 340, "clicked source value")
        try additionNumber(before.lines[1], equals: 1200, "actual destination value")
        guard let plan = AnswerTokenInsertion.plan(
            content: content, lineIDs: ids, references: [oldReference],
            sourceLineIndex: 0,
            selection: NSRange(location: 8, length: 0),
            destinationResult: before.lines[1].result) else {
            throw CaseFailure(message: "expected context-aware plan", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(plan.content, "340\n1200 + " + additionM + "\n" + additionM,
                        "the completed value receives one padded live operand")
        try expectEqual(plan.lineIDs, ids, "same-line edit preserves every line identity")
        try expectEqual(plan.newReference.sourceLineID, ids[0], "new token links to clicked source ID")
        try expectEqual(plan.newReference.location, 11, "marker follows the three-unit padding prefix")
        try expectEqual(plan.caret, 12, "caret lands after the one-unit marker")
        try expectEqual(plan.references.count, 2, "old and new references both survive")
        try expect(plan.references.contains(where: { $0.id == oldID && $0.location == 13 }),
                   "the following reference shifts by the entire four-unit insertion")
        try expect(plan.references.contains(where: { $0.id == plan.newReference.id && $0.location == 11 }),
                   "the fresh sidecar owns the actual marker position")

        let added = additionResolve(plan.content, ids: plan.lineIDs, refs: plan.references)
        try additionNumber(added.lines[1], equals: 1540, "1200 + live 340 resolves to 1540")
        try additionNumber(added.lines[2], equals: 340, "following reference remains live")
        try expectEqual(added.tokens.count, 2, "both live markers resolve")

        let editedSource = (plan.content as NSString).replacingCharacters(
            in: NSRange(location: 0, length: 3), with: "500")
        let afterEdit = additionResolve(editedSource, ids: plan.lineIDs, refs: plan.references)
        try additionNumber(afterEdit.lines[1], equals: 1700, "source edit updates the sum without reinsertion")
        try additionNumber(afterEdit.lines[2], equals: 500, "unrelated following link also updates")
        try expectEqual(afterEdit.tokens.count, 2, "source edit preserves both sidecars")
    },

    EngineCase("linked-addition-existing-token-line-sums-repeated-live-values") {
        let content = "340\n" + additionM
        let ids = additionIDs(2)
        let prior = AnswerReference(sourceLineID: ids[0], labelLine: 1, location: 4)
        let resolved = additionResolve(content, ids: ids, refs: [prior])
        guard let plan = AnswerTokenInsertion.plan(
            content: content, lineIDs: ids, references: [prior], sourceLineIndex: 0,
            selection: NSRange(location: 5, length: 0),
            destinationResult: resolved.lines[1].result) else {
            throw CaseFailure(message: "expected repeated-token plan", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(plan.content, "340\n" + additionM + " + " + additionM,
                        "a completed live-token row appends a second operand")
        try expectEqual(plan.newReference.location, 8, "new token location includes padding")
        let summed = additionResolve(plan.content, ids: plan.lineIDs, refs: plan.references)
        try additionNumber(summed.lines[1], equals: 680, "340 + 340 evaluates through two live references")
        let changed = (plan.content as NSString).replacingCharacters(
            in: NSRange(location: 0, length: 3), with: "500")
        try additionNumber(additionResolve(changed, ids: plan.lineIDs, refs: plan.references).lines[1],
                           equals: 1000, "both repeated operands remain linked")
    },

    EngineCase("linked-addition-padding-respects-preference-and-horizontal-whitespace") {
        let ids = additionIDs(2)
        let withTail = "340\n1200 \t\u{00A0}"
        let tailCaret = (withTail as NSString).length
        guard let padded = additionPlan(withTail, ids: ids, caret: tailCaret) else {
            throw CaseFailure(message: "expected padded plan", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(padded.content, "340\n1200 \t\u{00A0}+ " + additionM,
                        "padding-on appends after and preserves existing horizontal whitespace")
        try expectEqual(padded.newReference.location, tailCaret + 2,
                        "existing whitespace selects the two-unit '+ ' prefix")

        let noPad = "340\n1200   "
        guard let unpadded = additionPlan(noPad, ids: ids,
                                          caret: (noPad as NSString).length, padded: false) else {
            throw CaseFailure(message: "expected no-padding plan", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(unpadded.content, "340\n1200   +" + additionM,
                        "padding-off adds only '+' and preserves pre-existing spaces")
        try expectEqual(unpadded.newReference.location, (noPad as NSString).length + 1,
                        "unpad marker offset includes one inserted unit")

        let caretBeforeTail = "340\n1200   "
        guard let beforeTail = additionPlan(caretBeforeTail, ids: ids, caret: 8) else {
            throw CaseFailure(message: "expected insertion before trailing spaces", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(beforeTail.content, "340\n1200 + " + additionM + "   ",
                        "prefix and marker are inserted at the caret; right suffix is unchanged")
        try expectEqual(beforeTail.newReference.location, 11, "marker follows actual three-unit prefix")
    },

    EngineCase("linked-addition-only-at-completed-end-of-different-line") {
        let ids = additionIDs(2)
        let text = "340\n1200"
        let start = additionPlan(text, ids: ids, caret: 4)
        try expectEqual(start?.content, "340\n" + additionM + "1200",
                        "line-start insertion stays marker-only")
        let middle = additionPlan(text, ids: ids, caret: 6)
        try expectEqual(middle?.content, "340\n12" + additionM + "00",
                        "mid-expression insertion stays marker-only")
        let selection = additionPlan(text, ids: ids, caret: 4, length: 4)
        try expectEqual(selection?.content, "340\n" + additionM,
                        "nonempty selection replacement never gains a plus")
        let blank = "340\n \t"
        try expectEqual(additionPlan(blank, ids: ids, caret: (blank as NSString).length)?.content,
                        "340\n \t" + additionM,
                        "indent-only line is not a completed expression")
        try expectEqual(additionPlan(text, ids: ids, caret: (text as NSString).length,
                                     result: nil)?.content,
                        text + additionM,
                        "context-free callers preserve legacy marker-only behavior")

        let sourceCaret = (text as NSString).length
        let sameLine = additionPlan(text, ids: ids, source: 1, caret: sourceCaret)
        try expectEqual(sameLine?.content, text + "\n" + additionM,
                        "same-line source branch remains its legacy separate-line plan")
    },

    EngineCase("linked-addition-pending-operators-are-never-duplicated") {
        let ids = additionIDs(2)
        let pending = ["+", "-", "−", "*", "×", "/", "÷", "^", "=", "<", ">",
                       "!", "&", "|", ",", ";", "(", "`"]
        for op in pending {
            let text = "340\n1200" + op + " \t"
            let p = additionPlan(text, ids: ids, caret: (text as NSString).length)
            try expectEqual(p?.content, text + additionM,
                            "pending operator '\(op)' remains verbatim without a duplicate plus")
        }
        let postfix = "340\n1200%"
        guard let percent = additionPlan(postfix, ids: ids, caret: (postfix as NSString).length) else {
            throw CaseFailure(message: "postfix-percent plan", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(percent.content, postfix + " + " + additionM,
                        "percent is a completed postfix operand, not a pending operator")
    },

    EngineCase("linked-addition-comment-tag-and-heading-contexts-stay-marker-only") {
        let ids = additionIDs(2)
        for text in ["340\n1200 #tag", "340\n# Heading 1200", "340\n1200 // note"] {
            let p = additionPlan(text, ids: ids, caret: (text as NSString).length)
            try expectEqual(p?.content, text + additionM,
                            "lexical comment/tag/heading context stays unchanged: \(text)")
        }
    },

    EngineCase("linked-addition-crlf-is-kept-whole") {
        let ids = additionIDs(2)
        let text = "340\r\n1200\r\n"
        guard let p = additionPlan(text, ids: ids, caret: 9) else {
            throw CaseFailure(message: "caret before CRLF terminator is valid", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(p.content, "340\r\n1200 + " + additionM + "\r\n",
                        "operator is inserted before the terminating CR; CRLF is preserved")
        try expectEqual(p.newReference.location, 12, "marker offset is UTF-16 accurate")
        try expect(AnswerTokenInsertion.plan(content: text, lineIDs: ids, references: [],
                                             sourceLineIndex: 0,
                                             selection: NSRange(location: 10, length: 0),
                                             destinationResult: .number(value: 1200)) == nil,
                   "caret between CR and LF remains rejected as a split Character")
    },

    EngineCase("linked-addition-eligible-contexts-are-typed-not-text-guessed") {
        let ids = additionIDs(2)
        let regional = NumberFormatContext(
            locale: Locale(identifier: "de_DE"), decimalSeparator: ",",
            groupingSeparator: ".", argumentSeparator: ";",
            displayGrouping: true, compactNotation: false,
            convertForeignOnPaste: true)
        let cases: [(content: String, expectedDestination: Double, expectedSum: Double,
                     context: NumberFormatContext)] = [
            ("340\n1200,0", 1200, 1540, regional)
        ]
        for c in cases {
            let before = additionResolve(c.content, ids: ids, context: c.context)
            try additionNumber(before.lines[1], equals: c.expectedDestination,
                               "typed destination is resolved by its number/unit context")
            let caret = (c.content as NSString).length
            guard let p = AnswerTokenInsertion.plan(
                content: c.content, lineIDs: ids, references: [], sourceLineIndex: 0,
                selection: NSRange(location: caret, length: 0),
                destinationResult: before.lines[1].result) else {
                throw CaseFailure(message: "typed-context plan", location: "AnswerTokenAdditionCases")
            }
            let after = additionResolve(p.content, ids: p.lineIDs,
                                        refs: p.references, context: c.context)
            try additionNumber(after.lines[1], equals: c.expectedSum,
                               "regional/unit expression sums the live source value for \(c.content)")
        }

        // A grouped regional spelling is classified from the actual
        // resolved result, not guessed from the raw `1.200` text. Keep the
        // asserted scope at planning: the feature does not reparse it.
        let grouped = "340\n1.200"
        let groupedIDs = additionIDs(2)
        let groupedBefore = additionResolve(grouped, ids: groupedIDs, context: regional)
        try additionNumber(groupedBefore.lines[1], equals: 1200,
                           "regional grouping produces a typed 1200 result")
        guard let groupedPlan = AnswerTokenInsertion.plan(
            content: grouped, lineIDs: groupedIDs, references: [], sourceLineIndex: 0,
            selection: NSRange(location: (grouped as NSString).length, length: 0),
            destinationResult: groupedBefore.lines[1].result) else {
            throw CaseFailure(message: "grouped regional plan", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(groupedPlan.content, grouped + " + " + additionM,
                        "regional grouping is preserved while the live operand is appended")

        let unit = "340\n1 km to m"
        let unitIDs = additionIDs(2)
        let unitBefore = additionResolve(unit, ids: unitIDs)
        try additionNumber(unitBefore.lines[1], equals: 1000,
                           "conversion result is an actual typed unit destination")
        guard let unitPlan = AnswerTokenInsertion.plan(
            content: unit, lineIDs: unitIDs, references: [], sourceLineIndex: 0,
            selection: NSRange(location: (unit as NSString).length, length: 0),
            destinationResult: unitBefore.lines[1].result) else {
            throw CaseFailure(message: "unit-context plan", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(unitPlan.content, unit + " + " + additionM,
                        "a resolved unit-bearing result receives the live operand without reformatting")

        let money = "$340\n$1200"
        let moneyIDs = additionIDs(2)
        let moneyBefore = additionResolve(money, ids: moneyIDs)
        guard let moneyPlan = AnswerTokenInsertion.plan(
            content: money, lineIDs: moneyIDs, references: [], sourceLineIndex: 0,
            selection: NSRange(location: (money as NSString).length, length: 0),
            destinationResult: moneyBefore.lines[1].result) else {
            throw CaseFailure(message: "money-context plan", location: "AnswerTokenAdditionCases")
        }
        let moneyAfter = additionResolve(moneyPlan.content, ids: moneyPlan.lineIDs,
                                         refs: moneyPlan.references)
        let amount: Double
        let code: String
        switch moneyAfter.lines[1].result {
        case .money(let value, let currency):
            amount = value
            code = currency
        case .number(let value, .some("USD"), _, _):
            // The existing evaluator exposes a compatible money sum as
            // a numeric USD quantity on this route; preserve that lane.
            amount = value
            code = "USD"
        default:
            throw CaseFailure(message: "money sum lost its USD type",
                              location: "AnswerTokenAdditionCases")
        }
        try expectEqual(amount, 1540, "money operands remain compatible")
        try expectEqual(code, "USD", "money currency identity is retained")

        let assignment = "340\nnet = 1200"
        let assignedIDs = additionIDs(2)
        let assignmentBefore = additionResolve(assignment, ids: assignedIDs)
        guard case .variable(_, let variableValue, _, _) = assignmentBefore.lines[1].result else {
            throw CaseFailure(message: "destination assignment must resolve to a variable", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(variableValue, 1200, "actual variable destination")
        guard let assignmentPlan = AnswerTokenInsertion.plan(
            content: assignment, lineIDs: assignedIDs, references: [], sourceLineIndex: 0,
            selection: NSRange(location: (assignment as NSString).length, length: 0),
            destinationResult: assignmentBefore.lines[1].result) else {
            throw CaseFailure(message: "variable-context plan", location: "AnswerTokenAdditionCases")
        }
        let assignmentAfter = additionResolve(assignmentPlan.content,
                                              ids: assignmentPlan.lineIDs,
                                              refs: assignmentPlan.references)
        guard case .variable(_, let sum, _, _) = assignmentAfter.lines[1].result else {
            throw CaseFailure(message: "variable result stays typed", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(sum, 1540, "a named numeric value is a valid destination")
    },

    EngineCase("linked-addition-ineligible-results-remain-marker-only") {
        let ids = additionIDs(2)
        let rejected: [LineResult] = [
            .boolean(value: true),
            .date(year: 2026, month: 1, day: 1, showYear: false),
            .location(name: "Paris", country: "France",
                      coordinate: GeoCoordinate(latitude: 48.8566, longitude: 2.3522)),
            .clock(hour: 12, minute: 0, second: 0, hasSeconds: false, dayOffset: 0),
            .dateTime(year: 2026, month: 1, day: 1, hour: 12, minute: 0,
                      second: 0, hasSeconds: false, utcOffsetSeconds: 0, iso: false),
            .timestamp(seconds: 1), .timecode(frames: 30, fps: 30),
            .frameCount(frames: 30), .brokenToken(line: 1), .error(message: "bad"),
            .number(value: 1, unit: nil, kind: .timecodeSeconds, fraction: nil),
            .number(value: .infinity, unit: nil, kind: .plain, fraction: nil),
            .variable(name: "x", value: .infinity, kind: .plain, fraction: nil),
            .money(value: .nan, code: "USD")
        ]
        let text = "340\n1200"
        for result in rejected {
            let p = additionPlan(text, ids: ids, caret: (text as NSString).length,
                                 result: result)
            try expectEqual(p?.content, text + additionM,
                            "ineligible typed result \(result) stays marker-only")
        }
        for eligible in [LineResult.variable(name: "x", value: 1200),
                         .number(value: 1.2, unit: "km"),
                         .variableInt(name: "x", value: 1200, radix: 10),
                         .integer(value: 1200, radix: 10)] {
            guard let p = additionPlan(text, ids: ids, caret: (text as NSString).length,
                                       result: eligible, padded: false) else {
                throw CaseFailure(message: "finite variable/integer remains eligible", location: "AnswerTokenAdditionCases")
            }
            try expectEqual(p.content, text + "+" + additionM,
                            "answerable finite value adds a live operand")
        }
    },

    EngineCase("linked-addition-old-context-free-plans-stay-marker-only") {
        let text = "340\n1200"
        let ids = additionIDs(2)
        guard let legacy = AnswerTokenInsertion.plan(
            content: text, lineIDs: ids, references: [], sourceLineIndex: 0,
            selection: NSRange(location: (text as NSString).length, length: 0)) else {
            throw CaseFailure(message: "legacy plan remains available", location: "AnswerTokenAdditionCases")
        }
        try expectEqual(legacy.content, text + additionM,
                        "nil destination context preserves every old low-level caller")
        try expectEqual(legacy.newReference.location, (text as NSString).length,
                        "legacy marker starts exactly at the old caret")
        try expectEqual(legacy.caret, (text as NSString).length + 1,
                        "legacy caret remains one unit after marker")
    },

    EngineCase("linked-addition-appmodel-reuses-resolved-destination-and-preserves-guards") {
        guard let app = additionSource("Sources/NumlexApp/AppModel.swift"),
              let contentView = additionSource("Sources/NumlexApp/Views/ContentView.swift"),
              let editor = additionSource("Sources/NumlexApp/Editor/NotebookEditor.swift"),
              let deletionTests = additionSource("Tests/NumlexTestKit/DeletionCases.swift"),
              let body = additionInsertTokenBody(in: app) else {
            throw CaseFailure(message: "token insertion source-contract inputs missing",
                              location: "AnswerTokenAdditionCases")
        }
        try expectEqual(additionSourceCount("resolveSheet(", in: body), 1,
                        "AppModel reuses its one resolved input pass")
        try expect(body.contains("random: randomContext(for: sheet.id)"),
                   "the existing random context is preserved")
        try expect(body.contains("sourceIsDynamic = resolved.lines.indices.contains(sourceLineIndex)")
                   && body.contains("guard !sourceIsDynamic else {"),
                   "dynamic-source refusal remains before planning")
        try expect(body.contains("lineIndex(forCaret: selection.location, in: sheet.content)"),
                   "destination row comes from the actual UTF-16 caret")
        try expect(body.contains("resolved.lines.indices.contains(destinationLineIndex)")
                   && body.contains("!resolved.lines[destinationLineIndex].isTotal")
                   && body.contains("destinationResult = resolved.lines[destinationLineIndex].result")
                   && body.contains("destinationResult = nil"),
                   "invalid and special inline-total rows supply no auto-add context")
        guard let plannerStart = body.range(of: "AnswerTokenInsertion.plan("),
              let plannerEnd = body.range(of: "\n        ) else {",
                                       range: plannerStart.lowerBound..<body.endIndex) else {
            throw CaseFailure(message: "the single planner invocation is missing",
                              location: "AnswerTokenAdditionCases")
        }
        let planner = String(body[plannerStart.lowerBound..<plannerEnd.lowerBound])
        try expect(planner.contains("sourceLineIndex: sourceLineIndex")
                   && planner.contains("selection: selection")
                   && planner.contains("sourceIsDynamic: sourceIsDynamic")
                   && planner.contains("destinationResult: destinationResult")
                   && planner.contains("padOperators: settings.input.padOperators"),
                   "the existing selection, clicked source, typed result and padding preference reach the planner")
        try expectEqual(additionSourceCount("AnswerTokenInsertion.plan(", in: body), 1,
                        "the insertion still creates exactly one plan")
        try expectEqual(additionSourceCount("persist()", in: body), 1,
                        "one accepted insertion persists exactly once")
        try expectEqual(additionSourceCount("beginNewDynamicEpoch()", in: body), 1,
                        "the existing semantic-edit epoch advances exactly once")
        let mutationOrder = [
            "s.content = plan.content", "s.lineIDs = plan.lineIDs",
            "s.references = plan.references", "s.modifiedAt = Date()",
            "sheets[selectedIndex] = Sheet.retitled(s, content: plan.content",
            "beginNewDynamicEpoch()", "persist()", "focusSheetID = s.id",
            "focusCaret = plan.caret"
        ]
        var cursor = body.startIndex
        for marker in mutationOrder {
            guard let found = body.range(of: marker, range: cursor..<body.endIndex) else {
                throw CaseFailure(message: "insertion mutation/focus order changed at `\(marker)`",
                                  location: "AnswerTokenAdditionCases")
            }
            cursor = found.upperBound
        }
        try expect(contentView.contains("let snap = bridge?.selectionSnapshot(sheetID: sheetID)")
                   && contentView.contains("guard let range = snap else { return }")
                   && contentView.contains("model.insertToken(sourceLineIndex: lineIndex, selection: range)"),
                   "the live selection bridge and its sheet identity still gate dispatch")
        try expect(editor.contains("func selectionSnapshot(sheetID: Sheet.ID) -> NSRange?")
                   && editor.contains("guard self.sheetID == sheetID, textView.window != nil")
                   && editor.contains("if textView.hasMarkedText() { return nil }")
                   && editor.contains("sel.length <= len - sel.location"),
                   "the IME, sheet, window and UTF-16 range guards remain intact")
        try expect(deletionTests.contains("deletion-app-source-contracts-preserve-single-path-and-persist"),
                   "existing AppModel deletion source-contract coverage remains registered")
    },

    EngineCase("linked-addition-documentation-links-to-published-guides") {
        guard let readme = additionSource("README.md"),
              let contributor = additionSource("CONTRIBUTING.md") else {
            throw CaseFailure(message: "README or CONTRIBUTING.md missing",
                              location: "AnswerTokenAdditionCases")
        }
        try expect(readme.contains("https://www.numlex.tech/docs/linked-answers/")
                   && readme.contains("https://www.numlex.tech/docs/sheets-files/")
                   && readme.contains("https://www.numlex.tech/docs/styling-constants/"),
                   "README links directly to the published linked-answer, sheets and styling guides")
        try expect(readme.contains("Published manuals describe released behavior and may lag `main`")
                   && readme.contains("source code")
                   && readme.contains("tests define the behavior of the current branch."),
                   "README distinguishes current-main behavior from published manuals")
        try expect(contributor.contains("manuals are maintained on the [Numlex documentation site]")
                   && contributor.contains("may lag `main`")
                   && contributor.contains("current source and tests are authoritative."),
                   "contributor guidance keeps user manuals website-owned and source-backed")
    }
]
