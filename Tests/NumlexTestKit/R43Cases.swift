import Foundation
import NumlexCore

/// r43: answer-token insertion at the LIVE editor caret/selection.
/// The pure plan (AnswerTokenInsertion) pins the whole contract:
/// collapsed caret inserts, non-empty selection is REPLACED (never
/// appended on a new line), the source identity is the CLICKED line's
/// stable ID, existing references are preserved/shifted like a normal
/// edit, and every invalid or stale request is a deterministic no-op.

/// One UTF-16 marker unit, and a fresh-ID helper (file scope so the
/// @Sendable case closures may use them).
private let r43M = "\u{FFFC}"
private func r43Ids(_ n: Int) -> [UUID] { (0..<n).map { _ in UUID() } }

public let r43Cases: [EngineCase] = [
    EngineCase("r43-caret-start-middle-end") {
        // "7" / "x = 3" / "2 * x": carets at the start, after "7", at
        // line 2's start, and at the document end. Each inserts exactly
        // one marker at the caret; no newline is ever added.
        let content = "7\nx = 3\n2 * x"
        let lineIDs = r43Ids(3)
        let cases: [(pos: Int, source: Int, expectContent: String)] = [
            (0, 0, r43M + "7\nx = 3\n2 * x"),         // start of line 1
            (1, 0, "7" + r43M + "\nx = 3\n2 * x"),    // end of line 1
            (2, 1, "7\n" + r43M + "x = 3\n2 * x"),    // start of line 2
            ((content as NSString).length, 2, content + r43M) // doc end
        ]
        for c in cases {
            guard let p = AnswerTokenInsertion.plan(
                content: content, lineIDs: lineIDs, references: [],
                sourceLineIndex: c.source,
                selection: NSRange(location: c.pos, length: 0)) else {
                throw CaseFailure(message: "caret \(c.pos): expected a plan")
            }
            try expectEqual(p.content, c.expectContent,
                            "caret \(c.pos): exact replacement, no append/newline")
            try expectEqual(p.caret, c.pos + 1, "caret \(c.pos): caret lands after the marker")
            try expectEqual(p.lineIDs, lineIDs, "caret \(c.pos): line IDs untouched")
            try expect(p.references.count == 1 && p.references[0].location == c.pos,
                       "caret \(c.pos): exactly one reference at the marker")
            try expectEqual(p.newReference.sourceLineID, lineIDs[c.source],
                            "caret \(c.pos): source = clicked line")
            try expectEqual(p.newReference.labelLine, c.source + 1,
                            "caret \(c.pos): label = 1-based clicked line")
        }
    },

    EngineCase("r43-source-is-clicked-line-not-caret-line") {
        // The caret sits on line 3 but the CLICKED answer belongs to
        // line 1: the token's source is line 1's stable ID, while the
        // marker lands physically at the caret.
        let content = "12\nx = 4\n2 * x"
        let lineIDs = r43Ids(3)
        guard let p = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: (content as NSString).length, length: 0)) else {
            throw CaseFailure(message: "expected a plan")
        }
        try expectEqual(p.newReference.sourceLineID, lineIDs[0], "source is the clicked line")
        try expectEqual(p.newReference.labelLine, 1, "label is the clicked line's number")
        try expectEqual(p.newReference.location, (content as NSString).length,
                        "marker lands at the caret, not at the source")
        // And it RESOLVES: the token shows line 1's current value.
        let resolved = resolveSheet(
            content: p.content, lineIDs: p.lineIDs, references: p.references,
            rates: Rates(), decimalPlaces: 2)
        try expect(resolved.tokens.count == 1, "one token renders")
        var activeValue: Double? = nil
        if let t = resolved.tokens.first, case .active(let v, _, _) = t.state {
            activeValue = v
        }
        try expect(activeValue == 12.0,
                   "the fresh token resolves to the clicked line's current value (12)")
    },

    EngineCase("r43-emoji-utf16-boundaries") {
        // "a😀b" is 4 UTF-16 units (a@0, pair@1…3, b@3): the Character
        // boundaries are 0, 1, 3, 4. Carets before (1) and after (3)
        // the pair are valid; a caret INSIDE the pair (2) splits a
        // surrogate pair and must be a no-op. Whole-emoji selection
        // replaces; half-emoji selection is a no-op.
        let content = "a😀b"
        let lineIDs = r43Ids(1)
        guard let before = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 1, length: 0)) else {
            throw CaseFailure(message: "caret before the emoji must be valid")
        }
        try expectEqual(before.content, "a" + r43M + "😀b", "marker inserted before the pair")
        guard let after = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 3, length: 0)) else {
            throw CaseFailure(message: "caret after the emoji must be valid")
        }
        try expectEqual(after.content, "a😀" + r43M + "b", "marker inserted after the pair (before b)")
        try expect(AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 2, length: 0)) == nil,
            "caret mid-surrogate-pair is a no-op")
        guard let whole = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 1, length: 2)) else {
            throw CaseFailure(message: "whole-emoji selection must be valid")
        }
        try expectEqual(whole.content, "a" + r43M + "b", "emoji replaced by one marker")
        try expectEqual(whole.caret, 2, "caret after the replacement")
        try expect(AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 2, length: 1)) == nil,
            "half-emoji (one surrogate) selection is a no-op")
        try expect(AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 0, length: 2)) == nil,
            "selection ending mid-pair is a no-op")
    },

    EngineCase("r43-combining-mark-boundaries") {
        // "e◌́a" (e + U+0301 + a): the grapheme boundaries are 0, 2, 3.
        // A caret at 1 splits the combining sequence (no-op); carets at
        // 2 and 3 are valid; the whole grapheme (0..2) is a valid
        // selection, a lone combining mark is not.
        let content = "e\u{301}a"
        let lineIDs = r43Ids(1)
        try expect(AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 1, length: 0)) == nil,
            "caret between base and combining mark is a no-op")
        guard let p2 = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 2, length: 0)) else {
            throw CaseFailure(message: "caret after the grapheme must be valid")
        }
        try expectEqual(p2.content, "e\u{301}" + r43M + "a", "marker after the whole grapheme")
        guard let whole = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 0, length: 2)) else {
            throw CaseFailure(message: "whole-grapheme selection must be valid")
        }
        try expectEqual(whole.content, r43M + "a", "grapheme replaced by one marker")
        try expect(AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 1, length: 1)) == nil,
            "lone combining mark selection is a no-op")
    },

    EngineCase("r43-selection-replacement") {
        // Selecting "12.5" on line 1 and double-tapping line 2's answer
        // REPLACES the selection with one marker on line 1 — the source
        // stays the clicked (line 2) line. Exactly one marker results.
        let content = "price = 12.5\ntax = 20%"
        let lineIDs = r43Ids(2)
        guard let p = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 1,
            selection: NSRange(location: 8, length: 4)) else {
            throw CaseFailure(message: "expected a plan")
        }
        try expectEqual(p.content, "price = " + r43M + "\ntax = 20%",
                        "selection replaced in place, other line untouched")
        try expectEqual(p.caret, 9, "caret right after the replacement")
        try expectEqual(p.newReference.sourceLineID, lineIDs[1],
                        "source = the clicked answer's line")
        try expectEqual((p.content as NSString).length, 19, "no newline added by the replacement")
        try expectEqual(p.content.filter { $0 == "\u{FFFC}" }.count, 1, "exactly one marker")
        // A full-line selection replaces the whole line (its ID survives
        // the in-place replacement — the line is not split or dropped).
        guard let full = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 0, length: 12)) else {
            throw CaseFailure(message: "full-line selection expected a plan")
        }
        try expectEqual(full.content, r43M + "\ntax = 20%", "whole line replaced by one marker")
        try expectEqual(full.lineIDs[0], lineIDs[0], "replaced line keeps its ID")
    },

    EngineCase("r43-existing-reference-before") {
        // A pre-existing token on line 1 BEFORE the caret stays at its
        // exact position; the fresh token is added after it.
        // "￼1 / 5 / 3": the token (M) is at 0, "5" is at 3 — the caret
        // AFTER "5" is 4.
        let content = r43M + "1\n5\n3"
        let lineIDs = r43Ids(3)
        let refA = AnswerReference(sourceLineID: lineIDs[0], labelLine: 1, location: 0)
        guard let p = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [refA],
            sourceLineIndex: 1,
            selection: NSRange(location: 4, length: 0)) else {
            throw CaseFailure(message: "expected a plan")
        }
        try expectEqual(p.content, r43M + "1\n5" + r43M + "\n3", "both markers present")
        let at0 = p.references.filter { $0.location == 0 }.map { $0.id }
        try expect(at0 == [refA.id], "the earlier reference keeps its exact position")
        try expect(p.references.contains { $0.id == p.newReference.id && $0.location == 4 },
                   "fresh token at the caret (after \"5\")")
        try expectEqual(p.references.count, 2, "old + fresh reference")
    },

    EngineCase("r43-existing-reference-after-shifts") {
        // A token AFTER a replaced selection shifts by (1 - selection
        // length) — exactly like a normal typed replacement.
        let content = "\nabc" + r43M   // line 2 = "abc" + token
        let lineIDs = r43Ids(2)
        let refB = AnswerReference(sourceLineID: lineIDs[1], labelLine: 2, location: 4)
        // Replace ONE char before the old token: it shifts by (1-1) = 0.
        guard let p = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [refB],
            sourceLineIndex: 0,
            selection: NSRange(location: 2, length: 1)) else {
            throw CaseFailure(message: "expected a plan")
        }
        try expectEqual(p.content, "\na" + r43M + "c" + r43M,
                        "replaced char, old token shifted by (1-1) = 0")
        try expect(p.references.contains { $0.id == refB.id && $0.location == 4 },
                   "after-reference still on its marker")
        try expect(p.references.contains { $0.id == p.newReference.id && $0.location == 2 },
                   "fresh token at the replacement start")
        // A LONGER replacement shifts the after-reference by (1-2) = -1.
        guard let p2 = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [refB],
            sourceLineIndex: 0,
            selection: NSRange(location: 1, length: 2)) else {
            throw CaseFailure(message: "expected a plan (ab replaced)")
        }
        try expectEqual(p2.content, "\n" + r43M + "c" + r43M,
                        "ab replaced, old token shifted by (1-2) = -1")
        try expect(p2.references.contains { $0.id == refB.id && $0.location == 3 },
                   "after-reference at the shifted position")
    },

    EngineCase("r43-covered-token-takes-fresh-identity") {
        // The selection covers an existing token. One marker survives:
        // it belongs to the FRESH reference (the clicked source); the
        // displaced old reference is dropped — a single marker never
        // carries two references.
        let content = "\na" + r43M + "b"
        let lineIDs = r43Ids(2)
        let refB = AnswerReference(sourceLineID: lineIDs[1], labelLine: 2, location: 2)
        guard let p = AnswerTokenInsertion.plan(
            content: content, lineIDs: lineIDs, references: [refB],
            sourceLineIndex: 0,
            selection: NSRange(location: 1, length: 3)) else {
            throw CaseFailure(message: "expected a plan")
        }
        try expectEqual(p.content, "\n" + r43M, "one marker remains")
        try expectEqual(p.references.count, 1, "the displaced old reference is dropped")
        try expect(p.references[0].id == p.newReference.id, "the survivor is the fresh token")
        try expectEqual(p.references[0].sourceLineID, lineIDs[0], "it points at the clicked line")
    },

    EngineCase("r43-newline-spanning-selection-noop") {
        // A selection that crosses a newline would MERGE logical lines
        // — a destructive restructure for a double-click. No-op.
        let content = "1+1\n2+2"
        let lineIDs = r43Ids(2)
        for sel in [NSRange(location: 0, length: 4), NSRange(location: 2, length: 3),
                    NSRange(location: 1, length: 4)] {
            try expect(AnswerTokenInsertion.plan(
                content: content, lineIDs: lineIDs, references: [],
                sourceLineIndex: 0, selection: sel) == nil,
                "newline-spanning selection \(sel.location)+\(sel.length) is a no-op")
        }
    },

    EngineCase("r43-invalid-ranges-noop") {
        // Out-of-bounds, negative, or overflowing ranges are no-ops;
        // a caret exactly at the document end is valid.
        let content = "abc"
        let lineIDs = r43Ids(1)
        func plan(_ loc: Int, _ len: Int) -> AnswerTokenInsertion.Plan? {
            AnswerTokenInsertion.plan(
                content: content, lineIDs: lineIDs, references: [],
                sourceLineIndex: 0,
                selection: NSRange(location: loc, length: len))
        }
        try expect(plan(4, 0) == nil, "caret past the end is a no-op")
        try expect(plan(2, 3) == nil, "range overflowing the end is a no-op")
        try expect(plan(-1, 0) == nil, "negative location is a no-op")
        try expect(plan(0, -1) == nil, "negative length is a no-op")
        try expect(plan(3, 0) != nil, "caret exactly at the end is valid")
        // Stale/unknown SOURCE lines are no-ops too.
        for source in [-1, 1, 2, 99] {
            try expect(AnswerTokenInsertion.plan(
                content: content, lineIDs: lineIDs, references: [],
                sourceLineIndex: source,
                selection: NSRange(location: 0, length: 0)) == nil,
                "source line \(source) out of range is a no-op")
        }
    },

    EngineCase("r43-empty-sheet-caret") {
        // A fresh empty sheet has ONE empty logical line: minting at the
        // empty caret yields exactly the marker, nothing else.
        let lineIDs = r43Ids(1)
        guard let p = AnswerTokenInsertion.plan(
            content: "", lineIDs: lineIDs, references: [],
            sourceLineIndex: 0,
            selection: NSRange(location: 0, length: 0)) else {
            throw CaseFailure(message: "empty-sheet insertion expected a plan")
        }
        try expectEqual(p.content, r43M, "just the marker")
        try expectEqual(p.caret, 1, "caret after the marker")
        try expectEqual(p.lineIDs.count, 1, "still one line")
        try expectEqual(p.lineIDs, lineIDs, "the empty line keeps its ID")
    },

    EngineCase("r43-line-identity-and-sanitize-invariants") {
        // The marker never splits a line and the returned references are
        // always sanitized: every reference sits exactly on a marker of
        // the final content, and every marker has a reference.
        let content = "10\nx = 3\n2 * x\n4 + 5"
        let lineIDs = r43Ids(4)
        for pos in [0, 3, 9, (content as NSString).length] {
            guard let p = AnswerTokenInsertion.plan(
                content: content, lineIDs: lineIDs, references: [],
                sourceLineIndex: min(pos, 3),
                selection: NSRange(location: pos, length: 0)) else {
                throw CaseFailure(message: "pos \(pos): expected a plan")
            }
            try expectEqual(p.content.components(separatedBy: "\n").count, 4,
                            "pos \(pos): line count unchanged")
            try expectEqual(p.lineIDs, lineIDs, "pos \(pos): IDs identical")
            let ns = p.content as NSString
            for r in p.references {
                try expect(r.location < ns.length
                        && ns.character(at: r.location) == 0xFFFC,
                           "pos \(pos): every reference sits on a marker")
            }
            for i in 0..<ns.length where ns.character(at: i) == 0xFFFC {
                try expect(p.references.contains { $0.location == i },
                           "pos \(pos): every marker has a reference")
            }
        }
    },
]
