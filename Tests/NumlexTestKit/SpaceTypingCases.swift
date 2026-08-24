import Foundation
import NumlexCore

/// Focused coverage for the typed-space policy: whitespace-only user
/// edits must be preserved in the storage for the same edit (so a
/// conversion such as `5 m to cm` can be entered character by
/// character), while non-whitespace edits keep triggering the
/// canonical format pass and pure deletions keep never reformatting.
///
/// `applyEdit` mirrors `NotebookEditorCoordinator`'s pipeline
/// conceptually: the characters before the caret (a pure deletion
/// carries `deleting > 0` and an empty replacement) are replaced, then
/// the canonical pass runs exactly when `EditIntent` is `.content`,
/// with the caret remapped through the formatter's UTF-16 map.

private func applyEdit(_ doc: String, _ replacement: String,
                       caret: Int, deleting: Int = 0) throws -> (String, Int) {
    let joined = (doc as NSString).replacingCharacters(
        in: NSRange(location: caret - deleting, length: deleting),
        with: replacement)
    let caretInJoined = caret + (replacement as NSString).length
    guard EditIntent(replacement: replacement) == .content else {
        return (joined, caretInJoined)
    }
    let canonical = NotebookFormatting.canonicalDocument(joined)
    let map = NotebookFormatting.mapDocument(from: joined, to: canonical)
    return (canonical, map[caretInJoined])
}

private func evalOne(_ line: String) throws -> (Double, String?) {
    var v: [String: Double] = [:]
    guard case .number(let value, let unit)? = evalLine(line,
                                                       variables: &v,
                                                       rates: Rates(),
                                                       decimalPlaces: 7)
    else {
        throw CaseFailure(message: "line must evaluate: \(line)",
                          location: "SpaceTypingCases")
    }
    return (value, unit)
}

public let spaceTypingCases: [EngineCase] = [
    EngineCase("space-intent-policy") {
        try expectEqual(EditIntent(replacement: nil), .none, "nil replacement")
        try expectEqual(EditIntent(replacement: ""), .none, "empty replacement")
        try expectEqual(EditIntent(replacement: " "), .whitespace, "space")
        try expectEqual(EditIntent(replacement: "\t"), .whitespace, "tab")
        try expectEqual(EditIntent(replacement: "\n"), .whitespace, "newline")
        try expectEqual(EditIntent(replacement: " \t\n\r "),
                        .whitespace, "mixed typed whitespace")
        try expectEqual(EditIntent(replacement: "m"), .content, "letter")
        try expectEqual(EditIntent(replacement: "5m"), .content, "compact suffix")
        try expectEqual(EditIntent(replacement: "5 m"), .content, "spaced unit")
        try expectEqual(EditIntent(replacement: " to"), .content, "words")
        try expectEqual(EditIntent(replacement: "\u{00A0}"),
                        .content, "non-ASCII space is content")
    },

    EngineCase("space-typing-conversion-sequence") {
        // `5` -> `5 ` -> `5 m` -> `5 m ` -> `5 m to cm`, one user edit
        // at a time, exactly as the editor applies them.
        var (doc, caret) = try applyEdit("", "5", caret: 0)
        try expectEqual(doc, "5", "after 5")
        (doc, caret) = try applyEdit(doc, " ", caret: caret)
        try expectEqual(doc, "5 ", "typed space must survive the edit")
        try expectEqual(caret, 2, "caret right after the space")
        (doc, caret) = try applyEdit(doc, "m", caret: caret)
        try expectEqual(doc, "5 m", "spaced unit, not 5m")
        (doc, caret) = try applyEdit(doc, " ", caret: caret)
        try expectEqual(doc, "5 m ", "second typed space survives")
        (doc, caret) = try applyEdit(doc, "to cm", caret: caret)
        try expectEqual(doc, "5 m to cm", "complete conversion stored")
        let (value, unit) = try evalOne("5 m to cm")
        try expectEqual(value, 500.0, "5 m to cm value")
        try expectEqual(unit ?? "", "cm", "5 m to cm unit")
    },

    EngineCase("space-canonical-keeps-internal-spaces") {
        try expectEqual(NotebookFormatting.canonicalDocument("5 m to cm"),
                        "5 m to cm", "complete conversion untouched")
        try expectEqual(NotebookFormatting.canonicalDocument("5 m"),
                        "5 m", "intermediate `5 m` is a fixed point")
        try expectEqual(NotebookFormatting.canonicalDocument("10 km to meter\nx=5"),
                        "10 km to meter\nx = 5",
                        "math lines canonicalized, conversion kept")
    },

    EngineCase("space-compact-suffix-unchanged") {
        var (doc, caret) = try applyEdit("", "5", caret: 0)
        (doc, caret) = try applyEdit(doc, "m", caret: caret)
        try expectEqual(doc, "5m", "compact 5m is never split")
        let (fiveM, unitM) = try evalOne("5m")
        try expectEqual(fiveM, 5_000_000.0, "5m value")
        try expectEqual(unitM, nil, "5m has no unit")
        (doc, caret) = try applyEdit("", "2", caret: 0)
        (doc, caret) = try applyEdit(doc, ".", caret: caret)
        (doc, caret) = try applyEdit(doc, "5", caret: caret)
        (doc, caret) = try applyEdit(doc, "k", caret: caret)
        try expectEqual(doc, "2.5k", "compact 2.5k is never split")
        let (twoPointFiveK, unitK) = try evalOne("2.5k")
        try expectEqual(twoPointFiveK, 2500.0, "2.5k value")
        try expectEqual(unitK, nil, "2.5k has no unit")
    },

    EngineCase("space-typing-operator-whitespace") {
        var (doc, caret) = try applyEdit("", "7", caret: 0)
        (doc, caret) = try applyEdit(doc, "+", caret: caret)
        try expectEqual(doc, "7 +", "operator canonicalized on content edit")
        (doc, caret) = try applyEdit(doc, " ", caret: caret)
        try expectEqual(doc, "7 + ", "typed space after operator survives")
        (doc, caret) = try applyEdit(doc, "3", caret: caret)
        try expectEqual(doc, "7 + 3", "next non-whitespace keeps canonical form")
        let (value, _) = try evalOne("7 + 3")
        try expectEqual(value, 10.0, "7 + 3 value")
    },

    EngineCase("space-multiline-paste-formats") {
        let (doc, caret) = try applyEdit("", "a=5\nb+3", caret: 0)
        try expectEqual(doc, "a = 5\nb + 3", "multiline paste still formats")
        try expectEqual(caret, (doc as NSString).length, "caret at paste end")
    },

    EngineCase("space-pure-deletion-unformatted") {
        // Backspace (nil replacement) deletes the space but must not
        // reformat: canonicalDocument would re-insert it.
        let (doc, _) = try applyEdit("7 + 3", "", caret: 4, deleting: 1)
        try expectEqual(doc, "7 +3", "deletion leaves the text as-is")
        try expectEqual(EditIntent(replacement: ""), .none, "deletion intent")
    },

    EngineCase("space-caret-map-utf16") {
        let map = NotebookFormatting.mapDocument(from: "5m +2", to: "5m + 2")
        let from = ("5m +2" as NSString).length
        let to = ("5m + 2" as NSString).length
        try expectEqual(map.count, from + 1, "map size")
        try expectEqual(map[0], 0, "map start")
        try expectEqual(map.last ?? -1, to, "map end")
        try expectEqual(map[2], 2, "caret after 5m stays put")
        try expectEqual(map[4], 4, "caret before 2 shifts over inserted space")
        // The map is monotonic and pins every insertion point that sits
        // right after a non-space character (points inside a space run
        // collapse to that point, which is the formatter's contract).
        let pinned = NotebookFormatting.mapDocument(from: "5 m to cm",
                                                    to: "5 m to cm")
        for p in 1..<pinned.count {
            try expect(pinned[p - 1] <= pinned[p], "map monotonic at \(p)")
        }
        for p in [1, 3, 5, 6, 9] {
            try expectEqual(pinned[p], p, "post-core point pinned at \(p)")
        }
    },

    EngineCase("space-newline-preserves") {
        var (doc, caret) = try applyEdit("", "5 m to cm", caret: 0)
        try expectEqual(doc, "5 m to cm", "content paste of conversion")
        (doc, caret) = try applyEdit(doc, "\n", caret: caret)
        try expectEqual(doc, "5 m to cm\n", "typed newline survives")
        (doc, caret) = try applyEdit(doc, "2 + 2", caret: caret)
        try expectEqual(doc, "5 m to cm\n2 + 2", "new line canonicalized")
        var vars: [String: Double] = [:]
        let rows = evaluateSheet(doc, variables: &vars, rates: Rates(),
                                 decimalPlaces: 7)
        guard case .number(let v1, let u1) = rows[0].result,
              case .number(let v2, nil) = rows[1].result else {
            throw CaseFailure(message: "rows must evaluate",
                              location: "SpaceTypingCases")
        }
        try expectEqual(v1, 500.0, "line 1 value")
        try expectEqual(u1 ?? "", "cm", "line 1 unit")
        try expectEqual(v2, 4.0, "line 2 value")
    },
]
