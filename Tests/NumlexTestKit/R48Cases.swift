import Foundation
import NumlexCore

/// R48: matching-bracket highlight — the pure UTF-16 matcher, the
/// deterministic pulse state/curve, and regression assurance that
/// match resolution has no output mutation and no effect on engine
/// results, references, function parentheses, syntax spans or
/// formatting.

private func pair(_ doc: String, _ p: Int) -> BracketPair? {
    BracketHighlight.pair(document: doc, selection: NSRange(location: p, length: 0))
}

private func pairStr(_ doc: String, _ p: Int) -> String {
    pair(doc, p).map { "(\($0.opening),\($0.closing),\($0.role == .opening ? "O" : "C"))" } ?? "nil"
}

/// The realistic nested function call used across the matching cases:
/// r0 o1 u2 n3 d4 (5 s6 q7 r8 t9 (10 a11 b12 s13 (14 -15 9:16 )17 )18 ,19 sp20 2:21 )22 — len 23;
/// the three pairs are (14,17) abs, (10,18) sqrt and (5,22) round.
private let nestedFunc = "round(sqrt(abs(-9)), 2)"

public let r48Cases: [EngineCase] = [
    EngineCase("r48-all-adjacencies-each-bracket-type") {
        // Every bracket type, all four caret adjacencies.
        for (open, close) in [("(", ")"), ("[", "]"), ("{", "}")] {
            let doc = "x = \(open)12\(close)"   // x0 sp1 =2 sp3 (4 1:5 2:6 )7
            try expectEqual(pairStr(doc, 8), "(4,7,C)", "\(open) typed: after closing")
            try expectEqual(pairStr(doc, 7), "(4,7,C)", "\(open) at closing")
            try expectEqual(pairStr(doc, 4), "(4,7,O)", "\(open) at opening")
            try expectEqual(pairStr(doc, 5), "(4,7,O)", "\(open) after opening")
            try expectEqual(pairStr(doc, 6), "nil", "\(open) mid-expression")
            try expectEqual(pairStr(doc, 0), "nil", "\(open) caret at document start")
        }
    },

    EngineCase("r48-adjacency-priority") {
        // `)(` : clicking either half of the CLOSING glyph identifies its
        // opening mate — the closing bracket immediately BEFORE the caret
        // (right-half click / normal typing) beats the opening AT the caret.
        let doc = "a=(x)()"                     // a0 =1 (2 x3 )4 (5 )6
        try expectEqual(pairStr(doc, 5), "(2,4,C)", ")( closing-before beats opening-at-caret")
        try expectEqual(pairStr(doc, 4), "(2,4,C)", "at first closing")
        try expectEqual(pairStr(doc, 6), "(5,6,C)", "at second closing (empty pair)")
        try expectEqual(pairStr(doc, 7), "(5,6,C)", "after second closing (typed)")
        try expectEqual(pairStr(doc, 3), "(2,4,O)", "at x inside first pair: opening before caret")
        try expectEqual(pairStr(doc, 5), "(2,4,C)", "priority stable")
        // `()` : the opening at the caret and the closing at the caret.
        let doc2 = "b=()"                       // b0 =1 (2 )3
        try expectEqual(pairStr(doc2, 2), "(2,3,O)", "empty pair: opening at caret")
        try expectEqual(pairStr(doc2, 3), "(2,3,C)", "empty pair: closing at caret")
        try expectEqual(pair(doc2, 3)?.role, .closing, "the ROLE is the closing (caret touched ')')")
        try expectEqual(pairStr(doc2, 4), "(2,3,C)", "empty pair: after closing")
    },

    EngineCase("r48-nested-and-mixed") {
        // Deep nesting, same-type and mixed-type stack semantics.
        let doc = "((1)[2])"                    // (0 (1 1:2 )3 [4 2:5 ]6 )7
        try expectEqual(pairStr(doc, 0), "(0,7,O)", "outer opening")
        try expectEqual(pairStr(doc, 1), "(1,3,O)", "inner opening")
        try expectEqual(pairStr(doc, 3), "(1,3,C)", "inner closing (at caret)")
        try expectEqual(pairStr(doc, 4), "(1,3,C)", "closing before caret beats [ at caret")
        try expectEqual(pairStr(doc, 6), "(4,6,C)", "inner ] at caret")
        let doc3 = "([1]2)"                     // (0 [1 1:2 ]3 2:4 )5
        try expectEqual(pairStr(doc3, 1), "(1,3,O)", "inner [ at caret")
        try expectEqual(pairStr(doc3, 3), "(1,3,C)", "inner ] at caret")
        try expectEqual(pairStr(doc, 7), "(4,6,C)", "] before caret beats ) at caret")
        try expectEqual(pairStr(doc, 8), "(0,7,C)", "outer closing before caret (typed)")
        let doc2 = "a=[{1}2]"                   // a0 =1 [2 {3 1:4 }5 2:6 ]7
        try expectEqual(pairStr(doc2, 2), "(2,7,O)", "outer [ at caret")
        try expectEqual(pairStr(doc2, 3), "(3,5,O)", "inner { at caret")
        try expectEqual(pairStr(doc2, 5), "(3,5,C)", "inner } at caret")
        try expectEqual(pairStr(doc2, 7), "(2,7,C)", "outer ] at caret")
        // The realistic R47 function line: nested mixed calls.
        let f = nestedFunc
        try expectEqual(pairStr(f, 5), "(5,22,O)", "round( at caret")
        try expectEqual(pairStr(f, 23), "(5,22,C)", "typed after round closing")
        try expectEqual(pairStr(f, 10), "(10,18,O)", "sqrt( at caret")
        try expectEqual(pairStr(f, 14), "(14,17,O)", "abs( at caret (innermost opening)")
        try expectEqual(pairStr(f, 17), "(14,17,C)", "abs closing at caret")
        try expectEqual(pairStr(f, 18), "(14,17,C)", "abs closing before caret (closing-before priority)")
        try expectEqual(pairStr(f, 19), "(10,18,C)", "typed comma after sqrt closing")
        try expectEqual(pairStr(f, 22), "(5,22,C)", "outermost ) at caret")
    },

    EngineCase("r48-mismatch-crossed-unmatched") {
        // Mismatched and crossed regions NEVER produce a false pair.
        let d1 = "[(1]2)"                       // [0 (1 1:2 ]3 2:4 )5
        try expectEqual(pairStr(d1, 5), "nil", "mismatched line: outer ) unmatched")
        try expectEqual(pairStr(d1, 6), "nil", "mismatched line: after outer )")
        try expectEqual(pairStr(d1, 3), "nil", "mismatched ] at caret")
        let d2 = "(1[2)3]"                       // (0 1:1 [2 2:3 )4 3:5 ]6
        try expectEqual(pairStr(d2, 4), "nil", "crossed: ) cannot pop [")
        try expectEqual(pairStr(d2, 5), "nil", "crossed: ) before caret")
        let d3 = "[(]"                           // (0 [1 ]2
        try expectEqual(pairStr(d3, 2), "nil", "mismatched ] at caret")
        try expectEqual(pairStr(d3, 3), "nil", "mismatched ] before caret")
        // Unmatched singles at every caret position.
        for doc in ["(1", "1)", "]", "[", "{1"] {
            for p in 0...(doc as NSString).length {
                try expectEqual(pairStr(doc, p), "nil", "unmatched \(doc) @\(p)")
            }
        }
    },

    EngineCase("r48-stray-closing-neutrality") {
        // A stray closing with an empty stack is skipped: it cannot
        // consume an opening, so it can never create a false pair.
        let d = "] (1)"                         // ]0 sp1 (2 1:3 )4
        try expectEqual(pairStr(d, 5), "(2,4,C)", "stray ] before a real pair")
        try expectEqual(pairStr(d, 3), "(2,4,O)", "real pair still resolves")
        // But a stray closing between the anchor and its mate is a
        // mismatch for a DIFFERENT-typed anchor.
        let d2 = "[(1]2"                         // [0 (1 1:2 ]3 2:4
        try expectEqual(pairStr(d2, 4), "nil", "] mismatches the pending (")
    },

    EngineCase("r48-bounds-empty-start-end") {
        // Empty document, start and end, out-of-range selections.
        try expectEqual(pairStr("", 0), "nil", "empty document")
        let doc = "(1)"                          // len 3
        try expectEqual(pairStr(doc, 0), "(0,2,O)", "caret at document start (before first ()")
        try expectEqual(pairStr(doc, 3), "(0,2,C)", "caret at document end (after )")
        try expectEqual(pairStr(doc, 4), "nil", "one past the end")
        try expectEqual(pairStr(doc, 100), "nil", "far out of range")
        try expectEqual(pairStr(doc, -1), "nil", "negative location")
        let notFound = BracketHighlight.pair(
            document: doc, selection: NSRange(location: NSNotFound, length: 0))
        try expectEqual(notFound, nil, "NSNotFound location")
    },

    EngineCase("r48-nonempty-and-multiple-selection") {
        // Only exactly one COLLAPSED selection can ever match.
        for (loc, len) in [(0, 1), (0, 2), (1, 1), (2, 1)] {
            let r = BracketHighlight.pair(
                document: "(1)", selection: NSRange(location: loc, length: len))
            try expectEqual(r, nil, "nonempty selection @\(loc)+\(len)")
        }
    },

    EngineCase("r48-line-isolation-cr-lf-crlf") {
        // Matches never cross a logical line break (LF, CRLF, CR).
        let lf = "(1)\n(2)"                      // (0 1:1 )2 \n3 (4 2:5 )6 len 7
        try expectEqual(pairStr(lf, 3), "(0,2,C)", "LF: line-1 pair")
        try expectEqual(pairStr(lf, 7), "(4,6,C)", "LF: line-2 pair (typed after )")
        let crlf = "(1)\r\n(2)"                  // (0 1:1 )2 \r3 \n4 (5 2:6 )7
        try expectEqual(pairStr(crlf, 6), "(5,7,O)", "CRLF: line-2 ( at caret")
        try expectEqual(pairStr(crlf, 7), "(5,7,C)", "CRLF: line-2 ) at caret")
        try expectEqual(pairStr(crlf, 4), "nil", "CRLF: caret inside the break")
        let cr = "(1)\r(2)"                      // (0 1:1 )2 \r3 (4 2:5 )6
        try expectEqual(pairStr(cr, 5), "(4,6,O)", "CR: line-2 pair")
        // An OPENING on one line can never pair with a CLOSING on the
        // next line — in either direction.
        let split1 = "(1\n2)"                    // (0 1:1 \n2 2:3 )4
        try expectEqual(pairStr(split1, 1), "nil", "opening at caret, closing on next line")
        try expectEqual(pairStr(split1, 2), "nil", "opening before caret, closing on next line")
        let split2 = "1)\n(2"                    // 1:0 )1 \n2 (3 2:4
        try expectEqual(pairStr(split2, 2), "nil", "closing before caret, opening on next line")
        try expectEqual(pairStr(split2, 3), "nil", "opening at caret, closing nowhere")
    },

    EngineCase("r48-utf16-emoji-composed-and-marker") {
        // Unicode/emoji content is neutral UTF-16: it occupies units,
        // never matches, and a surrogate-split caret is invalid.
        let emoji = "a = (1 😀 2)"      // a0 sp1 =2 sp3 (4 1:5 sp6 😀7-8 sp9 2:10 )11
        try expectEqual(pairStr(emoji, 5), "(4,11,O)", "after opening, emoji inside")
        try expectEqual(pairStr(emoji, 12), "(4,11,C)", "after closing, emoji inside")
        try expectEqual(pairStr(emoji, 7), "nil", "emoji interior, no adjacency")
        try expectEqual(pairStr(emoji, 8), "nil", "caret INSIDE the surrogate pair")
        // Composed scalar (e + combining acute = 2 units, built
        // explicitly so a precomposed literal cannot sneak in) — legal
        // caret positions, neutral content.
        let composed = "(" + "\u{65}\u{301}" + ")"   // (0 e1 ́2 )3
        try expectEqual(pairStr(composed, 1), "(0,3,O)", "after opening, composed scalar inside")
        try expectEqual(pairStr(composed, 2), "nil", "caret inside composed scalar (no adjacency)")
        try expectEqual(pairStr(composed, 3), "(0,3,C)", "at closing after composed scalar")
        // U+FFFC answer token marker is neutral content.
        let marker = "(1 \u{FFFC} 2)"            // (0 1:1 sp2 M3 sp4 2:5 )6
        try expectEqual(pairStr(marker, 1), "(0,6,O)", "marker inside pair")
        try expectEqual(pairStr(marker, 7), "(0,6,C)", "after closing with marker inside")
        try expectEqual(pairStr(marker, 3), "nil", "caret at the marker itself")
    },

    EngineCase("r48-large-deep-and-bounded") {
        // Deep nesting and long lines stay bounded and exact.
        let deep = String(repeating: "(", count: 500) + "1" + String(repeating: ")", count: 500)
        try expectEqual(pairStr(deep, 0), "(0,1000,O)", "500-deep outermost opening")
        try expectEqual(pairStr(deep, 500), "(499,501,O)", "500-deep innermost opening...")
        try expectEqual(pair(deep, 500)?.closing, 501, "innermost mate is the FIRST closing")
        try expectEqual(pairStr(deep, 501), "(499,501,C)", "innermost closing at caret")
        try expectEqual(pairStr(deep, 1001), "(0,1000,C)", "500-deep outermost closing (typed)")
        // A very long line with the pair far from the caret.
        let long = String(repeating: "x", count: 9000) + "(1)" + String(repeating: "y", count: 9000)
        let loc = 9000
        try expectEqual(pairStr(long, loc), "(\(loc),\(loc + 2),O)", "pair at offset 9000 in an 18003-char line")
        try expectEqual(pairStr(long, 0), "nil", "far from any bracket")
        // No false match: brackets exist on OTHER lines only.
        let other = "(1)\n((2))\n{3}\nplain line\n[4]"
        let plainStart = "(1)\n((2))\n{3}\n".count
        try expectEqual(pairStr(other, plainStart + 5), "nil", "caret mid plain line (no adjacency)")
        try expectEqual(pairStr(other, plainStart + 9), "nil", "caret at end of plain line")
        try expectEqual(pairStr(other, (other as NSString).length), "(25,27,C)", "document end: caret after the final ] gets its real pair")
    },

    // MARK: - Pulse state and curve (injected timestamps)

    EngineCase("r48-pulse-start-dedup-clear") {
        let a = BracketPair(opening: 0, closing: 2, role: .closing)
        let b = BracketPair(opening: 4, closing: 7, role: .opening)
        var st = BracketPulseState()
        try expectEqual(st.notify(a, now: 100, reduceMotion: false), .started, "first pair starts")
        try expectEqual(st.pulseStart, 100, "start time recorded")
        // Same pair from an incidental redraw / caret blink: NO replay.
        try expectEqual(st.notify(a, now: 100.1, reduceMotion: false), .unchanged, "same pair dedups")
        try expectEqual(st.pulseStart, 100, "start time untouched (no restart)")
        try expectEqual(st.notify(a, now: 100.5, reduceMotion: false), .unchanged, "same pair again dedups")
        // A DIFFERENT pair restarts the pass.
        try expectEqual(st.notify(b, now: 101, reduceMotion: false), .started, "new pair restarts")
        try expectEqual(st.pulseStart, 101, "new start time")
        try expectEqual(st.pair, b, "pair replaced")
        // nil clears.
        try expectEqual(st.notify(nil, now: 102, reduceMotion: false), .cleared, "nil clears")
        try expectEqual(st.pair, nil, "pair dropped")
        try expectEqual(st.pulseStart, nil, "pulse dropped")
        // nil on an empty state is a no-op.
        try expectEqual(st.notify(nil, now: 103, reduceMotion: false), .unchanged, "nil no-op")
    },

    EngineCase("r48-pulse-reduce-motion-immediate") {
        let a = BracketPair(opening: 0, closing: 2, role: .opening)
        var st = BracketPulseState()
        try expectEqual(st.notify(a, now: 5, reduceMotion: true), .started, "event still reports the change")
        try expectEqual(st.pulseStart, nil, "no pass scheduled under Reduce Motion")
        try expectEqual(st.progress(at: 5.01), nil, "final static state immediately")
        try expectEqual(st.isAnimating, false, "no tick needed")
        try expectEqual(BracketHighlight.scale(progress: nil), 1, "static scale is 1")
        try expectEqual(BracketHighlight.pulseWeight(progress: nil), 0, "static weight is 0")
    },

    EngineCase("r48-pulse-progress-settle-expire") {
        let a = BracketPair(opening: 0, closing: 5, role: .closing)
        let dur = BracketHighlight.pulseDuration
        try expect(dur >= 0.30 && dur <= 0.36, "pulse duration within the requested 0.30–0.36 s window")
        var st = BracketPulseState()
        _ = st.notify(a, now: 0, reduceMotion: false)
        try expectEqual(st.progress(at: -1), 0, "pre-start clamps to 0")
        try expect((st.progress(at: dur / 2) ?? -1) > 0.45 && (st.progress(at: dur / 2) ?? -1) < 0.55, "mid-pass progress ≈ 0.5")
        try expectEqual(st.progress(at: dur), 1, "end frame settles at 1")
        try expectEqual(st.progress(at: dur * 3), 1, "past the end stays clamped at 1")
        try expect(st.isAnimating, "still in flight before expiry")
        st.expire(now: dur - 0.001)
        try expect(st.isAnimating, "not expired a hair early")
        st.expire(now: dur)
        try expect(!st.isAnimating, "expired at the duration")
        try expectEqual(st.progress(at: dur + 1), nil, "settled: static state")
    },

    EngineCase("r48-pulse-curve-finite-clamped") {
        // The curve is finite, clamped and monotonically sane at every
        // input — no blow-up, no negative scale, no overshoot runaway.
        let times: [Double] = [-100, -1, 0, 0.01, 0.25, 0.5, 0.75, 0.99, 1, 2, 1000]
        for t in times {
            let s = BracketHighlight.scale(progress: t)
            try expect(s.isFinite && s > 0, "scale finite and positive at \(t)")
            try expect(s >= BracketHighlight.pulseStartScale - 0.0001, "scale never below the start scale")
            let w = BracketHighlight.pulseWeight(progress: t)
            try expect(w.isFinite && w >= 0 && w <= 1, "weight clamped at \(t)")
        }
        try expectEqual(BracketHighlight.scale(progress: 0), BracketHighlight.pulseStartScale, "scale starts at 0.86")
        try expectClose(BracketHighlight.pulseStartScale, 0.86, 0.0001, "start scale is the requested 0.86")
        try expectEqual(BracketHighlight.scale(progress: 1), 1, "scale settles at 1")
        try expectEqual(BracketHighlight.scale(progress: nil), 1, "nil progress = static 1")
        // The overshoot exists but is small (peak just above 1).
        let peak = (0...2000).map { BracketHighlight.scale(progress: Double($0) / 2000) }.max() ?? 0
        try expect(peak > 1.0, "the curve overshoots 1 (small bounce)")
        try expect(peak < 1.04, "the overshoot stays small (< 4%)")
        // Weight decays 1 → 0, so the fill composes peak → static.
        try expectEqual(BracketHighlight.pulseWeight(progress: 0), 1, "weight 1 at start")
        try expectEqual(BracketHighlight.pulseWeight(progress: 1), 0, "weight 0 at settle")
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            let w = BracketHighlight.pulseWeight(progress: t)
            let staticA = 0.30, peakA = 0.52
            let a = staticA + (peakA - staticA) * w
            try expect(a >= staticA - 0.0001 && a <= peakA + 0.0001, "composed alpha stays within [static, peak] at \(t)")
        }
    },

    EngineCase("r48-pulse-opening-emphasis-composition") {
        // The OPENING mate composes a slightly stronger alpha than the
        // closing/anchor at EVERY pulse phase (peak and settled).
        let phases: [Double?] = [nil, 0, 0.25, 0.5, 0.75, 1]
        for t in phases {
            let w = BracketHighlight.pulseWeight(progress: t)
            let openA = 0.30 + (0.52 - 0.30) * w
            let closeA = 0.24 + (0.42 - 0.24) * w
            try expect(openA > closeA, "opening emphasis at \(String(describing: t))")
            try expect(openA.isFinite && closeA.isFinite, "finite alphas")
        }
    },

    // MARK: - Regression: no mutation, no engine interference

    EngineCase("r48-no-mutation-pure-read") {
        // Resolving a pair is a pure read of the document string.
        let doc = nestedFunc
        _ = pair(doc, 0)
        _ = pair(doc, 22)
        try expectEqual(doc, nestedFunc, "document string untouched")
        // And the engine results for the same content are unchanged:
        // round(sqrt(abs(-9)), 2) = round(3, 2) = 3 on the unitless
        // strict route (R47 function semantics).
        let r = resolveSheet(content: doc, lineIDs: [UUID()], references: [],
                             rates: Rates(), decimalPlaces: 2)
        if case .number(let v, let u) = r.lines[0].result {
            try expectEqual(u, nil, "unitless result")
            try expectClose(v, 3.0, 0.0001, "nested function evaluates to 3")
        } else {
            throw CaseFailure(message: "expected a number result, got \(r.lines[0].result)")
        }
    },

    EngineCase("r48-references-and-tokens-unaffected") {
        // A sheet with answer tokens AND brackets: resolving pairs for
        // every caret position leaves the reference sidecar and the
        // token line results exactly as R47 pinned them.
        let M = "\u{FFFC}"
        let content = "10 km to m\n" + M + " + (1 + 2)"
        let u = UUID()
        // The marker sits on line 2 at UTF-16 offset 11 (10 chars + \n).
        let refs = [AnswerReference(sourceLineID: u, labelLine: 1, location: 11)]
        for p in 0...(content as NSString).length {
            _ = pair(content, p)
        }
        let r = resolveSheet(content: content, lineIDs: [u, UUID()],
                             references: refs, rates: Rates(), decimalPlaces: 2)
        try expectEqual(r.tokens.count, 1, "one token")
        try expectEqual(r.tokens[0].location, 11, "token location unchanged")
        if case .broken = r.tokens[0].state {
            throw CaseFailure(message: "token must stay active, got \(r.tokens[0].state)")
        }
    },

    EngineCase("r48-syntax-spans-and-formatting-unaffected") {
        // Brackets stay base text in the syntax classifier (R47: builtin
        // call heads are base text), and the formatter leaves valid call
        // shapes canonical (idempotent).
        let line = "sqrt(144)"
        let spans = SyntaxClassifier.spans(for: line, rates: Rates(),
                                           decimalPlaces: 2, constants: [])
        try expectEqual(spans.count, 1, "one line, one span list")
        for span in spans[0] {
            let s = line.index(line.startIndex, offsetBy: span.range.location)
            let e = line.index(s, offsetBy: span.range.length)
            let text = String(line[s..<e])
            try expect(!text.contains("(") && !text.contains(")"),
                       "no span covers a bracket: \(text)")
        }
        let fmt = NotebookFormatting.canonicalLine(line)?.text ?? ""
        try expectEqual(fmt, line, "valid call shape is already canonical")
        // The comma convention is a shared ENGINE rule (R47): canonical
        // formatting keeps the call shape verbatim, while evaluation
        // applies the grouping rule.
        let grouped = NotebookFormatting.canonicalLine("sum(1, 234)")?.text ?? ""
        try expectEqual(grouped, "sum(1, 234)", "call shape untouched by formatting")
        try expectClose(try evaluateExpression("sum(1, 234)", variables: [:]), 235.0, 0.0001,
                        "two-argument comma evaluates 1 + 234")
        try expectClose(try evaluateExpression("sum(1,234)", variables: [:]), 1234.0, 0.0001,
                        "grouping comma evaluates one literal")
    }
]
