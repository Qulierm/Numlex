import Foundation
import NumlexCore

/// Live answer reference tokens. Coverage:
/// 1. Marker invariant: exactly one U+FFFC, one UTF-16 unit.
/// 2. Line identity: stable per-line UUIDs survive edits above, marker
///    positions follow the announced edit, deleted sources break tokens.
/// 3. Reference-aware evaluation: bare tokens show the full quantity,
///    tokens are live operands with strict unit rules, `token to unit`,
///    broken/forward references never hang and never show stale values.
/// 4. Persistence: legacy sheets decode, export/import roundtrips.

private let M = "\u{FFFC}"

/// Apply an edit to the content the way AppKit would, then reconcile.
private func step(_ old: String,
                  edit: NotebookEdit?,
                  ids: [UUID],
                  refs: [AnswerReference]) throws -> (new: String, ids: [UUID], refs: [AnswerReference]) {
    var new = old
    if let edit, let range = edit.range {
        new = (old as NSString).replacingCharacters(in: range, with: edit.replacement)
    }
    let r = LineIdentity.reconcile(
        oldContent: old,
        oldLineIDs: ids,
        oldReferences: refs,
        newContent: new,
        edit: edit
    )
    return (new, r.lineIDs, r.references)
}

private func resolve(_ content: String,
                     ids: [UUID],
                     refs: [AnswerReference]) -> (lines: [SheetLine], tokens: [TokenResolution]) {
    resolveSheet(content: content, lineIDs: ids, references: refs,
                 rates: Rates(), decimalPlaces: 7)
}

public let answerReferenceCases: [EngineCase] = [
    // MARK: Marker invariant

    EngineCase("ref-marker-single-utf16-unit") {
        try expectEqual(answerTokenMarkerUTF16, 0xFFFC, "marker is U+FFFC")
        try expectEqual((String(answerTokenMarker) as NSString).length, 1, "exactly one UTF-16 unit")
        try expectEqual(answerTokenMarker.unicodeScalars.count, 1, "single scalar")
    },

    // MARK: Line identity / reconciliation

    EngineCase("ref-typing-above-keeps-token-linked") {
        let u0 = UUID(), u1 = UUID()
        let old = "5 km to m\n" + M
        var (new, ids, refs) = try step(old,
                                        edit: NotebookEdit(range: NSRange(location: 0, length: 0),
                                                           replacement: "2 + 2\n"),
                                        ids: [u0, u1],
                                        refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10)])
        try expectEqual(new, "2 + 2\n5 km to m\n" + M, "inserted line above")
        try expectEqual(ids.count, 3, "three logical lines")
        try expectEqual(ids[1], u0, "the source line kept its ID")
        try expectEqual(refs.count, 1, "token survived")
        try expectEqual(refs[0].sourceLineID, u0, "still points at the SAME line")
        try expectEqual(refs[0].location, 16, "marker offset followed the edit")
        // And the link really resolves after the shift.
        let (lines, tokens) = resolve(new, ids: ids, refs: refs)
        if case .number(let v, let u) = lines[2].result {
            try expectEqual(v, 5000, "live value after edits above")
            try expectEqual(u ?? "<none>", "m", "unit kept")
        } else {
            throw CaseFailure(message: "token line must stay live, got \(lines[2].result)",
                              location: "AnswerReferenceCases")
        }
        try expectEqual(tokens[0].state, .active(value: 5000, unit: "m", display: "5,000 m"),
                        "token resolution matches the shifted source")
    },

    EngineCase("ref-deleting-source-breaks-token") {
        let u0 = UUID(), u1 = UUID()
        let old = "5 km to m\n" + M
        let (new, ids, refs) = try step(old,
                                        edit: NotebookEdit(range: NSRange(location: 0, length: 10), replacement: ""),
                                        ids: [u0, u1],
                                        refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10)])
        try expectEqual(new, M, "only the marker line remains")
        try expectEqual(ids.count, 1, "one logical line")
        try expectEqual(refs.count, 1, "the token stays in place")
        // Its source line's ID is gone from the sheet: the token is
        // inactive and shows the remembered label.
        let (lines, tokens) = resolve(new, ids: ids, refs: refs)
        try expectEqual(lines[0].result, .brokenToken(line: 1), "broken with remembered Line 1")
        try expectEqual(tokens[0].state, .broken(line: 1), "inactive state")
    },

    EngineCase("ref-deleting-middle-line-keeps-link") {
        let u0 = UUID(), u1 = UUID(), u2 = UUID()
        let old = "5 km to m\nx = 1\n" + M
        let (new, ids, refs) = try step(old,
                                        edit: NotebookEdit(range: NSRange(location: 10, length: 6), replacement: ""),
                                        ids: [u0, u1, u2],
                                        refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 16)])
        try expectEqual(new, "5 km to m\n" + M, "middle line removed")
        try expectEqual(refs.count, 1, "token survived")
        try expectEqual(refs[0].sourceLineID, u0, "still the original source")
        try expectEqual(refs[0].location, 10, "marker offset remapped")
        try expectEqual(ids[1], u2, "token line kept its own ID")
        let (lines, _) = resolve(new, ids: ids, refs: refs)
        if case .number(let v, _) = lines[1].result {
            try expectEqual(v, 5000, "still live")
        } else {
            throw CaseFailure(message: "expected live number, got \(lines[1].result)",
                              location: "AnswerReferenceCases")
        }
    },

    EngineCase("ref-inserting-line-below-source-keeps-link") {
        let u0 = UUID(), u1 = UUID(), u2 = UUID()
        let old = "5 km to m\nx = 1\n" + M
        let (new, ids, refs) = try step(old,
                                        edit: NotebookEdit(range: NSRange(location: 10, length: 0),
                                                           replacement: "9 + 9\n"),
                                        ids: [u0, u1, u2],
                                        refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 16)])
        try expectEqual(new, "5 km to m\n9 + 9\nx = 1\n" + M, "line inserted between")
        try expectEqual(refs.count, 1, "token survived")
        try expectEqual(refs[0].sourceLineID, u0, "still the original source")
        try expectEqual(refs[0].location, 22, "marker offset remapped")
        try expectEqual(ids.count, 4, "four logical lines")
        let (lines, _) = resolve(new, ids: ids, refs: refs)
        if case .number(let v, let u) = lines[3].result {
            try expectEqual(v, 5000, "live across the insertion")
            try expectEqual(u ?? "<none>", "m", "unit kept")
        } else {
            throw CaseFailure(message: "expected live number, got \(lines[3].result)",
                              location: "AnswerReferenceCases")
        }
    },

    EngineCase("ref-backspace-merge-keeps-previous-line-id") {
        let u0 = UUID(), u1 = UUID()
        let old = "5 km to m\n" + M
        let (new, ids, refs) = try step(old,
                                        edit: NotebookEdit(range: NSRange(location: 9, length: 1), replacement: ""),
                                        ids: [u0, u1],
                                        refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10)])
        try expectEqual(new, "5 km to m" + M, "lines merged")
        try expectEqual(ids.count, 1, "one logical line")
        try expectEqual(ids[0], u0, "merged line keeps the PREVIOUS line's ID")
        try expectEqual(refs.count, 1, "marker survived the merge")
        try expectEqual(refs[0].location, 9, "marker offset remapped")
        // The token now references its own line: not strictly above →
        // inactive. The merged line is no longer a bare token line, so
        // the expression hides a generic error (never a stale value).
        let (lines, tokens) = resolve(new, ids: ids, refs: refs)
        try expectEqual(lines[0].result, .error(message: "Invalid reference"), "self reference hides a generic error")
        try expectEqual(tokens[0].state, .broken(line: 1), "inactive state, remembered label")
    },

    EngineCase("ref-editing-token-line-content-follows-marker") {
        let u0 = UUID(), u1 = UUID()
        let old = "x = 12\n" + M
        let (new, ids, refs) = try step(old,
                                        edit: NotebookEdit(range: NSRange(location: 7, length: 1),
                                                           replacement: "y = " + M),
                                        ids: [u0, u1],
                                        refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 7)])
        try expectEqual(new, "x = 12\ny = " + M, "marker pushed right")
        try expectEqual(refs.count, 1, "token survived the in-place replacement")
        try expectEqual(refs[0].location, 11, "marker offset remapped")
        let (lines, _) = resolve(new, ids: ids, refs: refs)
        if case .variable(let name, let v) = lines[1].result {
            try expectEqual(name, "y", "assignment variable")
            try expectEqual(v, 12, "assignment takes the live unitless value")
        } else {
            throw CaseFailure(message: "expected variable, got \(lines[1].result)",
                              location: "AnswerReferenceCases")
        }
    },

    EngineCase("ref-wholesale-replacement-drops-unprovable-markers") {
        let u0 = UUID(), u1 = UUID()
        let old = "5 km to m\n" + M
        let (ids, refs) = LineIdentity.reconcile(
            oldContent: old,
            oldLineIDs: [u0, u1],
            oldReferences: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10)],
            newContent: "7 + 7",
            edit: nil
        )
        let new = "7 + 7"
        try expectEqual(new, "7 + 7", "replaced content")
        try expectEqual(ids.count, 1, "fresh single line ID")
        try expectEqual(refs.count, 0, "marker cannot be proven to survive")
    },

    EngineCase("ref-sanitize-removes-dead-markers") {
        let content = "x = 11\n" + M
        let refs = [
            AnswerReference(sourceLineID: UUID(), labelLine: 1, location: 3), // not a marker
            AnswerReference(sourceLineID: UUID(), labelLine: 1, location: 7), // the marker
            AnswerReference(sourceLineID: UUID(), labelLine: 1, location: 99) // out of range
        ]
        let kept = Sheet.sanitizeReferences(refs, in: content)
        try expectEqual(kept.count, 1, "only the real marker survives")
        try expectEqual(kept[0].location, 7, "the surviving location")
        // And a sheet init sanitizes the same way.
        let sheet = Sheet(title: "S", content: content, references: refs)
        try expectEqual(sheet.references.count, 1, "sheet init sanitizes")
    },

    // MARK: Reference-aware evaluation

    EngineCase("ref-token-bare-shows-full-quantity") {
        let u0 = UUID(), u1 = UUID()
        let (lines, tokens) = resolve("5 km to m\n" + M,
                                      ids: [u0, u1],
                                      refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10)])
        try expectEqual(lines[1].result, .number(value: 5000, unit: "m"), "bare token = full quantity")
        try expectEqual(tokens.count, 1, "one token")
        try expectEqual(tokens[0].location, 10, "token location")
        try expectEqual(tokens[0].state, .active(value: 5000, unit: "m", display: "5,000 m"),
                        "live display text")
    },

    EngineCase("ref-token-as-operand-multiply") {
        let u0 = UUID(), u1 = UUID()
        let (lines, _) = resolve("5 km to m\n" + M + " * 2",
                                 ids: [u0, u1],
                                 refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10)])
        try expectEqual(lines[1].result, .number(value: 10000, unit: "m"), "token × scalar")
    },

    EngineCase("ref-token-same-unit-sum") {
        let u0 = UUID(), u1 = UUID()
        let (lines, _) = resolve("5 km to m\n" + M + " + " + M,
                                 ids: [u0, u1],
                                 refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10),
                                        AnswerReference(sourceLineID: u0, labelLine: 1, location: 14)])
        try expectEqual(lines[1].result, .number(value: 10000, unit: "m"), "same-unit addition")
    },

    EngineCase("ref-token-same-unit-division-ratio") {
        let u0 = UUID(), u1 = UUID()
        let (lines, _) = resolve("5 km to m\n" + M + " ÷ " + M,
                                 ids: [u0, u1],
                                 refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10),
                                        AnswerReference(sourceLineID: u0, labelLine: 1, location: 14)])
        try expectEqual(lines[1].result, .number(value: 1, unit: nil), "same-unit division is a ratio")
    },

    EngineCase("ref-token-incompatible-units-generic-error") {
        let u0 = UUID(), u1 = UUID()
        let (lines, _) = resolve("5 km to m\n3 s\n" + M + " + " + M,
                                 ids: [u0, u1, UUID()],
                                 refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 14),
                                        AnswerReference(sourceLineID: u1, labelLine: 2, location: 18)])
        if case .error = lines[2].result {
            // generic hidden error
        } else {
            throw CaseFailure(message: "incompatible units must be a generic error, got \(lines[2].result)",
                              location: "AnswerReferenceCases")
        }
    },

    EngineCase("ref-token-to-unit-conversion") {
        let u0 = UUID(), u1 = UUID()
        let (lines, _) = resolve("5 km to m\n" + M + " to cm",
                                 ids: [u0, u1],
                                 refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10)])
        try expectEqual(lines[1].result, .number(value: 500000, unit: "cm"), "token to cm")
    },

    EngineCase("ref-broken-token-remembers-label") {
        let u0 = UUID()
        let (lines, tokens) = resolve(M,
                                      ids: [u0],
                                      refs: [AnswerReference(sourceLineID: UUID(), labelLine: 3, location: 0)])
        try expectEqual(lines[0].result, .brokenToken(line: 3), "remembered Line N label")
        try expectEqual(tokens[0].state, .broken(line: 3), "inactive state")
    },

    EngineCase("ref-forward-reference-broken-no-hang") {
        let u0 = UUID(), u1 = UUID()
        let (lines, tokens) = resolve(M + "\n5 km to m",
                                      ids: [u0, u1],
                                      refs: [AnswerReference(sourceLineID: u1, labelLine: 2, location: 0)])
        try expectEqual(lines[0].result, .brokenToken(line: 2), "forward reference is broken")
        try expectEqual(tokens[0].state, .broken(line: 2), "inactive state")
        try expectEqual(lines[1].result, .number(value: 5000, unit: "m"), "source below still evaluates")
    },

    EngineCase("ref-chain-of-tokens-live") {
        let u0 = UUID(), u1 = UUID()
        // line0: 3 + 3 = 6, line1: 5 km to m, line2: <token(line1)> * <token(line0)>
        // document offsets: line2 starts at 6 + 10 = 16, markers at 16 and 20.
        let (lines, tokens) = resolve("3 + 3\n5 km to m\n" + M + " * " + M,
                                      ids: [u0, u1, UUID()],
                                      refs: [AnswerReference(sourceLineID: u1, labelLine: 2, location: 16),
                                             AnswerReference(sourceLineID: u0, labelLine: 1, location: 20)])
        try expectEqual(lines[2].result, .number(value: 30000, unit: "m"), "5,000 m × 6")
        try expectEqual(tokens.count, 2, "both tokens resolve")
        try expectEqual(tokens[0].state, .active(value: 5000, unit: "m", display: "5,000 m"), "quantity token")
        try expectEqual(tokens[1].state, .active(value: 6, unit: nil, display: "6"), "unitless token")
    },

    EngineCase("ref-broken-in-expression-hides-error") {
        let u0 = UUID(), u1 = UUID()
        let (lines, _) = resolve("5 km to m\n" + M + " * 2",
                                 ids: [u0, u1],
                                 refs: [AnswerReference(sourceLineID: UUID(), labelLine: 1, location: 10)])
        if case .error = lines[1].result {
            // generic hidden error — never a stale snapshot
        } else {
            throw CaseFailure(message: "broken token in expression must error, got \(lines[1].result)",
                              location: "AnswerReferenceCases")
        }
    },

    EngineCase("ref-source-error-breaks-token") {
        let u0 = UUID(), u1 = UUID()
        let (lines, _) = resolve("1 / 0\n" + M,
                                 ids: [u0, u1],
                                 refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 6)])
        try expectEqual(lines[1].result, .brokenToken(line: 1), "error source breaks the token")
    },

    EngineCase("ref-variable-source-is-unitless") {
        let u0 = UUID(), u1 = UUID()
        let (lines, tokens) = resolve("x = 12\n" + M + " * 2",
                                      ids: [u0, u1],
                                      refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 7)])
        try expectEqual(lines[1].result, .number(value: 24, unit: nil), "12 × 2 unitless")
        try expectEqual(tokens[0].state, .active(value: 12, unit: nil, display: "12"), "variable display")
    },

    EngineCase("ref-temperature-quantity-math") {
        let u0 = UUID(), u1 = UUID()
        // "30 C to F" is 9 chars + newline: markers at document 10 and 14.
        let (lines, _) = resolve("30 C to F\n" + M + " + " + M,
                                 ids: [u0, u1],
                                 refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 10),
                                        AnswerReference(sourceLineID: u0, labelLine: 1, location: 14)])
        try expectEqual(lines[1].result, .number(value: 172, unit: "F°"), "86 F° + 86 F°")
    },

    EngineCase("ref-legacy-evaluate-sheet-ignores-tokens") {
        var vars: [String: Double] = [:]
        let lines = evaluateSheet("5 km to m\n" + M, variables: &vars, rates: Rates(), decimalPlaces: 7)
        try expectEqual(lines[0].result, .number(value: 5000, unit: "m"), "conversion untouched")
        if case .skip = lines[1].result {
            // legacy evaluator understands no markers at all — it never
            // produces a value from one; resolveSheet is the only token path
        } else {
            throw CaseFailure(message: "legacy eval must not understand markers, got \(lines[1].result)",
                              location: "AnswerReferenceCases")
        }
    },

    // MARK: Persistence

    EngineCase("ref-legacy-sheet-decode-fallback") {
        let json = """
        {
            "id": "A1B2C3D4-E5F6-4A5B-8C7D-9E0F1A2B3C4D",
            "title": "Legacy",
            "content": "5 km to m\\nx = 1\\n",
            "createdAt": 0.0,
            "modifiedAt": 0.0
        }
        """
        let data = json.data(using: .utf8)!
        let sheet = try JSONDecoder().decode(Sheet.self, from: data)
        try expectEqual(sheet.content, "5 km to m\nx = 1\n", "content intact")
        try expectEqual(sheet.lineIDs.count, 3, "line IDs regenerated per logical line")
        try expectEqual(sheet.references.count, 0, "no references invented")
    },

    EngineCase("ref-sheet-export-roundtrip") {
        let u0 = UUID(), u1 = UUID()
        let content = "5 km to m\n" + M
        let ref = AnswerReference(sourceLineID: u0, labelLine: 1, location: 10)
        let export = SheetExport(title: "Tok", content: content, lineIDs: [u0, u1], references: [ref])
        let data = try JSONEncoder().encode(export)
        let back = try JSONDecoder().decode(SheetExport.self, from: data)
        try expectEqual(back.lineIDs ?? [], [u0, u1], "line IDs roundtrip")
        try expectEqual(back.references ?? [], [ref], "references roundtrip")
        // Decoding the export back into a live sheet keeps the link.
        let sheet = Sheet(title: back.title, content: back.content,
                          lineIDs: back.lineIDs ?? [], references: back.references ?? [])
        let (lines, tokens) = resolve(sheet.content, ids: sheet.lineIDs, refs: sheet.references)
        try expectEqual(lines[1].result, .number(value: 5000, unit: "m"), "imported token is live")
        try expectEqual(tokens[0].state, .active(value: 5000, unit: "m", display: "5,000 m"), "imported display")
    },

    EngineCase("ref-canonical-format-preserves-marker") {
        let content = "5 km to m\n" + M
        let canonical = Sheet.canonicalized(Sheet(title: "T", content: content)).sheet
        try expect(canonical.content.contains(M), "canonicalization keeps the marker")
        let loc = (canonical.content as NSString).range(of: M).location
        try expectEqual(loc, 10, "marker offset unchanged")
    },

    // MARK: Live-update regression (r14): same-line source edits

    EngineCase("ref-same-line-edit-preserves-uuid") {
        let u0 = UUID(), u1 = UUID()
        let old = "800 + 98\n" + M
        var (new, ids, refs) = try step(old,
                                        edit: NotebookEdit(range: NSRange(location: 0, length: 3),
                                                           replacement: "900"),
                                        ids: [u0, u1],
                                        refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 9)])
        try expectEqual(new, "900 + 98\n" + M, "same-length value swap")
        try expectEqual(ids[0], u0, "source line kept its UUID")
        try expectEqual(refs[0].sourceLineID, u0, "token still bound to it")
        try expectEqual(refs[0].location, 9, "marker offset unchanged (same line count)")
        let (lines, tokens) = resolve(new, ids: ids, refs: refs)
        try expectEqual(tokens[0].state, .active(value: 998, unit: nil, display: "998"),
                        "live value after the same-line edit")
        if case .number(let v, _) = lines[0].result {
            try expectEqual(v, 998, "source line evaluated")
        } else {
            throw CaseFailure(message: "expected 998, got \(lines[0].result)",
                              location: "AnswerReferenceCases")
        }
    },

    EngineCase("ref-same-line-length-change-preserves-uuid") {
        let u0 = UUID(), u1 = UUID()
        let old = "800 + 98\n" + M
        var (new, ids, refs) = try step(old,
                                        edit: NotebookEdit(range: NSRange(location: 3, length: 0),
                                                           replacement: "0"),
                                        ids: [u0, u1],
                                        refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 9)])
        try expectEqual(new, "8000 + 98\n" + M, "value grew by one digit")
        try expectEqual(ids[0], u0, "UUID stable on length change")
        try expectEqual(refs[0].location, 10, "marker followed the inserted digit")
        let (lines, tokens) = resolve(new, ids: ids, refs: refs)
        try expectEqual(tokens[0].state, .active(value: 8098, unit: nil, display: "8,098"),
                        "live value after growth")
        // Now the value shrinks again (raw edit, canonical keeps it).
        var (new2, ids2, refs2) = try step(new,
                                           edit: NotebookEdit(range: NSRange(location: 3, length: 1),
                                                              replacement: ""),
                                           ids: ids,
                                           refs: refs)
        try expectEqual(new2, "800 + 98\n" + M, "value shrank back")
        try expectEqual(ids2[0], u0, "UUID still the original one")
        try expectEqual(refs2[0].location, 9, "marker back to its original offset")
        let (lines2, tokens2) = resolve(new2, ids: ids2, refs: refs2)
        try expectEqual(tokens2[0].state, .active(value: 898, unit: nil, display: "898"),
                        "live value after shrink")
        _ = lines
    },

    EngineCase("ref-valid-invalid-valid-resolution") {
        let u0 = UUID(), u1 = UUID()
        var (new, ids, refs) = try step("800 + 98\n" + M,
                                        edit: NotebookEdit(range: NSRange(location: 6, length: 2),
                                                           replacement: ""),
                                        ids: [u0, u1],
                                        refs: [AnswerReference(sourceLineID: u0, labelLine: 1, location: 9)])
        try expectEqual(new, "800 + \n" + M, "dangling operator: source truly invalid")
        try expectEqual(ids.count, 2, "both lines still exist")
        var (lines, tokens) = resolve(new, ids: ids, refs: refs)
        try expectEqual(tokens[0].state, .broken(line: 1), "inactive while the source is invalid")
        // Type a valid number back in (after the pending operator space).
        let (new2, ids2, refs2) = try step(new,
                                           edit: NotebookEdit(range: NSRange(location: 6, length: 0),
                                                              replacement: "99"),
                                           ids: ids,
                                           refs: refs)
        try expectEqual(new2, "800 + 99\n" + M, "source valid again")
        try expectEqual(ids2[0], u0, "same source UUID all along")
        let (lines2, tokens2) = resolve(new2, ids: ids2, refs: refs2)
        try expectEqual(tokens2[0].state, .active(value: 899, unit: nil, display: "899"),
                        "immediately live once valid again — no stale snapshot")
        _ = (lines, lines2)
    },

    EngineCase("ref-state-change-detection-stability") {
        // Models the coordinator's statesChanged guard: a commit that
        // keeps the text identical but changes the token states must be
        // DETECTED (re-render), and an unchanged commit must compare
        // equal (no feedback loop).
        let u0 = UUID(), u1 = UUID()
        let old = "800 + 98\n" + M
        let refs = [AnswerReference(sourceLineID: u0, labelLine: 1, location: 9)]
        let (lines0, tokens0) = resolve(old, ids: [u0, u1], refs: refs)
        let (new, ids, refsNew) = try step(old,
                                           edit: NotebookEdit(range: NSRange(location: 0, length: 3),
                                                              replacement: "900"),
                                           ids: [u0, u1],
                                           refs: refs)
        let (lines1, tokens1) = resolve(new, ids: ids, refs: refsNew)
        _ = (lines0, lines1)
        try expect(tokens0 != tokens1, "edited source changes the token state (triggers re-render)")
        try expectEqual(refsNew[0].sourceLineID, u0, "reference stays bound while text churns")
        // Re-resolving the same state is stable: the next identical
        // SwiftUI commit must be a no-op.
        let (_, tokens1Again) = resolve(new, ids: ids, refs: refsNew)
        try expectEqual(tokens1Again, tokens1, "re-resolution is stable (no feedback loop)")
    }
]
