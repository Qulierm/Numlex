import Foundation
import NumlexCore

// MARK: - r80: Total-bar visibility + same-line answer insertion
//
// Two features, both additive on top of the r77c insertion chain:
//
// 1. `AppSettings.showTotalBar` (default ON = the pre-r80 layout) hides
//    ONLY the sheet's bottom Total panel under the answer column (and
//    its reserved space). Inline total lines keep evaluating/rendering.
//    Decode is per-key failure-proof like r60/r38 (missing or malformed
//    value -> true). StorePayload.version is NOT bumped.
//
// 2. A double-click whose caret (or contained selection) sits ON the
//    clicked source line no longer no-ops (r77c): the token is minted
//    on a NEW logical line immediately after the entire source line —
//    one extra newline, source and following lines preserved verbatim,
//    one pure NotebookEdit through LineIdentity.reconcile, caret right
//    after the marker. A second pair on the same answer then inserts at
//    that caret (a different line) without adding another line.

private let r80M = "\u{FFFC}"

/// Repo-root-relative source read, independent of the runner's cwd.
private func r80ReadSource(_ rel: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // NumlexTestKit
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // <root>
    let url = root.appendingPathComponent(rel)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        throw CaseFailure(message: "missing source file \(rel)")
    }
    return text
}

/// Deterministic line IDs for the insertion cases.
private func r80Ids(_ n: Int) -> [UUID] {
    (0..<n).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
}

/// The minimal AppSettings JSON: every key the custom decoder REQUIRES.
private func r80SettingsJSON(extra: String) -> String {
    """
    {"decimalPlaces":10,"fontSizeKey":"tf","language":"en",\
    "sheetName":"Sheet","lineNumbers":true,"fontColor":"white"\(extra)}
    """
}

/// Plans a same-line (or cross-line) token mint over explicit IDs.
private func r80Plan(_ content: String,
                     ids: [UUID],
                     refs: [AnswerReference] = [],
                     source: Int,
                     caret: Int,
                     length: Int = 0) -> AnswerTokenInsertion.Plan? {
    AnswerTokenInsertion.plan(
        content: content, lineIDs: ids, references: refs,
        sourceLineIndex: source,
        selection: NSRange(location: caret, length: length))
}

/// The sheet's evaluated lines (1:1 with logical lines).
private func r80Lines(_ content: String) -> [SheetLine] {
    var v: [String: Double] = [:]
    return evaluateSheet(content, variables: &v, rates: Rates(), decimalPlaces: 7)
}

public let r80Cases: [EngineCase] = [
    // MARK: showTotalBar — additive setting

    EngineCase("r80-totalbar-default-on") {
        try expectEqual(AppSettings.defaults.showTotalBar, true,
                        "static defaults keep the pre-r80 layout")
        try expectEqual(AppSettings().showTotalBar, true,
                        "memberwise init defaults ON")
    },

    EngineCase("r80-totalbar-decode-missing-key") {
        // Pre-r80 stores carry no key and must decode to ON, not fail.
        let s = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(r80SettingsJSON(extra: "").utf8))
        try expectEqual(s.showTotalBar, true,
                        "a legacy store decodes to the pre-r80 layout")
    },

    EngineCase("r80-totalbar-decode-true-and-false") {
        for (flag, json) in [(true, "true"), (false, "false")] {
            let s = try JSONDecoder().decode(
                AppSettings.self,
                from: Data(r80SettingsJSON(extra: "," + "\"showTotalBar\":\(json)").utf8))
            try expectEqual(s.showTotalBar, flag,
                            "persisted \(json) decodes \(flag)")
        }
    },

    EngineCase("r80-totalbar-decode-invalid-type") {
        // A malformed value (wrong JSON type) falls back to ON instead
        // of failing the whole store (r60/r38 convention).
        let s = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(r80SettingsJSON(extra: "," + "\"showTotalBar\":\"yes\"" ).utf8))
        try expectEqual(s.showTotalBar, true,
                        "wrong-type value falls back to the pre-r80 layout")
    },

    EngineCase("r80-totalbar-roundtrip") {
        // Encode -> decode preserves both states (the persist path the
        // Settings switch writes through).
        for flag in [true, false] {
            var s = AppSettings.defaults
            s.showTotalBar = flag
            let data = try JSONEncoder().encode(s)
            let back = try JSONDecoder().decode(AppSettings.self, from: data)
            try expectEqual(back.showTotalBar, flag,
                            "roundtrip preserves \(flag)")
        }
    },

    EngineCase("r80-totalbar-store-version-unchanged") {
        // Purely additive: no migration, no version bump.
        let persistence = try r80ReadSource("Sources/NumlexCore/Services/Persistence.swift")
        try expect(persistence.contains("version stays 2"),
                   "StorePayload version stays 2")
        try expect(!persistence.contains("version = 3"),
                   "no version-3 bump")
    },

    EngineCase("r80-totalbar-localized-six-languages") {
        for lang in AppLanguage.allCases {
            for key in ["showTotalBar", "showTotalBarCap"] {
                let t = L10n.t(key, language: lang)
                try expect(!t.isEmpty && t != key,
                           "\(lang.rawValue): \"\(key)\" is translated")
            }
        }
        try expectEqual(AppLanguage.allCases.count, 6, "the six supported languages")
    },

    EngineCase("r80-totalbar-settings-ui") {
        // The switch lives in General -> Notebook, bound through the
        // standard boolBinding (one write, one persist, live update).
        let settings = try r80ReadSource("Sources/NumlexApp/Views/SettingsView.swift")
        try expect(settings.contains("boolBinding(\\AppSettings.showTotalBar)"),
                   "General tab binds the Show Total bar switch")
        try expect(settings.contains(#"L10n.t("showTotalBar", language: language)"#),
                   "the switch title is localized")
        // The answer column consumes the flag; the wiring exists once.
        let view = try r80ReadSource("Sources/NumlexApp/Views/ContentView.swift")
        try expectEqual(view.components(separatedBy: "showTotalBar: settings.showTotalBar").count - 1,
                        1, "ContentView threads the flag into the answer column")
    },

    EngineCase("r80-totalbar-footer-gate-only") {
        // OFF removes ONLY the bottom panel + reserved space: the gate
        // is exactly one (the footer), and nothing else in the column —
        // notably the inline total lines' row rendering — references the
        // flag.
        let view = try r80ReadSource("Sources/NumlexApp/Views/AnswerColumnView.swift")
        let occurrences = view.components(separatedBy: "showTotalBar").count - 1
        // 1: the property, 2: the footer gate (the doc comment never
        // repeats the identifier).
        try expectEqual(occurrences, 2,
                        "the flag is consumed once (footer gate) + declared once")
        try expect(view.contains("if showTotalBar, let s = summary {"),
                   "the footer HStack (label + value + glass bar) is the only gated region")
        // No geometry animation on the toggle: the r62 hit surface
        // (ScrollWheelCatcher lockstep) must never chase an animated
        // frame, so the toggle snaps in a single layout pass.
        try expect(!view.contains("animation(.spring") &&
                   !view.contains(".animation(.default"),
                   "no view-level implicit animation in the answer column")
    },

    // MARK: same-line insertion — the marker goes to a NEW line below

    EngineCase("r80-same-line-single-line-caret-sweep") {
        // "7×8" (3 units, last line, no trailing newline): every caret
        // on the line mints "7×8\nM" — one newline at the document end.
        let content = "7×8"
        let ids = r80Ids(1)
        for caret in [0, 1, 2, 3] { // 3 = end-of-document on the line
            guard let p = r80Plan(content, ids: ids, source: 0, caret: caret) else {
                throw CaseFailure(message: "caret \(caret): same-line branch must plan")
            }
            try expectEqual(p.content, content + "\n" + r80M,
                            "caret \(caret): one newline + marker at EOF")
            try expectEqual(p.lineIDs.count, 2, "caret \(caret): exactly one new line")
            try expectEqual(p.lineIDs[0], ids[0],
                            "caret \(caret): the source line keeps its stable ID")
            try expect(p.lineIDs[1] != ids[0],
                       "caret \(caret): the marker line was minted a fresh ID")
            try expectEqual(p.newReference.sourceLineID, ids[0],
                            "caret \(caret): the token references the source line")
            try expectEqual(p.newReference.location, 4, "caret \(caret): marker at unit 4")
            try expectEqual(p.caret, 5, "caret \(caret): caret right after the marker")
            // The source line still ANSWERS (no self-cycle): 7×8 = 56.
            let lines = r80Lines(p.content)
            guard case .number(let v, let u) = lines[0].result, u == nil else {
                throw CaseFailure(message: "caret \(caret): source line lost its result")
            }
            try expectEqual(v, 56.0, "caret \(caret): the source line still evaluates 56")
        }
    },

    EngineCase("r80-same-line-middle-line-following-verbatim") {
        // "A\n7×8\nB": the marker line goes between the source and B;
        // B keeps its ID and shifts by the inserted length.
        // Line 3 carries a pre-existing token (unit 7) referencing it.
        let content = "A\n7×8\nB" + r80M
        let ids = r80Ids(3)
        let refs = [AnswerReference(sourceLineID: ids[2], labelLine: 3, location: 7)]
        guard let p = r80Plan(content, ids: ids, refs: refs, source: 1, caret: 4) else {
            throw CaseFailure(message: "middle-line same-line caret: expected a plan")
        }
        try expectEqual(p.content, "A\n7×8\n\(r80M)\nB" + r80M,
                        "the new line sits between source and the following line")
        try expectEqual(p.lineIDs[0], ids[0], "A keeps its ID")
        try expectEqual(p.lineIDs[1], ids[1], "the source line keeps its ID")
        try expect(p.lineIDs[2] != ids[0] && p.lineIDs[2] != ids[1] && p.lineIDs[2] != ids[2],
                   "the marker line is a fresh ID")
        try expectEqual(p.lineIDs[3], ids[2], "B keeps its ID")
        try expect(p.references.contains { $0.id == refs[0].id && $0.location == 9 },
                   "the following reference shifted by the inserted 2 units (7 -> 9)")
        try expectEqual(p.lineIDs[3], ids[2], "line 3 keeps its ID")
        try expectEqual(p.caret, 7, "caret right after the marker on the new line")
        let lines = r80Lines(p.content)
        guard case .number(let v, let u) = lines[1].result, u == nil else {
            throw CaseFailure(message: "the source line lost its result")
        }
        try expectEqual(v, 56.0, "7×8 still answers 56 after the same-line mint")
    },

    EngineCase("r80-same-line-trailing-newline-blank-preserved") {
        // "7×8\n": the existing blank line 2 survives AFTER the new
        // marker line — "7×8\nM\n" (three lines).
        let content = "7×8\n"
        let ids = r80Ids(2)
        guard let p = r80Plan(content, ids: ids, source: 0, caret: 2) else {
            throw CaseFailure(message: "trailing-newline same-line caret: expected a plan")
        }
        try expectEqual(p.content, "7×8\n" + r80M + "\n",
                        "marker + newline after the source's own newline; blank line preserved")
        try expectEqual(p.lineIDs[0], ids[0], "source keeps its ID")
        try expect(p.lineIDs[1] != ids[0] && p.lineIDs[1] != ids[1],
                   "the marker line is a fresh ID")
        try expectEqual(p.lineIDs[2], ids[1], "the original blank line keeps its ID")
    },

    EngineCase("r80-same-line-blank-next-line-preserved") {
        // "7×8\n\nB": the requested NEW line is dedicated to the token;
        // the pre-existing blank line stays after it (no joining).
        let content = "7×8\n\nB"
        let ids = r80Ids(3)
        guard let p = r80Plan(content, ids: ids, source: 0, caret: 1) else {
            throw CaseFailure(message: "blank-next same-line caret: expected a plan")
        }
        try expectEqual(p.content, "7×8\n" + r80M + "\n\nB",
                        "new marker line, then the preserved blank line, then B")
        try expectEqual(p.lineIDs[0], ids[0], "source keeps its ID")
        try expect(p.lineIDs[1] != ids[0] && p.lineIDs[1] != ids[1] && p.lineIDs[1] != ids[2],
                   "the new marker line is a fresh ID")
        try expectEqual(p.lineIDs[2], ids[1], "the pre-existing blank line keeps its ID")
        try expectEqual(p.lineIDs[3], ids[2], "B keeps its ID")
    },

    EngineCase("r80-same-line-contained-selection-preserved") {
        // A non-empty selection ON the source line no longer replaces
        // anything: the whole source stays and the marker goes below.
        let content = "7×8"
        let ids = r80Ids(1)
        guard let p = r80Plan(content, ids: ids, source: 0, caret: 1, length: 2) else {
            throw CaseFailure(message: "same-line selection: expected the r80 plan")
        }
        try expectEqual(p.content, "7×8\n" + r80M,
                        "the selection's text is preserved; the token is below")
        try expectEqual(p.caret, 5, "caret on the new marker line")
    },

    EngineCase("r80-same-line-multiline-selection-invalid") {
        // A selection crossing a newline would merge lines — still a
        // deterministic no-op (r77c policy, unchanged).
        let content = "7×8\nB"
        let ids = r80Ids(2)
        for sel in [NSRange(location: 2, length: 3), NSRange(location: 0, length: 4)] {
            try expect(r80Plan(content, ids: ids, source: 0,
                               caret: sel.location, length: sel.length) == nil,
                       "newline-spanning selection \(sel.location)+\(sel.length) is a no-op")
        }
    },

    EngineCase("r80-same-line-no-self-cycle") {
        // The marker never lands on the source line: after the plan the
        // source line's units contain no marker and the line's result
        // is intact — the r77c failure mode is impossible by
        // construction now.
        let content = "7×8"
        let ids = r80Ids(1)
        guard let p = r80Plan(content, ids: ids, source: 0, caret: 1) else {
            throw CaseFailure(message: "expected a plan")
        }
        let ns = p.content as NSString
        let sourceEnd = (content as NSString).length // 3: the source's own range
        for i in 0..<sourceEnd where ns.character(at: i) == 0xFFFC {
            throw CaseFailure(message: "a marker landed inside the source line at \(i)")
        }
        try expectEqual(ns.character(at: 4), 0xFFFC, "the marker sits on the new line")
        guard case .number(let v, _) = r80Lines(p.content)[0].result else {
            throw CaseFailure(message: "the source line's result broke")
        }
        try expectEqual(v, 56.0, "the source answers 56 — no circular token")
    },

    EngineCase("r80-same-line-existing-token-shifts") {
        // "7×8\nM\nB" (an existing token already on the line below,
        // referencing line 1): the same-line mint pushes it down; both
        // tokens survive on their own lines.
        let content = "7×8\n" + r80M + "\nB"
        let ids = r80Ids(3)
        let old = AnswerReference(sourceLineID: ids[0], labelLine: 1, location: 4)
        guard let p = r80Plan(content, ids: ids, refs: [old], source: 0, caret: 1) else {
            throw CaseFailure(message: "expected a plan")
        }
        try expectEqual(p.content, "7×8\n" + r80M + "\n" + r80M + "\nB",
                        "fresh marker line, old token shifted by +2")
        try expect(p.references.contains { $0.id == p.newReference.id && $0.location == 4 },
                   "the fresh reference sits on the new marker")
        try expect(p.references.contains { $0.id == old.id && $0.location == 6 },
                   "the pre-existing reference shifted to its marker")
        try expectEqual(p.references.count, 2, "both tokens keep exactly one reference each")
        // Both tokens resolve to the source's live value (56).
        let resolved = resolveSheet(content: p.content, lineIDs: p.lineIDs,
                                    references: p.references, rates: Rates(),
                                    decimalPlaces: 2)
        var active = 0
        for t in resolved.tokens {
            if case .active(let value, _, _) = t.state, value == 56.0 { active += 1 }
        }
        try expectEqual(active, 2, "both tokens resolve to 56")
    },

    EngineCase("r80-same-line-emoji-utf16") {
        // "👍+1": the emoji is two UTF-16 units; a caret after it (unit
        // 3) is on the source line and plans; mid-pair (unit 2) is
        // malformed and no-ops.
        let content = "\u{1F44D}+1"
        let ids = r80Ids(1)
        guard let p = r80Plan(content, ids: ids, source: 0, caret: 3) else {
            throw CaseFailure(message: "caret after the emoji must plan")
        }
        try expectEqual(p.content, content + "\n" + r80M,
                        "the emoji line is preserved; the marker is below")
        try expect(r80Plan(content, ids: ids, source: 0, caret: 1) == nil,
                   "a mid-surrogate caret is a no-op")
    },

    EngineCase("r80-same-line-repeated-pairs-no-extra-lines") {
        // Pair 1: same-line caret mints the marker line. Pair 2 (the
        // caret now sits on the marker line — a line DIFFERENT from the
        // source) inserts the second token at that caret; NO further
        // line is added.
        let ids = r80Ids(1)
        guard let p1 = r80Plan("7×8", ids: ids, source: 0, caret: 3) else {
            throw CaseFailure(message: "pair 1: expected a plan")
        }
        let ids2 = p1.lineIDs
        let refs1 = p1.references
        guard let p2 = r80Plan(p1.content, ids: ids2, refs: refs1,
                               source: 0, caret: p1.caret) else {
            throw CaseFailure(message: "pair 2: expected a plan")
        }
        try expectEqual(p2.content, "7×8\n" + r80M + r80M,
                        "the second bubble joins the first on the caret line")
        try expectEqual(p2.lineIDs.count, 2, "no extra line from the second pair")
        try expectEqual(p2.lineIDs, p1.lineIDs, "line IDs are stable across both pairs")
        try expectEqual(p2.references.count, 2, "two tokens, two references")
        try expect(p2.references.allSatisfy { $0.sourceLineID == ids[0] },
                   "both tokens reference the original source line")
    },

    EngineCase("r80-other-line-replacement-unchanged") {
        // The cross-line contract is untouched: a caret on a DIFFERENT
        // line still replaces/inserts in place (no new line).
        let content = "7×8\n"
        let ids = r80Ids(2)
        guard let p = r80Plan(content, ids: ids, source: 0, caret: 4) else {
            throw CaseFailure(message: "cross-line caret must plan")
        }
        try expectEqual(p.content, content + r80M, "in-place insertion, no newline added")
        try expectEqual(p.lineIDs, ids, "cross-line insertion keeps every line ID")
    },
]
